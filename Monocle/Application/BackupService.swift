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
        let result = BookBackup(categories: try repository.categories(), expenses: try repository.expenses(), draft: draft, settings: settings)
        try result.validate()
        return result
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
        guard try canonical(store.expenses()) == canonical(candidate.expenses),
              (try store.categories()) == candidate.categories.sorted(by: { $0.id.uuidString < $1.id.uuidString }) else { throw BackupError.invalid }
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
