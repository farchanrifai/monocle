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
    func updateCard(_ profile: BookProfile) throws
    func deleteBook(id: UUID) throws

    func categories(in bookID: UUID) throws -> [ExpenseCategory]
    func expenses(in bookID: UUID) throws -> [Expense]
    func expenses(in bookID: UUID, from startDay: String, to endDay: String, limit: Int, offset: Int) throws -> [Expense]
    func budgets(in bookID: UUID) throws -> [BudgetVersion]
    func bills(in bookID: UUID) throws -> [BillRule]
    func billOccurrences(in bookID: UUID) throws -> [BillOccurrence]
    func saveExpenses(_ batch: [Expense], in bookID: UUID) throws
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
    func categoryMigrationMapping(to catalog: [GlobalCategory]) throws -> [UUID: [UUID: UUID]]
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
    func delete(_ id: UUID, in bookID: UUID) throws
    func delete(_ id: UUID, in bookID: UUID, at date: Date) throws
    func saveCategory(_ category: ExpenseCategory) throws
    func deleteCategory(_ id: UUID) throws
    func clearExpenses(in bookID: UUID?) throws
}

extension ExpenseStore {
    func createBook(named name: String) throws -> BookProfile {
        try createBook(named: name, initialCategories: nil)
    }
    func createBook(named name: String, initialCategories: [GlobalCategory]?) throws -> BookProfile {
        try createBook(named: name)
    }
    func updateGlobalCategoryMetadata(id: UUID, name: String, symbol: String) throws {}
    func updateCard(_ profile: BookProfile) throws {}
    func activateCategory(_ category: GlobalCategory, in bookID: UUID) throws {}
    func deactivateCategory(_ categoryID: UUID, in bookID: UUID) throws {}
    func expenses(in bookID: UUID, from startDay: String, to endDay: String, limit: Int, offset: Int) throws -> [Expense] {
        guard Day.date(startDay) != nil, Day.date(endDay) != nil, startDay < endDay,
              (1...1_000).contains(limit), offset >= 0 else { throw EntryError.invalidDate }
        return Array(try expenses(in: bookID).filter { $0.day >= startDay && $0.day < endDay }.dropFirst(offset).prefix(limit))
    }
    func saveExpenses(_ batch: [Expense], in bookID: UUID) throws {
        for expense in batch { try save(expense, in: bookID) }
    }
    func categoryMigrationMapping(to catalog: [GlobalCategory]) throws -> [UUID: [UUID: UUID]] { [:] }
    func unifyCategoriesToGlobalCatalog(_ catalog: [GlobalCategory]) throws {}
    func clearExpenses(in bookID: UUID?) throws {}
    func delete(_ id: UUID, in bookID: UUID, at date: Date) throws { try delete(id, in: bookID) }
    func delete(_ id: UUID, in bookID: UUID) throws {
        guard try expenses(in: bookID).contains(where: { $0.id == id }) else { throw EntryError.corruptStore }
        try delete(id)
    }
}

/// Shared by screen state and App Intents. Main-actor isolation serializes local commands.
@MainActor @Observable
final class ExpenseService {
    var isBlocked = false
    private let store: any ExpenseStore
    let notifications: BillNotificationService
    private(set) var books: [BookProfile] = []
    private(set) var activeBookID: UUID = BookProfile.sample.id
    private(set) var expenses: [Expense] = []
    private(set) var categories: [ExpenseCategory] = []
    private(set) var budgets: [BudgetVersion] = []
    private(set) var bills: [BillRule] = []
    private(set) var billOccurrences: [BillOccurrence] = []
    private(set) var committedRevision: UInt64 = 0
    private(set) var projectionRefreshError: String?
    var onCommit: (@MainActor () -> Void)?
    private var categoryRules: [CategoryRule] = []
    private var archivedCategoryIDs: Set<UUID> = []
    private var transactionDepth = 0
    private var pendingAuthorization = false
    private var workspaceExpenses: [UUID: [Expense]] = [:]
    private var workspaceBills: [UUID: [BillRule]] = [:]
    private var workspaceOccurrences: [UUID: [BillOccurrence]] = [:]
    private var stagedSnapshot: Snapshot?

    private struct BookState {
        let categories: [ExpenseCategory]
        let expenses: [Expense]
        let budgets: [BudgetVersion]
        let bills: [BillRule]
        let occurrences: [BillOccurrence]
    }
    private struct Snapshot {
        let books: [BookProfile]
        let activeID: UUID
        let states: [UUID: BookState]
    }

    init(store: any ExpenseStore, notifications: BillNotificationService = .shared) throws {
        self.store = store
        self.notifications = notifications
        try reload()
    }

    private func snapshot(preferredID: UUID) throws -> Snapshot {
        let storedBooks = try store.books()
        guard Set(storedBooks.map(\.id)).count == storedBooks.count,
              let targetID = storedBooks.first(where: { $0.id == preferredID })?.id ?? storedBooks.first?.id else {
            throw EntryError.corruptStore
        }
        var states: [UUID: BookState] = [:]
        var total: Int64 = 0
        for book in storedBooks {
            let categories = try store.categories(in: book.id)
            let expenses = try store.expenses(in: book.id)
            let budgets = try store.budgets(in: book.id)
            let bills = try store.bills(in: book.id)
            let occurrences = try store.billOccurrences(in: book.id)
            for bill in bills { try bill.validate(categories: categories) }
            try BillOccurrence.validate(occurrences, rules: bills, expenses: expenses, bookID: book.id)
            total = try Money.checkedSum([total, Money.checkedSum(expenses.map(\.amount))])
            states[book.id] = BookState(categories: categories, expenses: expenses, budgets: budgets, bills: bills, occurrences: occurrences)
        }
        return Snapshot(books: storedBooks, activeID: targetID, states: states)
    }

    private func publish(_ snapshot: Snapshot, requestAuthorization: Bool = false) {
        guard let active = snapshot.states[snapshot.activeID] else { return }
        workspaceExpenses = snapshot.states.mapValues(\.expenses)
        workspaceBills = snapshot.states.mapValues(\.bills)
        workspaceOccurrences = snapshot.states.mapValues(\.occurrences)
        books = snapshot.books
        activeBookID = snapshot.activeID
        categories = active.categories
        expenses = active.expenses
        budgets = active.budgets
        bills = active.bills
        billOccurrences = active.occurrences
        projectionRefreshError = nil
        notifications.reconcile(rules: snapshot.states.values.flatMap(\.bills),
                                occurrences: snapshot.states.values.flatMap(\.occurrences),
                                requestAuthorization: requestAuthorization)
    }

    func reload() throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let current = try snapshot(preferredID: activeBookID)
        stagedSnapshot = nil
        publish(current)
    }

    /// Read/validate a committed candidate without publishing it while a recovery journal remains.
    func stageCommittedState() throws { stagedSnapshot = try snapshot(preferredID: activeBookID) }

    /// A command has already committed when this runs. Refresh errors are separate observable state.
    private func didCommit(requestAuthorization: Bool = false, refreshSnapshot: Bool = true) {
        pendingAuthorization = pendingAuthorization || requestAuthorization
        guard transactionDepth == 0 else { return }
        if let stagedSnapshot {
            self.stagedSnapshot = nil
            publish(stagedSnapshot, requestAuthorization: pendingAuthorization)
        } else if refreshSnapshot {
            do { publish(try snapshot(preferredID: activeBookID), requestAuthorization: pendingAuthorization) }
            catch { projectionRefreshError = error.localizedDescription }
        } else {
            notifications.reconcile(rules: workspaceBills.values.flatMap { $0 },
                                    occurrences: workspaceOccurrences.values.flatMap { $0 },
                                    requestAuthorization: pendingAuthorization)
        }
        pendingAuthorization = false
        committedRevision &+= 1
        onCommit?()
    }

    /// Nested commands share one durable SQLite commit and one publication callback.
    func performTransaction(publish: Bool = true, _ operation: () throws -> Void) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let priorAuthorization = pendingAuthorization
        transactionDepth += 1
        do {
            try BackendDiagnostics.measure("WorkspaceCommand") { try store.transaction(operation) }
            transactionDepth -= 1
            if transactionDepth == 0, publish { didCommit() }
        } catch {
            transactionDepth -= 1
            pendingAuthorization = priorAuthorization
            throw error
        }
    }

    /// Recovery coordinators publish after their journal/files have also completed.
    func publishCommittedState() { didCommit() }

    func selectBook(_ id: UUID) throws {
        guard books.contains(where: { $0.id == id }) else { return }
        publish(try snapshot(preferredID: id))
    }

    func createBook(named name: String, initialCategories: [GlobalCategory]? = nil) throws -> BookProfile {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let book = try store.createBook(named: name, initialCategories: initialCategories)
        if transactionDepth == 0 {
            books.append(book)
            workspaceExpenses[book.id] = []
        }
        didCommit()
        return book
    }

    func updateGlobalCategoryMetadata(id: UUID, name: String, symbol: String) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.updateGlobalCategoryMetadata(id: id, name: name, symbol: symbol)
        didCommit()
    }

    func activateCategory(_ category: GlobalCategory, in bookID: UUID) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.activateCategory(category, in: bookID)
        didCommit()
    }

    func deactivateCategory(_ categoryID: UUID, in bookID: UUID) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.deactivateCategory(categoryID, in: bookID)
        didCommit()
    }

    func categoryMigrationMapping(to catalog: [GlobalCategory]) throws -> [UUID: [UUID: UUID]] {
        try store.categoryMigrationMapping(to: catalog)
    }

    func unifyCategoriesToGlobalCatalog(_ catalog: [GlobalCategory]) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.unifyCategoriesToGlobalCatalog(catalog)
        didCommit()
    }

    func renameBook(id: UUID, to name: String) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.renameBook(id: id, to: name)
        didCommit()
    }

    /// Saves a card's currency and Paid with defaults; its name and look have their own commands.
    func updateCard(_ profile: BookProfile) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try profile.validate()
        try store.updateCard(profile)
        didCommit()
    }

    /// Expenses on any card that use this Paid with label.
    func expenseCount(paidWith id: UUID) -> Int {
        workspaceExpenses.values.reduce(0) { $0 + $1.filter { $0.paidWithID == id }.count }
    }

    func deleteBook(id: UUID) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.deleteBook(id: id)
        didCommit()
    }

    func expenses(for bookID: UUID) throws -> [Expense] { try store.expenses(in: bookID) }
    func expenses(for bookID: UUID, from startDay: String, to endDay: String, limit: Int = 200, offset: Int = 0) throws -> [Expense] {
        try store.expenses(in: bookID, from: startDay, to: endDay, limit: limit, offset: offset)
    }
    func categories(for bookID: UUID) throws -> [ExpenseCategory] { try store.categories(in: bookID) }
    func budgets(for bookID: UUID) throws -> [BudgetVersion] { try store.budgets(in: bookID) }
    func bills(for bookID: UUID) throws -> [BillRule] { try store.bills(in: bookID) }
    func billOccurrences(for bookID: UUID) throws -> [BillOccurrence] { try store.billOccurrences(in: bookID) }

    func saveBill(_ bill: BillRule, in bookID: UUID? = nil, asOf date: Date = .now) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? bill.bookID
        var bill = bill
        bill.bookID = targetID
        let cats = try store.categories(in: targetID)
        let prior = try store.bills(in: targetID).first { $0.id == bill.id }
        let existing = try store.billOccurrences(in: targetID)
        var retired: [UUID] = []
        if let prior {
            // The caller edits visible fields; durable history metadata belongs to this command.
            bill.createdAt = prior.createdAt
            bill.scheduleRevision = prior.scheduleRevision
            bill.scheduleEffectiveDay = prior.scheduleEffectiveDay
            if prior.recurrence != bill.recurrence {
                guard prior.scheduleRevision < Int.max else { throw BillError.invalidRecurrence }
                bill.scheduleRevision += 1
                bill.scheduleEffectiveDay = Day.string(date)
                retired = existing.filter {
                    $0.billRuleID == bill.id && $0.status == .pending && $0.dueDay >= Day.string(date)
                }.map(\.id)
            }
            if prior.isActive && !bill.isActive {
                // Pausing drops lookahead; bills already due stay pending for the user to resolve.
                retired += existing.filter {
                    $0.billRuleID == bill.id && $0.status == .pending && $0.dueDay > Day.string(date)
                }.map(\.id)
            } else if !prior.isActive && bill.isActive {
                // Resuming starts a fresh schedule today, so the paused gap is never backfilled.
                bill.scheduleEffectiveDay = Day.string(date)
            }
        }
        try bill.validate(categories: cats)
        let eligible = existing.filter { !retired.contains($0.id) }
        let result = BillReconciliationEngine.reconcile(rule: bill, existingOccurrences: eligible, asOf: date)
        try performTransaction {
            try store.saveBill(bill, in: targetID)
            for id in retired + result.retiredOccurrenceIDs { try store.deleteOccurrence(id, in: targetID) }
            try store.saveExpenses(result.autoExpenses, in: targetID)
            for occurrence in result.newOccurrences { try store.saveOccurrence(occurrence, in: targetID) }
            pendingAuthorization = pendingAuthorization || bill.hasReminder
        }
    }

    func deleteBill(_ id: UUID, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.deleteBill(id, in: bookID ?? activeBookID)
        didCommit()
    }

    /// Nil scope reconciles every card, independent of selection, in one workspace commit.
    func reconcileBills(asOf date: Date = .now, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targets = try bookID.map { [$0] } ?? store.books().map(\.id)
        var results: [(UUID, ReconciliationResult)] = []
        for targetID in targets {
            let currentBills = try store.bills(in: targetID)
            let existing = try store.billOccurrences(in: targetID)
            for bill in currentBills where bill.isActive {
                let result = BillReconciliationEngine.reconcile(rule: bill, existingOccurrences: existing, asOf: date)
                if !result.newOccurrences.isEmpty || !result.retiredOccurrenceIDs.isEmpty { results.append((targetID, result)) }
            }
        }
        if results.isEmpty {
            // Existing/restored reminders are rebuilt even when no ledger rows change.
            publish(try snapshot(preferredID: activeBookID))
            return
        }
        try performTransaction {
            for (targetID, result) in results {
                for id in result.retiredOccurrenceIDs { try store.deleteOccurrence(id, in: targetID) }
                try store.saveExpenses(result.autoExpenses, in: targetID)
                for occurrence in result.newOccurrences { try store.saveOccurrence(occurrence, in: targetID) }
            }
        }
    }

    @discardableResult
    func confirmBillOccurrence(_ occurrenceID: UUID, customDate: Date? = nil,
                               customAmount: Int64? = nil, customNote: String? = nil,
                               in bookID: UUID? = nil) throws -> Expense {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? activeBookID
        guard var occurrence = try store.billOccurrences(in: targetID).first(where: { $0.id == occurrenceID }) else {
            throw BillError.occurrenceNotFound
        }
        guard let rule = try store.bills(in: targetID).first(where: { $0.id == occurrence.billRuleID }) else {
            throw BillError.ruleNotFound
        }
        guard occurrence.status == .pending else { throw BillError.alreadyResolved }
        let expenseDate = customDate ?? Day.date(occurrence.dueDay) ?? .now
        let amount = customAmount ?? rule.amount
        let expense = Expense(id: UUID(), amount: amount, day: Day.string(expenseDate), note: customNote ?? rule.name,
            allocations: [.init(categoryID: rule.categoryID, amount: amount)], source: "bill-confirmed",
            createdAt: expenseDate, bookID: targetID)
        occurrence.status = .recorded
        occurrence.expenseID = expense.id
        occurrence.updatedAt = .now
        try performTransaction {
            try store.save(expense, in: targetID)
            try store.saveOccurrence(occurrence, in: targetID)
        }
        return expense
    }

    func skipBillOccurrence(_ occurrenceID: UUID, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? activeBookID
        guard var occurrence = try store.billOccurrences(in: targetID).first(where: { $0.id == occurrenceID }) else {
            throw BillError.occurrenceNotFound
        }
        guard occurrence.status == .pending else { throw BillError.alreadyResolved }
        occurrence.status = .skipped
        occurrence.updatedAt = .now
        try store.saveOccurrence(occurrence, in: targetID)
        didCommit()
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
        let cats = transactionDepth == 0 && targetID == activeBookID ? categories : try store.categories(in: targetID)
        try expense.validate(categories: cats)
        try validateAdmission(replacing: [expense], in: targetID)
        try store.save(expense, in: targetID)
        if transactionDepth == 0 {
            workspaceExpenses[targetID, default: []].removeAll { $0.id == expense.id }
            workspaceExpenses[targetID, default: []].append(expense)
        }
        if transactionDepth == 0, targetID == activeBookID {
            expenses.removeAll { $0.id == expense.id }
            expenses.append(expense)
            expenses.sort { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
        }
        didCommit(refreshSnapshot: false)
    }

    private func validateAdmission(replacing batch: [Expense], in bookID: UUID) throws {
        guard Set(batch.map(\.id)).count == batch.count else { throw EntryError.corruptStore }
        let replacingIDs = Set(batch.map(\.id))
        var total: Int64 = 0
        for (owner, stored) in workspaceExpenses {
            let amounts = stored.filter {
                !(owner == bookID && replacingIDs.contains($0.id))
            }.map(\.amount)
            total = try Money.checkedSum([total, Money.checkedSum(amounts)])
        }
        _ = try Money.checkedSum([total, Money.checkedSum(batch.map(\.amount))])
    }

    func saveExpenses(_ batch: [Expense], in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? activeBookID
        let cats = try store.categories(in: targetID)
        let normalized = try batch.map { expense -> Expense in
            var value = expense
            value.bookID = targetID
            try value.validate(categories: cats)
            return value
        }
        try validateAdmission(replacing: normalized, in: targetID)
        try performTransaction {
            try store.saveExpenses(normalized, in: targetID)
        }
    }

    func save(_ budget: BudgetVersion, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? budget.bookID ?? activeBookID
        var budget = budget
        budget.bookID = targetID
        try budget.validate(categories: try store.categories(in: targetID))
        try store.save(budget, in: targetID)
        if transactionDepth == 0, targetID == activeBookID {
            budgets.removeAll { $0.id == budget.id || $0.effectiveDay == budget.effectiveDay }
            budgets.append(budget)
            budgets.sort { $0.effectiveDay < $1.effectiveDay }
        }
        didCommit()
    }

    func saveCategory(_ category: ExpenseCategory, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? activeBookID
        let category = try category.validated(against: store.categories(in: targetID))
        try store.saveCategory(category, in: targetID)
        didCommit()
    }

    func deleteCategory(_ id: UUID, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? activeBookID
        guard try !store.expenses(in: targetID).contains(where: { $0.allocations.contains(where: { $0.categoryID == id }) }),
              try !store.bills(in: targetID).contains(where: { $0.categoryID == id }),
              try !store.budgets(in: targetID).contains(where: { $0.categoryLimits.contains(where: { $0.categoryID == id }) }) else {
            throw CategoryError.inUse
        }
        try store.deleteCategory(id, in: targetID)
        didCommit()
    }

    @discardableResult
    func record(text: String, date: Date = .now, id: UUID = UUID(), in bookID: UUID? = nil) throws -> Expense {
        let targetID = bookID ?? activeBookID
        let cats = targetID == activeBookID ? categories : try store.categories(in: targetID)
        let parsed = try ExpenseParser.parse(text, categories: cats.filter { !archivedCategoryIDs.contains($0.id) }, rules: categoryRules)
        guard let categoryID = parsed.categoryID else { throw EntryError.missingCategory }
        let expense = Expense(id: id, amount: parsed.amount, day: Day.string(date), note: parsed.note,
            allocations: [.init(categoryID: categoryID, amount: parsed.amount)], source: "shortcut-text", createdAt: date, bookID: targetID)
        try save(expense, in: targetID)
        return expense
    }

    @discardableResult
    func record(amountInRupiah: Int64, categoryID: UUID, note: String? = nil, date: Date = .now,
                id: UUID = UUID(), source: String = "shortcut", in bookID: UUID? = nil) throws -> Expense {
        let targetID = bookID ?? activeBookID
        guard amountInRupiah > 0 else { throw EntryError.invalidAmount }
        let multiplication = amountInRupiah.multipliedReportingOverflow(by: 100)
        guard !multiplication.overflow, multiplication.partialValue <= Money.maximum else { throw EntryError.invalidAmount }
        let cats = targetID == activeBookID ? categories : try store.categories(in: targetID)
        guard cats.contains(where: { $0.id == categoryID }), !archivedCategoryIDs.contains(categoryID) else { throw EntryError.missingCategory }
        let expense = Expense(id: id, amount: multiplication.partialValue, day: Day.string(date),
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            allocations: [.init(categoryID: categoryID, amount: multiplication.partialValue)],
            source: source, createdAt: date, bookID: targetID)
        try save(expense, in: targetID)
        return expense
    }

    func delete(_ id: UUID, in bookID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = bookID ?? activeBookID
        // Capture the complete affected occurrence state before the commit, so failures still mean no deletion.
        var resultingOccurrences = try store.billOccurrences(in: targetID)
        let deletedAt = Date.now
        for index in resultingOccurrences.indices where resultingOccurrences[index].expenseID == id {
            resultingOccurrences[index].status = .skipped
            resultingOccurrences[index].expenseID = nil
            resultingOccurrences[index].updatedAt = deletedAt
        }
        try store.delete(id, in: targetID, at: deletedAt)
        if transactionDepth == 0 {
            workspaceExpenses[targetID]?.removeAll { $0.id == id }
            workspaceOccurrences[targetID] = resultingOccurrences
            if targetID == activeBookID {
                expenses.removeAll { $0.id == id }
                billOccurrences = resultingOccurrences
            }
        }
        didCommit(refreshSnapshot: false)
    }

    func restoreExpense(_ expense: Expense, occurrences: [BillOccurrence], in bookID: UUID? = nil) throws {
        let owner = bookID ?? expense.bookID ?? activeBookID
        try performTransaction {
            try save(expense, in: owner)
            for occurrence in occurrences {
                guard occurrence.expenseID == expense.id, occurrence.bookID == owner else { throw EntryError.corruptStore }
                try store.saveOccurrence(occurrence, in: owner)
            }
        }
    }
}
