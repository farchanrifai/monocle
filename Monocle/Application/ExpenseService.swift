import Foundation
import Observation

/// Value-only boundary. Managed objects never leave the persistence adapter.
@MainActor
protocol ExpenseStore {
    func transaction(_ operation: () throws -> Void) throws
    func books() throws -> [BookProfile]
    func createBook(named name: String) throws -> BookProfile
    func createBook(named name: String, initialCategories: [GlobalCategory]?) throws -> BookProfile
    func renameBook(id: UUID, to name: String) throws
    func deleteBook(id: UUID) throws

    func categories(in bookID: UUID) throws -> [ExpenseCategory]
    func expenses(in bookID: UUID) throws -> [Expense]
    func budgets(in bookID: UUID) throws -> [BudgetVersion]
    func bills(in bookID: UUID) throws -> [BillRule]
    func billOccurrences(in bookID: UUID) throws -> [BillOccurrence]
    func save(_ expense: Expense, in bookID: UUID) throws
    func save(_ budget: BudgetVersion, in bookID: UUID) throws
    func saveBill(_ bill: BillRule, in bookID: UUID) throws
    func deleteBill(_ id: UUID, in bookID: UUID) throws
    func saveOccurrence(_ occurrence: BillOccurrence, in bookID: UUID) throws
    func deleteOccurrence(_ id: UUID, in bookID: UUID) throws
    func saveCategory(_ category: ExpenseCategory, in bookID: UUID) throws
    func deleteCategory(_ id: UUID, in bookID: UUID) throws
    func updateGlobalCategoryMetadata(id: UUID, name: String, symbol: String) throws
    func activateCategory(_ category: GlobalCategory, in bookID: UUID) throws
    func deactivateCategory(_ categoryID: UUID, in bookID: UUID) throws
    func unifyCategoriesToGlobalCatalog(_ catalog: [GlobalCategory]) throws

    func categories() throws -> [ExpenseCategory]
    func expenses() throws -> [Expense]
    func budgets() throws -> [BudgetVersion]
    func bills() throws -> [BillRule]
    func billOccurrences() throws -> [BillOccurrence]
    func save(_ expense: Expense) throws
    func save(_ budget: BudgetVersion) throws
    func saveBill(_ bill: BillRule) throws
    func deleteBill(_ id: UUID) throws
    func saveOccurrence(_ occurrence: BillOccurrence) throws
    func deleteOccurrence(_ id: UUID) throws
    func delete(_ id: UUID) throws
    func saveCategory(_ category: ExpenseCategory) throws
    func deleteCategory(_ id: UUID) throws
}

extension ExpenseStore {
    func createBook(named name: String) throws -> BookProfile {
        try createBook(named: name, initialCategories: nil)
    }
    func createBook(named name: String, initialCategories: [GlobalCategory]?) throws -> BookProfile {
        try createBook(named: name)
    }
    func updateGlobalCategoryMetadata(id: UUID, name: String, symbol: String) throws {}
    func activateCategory(_ category: GlobalCategory, in bookID: UUID) throws {}
    func deactivateCategory(_ categoryID: UUID, in bookID: UUID) throws {}
    func unifyCategoriesToGlobalCatalog(_ catalog: [GlobalCategory]) throws {}
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
    private(set) var bills: [BillRule] = []
    private(set) var billOccurrences: [BillOccurrence] = []
    private var categoryRules: [CategoryRule] = []
    private var archivedCategoryIDs: Set<UUID> = []

    init(store: any ExpenseStore) throws {
        self.store = store
        try reload()
    }

    func reload() throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let storedBooks = try store.books()
        guard let targetID = storedBooks.first(where: { $0.id == activeBookID })?.id ?? storedBooks.first?.id else {
            throw EntryError.corruptStore
        }
        let categories = try store.categories(in: targetID)
        let expenses = try store.expenses(in: targetID)
        let budgets = try store.budgets(in: targetID)
        let bills = try store.bills(in: targetID)
        let occurrences = try store.billOccurrences(in: targetID)
        self.books = storedBooks
        self.activeBookID = targetID
        self.categories = categories
        self.expenses = expenses
        self.budgets = budgets
        self.bills = bills
        self.billOccurrences = occurrences
    }

    func selectBook(_ id: UUID) throws {
        guard books.contains(where: { $0.id == id }) else { return }
        let previousID = activeBookID
        activeBookID = id
        do { try reload() }
        catch { activeBookID = previousID; throw error }
    }

    func createBook(named name: String, initialCategories: [GlobalCategory]? = nil) throws -> BookProfile {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let book = try store.createBook(named: name, initialCategories: initialCategories)
        try reload()
        return book
    }

    func updateGlobalCategoryMetadata(id: UUID, name: String, symbol: String) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.updateGlobalCategoryMetadata(id: id, name: name, symbol: symbol)
        try reload()
    }

    func activateCategory(_ category: GlobalCategory, in bookID: UUID) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.activateCategory(category, in: bookID)
        try reload()
    }

    func deactivateCategory(_ categoryID: UUID, in bookID: UUID) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.deactivateCategory(categoryID, in: bookID)
        try reload()
    }

    func unifyCategoriesToGlobalCatalog(_ catalog: [GlobalCategory]) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.unifyCategoriesToGlobalCatalog(catalog)
        try reload()
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

    func bills(for bookID: UUID) throws -> [BillRule] {
        try store.bills(in: bookID)
    }

    func billOccurrences(for bookID: UUID) throws -> [BillOccurrence] {
        try store.billOccurrences(in: bookID)
    }

    func saveBill(_ bill: BillRule, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? bill.bookID
        var bill = bill
        bill.bookID = targetID
        let cats = (targetID == activeBookID) ? categories : try store.categories(in: targetID)
        try bill.validate(categories: cats)
        let existing = try store.billOccurrences(in: targetID)
        let result = BillReconciliationEngine.reconcile(rule: bill, existingOccurrences: existing)
        try store.transaction {
            try store.saveBill(bill, in: targetID)
            for expense in result.autoExpenses { try store.save(expense, in: targetID) }
            for occ in result.newOccurrences { try store.saveOccurrence(occ, in: targetID) }
        }
        BillNotificationService.shared.cancelAllReminders(for: bill.id, occurrences: existing)
        let updatedIDs = Set(result.newOccurrences.map(\.id))
        let reminders = existing.filter { $0.billRuleID == bill.id && !updatedIDs.contains($0.id) } + result.newOccurrences
        for occurrence in reminders where occurrence.status == .pending {
            BillNotificationService.shared.scheduleReminder(for: occurrence, rule: bill)
        }
        try reload()
    }

    func deleteBill(_ id: UUID, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? activeBookID
        let existingOccurrences = try store.billOccurrences(in: targetID)
        try store.deleteBill(id, in: targetID)
        BillNotificationService.shared.cancelAllReminders(for: id, occurrences: existingOccurrences)
        try reload()
    }

    func reconcileBills(asOf date: Date = .now, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? activeBookID
        let currentBills = try store.bills(in: targetID)
        let existingOccurrences = try store.billOccurrences(in: targetID)

        var hasChanges = false
        for bill in currentBills where bill.isActive {
            let result = BillReconciliationEngine.reconcile(
                rule: bill,
                existingOccurrences: existingOccurrences,
                asOf: date
            )
            try store.transaction {
                for expense in result.autoExpenses { try store.save(expense, in: targetID) }
                for occ in result.newOccurrences { try store.saveOccurrence(occ, in: targetID) }
            }
            for occ in result.newOccurrences {
                hasChanges = true
                if occ.status == .pending {
                    BillNotificationService.shared.scheduleReminder(for: occ, rule: bill)
                } else {
                    BillNotificationService.shared.cancelReminder(for: occ.id)
                }
            }
        }
        if hasChanges {
            try reload()
        }
    }

    @discardableResult
    func confirmBillOccurrence(
        _ occurrenceID: UUID,
        customDate: Date? = nil,
        customAmount: Int64? = nil,
        customNote: String? = nil,
        in bookID: UUID? = nil
    ) throws -> Expense {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? activeBookID
        let occurrences = try store.billOccurrences(in: targetID)
        guard var occurrence = occurrences.first(where: { $0.id == occurrenceID }) else {
            throw BillError.occurrenceNotFound
        }
        let allBills = try store.bills(in: targetID)
        guard let rule = allBills.first(where: { $0.id == occurrence.billRuleID }) else {
            throw BillError.ruleNotFound
        }

        guard occurrence.status == .pending else { throw BillError.alreadyResolved }

        let expenseID = UUID()
        let expenseDate = customDate ?? Day.date(occurrence.dueDay) ?? .now
        let expenseAmount = customAmount ?? rule.amount
        let expenseNote = customNote ?? rule.name

        let expense = Expense(
            id: expenseID,
            amount: expenseAmount,
            day: Day.string(expenseDate),
            note: expenseNote,
            allocations: [.init(categoryID: rule.categoryID, amount: expenseAmount)],
            source: "bill-confirmed",
            createdAt: expenseDate,
            bookID: targetID
        )

        occurrence.status = .recorded
        occurrence.expenseID = expenseID
        occurrence.updatedAt = .now
        try store.transaction {
            try store.save(expense, in: targetID)
            try store.saveOccurrence(occurrence, in: targetID)
        }

        BillNotificationService.shared.cancelReminder(for: occurrenceID)

        try reload()
        return expense
    }

    func skipBillOccurrence(_ occurrenceID: UUID, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? activeBookID
        let occurrences = try store.billOccurrences(in: targetID)
        guard var occurrence = occurrences.first(where: { $0.id == occurrenceID }) else {
            throw BillError.occurrenceNotFound
        }

        guard occurrence.status == .pending else { throw BillError.alreadyResolved }
        occurrence.status = .skipped
        occurrence.updatedAt = .now
        try store.saveOccurrence(occurrence, in: targetID)

        BillNotificationService.shared.cancelReminder(for: occurrenceID)

        try reload()
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

    func saveExpenses(_ batch: [Expense], in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? activeBookID
        let cats = (targetID == activeBookID) ? categories : try store.categories(in: targetID)
        try store.transaction {
            for expense in batch {
                var exp = expense
                exp.bookID = targetID
                try exp.validate(categories: cats)
                try store.save(exp, in: targetID)
            }
        }
        try reload()
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
