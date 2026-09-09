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

    func startEmptyRealBook(named name: String, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws -> PrototypeSettings {
        let profile = try BookProfile.real(named: name)
        var updated = settings
        updated.book = profile
        let original = try snapshot(draft: currentDraft, settings: settings).encoded()
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
        let original = try snapshot(draft: currentDraft, settings: settings).encoded()
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
    func restore(_ candidate: BookBackup, currentDraft: ExpenseDraft, settings: PrototypeSettings) throws {
        // Validate again at activation; callers cannot bypass preview with a mutated value.
        _ = try preview(data: candidate.encoded())
        guard !FileManager.default.fileExists(atPath: journal.path) else { throw BackupError.recoveryRequired }
        let original = try snapshot(draft: currentDraft, settings: settings).encoded()
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
        let original = try BookBackup.decode(Data(contentsOf: journal))
        try repository.replace(with: original)
        try state.saveDraft(original.draft)
        try state.saveSettings(original.settings)
        try Data("1".utf8).write(to: directory.appendingPathComponent("sample-seeded"), options: .atomic)
        try FileManager.default.removeItem(at: journal)
    }
}
