import Foundation
import Observation

/// Value-only boundary. Managed objects never leave the persistence adapter.
@MainActor
protocol ExpenseStore {
    func categories() throws -> [ExpenseCategory]
    func expenses() throws -> [Expense]
    func save(_ expense: Expense) throws
    func delete(_ id: UUID) throws
    func saveCategory(_ category: ExpenseCategory) throws
    func deleteCategory(_ id: UUID) throws
}

/// Shared by screen state and App Intents. Main-actor isolation serializes local commands.
@MainActor @Observable
final class ExpenseService {
    var isBlocked = false
    private let store: any ExpenseStore
    private(set) var expenses: [Expense] = []
    private(set) var categories: [ExpenseCategory] = []

    init(store: any ExpenseStore) throws {
        self.store = store
        try reload()
    }

    func reload() throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let categories = try store.categories()
        let expenses = try store.expenses()
        self.categories = categories
        self.expenses = expenses
    }

    func save(_ expense: Expense) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try expense.validate(categories: categories)
        try store.save(expense)
        // Publish the committed value without a second fallible read after the commit.
        expenses.removeAll { $0.id == expense.id }
        expenses.append(expense)
        expenses.sort { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
    }

    func saveCategory(_ category: ExpenseCategory) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let category = try category.validated(against: categories)
        try store.saveCategory(category)
        categories.removeAll { $0.id == category.id }
        categories.append(category)
        categories.sort { $0.id.uuidString < $1.id.uuidString }
    }

    func deleteCategory(_ id: UUID) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        guard !expenses.contains(where: { $0.allocations.contains(where: { $0.categoryID == id }) }) else { throw CategoryError.inUse }
        try store.deleteCategory(id)
        categories.removeAll { $0.id == id }
    }

    @discardableResult
    func record(text: String, date: Date = .now, id: UUID = UUID()) throws -> Expense {
        let parsed = try ExpenseParser.parse(text, categories: categories)
        guard let categoryID = parsed.categoryID else { throw EntryError.missingCategory }
        let expense = Expense(id: id, amount: parsed.amount, day: Day.string(date), note: parsed.note,
                              allocations: [.init(categoryID: categoryID, amount: parsed.amount)],
                              source: "shortcut", createdAt: date)
        try save(expense)
        return expense
    }

    func delete(_ id: UUID) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.delete(id)
        expenses.removeAll { $0.id == id }
    }
}
