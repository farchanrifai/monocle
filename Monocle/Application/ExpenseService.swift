import Foundation
import Observation

/// Value-only boundary. Managed objects never leave the persistence adapter.
@MainActor
protocol ExpenseStore {
    func categories() throws -> [ExpenseCategory]
    func expenses() throws -> [Expense]
    func save(_ expense: Expense) throws
    func delete(_ id: UUID) throws
}

/// Shared by screen state and App Intents. Main-actor isolation serializes local commands.
@MainActor @Observable
final class ExpenseService {
    private let store: any ExpenseStore
    private(set) var expenses: [Expense] = []
    private(set) var categories: [ExpenseCategory] = []

    init(store: any ExpenseStore) throws {
        self.store = store
        try reload()
    }

    func reload() throws {
        let categories = try store.categories()
        let expenses = try store.expenses()
        self.categories = categories
        self.expenses = expenses
    }

    func save(_ expense: Expense) throws {
        try expense.validate(categories: categories)
        try store.save(expense)
        // Publish the committed value without a second fallible read after the commit.
        expenses.removeAll { $0.id == expense.id }
        expenses.append(expense)
        expenses.sort { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
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
        try store.delete(id)
        expenses.removeAll { $0.id == id }
    }
}
