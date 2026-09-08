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
    private var categoryRules: [CategoryRule] = []
    private var archivedCategoryIDs: Set<UUID> = []

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

    func configure(categoryRules: [CategoryRule], archivedCategoryIDs: Set<UUID>) {
        self.categoryRules = categoryRules
        self.archivedCategoryIDs = archivedCategoryIDs
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
        let parsed = try ExpenseParser.parse(text, categories: categories.filter { !archivedCategoryIDs.contains($0.id) }, rules: categoryRules)
        guard let categoryID = parsed.categoryID else { throw EntryError.missingCategory }
        return try record(amountInRupiah: parsed.amount / 100, categoryID: categoryID, note: parsed.note, date: date, id: id, source: "shortcut-text")
    }

    /// The structured Shortcut path. It accepts whole IDR, validates the selected live category,
    /// and shares the same committed save path as manual capture.
    @discardableResult
    func record(amountInRupiah: Int64, categoryID: UUID, note: String? = nil, date: Date = .now, id: UUID = UUID(), source: String = "shortcut") throws -> Expense {
        guard amountInRupiah > 0 else { throw EntryError.invalidAmount }
        let multiplication = amountInRupiah.multipliedReportingOverflow(by: 100)
        guard !multiplication.overflow, multiplication.partialValue <= Money.maximum else { throw EntryError.invalidAmount }
        guard categories.contains(where: { $0.id == categoryID }), !archivedCategoryIDs.contains(categoryID) else { throw EntryError.missingCategory }
        let expense = Expense(id: id, amount: multiplication.partialValue, day: Day.string(date),
                              note: note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                              allocations: [.init(categoryID: categoryID, amount: multiplication.partialValue)],
                              source: source, createdAt: date)
        try save(expense)
        return expense
    }

    func delete(_ id: UUID) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.delete(id)
        expenses.removeAll { $0.id == id }
    }
}
