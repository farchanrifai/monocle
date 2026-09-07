import Foundation
import Observation

struct PrototypeSettings: Codable {
    var budget: Int64 = 450_000_000
    var startDay = 1
    var billAutomatic = false
    var billReminder = true
}

@MainActor @Observable
final class AppModel {
    static let shared = AppModel()
    private(set) var expenses: [Expense] = []
    private(set) var categories: [ExpenseCategory] = []
    var draft = ExpenseDraft()
    var settings = PrototypeSettings()
    var showEntry = false
    var showSettings = false
    var selectedTab = 0
    var error: String?
    var startupError: String?
    var toast: String?
    var undoExpense: Expense?
    private var repository: ExpenseRepository?
    private var directory: URL?

    var cycle: BudgetCycle { BudgetCycle.containing(.now, startDay: settings.startDay) }
    var cycleExpenses: [Expense] { expenses.filter { cycle.contains($0) } }
    var spent: Int64 { cycleExpenses.reduce(0) { $0 + $1.amount } }
    var remaining: Int64 { settings.budget - spent }

    init() {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            // Deliberately isolated from the eventual personal-data store.
            var folderName = "monocle-prototype"
            #if DEBUG
            if let run = ProcessInfo.processInfo.environment["MONOCLE_TEST_RUN"], UUID(uuidString: run) != nil {
                folderName = "monocle-ui-test-" + run
            }
            #endif
            let directory = support.appendingPathComponent(folderName, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.directory = directory
            let repository = try ExpenseRepository(url: directory.appendingPathComponent("Monocle.sqlite"))
            try repository.prepareSampleBook()
            self.repository = repository
            try reload()
            let draftURL = directory.appendingPathComponent("draft.json")
            if FileManager.default.fileExists(atPath: draftURL.path) {
                draft = try JSONDecoder().decode(ExpenseDraft.self, from: Data(contentsOf: draftURL))
            }
            let settingsURL = directory.appendingPathComponent("settings.json")
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                settings = try JSONDecoder().decode(PrototypeSettings.self, from: Data(contentsOf: settingsURL))
            }
            // Seed only on first creation, never because the user emptied their book.
            let marker = directory.appendingPathComponent("sample-seeded")
            if !FileManager.default.fileExists(atPath: marker.path) {
                try seed()
                try Data("1".utf8).write(to: marker, options: .atomic)
                try reload()
            }
        } catch { startupError = error.localizedDescription }
    }

    func reload() throws {
        guard let repository else { throw EntryError.corruptStore }
        let categories = try repository.categories()
        let expenses = try repository.expenses()
        self.categories = categories; self.expenses = expenses
    }
    func category(_ id: UUID?) -> ExpenseCategory? { categories.first { $0.id == id } }
    func title(_ expense: Expense) -> String { expense.note.isEmpty ? category(expense.allocations.first?.categoryID)?.name ?? "Expense" : expense.note }
    func spent(in category: ExpenseCategory) -> Int64 {
        cycleExpenses.flatMap(\.allocations).filter { $0.categoryID == category.id }.reduce(0) { $0 + $1.amount }
    }
    func openEntry() { showEntry = true }
    func edit(_ expense: Expense) {
        if draft.hasContent { error = "Finish or discard your current draft before editing another expense."; return }
        guard expense.allocations.count == 1 else { error = "Split editing is coming in the next milestone."; return }
        draft = ExpenseDraft(expense: expense); showEntry = true
    }
    func persistDraft() {
        do { try write(draft, name: "draft.json") } catch { self.error = "Your draft could not be saved: \(error.localizedDescription)" }
    }
    func discardDraft() { draft = ExpenseDraft(); persistDraft() }
    func saveDraft() {
        do {
            let expense = try draft.expense()
            try save(expense)
            let editing = draft.editing
            draft = ExpenseDraft(); persistDraft(); showEntry = false
            toast = editing ? "Expense updated" : "Expense recorded"
        } catch { self.error = error.localizedDescription }
    }
    func save(_ expense: Expense) throws {
        guard let repository else { throw EntryError.corruptStore }
        try repository.save(expense)
        try reload()
    }
    func delete(_ expense: Expense) {
        do {
            guard let repository else { throw EntryError.corruptStore }
            try repository.delete(expense.id); try reload()
            undoExpense = expense; toast = "Expense deleted"
        } catch { self.error = error.localizedDescription }
    }
    func undoDelete() {
        guard let undoExpense else { return }
        do { try save(undoExpense); self.undoExpense = nil; toast = "Expense restored" }
        catch { self.error = error.localizedDescription }
    }
    func repeatExpense(_ expense: Expense) {
        guard !draft.hasContent else { error = "Finish or discard your current draft first."; return }
        draft = ExpenseDraft(expense: expense); draft.id = UUID(); draft.editing = false
        draft.createdAt = .now; draft.date = .now; draft.source = "repeat"; showEntry = true
    }
    func saveSettings(_ proposed: PrototypeSettings) throws {
        guard proposed.budget > 0, (1...31).contains(proposed.startDay) else { throw EntryError.invalidAmount }
        try write(proposed, name: "settings.json"); settings = proposed
    }
    private func write<T: Encodable>(_ value: T, name: String) throws {
        guard let directory else { throw EntryError.corruptStore }
        try JSONEncoder().encode(value).write(to: directory.appendingPathComponent(name), options: .atomic)
    }
    private func seed() throws {
        let sample: [(Int, String, Int64, Int)] = [(0, "Morning coffee", 28_000, 0), (0, "Lunch at work", 45_000, 0), (0, "Ride home", 32_000, 1), (-1, "Weekly groceries", 185_000, 3), (-1, "Cinema night", 65_000, 5), (-2, "Coffee with friends", 56_000, 0)]
        for (index, value) in sample.enumerated() {
            let date = Calendar.current.date(byAdding: .day, value: value.0, to: .now) ?? .now
            let id = UUID(uuidString: String(format: "30000000-0000-0000-0000-%012d", index + 1))!
            // Stable sample IDs make an interrupted first-run seed safe to repeat.
            let expense = Expense(id: id, amount: value.2 * 100, day: Day.string(date), note: value.1, allocations: [.init(categoryID: categories[value.3].id, amount: value.2 * 100)], source: "sample", createdAt: date.addingTimeInterval(Double(-index) * 60))
            try repository?.save(expense)
        }
    }
}
