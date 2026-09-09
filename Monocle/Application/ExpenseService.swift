import Foundation
import Observation

/// Value-only boundary. Managed objects never leave the persistence adapter.
@MainActor
protocol ExpenseStore {
    func books() throws -> [BookProfile]
    func createBook(named name: String) throws -> BookProfile
    func renameBook(id: UUID, to name: String) throws
    func deleteBook(id: UUID) throws

    func categories(in bookID: UUID) throws -> [ExpenseCategory]
    func expenses(in bookID: UUID) throws -> [Expense]
    func budgets(in bookID: UUID) throws -> [BudgetVersion]
    func save(_ expense: Expense, in bookID: UUID) throws
    func save(_ budget: BudgetVersion, in bookID: UUID) throws
    func saveCategory(_ category: ExpenseCategory, in bookID: UUID) throws
    func deleteCategory(_ id: UUID, in bookID: UUID) throws

    func categories() throws -> [ExpenseCategory]
    func expenses() throws -> [Expense]
    func budgets() throws -> [BudgetVersion]
    func save(_ expense: Expense) throws
    func save(_ budget: BudgetVersion) throws
    func delete(_ id: UUID) throws
    func saveCategory(_ category: ExpenseCategory) throws
    func deleteCategory(_ id: UUID) throws
}

/// Shared by screen state and App Intents. Main-actor isolation serializes local commands.
@MainActor @Observable
final class ExpenseService {
    var isBlocked = false
    private let store: any ExpenseStore
    private(set) var books: [BookProfile] = []
    private(set) var activeBookID: UUID = BookProfile.sample.id
    private(set) var expenses: [Expense] = []
    private(set) var categories: [ExpenseCategory] = []
    private(set) var budgets: [BudgetVersion] = []
    private var categoryRules: [CategoryRule] = []
    private var archivedCategoryIDs: Set<UUID> = []

    init(store: any ExpenseStore) throws {
        self.store = store
        try reload()
    }

    func reload() throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let storedBooks = (try? store.books()) ?? []
        self.books = storedBooks
        if !storedBooks.contains(where: { $0.id == activeBookID }), let first = storedBooks.first {
            activeBookID = first.id
        }
        let categories: [ExpenseCategory]
        if let scoped = try? store.categories(in: activeBookID) {
            categories = scoped
        } else {
            categories = try store.categories()
        }
        let expenses: [Expense]
        if let scoped = try? store.expenses(in: activeBookID) {
            expenses = scoped
        } else {
            expenses = try store.expenses()
        }
        let budgets: [BudgetVersion]
        if let scoped = try? store.budgets(in: activeBookID) {
            budgets = scoped
        } else {
            budgets = try store.budgets()
        }
        self.categories = categories
        self.expenses = expenses
        self.budgets = budgets
    }

    func selectBook(_ id: UUID) throws {
        guard books.contains(where: { $0.id == id }) else { return }
        activeBookID = id
        try reload()
    }

    func createBook(named name: String) throws -> BookProfile {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let book = try store.createBook(named: name)
        try reload()
        return book
    }

    func renameBook(id: UUID, to name: String) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.renameBook(id: id, to: name)
        try reload()
    }

    func deleteBook(id: UUID) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.deleteBook(id: id)
        try reload()
    }

    func expenses(for bookID: UUID) throws -> [Expense] {
        try store.expenses(in: bookID)
    }

    func categories(for bookID: UUID) throws -> [ExpenseCategory] {
        try store.categories(in: bookID)
    }

    func budgets(for bookID: UUID) throws -> [BudgetVersion] {
        try store.budgets(in: bookID)
    }

    func configure(categoryRules: [CategoryRule], archivedCategoryIDs: Set<UUID>) {
        self.categoryRules = categoryRules
        self.archivedCategoryIDs = archivedCategoryIDs
    }

    func save(_ expense: Expense, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? expense.bookID ?? activeBookID
        var expense = expense
        expense.bookID = targetID
        let cats = (targetID == activeBookID) ? categories : try store.categories(in: targetID)
        try expense.validate(categories: cats)
        try store.save(expense, in: targetID)
        if targetID == activeBookID {
            expenses.removeAll { $0.id == expense.id }
            expenses.append(expense)
            expenses.sort { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
        }
    }

    func save(_ budget: BudgetVersion, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? budget.bookID ?? activeBookID
        var budget = budget
        budget.bookID = targetID
        let cats = (targetID == activeBookID) ? categories : try store.categories(in: targetID)
        try budget.validate(categories: cats)
        try store.save(budget, in: targetID)
        if targetID == activeBookID {
            budgets.removeAll { $0.id == budget.id || $0.effectiveDay == budget.effectiveDay }
            budgets.append(budget)
            budgets.sort { $0.effectiveDay < $1.effectiveDay }
        }
    }

    func saveCategory(_ category: ExpenseCategory, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? activeBookID
        let cats = (targetID == activeBookID) ? categories : try store.categories(in: targetID)
        let category = try category.validated(against: cats)
        try store.saveCategory(category, in: targetID)
        if targetID == activeBookID {
            categories.removeAll { $0.id == category.id }
            categories.append(category)
            categories.sort { $0.id.uuidString < $1.id.uuidString }
        }
    }

    func deleteCategory(_ id: UUID, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? activeBookID
        let bookExpenses = (targetID == activeBookID) ? expenses : try store.expenses(in: targetID)
        guard !bookExpenses.contains(where: { $0.allocations.contains(where: { $0.categoryID == id }) }) else { throw CategoryError.inUse }
        try store.deleteCategory(id, in: targetID)
        if targetID == activeBookID {
            categories.removeAll { $0.id == id }
        }
    }

    @discardableResult
    func record(text: String, date: Date = .now, id: UUID = UUID(), in bookID: UUID? = nil) throws -> Expense {
        let targetID = bookID ?? activeBookID
        let cats = (targetID == activeBookID) ? categories : try store.categories(in: targetID)
        let parsed = try ExpenseParser.parse(text, categories: cats.filter { !archivedCategoryIDs.contains($0.id) }, rules: categoryRules)
        guard let categoryID = parsed.categoryID else { throw EntryError.missingCategory }
        return try record(amountInRupiah: parsed.amount / 100, categoryID: categoryID, note: parsed.note, date: date, id: id, source: "shortcut-text", in: targetID)
    }

    /// The structured Shortcut path. It accepts whole IDR, validates the selected live category,
    /// and shares the same committed save path as manual capture.
    @discardableResult
    func record(amountInRupiah: Int64, categoryID: UUID, note: String? = nil, date: Date = .now, id: UUID = UUID(), source: String = "shortcut", in bookID: UUID? = nil) throws -> Expense {
        let targetID = bookID ?? activeBookID
        guard amountInRupiah > 0 else { throw EntryError.invalidAmount }
        let multiplication = amountInRupiah.multipliedReportingOverflow(by: 100)
        guard !multiplication.overflow, multiplication.partialValue <= Money.maximum else { throw EntryError.invalidAmount }
        let cats = (targetID == activeBookID) ? categories : try store.categories(in: targetID)
        guard cats.contains(where: { $0.id == categoryID }), !archivedCategoryIDs.contains(categoryID) else { throw EntryError.missingCategory }
        let expense = Expense(id: id, amount: multiplication.partialValue, day: Day.string(date),
                              note: note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                              allocations: [.init(categoryID: categoryID, amount: multiplication.partialValue)],
                              source: source, createdAt: date, bookID: targetID)
        try save(expense, in: targetID)
        return expense
    }

    func delete(_ id: UUID) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.delete(id)
        expenses.removeAll { $0.id == id }
    }
}
