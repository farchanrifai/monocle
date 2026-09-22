import Foundation

/// A retained rollback document bridges the database and the two atomic JSON files.
/// Until the journal is removed, restart always restores the original complete snapshot.
@MainActor
final class BackupService {
    enum Stage: CaseIterable { case journalWritten, databaseReplaced, draftWritten, settingsWritten }
    let directory: URL
    private let repository: ExpenseRepository
    private let state: FileLocalStateStore
    private let expenses: ExpenseService
    var fault: ((Stage) throws -> Void)? // Inject interruptions/failures in tests only.
    private(set) var requiresRecovery = false
    private var journal: URL { directory.appendingPathComponent("restore-journal.json") }
    var safetyURL: URL { directory.appendingPathComponent("last-safety-backup.monoclebackup") }

    init(directory: URL, repository: ExpenseRepository, state: FileLocalStateStore, expenses: ExpenseService) {
        self.directory = directory; self.repository = repository; self.state = state; self.expenses = expenses
    }
    func snapshot(draft: ExpenseDraft, settings: PrototypeSettings) throws -> BookBackup {
        let exportedAt = Date.now
        let storedBudgets = try repository.budgets()
        let fallbackBudget = BudgetVersion.initial(overallLimit: settings.budget, startDay: settings.startDay, date: exportedAt)
        let result = BookBackup(formatVersion: 3, exportedAt: exportedAt, bookID: settings.book.id, bookName: settings.book.name,
                                bookKind: settings.book.kind.rawValue, sampleSeeded: settings.book.kind == .sample,
                                categories: try repository.categories(), expenses: try repository.expenses(), draft: draft, settings: settings,
                                budgets: storedBudgets.isEmpty ? [fallbackBudget] : storedBudgets)
        try result.validate()
        return result
    }

    func workspaceSnapshot(currentDraft: ExpenseDraft, settings: PrototypeSettings) throws -> WorkspaceBackup {
        let exportedAt = Date.now
        let allBooks = try repository.books()
        var items: [BookBackupItem] = []
        for book in allBooks {
            let cats = try repository.categories(in: book.id)
            let exps = try repository.expenses(in: book.id)
            let budgets = try repository.budgets(in: book.id)
            let bills = try repository.bills(in: book.id)
            let occurrences = try repository.billOccurrences(in: book.id)
            let draft = (book.id == (currentDraft.bookID ?? settings.book.id)) ? currentDraft : (try state.loadDraft(for: book.id))
            items.append(BookBackupItem(book: book, categories: cats, expenses: exps, budgets: budgets, draft: draft, bills: bills, billOccurrences: occurrences))
        }
        let prefs = try state.loadWorkspacePreferences()
        var artworks: [String: Data] = [:]
        for (_, custom) in prefs.cardCustomizations {
            if case .customPhoto(let filename) = custom.style,
               let data = CardArtworkStore.shared.loadArtworkData(filename: filename) {
                artworks[filename] = data
            }
        }
        let workspace = WorkspaceBackup(formatVersion: 6, exportedAt: exportedAt, currency: "IDR", minorUnitScale: 2,
                                        books: items, preferences: prefs, settings: settings,
                                        cardArtworks: artworks.isEmpty ? nil : artworks)
        try workspace.validate()
        return workspace
    }

    func startEmptyRealBook(named name: String, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws -> PrototypeSettings {
        let profile = try BookProfile.real(named: name)
        var updated = settings
        updated.book = profile
        let original = try workspaceSnapshot(currentDraft: currentDraft, settings: settings).encoded()
        try original.write(to: safetyURL, options: .atomic)
        try original.write(to: journal, options: .atomic)
        do {
            try repository.startEmptyRealBook(profile)
            try state.saveDraft(ExpenseDraft())
            try state.saveSettings(updated)
            try expenses.reload()
            try FileManager.default.removeItem(at: journal)
            return updated
        } catch {
            do {
                try Self.recoverIfNeeded(directory: directory, repository: repository, state: state)
                try expenses.reload()
            } catch {
                requiresRecovery = true; expenses.isBlocked = true
                throw BackupError.recoveryRequired
            }
            throw error
        }
    }

    func renameRealBook(to name: String, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws -> PrototypeSettings {
        let profile = try settings.book.renamed(to: name)
        var updated = settings
        updated.book = profile
        let original = try workspaceSnapshot(currentDraft: currentDraft, settings: settings).encoded()
        try original.write(to: safetyURL, options: .atomic)
        try original.write(to: journal, options: .atomic)
        do {
            try repository.renameRealBook(profile)
            try state.saveSettings(updated)
            try expenses.reload()
            try FileManager.default.removeItem(at: journal)
            return updated
        } catch {
            do {
                try Self.recoverIfNeeded(directory: directory, repository: repository, state: state)
                try expenses.reload()
            } catch {
                requiresRecovery = true; expenses.isBlocked = true
                throw BackupError.recoveryRequired
            }
            throw error
        }
    }

    func clearExpenses(in bookID: UUID? = nil, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws {
        let original = try workspaceSnapshot(currentDraft: currentDraft, settings: settings).encoded()
        try original.write(to: safetyURL, options: .atomic)
        try original.write(to: journal, options: .atomic)
        do {
            try repository.clearExpenses(in: bookID)
            if let bookID {
                try state.saveDraft(ExpenseDraft(), for: bookID)
            } else {
                for book in try repository.books() {
                    try state.saveDraft(ExpenseDraft(), for: book.id)
                }
            }
            try expenses.reload()
            try FileManager.default.removeItem(at: journal)
        } catch {
            do {
                try Self.recoverIfNeeded(directory: directory, repository: repository, state: state)
                try expenses.reload()
            } catch {
                requiresRecovery = true; expenses.isBlocked = true
                throw BackupError.recoveryRequired
            }
            throw error
        }
    }

    func resetAllData(cardName: String, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws -> PrototypeSettings {
        let original = try workspaceSnapshot(currentDraft: currentDraft, settings: settings).encoded()
        try original.write(to: safetyURL, options: .atomic)
        try original.write(to: journal, options: .atomic)
        do {
            CardArtworkStore.shared.deleteAllArtworks()
            let resolvedName = cardName.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalName = resolvedName.isEmpty ? "My expenses" : resolvedName
            let defaultCategories = ExpenseCategory.defaults
            let (newBookID, _) = try repository.resetToFreshWorkspace(bookName: finalName, categories: defaultCategories)

            var updatedSettings = settings
            updatedSettings.book = BookProfile(id: newBookID, name: finalName, kind: .real)

            var freshPreferences = WorkspacePreferences()
            freshPreferences.visibleBookIDs = [newBookID]
            freshPreferences.bookOrder = [newBookID]
            freshPreferences.globalCategories = defaultCategories.map {
                GlobalCategory(id: $0.id, name: $0.name, symbol: $0.symbol, defaultActiveForNewCards: true)
            }
            freshPreferences.cardInactiveCategoryIDs = [:]
            freshPreferences.cardCustomizations = [:]
            freshPreferences.stacks = []
            freshPreferences.activeStackID = nil

            try state.saveDraft(ExpenseDraft(), for: newBookID)
            try state.saveSettings(updatedSettings)
            try state.saveWorkspacePreferences(freshPreferences)
            try Data("1".utf8).write(to: directory.appendingPathComponent("sample-seeded"), options: .atomic)

            try expenses.reload()
            try FileManager.default.removeItem(at: journal)
            return updatedSettings
        } catch {
            do {
                try Self.recoverIfNeeded(directory: directory, repository: repository, state: state)
                try expenses.reload()
            } catch {
                requiresRecovery = true; expenses.isBlocked = true
                throw BackupError.recoveryRequired
            }
            throw error
        }
    }

    func preview(data: Data) throws -> BookBackup {
        let candidate = try BookBackup.decode(data)
        let store = try ExpenseRepository(inMemory: true)
        try store.replace(with: candidate)
        func canonical(_ expenses: [Expense]) -> [Expense] {
            expenses.map { expense in
                var value = expense
                value.allocations.sort { $0.categoryID == $1.categoryID ? $0.amount < $1.amount : $0.categoryID.uuidString < $1.categoryID.uuidString }
                return value
            }.sorted { $0.id.uuidString < $1.id.uuidString }
        }
        func canonicalBudgets(_ budgets: [BudgetVersion]) -> [BudgetVersion] {
            budgets.map { budget in
                var value = budget
                value.categoryLimits.sort { $0.categoryID.uuidString < $1.categoryID.uuidString }
                return value
            }.sorted { $0.effectiveDay < $1.effectiveDay }
        }
        let expectedBudgets = candidate.budgets.isEmpty
            ? [BudgetVersion.initial(overallLimit: candidate.settings.budget, startDay: candidate.settings.startDay, date: candidate.exportedAt)]
            : candidate.budgets
        guard try canonical(store.expenses()) == canonical(candidate.expenses),
              (try store.categories()) == candidate.categories.sorted(by: { $0.id.uuidString < $1.id.uuidString }),
              canonicalBudgets(try store.budgets()) == canonicalBudgets(expectedBudgets) else { throw BackupError.invalid }
        return candidate
    }

    func previewWorkspace(data: Data) throws -> WorkspaceBackup {
        let candidate = try WorkspaceBackup.decode(data)
        let store = try ExpenseRepository(inMemory: true)
        try store.replace(with: candidate, importArtworks: false)
        return candidate
    }

    func restoreWorkspace(_ candidate: WorkspaceBackup, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws {
        _ = try previewWorkspace(data: candidate.encoded())
        guard !FileManager.default.fileExists(atPath: journal.path) else { throw BackupError.recoveryRequired }
        let original = try workspaceSnapshot(currentDraft: currentDraft, settings: settings).encoded()
        try original.write(to: safetyURL, options: .atomic)
        try original.write(to: journal, options: .atomic)
        do {
            try fault?(.journalWritten)
            try repository.replace(with: candidate)
            try fault?(.databaseReplaced)
            for book in candidate.books {
                try state.saveDraft(book.draft ?? ExpenseDraft(), for: book.book.id)
            }
            try fault?(.draftWritten)
            try state.saveSettings(candidate.settings)
            try state.saveWorkspacePreferences(candidate.preferences)
            try fault?(.settingsWritten)
            try Data("1".utf8).write(to: directory.appendingPathComponent("sample-seeded"), options: .atomic)
            try expenses.reload()
            try FileManager.default.removeItem(at: journal)
        } catch {
            let originalError = error
            do {
                try Self.recoverIfNeeded(directory: directory, repository: repository, state: state)
                try expenses.reload()
            } catch {
                requiresRecovery = true
                expenses.isBlocked = true
                throw BackupError.recoveryRequired
            }
            throw originalError
        }
    }

    func restore(_ candidate: BookBackup, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws {
        // Validate single-book candidate preview:
        _ = try preview(data: candidate.encoded())
        guard !FileManager.default.fileExists(atPath: journal.path) else { throw BackupError.recoveryRequired }
        let original = try workspaceSnapshot(currentDraft: currentDraft, settings: settings).encoded()
        try original.write(to: safetyURL, options: .atomic)
        try original.write(to: journal, options: .atomic)
        do {
            try fault?(.journalWritten)
            try repository.replace(with: candidate)
            try fault?(.databaseReplaced)
            try state.saveDraft(candidate.draft)
            try fault?(.draftWritten)
            try state.saveSettings(candidate.settings)
            try fault?(.settingsWritten)
            try Data("1".utf8).write(to: directory.appendingPathComponent("sample-seeded"), options: .atomic)
            try expenses.reload()
            try FileManager.default.removeItem(at: journal)
        } catch {
            let originalError = error
            do {
                try Self.recoverIfNeeded(directory: directory, repository: repository, state: state)
                try expenses.reload()
            } catch {
                requiresRecovery = true
                expenses.isBlocked = true
                throw BackupError.recoveryRequired
            }
            throw originalError
        }
    }

    static func recoverIfNeeded(directory: URL, repository: ExpenseRepository, state: FileLocalStateStore) throws {
        let journal = directory.appendingPathComponent("restore-journal.json")
        guard FileManager.default.fileExists(atPath: journal.path) else { return }
        let journalData = try Data(contentsOf: journal)
        if let workspace = try? WorkspaceBackup.decode(journalData) {
            try repository.replace(with: workspace)
            for book in workspace.books {
                try state.saveDraft(book.draft ?? ExpenseDraft(), for: book.book.id)
            }
            try state.saveSettings(workspace.settings)
            try state.saveWorkspacePreferences(workspace.preferences)
        } else {
            let original = try BookBackup.decode(journalData)
            try repository.replace(with: original)
            try state.saveDraft(original.draft)
            try state.saveSettings(original.settings)
        }
        try Data("1".utf8).write(to: directory.appendingPathComponent("sample-seeded"), options: .atomic)
        try FileManager.default.removeItem(at: journal)
    }
}
