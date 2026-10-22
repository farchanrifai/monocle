import Foundation

/// A retained rollback document bridges SQLite, preferences, drafts and artwork.
/// Until the journal is removed, restart restores the original complete snapshot.
@MainActor
final class BackupService {
    enum Stage: CaseIterable {
        case journalWritten, artworkStaged, databaseReplaced, artworksWritten, draftWritten, settingsWritten, preferencesWritten
    }
    let directory: URL
    private let repository: ExpenseRepository
    private let state: any LocalStateStore
    private let expenses: ExpenseService
    private let artworkStore: CardArtworkStore
    var fault: ((Stage) throws -> Void)? // Inject interruptions/failures in tests only.
    var recoveryFault: (() throws -> Void)?
    private(set) var requiresRecovery = false
    private var journal: URL { directory.appendingPathComponent("restore-journal.json") }
    var safetyURL: URL { directory.appendingPathComponent("last-safety-backup.ankabackup") }

    init(directory: URL, repository: ExpenseRepository, state: any LocalStateStore, expenses: ExpenseService,
         artworkStore: CardArtworkStore = .shared) {
        self.directory = directory; self.repository = repository; self.state = state; self.expenses = expenses
        self.artworkStore = artworkStore
    }

    /// Use one admission gate before any destructive snapshot or file write.
    /// A retry must never replace the only surviving copy of the original workspace.
    func admitMutation() throws {
        guard !requiresRecovery, !expenses.isBlocked,
              !FileManager.default.fileExists(atPath: journal.path) else {
            requiresRecovery = true
            expenses.isBlocked = true
            throw BackupError.recoveryRequired
        }
    }

    /// Coordinate compound workspace commands under a single SQLite transaction
    /// and a durable rollback document for the accompanying JSON/artwork writes.
    func withRecovery<T>(currentDraft: ExpenseDraft, settings: PrototypeSettings, operation: () throws -> T) throws -> T {
        try admitMutation()
        let original = try workspaceSnapshot(currentDraft: currentDraft, settings: settings).encoded()
        try original.write(to: safetyURL, options: .atomic)
        try original.write(to: journal, options: .atomic)
        do {
            try fault?(.journalWritten)
            var result: T?
            try expenses.performTransaction(publish: false) { result = try operation() }
            let committedSettings = try state.loadSettings()
            _ = try makeWorkspaceSnapshot(currentDraft: nil, settings: committedSettings)
            try expenses.stageCommittedState()
            expenses.configure(categoryRules: committedSettings.categoryRules, archivedCategoryIDs: committedSettings.archivedCategoryIDs)
            try FileManager.default.removeItem(at: journal)
            expenses.publishCommittedState()
            return result!
        } catch {
            let originalError = error
            do {
                try recoveryFault?()
                try Self.recoverIfNeeded(directory: directory, repository: repository, state: state, artworkStore: artworkStore)
                try expenses.reload()
                let recoveredSettings = try state.loadSettings()
                expenses.configure(categoryRules: recoveredSettings.categoryRules, archivedCategoryIDs: recoveredSettings.archivedCategoryIDs)
                expenses.publishCommittedState()
            } catch {
                requiresRecovery = true
                expenses.isBlocked = true
                throw BackupError.recoveryRequired
            }
            throw originalError
        }
    }

    func snapshot(draft: ExpenseDraft, settings: PrototypeSettings) throws -> CardBackup {
        let exportedAt = Date.now
        let storedBudgets = try repository.budgets()
        let fallbackBudget = BudgetVersion.initial(overallLimit: settings.budget, startDay: settings.startDay, date: exportedAt)
        let result = CardBackup(formatVersion: 3, exportedAt: exportedAt, cardID: settings.card.id, cardName: settings.card.name,
                                cardKind: settings.card.kind.rawValue, sampleSeeded: settings.card.kind == .demo,
                                categories: try repository.categories(), expenses: try repository.expenses(), draft: draft, settings: settings,
                                budgets: storedBudgets.isEmpty ? [fallbackBudget] : storedBudgets)
        try result.validate()
        return result
    }

    func workspaceSnapshot(currentDraft: ExpenseDraft, settings: PrototypeSettings) throws -> WorkspaceBackup {
        try BackendDiagnostics.measure("WorkspaceSnapshot") {
            try makeWorkspaceSnapshot(currentDraft: currentDraft, settings: settings)
        }
    }

    private func makeWorkspaceSnapshot(currentDraft: ExpenseDraft?, settings: PrototypeSettings) throws -> WorkspaceBackup {
        let exportedAt = Date.now
        let allCards = try repository.cards()
        var items: [CardBackupItem] = []
        for card in allCards {
            let draft: ExpenseDraft
            if let currentDraft, card.id == (currentDraft.cardID ?? settings.card.id) { draft = currentDraft }
            else { draft = try state.loadDraft(for: card.id) }
            items.append(CardBackupItem(card: card, categories: try repository.categories(in: card.id),
                                        expenses: try repository.expenses(in: card.id), budgets: try repository.budgets(in: card.id), draft: draft,
                                        bills: try repository.bills(in: card.id), billOccurrences: try repository.billOccurrences(in: card.id)))
        }
        let prefs = try state.loadWorkspacePreferences()
        var artworks: [String: Data] = [:]
        for custom in prefs.cardCustomizations.values {
            if case .customPhoto(let filename) = custom.style {
                guard let data = artworkStore.loadArtworkData(filename: filename) else { throw BackupError.missingArtwork }
                try CardArtworkStore.validateArtworkData(data)
                artworks[filename] = data
            }
        }
        let workspace = WorkspaceBackup(formatVersion: WorkspaceBackup.currentFormat, exportedAt: exportedAt, currency: prefs.reportingCurrency, minorUnitScale: 2,
                                        cards: items, preferences: prefs, settings: settings,
                                        cardArtworks: artworks.isEmpty ? nil : artworks)
        try workspace.validate()
        return workspace
    }

    func startEmptyRealCard(named name: String, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws -> PrototypeSettings {
        try admitMutation()
        let profile = try Card.real(named: name)
        var updated = settings
        updated.card = profile
        return try withRecovery(currentDraft: currentDraft, settings: settings) {
            try repository.startEmptyRealCard(profile)
            try state.saveDraft(ExpenseDraft(), for: Card.demo.id)
            try state.saveDraft(ExpenseDraft(), for: profile.id)
            try state.saveSettings(updated)
            var preferences = try state.loadWorkspacePreferences()
            func remap(_ ids: [UUID]) -> [UUID] { ids.map { $0 == Card.demo.id ? profile.id : $0 } }
            preferences.visibleCardIDs = remap(preferences.visibleCardIDs)
            preferences.cardOrder = remap(preferences.cardOrder)
            preferences.alwaysHiddenCardIDs = remap(preferences.alwaysHiddenCardIDs)
            preferences.stacks = preferences.stacks.map { var value = $0; value.cardIDs = remap(value.cardIDs); return value }
            if let value = preferences.cardCustomizations.removeValue(forKey: Card.demo.id) { preferences.cardCustomizations[profile.id] = value }
            if let value = preferences.cardInactiveCategoryIDs.removeValue(forKey: Card.demo.id) { preferences.cardInactiveCategoryIDs[profile.id] = value }
            try state.saveWorkspacePreferences(preferences)
            return updated
        }
    }

    func renameRealCard(to name: String, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws -> PrototypeSettings {
        try admitMutation()
        let profile = try settings.card.renamed(to: name)
        var updated = settings
        updated.card = profile
        return try withRecovery(currentDraft: currentDraft, settings: settings) {
            try repository.renameRealCard(profile)
            try state.saveSettings(updated)
            return updated
        }
    }

    func clearExpenses(in cardID: UUID? = nil, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws {
        try withRecovery(currentDraft: currentDraft, settings: settings) {
            try repository.clearExpenses(in: cardID)
            for id in try cardID.map({ [$0] }) ?? repository.cards().map(\.id) {
                try state.saveDraft(ExpenseDraft(), for: id)
            }
        }
    }

    func resetAllData(cardName: String, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws -> PrototypeSettings {
        try withRecovery(currentDraft: currentDraft, settings: settings) {
            let resolvedName = cardName.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = resolvedName.isEmpty ? "My expenses" : resolvedName
            let defaultCategories = ExpenseCategory.defaults
            let (newCardID, _) = try repository.resetToFreshWorkspace(cardName: finalName, categories: defaultCategories)
            var updatedSettings = settings
            updatedSettings.card = Card(id: newCardID, name: finalName, kind: .real)
            if let budget = try repository.budgets(in: newCardID).first {
                updatedSettings.budget = budget.overallLimit
                updatedSettings.startDay = budget.startDay
            }
            updatedSettings.archivedCategoryIDs = []
            updatedSettings.categoryRules = []
            let freshPreferences = WorkspacePreferences(visibleCardIDs: [newCardID], cardOrder: [newCardID],
                                                        globalCategories: defaultCategories.map { GlobalCategory(category: $0) })
            try state.saveDraft(ExpenseDraft(), for: newCardID)
            try state.saveSettings(updatedSettings)
            try state.saveWorkspacePreferences(freshPreferences)
            try Data("1".utf8).write(to: directory.appendingPathComponent("sample-seeded"), options: .atomic)
            return updatedSettings
        }
        // Old assets are harmless once no customization references them. Removing
        // them before commit would make rollback depend on a second file mutation.
    }

    func preview(data: Data) throws -> CardBackup {
        let candidate = try CardBackup.decode(data)
        _ = try materializedPreview(WorkspaceBackup(singleCard: candidate))
        return candidate
    }

    func previewWorkspace(data: Data) throws -> WorkspaceBackup {
        try BackendDiagnostics.measure("WorkspacePreview") {
            try materializedPreview(WorkspaceBackup.decode(data))
        }
    }

    /// Materialize every durable component in isolation and compare the entire
    /// canonical graph, including rules, occurrences, drafts, metadata and bytes.
    private func materializedPreview(_ source: WorkspaceBackup) throws -> WorkspaceBackup {
        let candidate = try source.normalized()
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("anka-preview-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = try ExpenseRepository(inMemory: true)
        let local = FileLocalStateStore(directory: temporary)
        let artwork = CardArtworkStore(directory: temporary.appendingPathComponent("artwork", isDirectory: true))
        try store.replace(with: candidate, importArtworks: false)
        for item in candidate.cards { try local.saveDraft(item.draft!, for: item.card.id) }
        try local.saveSettings(candidate.settings)
        try local.saveWorkspacePreferences(candidate.preferences)
        for (filename, data) in candidate.cardArtworks ?? [:] { try artwork.importArtworkData(data, filename: filename) }
        let actual = try Self.readback(template: candidate, repository: store, state: local, artworkStore: artwork)
        guard try candidate.canonical() == actual.canonical() else { throw BackupError.invalid }
        return candidate
    }

    func restoreWorkspace(_ candidate: WorkspaceBackup, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws {
        try admitMutation()
        let candidate = try materializedPreview(candidate)
        try withRecovery(currentDraft: currentDraft, settings: settings) {
            try activate(candidate)
        }
    }

    func restore(_ candidate: CardBackup, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws {
        try admitMutation()
        _ = try preview(data: candidate.encoded())
        let workspace = try materializedPreview(WorkspaceBackup(singleCard: candidate))
        try withRecovery(currentDraft: currentDraft, settings: settings) {
            try activate(workspace)
        }
    }

    private func activate(_ candidate: WorkspaceBackup) throws {
        let staged = try artworkStore.stageArtworks(candidate.cardArtworks ?? [:], in: directory)
        defer { try? FileManager.default.removeItem(at: staged) }
        try fault?(.artworkStaged)
        try repository.replace(with: candidate, importArtworks: false)
        try fault?(.databaseReplaced)
        try artworkStore.installStagedArtworks(staged)
        try fault?(.artworksWritten)
        for card in candidate.cards { try state.saveDraft(card.draft!, for: card.card.id) }
        try fault?(.draftWritten)
        try state.saveSettings(candidate.settings)
        try fault?(.settingsWritten)
        try state.saveWorkspacePreferences(candidate.preferences)
        try fault?(.preferencesWritten)
        try Data("1".utf8).write(to: directory.appendingPathComponent("sample-seeded"), options: .atomic)
    }

    private static func readback(template: WorkspaceBackup, repository: ExpenseRepository, state: any LocalStateStore,
                                 artworkStore: CardArtworkStore) throws -> WorkspaceBackup {
        var items: [CardBackupItem] = []
        for card in try repository.cards() {
            items.append(CardBackupItem(card: card, categories: try repository.categories(in: card.id), expenses: try repository.expenses(in: card.id),
                                        budgets: try repository.budgets(in: card.id), draft: try state.loadDraft(for: card.id),
                                        bills: try repository.bills(in: card.id), billOccurrences: try repository.billOccurrences(in: card.id)))
        }
        var bytes: [String: Data] = [:]
        for filename in (template.cardArtworks ?? [:]).keys {
            guard let data = artworkStore.loadArtworkData(filename: filename) else { throw BackupError.missingArtwork }
            bytes[filename] = data
        }
        return WorkspaceBackup(formatVersion: template.formatVersion, exportedAt: template.exportedAt, currency: template.currency,
                               minorUnitScale: template.minorUnitScale, cards: items, preferences: try state.loadWorkspacePreferences(),
                               settings: try state.loadSettings(), cardArtworks: bytes)
    }

    static func recoverIfNeeded(directory: URL, repository: ExpenseRepository, state: any LocalStateStore,
                                artworkStore: CardArtworkStore = .shared) throws {
        let journal = directory.appendingPathComponent("restore-journal.json")
        guard FileManager.default.fileExists(atPath: journal.path) else { return }
        let workspace = try WorkspaceBackup.decode(Data(contentsOf: journal)).normalized()
        let staged = try artworkStore.stageArtworks(workspace.cardArtworks ?? [:], in: directory)
        defer { try? FileManager.default.removeItem(at: staged) }
        try repository.transaction {
            try repository.replace(with: workspace, importArtworks: false)
            try artworkStore.installStagedArtworks(staged)
            for card in workspace.cards { try state.saveDraft(card.draft!, for: card.card.id) }
            try state.saveSettings(workspace.settings)
            try state.saveWorkspacePreferences(workspace.preferences)
            try Data("1".utf8).write(to: directory.appendingPathComponent("sample-seeded"), options: .atomic)
        }
        let actual = try readback(template: workspace, repository: repository, state: state, artworkStore: artworkStore)
        guard try workspace.canonical() == actual.canonical() else { throw BackupError.recoveryRequired }
        try FileManager.default.removeItem(at: journal)
    }
}
