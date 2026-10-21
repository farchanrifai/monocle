import Foundation
import Observation

/// Value-only boundary. Managed objects never leave the persistence adapter.
@MainActor
protocol ExpenseStore {
    func transaction(_ operation: () throws -> Void) throws
    func cards() throws -> [Card]
    func createCard(named name: String) throws -> Card
    func createCard(named name: String, initialCategories: [GlobalCategory]?) throws -> Card
    func renameCard(id: UUID, to name: String) throws
    func updateCard(_ profile: Card) throws
    func deleteCard(id: UUID) throws

    func categories(in cardID: UUID) throws -> [ExpenseCategory]
    func expenses(in cardID: UUID) throws -> [Expense]
    func expenses(in cardID: UUID, from startDay: String, to endDay: String, limit: Int, offset: Int) throws -> [Expense]
    func budgets(in cardID: UUID) throws -> [BudgetVersion]
    func bills(in cardID: UUID) throws -> [Bill]
    func billOccurrences(in cardID: UUID) throws -> [BillOccurrence]
    func saveExpenses(_ batch: [Expense], in cardID: UUID) throws
    func save(_ expense: Expense, in cardID: UUID) throws
    func save(_ budget: BudgetVersion, in cardID: UUID) throws
    func saveBill(_ bill: Bill, in cardID: UUID) throws
    func deleteBill(_ id: UUID, in cardID: UUID) throws
    func saveOccurrence(_ occurrence: BillOccurrence, in cardID: UUID) throws
    func deleteOccurrence(_ id: UUID, in cardID: UUID) throws
    func saveCategory(_ category: ExpenseCategory, in cardID: UUID) throws
    func deleteCategory(_ id: UUID, in cardID: UUID) throws
    func updateGlobalCategoryMetadata(id: UUID, name: String, symbol: String) throws
    func activateCategory(_ category: GlobalCategory, in cardID: UUID) throws
    func deactivateCategory(_ categoryID: UUID, in cardID: UUID) throws
    func categoryMigrationMapping(to catalog: [GlobalCategory]) throws -> [UUID: [UUID: UUID]]
    func unifyCategoriesToGlobalCatalog(_ catalog: [GlobalCategory]) throws

    func categories() throws -> [ExpenseCategory]
    func expenses() throws -> [Expense]
    func budgets() throws -> [BudgetVersion]
    func bills() throws -> [Bill]
    func billOccurrences() throws -> [BillOccurrence]
    func save(_ expense: Expense) throws
    func save(_ budget: BudgetVersion) throws
    func saveBill(_ bill: Bill) throws
    func deleteBill(_ id: UUID) throws
    func saveOccurrence(_ occurrence: BillOccurrence) throws
    func deleteOccurrence(_ id: UUID) throws
    func delete(_ id: UUID) throws
    func delete(_ id: UUID, in cardID: UUID) throws
    func delete(_ id: UUID, in cardID: UUID, at date: Date) throws
    func saveCategory(_ category: ExpenseCategory) throws
    func deleteCategory(_ id: UUID) throws
    func clearExpenses(in cardID: UUID?) throws
}

extension ExpenseStore {
    func createCard(named name: String) throws -> Card {
        try createCard(named: name, initialCategories: nil)
    }
    func createCard(named name: String, initialCategories: [GlobalCategory]?) throws -> Card {
        try createCard(named: name)
    }
    func updateGlobalCategoryMetadata(id: UUID, name: String, symbol: String) throws {}
    func updateCard(_ profile: Card) throws {}
    func activateCategory(_ category: GlobalCategory, in cardID: UUID) throws {}
    func deactivateCategory(_ categoryID: UUID, in cardID: UUID) throws {}
    func expenses(in cardID: UUID, from startDay: String, to endDay: String, limit: Int, offset: Int) throws -> [Expense] {
        guard Day.date(startDay) != nil, Day.date(endDay) != nil, startDay < endDay,
              (1...1_000).contains(limit), offset >= 0 else { throw EntryError.invalidDate }
        return Array(try expenses(in: cardID).filter { $0.day >= startDay && $0.day < endDay }.dropFirst(offset).prefix(limit))
    }
    func saveExpenses(_ batch: [Expense], in cardID: UUID) throws {
        for expense in batch { try save(expense, in: cardID) }
    }
    func categoryMigrationMapping(to catalog: [GlobalCategory]) throws -> [UUID: [UUID: UUID]] { [:] }
    func unifyCategoriesToGlobalCatalog(_ catalog: [GlobalCategory]) throws {}
    func clearExpenses(in cardID: UUID?) throws {}
    func delete(_ id: UUID, in cardID: UUID, at date: Date) throws { try delete(id, in: cardID) }
    func delete(_ id: UUID, in cardID: UUID) throws {
        guard try expenses(in: cardID).contains(where: { $0.id == id }) else { throw EntryError.corruptStore }
        try delete(id)
    }
}

/// Shared by screen state and App Intents. Main-actor isolation serializes local commands.
@MainActor @Observable
final class ExpenseService {
    var isBlocked = false
    private let store: any ExpenseStore
    let notifications: BillNotificationService
    private(set) var cards: [Card] = []
    private(set) var activeCardID: UUID = Card.demo.id
    private(set) var expenses: [Expense] = []
    private(set) var categories: [ExpenseCategory] = []
    private(set) var budgets: [BudgetVersion] = []
    private(set) var bills: [Bill] = []
    private(set) var billOccurrences: [BillOccurrence] = []
    private(set) var committedRevision: UInt64 = 0
    private(set) var projectionRefreshError: String?
    var onCommit: (@MainActor () -> Void)?
    /// Free/Pro rules. nil leaves every write open (tests, tools); the app sets it from ProStore.
    var plan: Plan? {
        didSet { if plan != oldValue, transactionDepth == 0, let snapshot = try? snapshot(preferredID: activeCardID) { publish(snapshot) } }
    }
    private var categoryRules: [CategoryRule] = []
    private var archivedCategoryIDs: Set<UUID> = []
    private var transactionDepth = 0
    private var pendingAuthorization = false
    private var workspaceExpenses: [UUID: [Expense]] = [:]
    private var workspaceBills: [UUID: [Bill]] = [:]
    private var workspaceOccurrences: [UUID: [BillOccurrence]] = [:]
    private var stagedSnapshot: Snapshot?

    private struct CardState {
        let categories: [ExpenseCategory]
        let expenses: [Expense]
        let budgets: [BudgetVersion]
        let bills: [Bill]
        let occurrences: [BillOccurrence]
    }
    private struct Snapshot {
        let cards: [Card]
        let activeID: UUID
        let states: [UUID: CardState]
    }

    init(store: any ExpenseStore, notifications: BillNotificationService = .shared) throws {
        self.store = store
        self.notifications = notifications
        try reload()
    }

    private func snapshot(preferredID: UUID) throws -> Snapshot {
        let storedCards = try store.cards()
        guard Set(storedCards.map(\.id)).count == storedCards.count,
              let targetID = storedCards.first(where: { $0.id == preferredID })?.id ?? storedCards.first?.id else {
            throw EntryError.corruptStore
        }
        var states: [UUID: CardState] = [:]
        var total: Int64 = 0
        for card in storedCards {
            let categories = try store.categories(in: card.id)
            let expenses = try store.expenses(in: card.id)
            let budgets = try store.budgets(in: card.id)
            let bills = try store.bills(in: card.id)
            let occurrences = try store.billOccurrences(in: card.id)
            for bill in bills { try bill.validate(categories: categories) }
            try BillOccurrence.validate(occurrences, rules: bills, expenses: expenses, cardID: card.id)
            total = try Money.checkedSum([total, Money.checkedSum(expenses.map(\.amount))])
            states[card.id] = CardState(categories: categories, expenses: expenses, budgets: budgets, bills: bills, occurrences: occurrences)
        }
        return Snapshot(cards: storedCards, activeID: targetID, states: states)
    }

    private func publish(_ snapshot: Snapshot, requestAuthorization: Bool = false) {
        guard let active = snapshot.states[snapshot.activeID] else { return }
        workspaceExpenses = snapshot.states.mapValues(\.expenses)
        workspaceBills = snapshot.states.mapValues(\.bills)
        workspaceOccurrences = snapshot.states.mapValues(\.occurrences)
        cards = snapshot.cards
        activeCardID = snapshot.activeID
        categories = active.categories
        expenses = active.expenses
        budgets = active.budgets
        bills = active.bills
        billOccurrences = active.occurrences
        projectionRefreshError = nil
        notifications.reconcile(rules: runnable(snapshot.states.values.flatMap(\.bills)),
                                occurrences: snapshot.states.values.flatMap(\.occurrences),
                                requestAuthorization: requestAuthorization)
    }

    /// Bills as they run under the plan: frozen ones (locked card, past the Free limit) behave as paused.
    private func runnable(_ bills: [Bill]) -> [Bill] {
        guard let plan else { return bills }
        let frozen = plan.frozenBills(bills, cards: cards)
        return bills.map { var bill = $0; if frozen.contains(bill.id) { bill.isActive = false }; return bill }
    }

    /// Throws when the plan keeps this card read-only.
    private func checkWritable(_ cardID: UUID) throws {
        if let plan, plan.isLocked(cardID, in: cards) { throw PlanError.lockedCard }
    }

    /// The Sample card's entry cap and Pro-only foreign currency, for expenses about to be saved on `cardID`.
    private func checkPlan(_ batch: [Expense], in cardID: UUID) throws {
        guard let plan else { return }
        try checkWritable(cardID)
        let stored = workspaceExpenses[cardID] ?? []
        if cardID == Card.demo.id {
            let added = Set(stored.filter { $0.source != "sample" }.map(\.id))
            let new = batch.filter { $0.source != "sample" && !added.contains($0.id) }.count
            if new > 0, added.count + new > Plan.sampleEntries { throw PlanError.sampleLimit }
        }
        if !plan.isPro {
            let before = Dictionary(stored.map { ($0.id, $0.originalCurrency) }, uniquingKeysWith: { a, _ in a })
            // An expense already saved in another currency (from Pro days) can still be edited as it is.
            if batch.contains(where: { $0.originalCurrency != nil && before[$0.id] != $0.originalCurrency }) { throw PlanError.foreignCurrency }
        }
    }

    func reload() throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let current = try snapshot(preferredID: activeCardID)
        stagedSnapshot = nil
        publish(current)
    }

    /// Read/validate a committed candidate without publishing it while a recovery journal remains.
    func stageCommittedState() throws { stagedSnapshot = try snapshot(preferredID: activeCardID) }

    /// A command has already committed when this runs. Refresh errors are separate observable state.
    private func didCommit(requestAuthorization: Bool = false, refreshSnapshot: Bool = true) {
        pendingAuthorization = pendingAuthorization || requestAuthorization
        guard transactionDepth == 0 else { return }
        if let stagedSnapshot {
            self.stagedSnapshot = nil
            publish(stagedSnapshot, requestAuthorization: pendingAuthorization)
        } else if refreshSnapshot {
            do { publish(try snapshot(preferredID: activeCardID), requestAuthorization: pendingAuthorization) }
            catch { projectionRefreshError = error.localizedDescription }
        } else {
            notifications.reconcile(rules: runnable(workspaceBills.values.flatMap { $0 }),
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

    func selectCard(_ id: UUID) throws {
        guard cards.contains(where: { $0.id == id }) else { return }
        publish(try snapshot(preferredID: id))
    }

    func createCard(named name: String, initialCategories: [GlobalCategory]? = nil) throws -> Card {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        if let plan, !plan.isPro, cards.filter({ $0.kind == .real }).count >= Plan.freeCards { throw PlanError.cardLimit }
        let card = try store.createCard(named: name, initialCategories: initialCategories)
        if transactionDepth == 0 {
            cards.append(card)
            workspaceExpenses[card.id] = []
        }
        didCommit()
        return card
    }

    func updateGlobalCategoryMetadata(id: UUID, name: String, symbol: String) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.updateGlobalCategoryMetadata(id: id, name: name, symbol: symbol)
        didCommit()
    }

    func activateCategory(_ category: GlobalCategory, in cardID: UUID) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try checkWritable(cardID)
        try store.activateCategory(category, in: cardID)
        didCommit()
    }

    func deactivateCategory(_ categoryID: UUID, in cardID: UUID) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try checkWritable(cardID)
        try store.deactivateCategory(categoryID, in: cardID)
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

    func renameCard(id: UUID, to name: String) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try checkWritable(id)
        try store.renameCard(id: id, to: name)
        didCommit()
    }

    /// Saves a card's currency and Paid with defaults; its name and look have their own commands.
    func updateCard(_ profile: Card) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try checkWritable(profile.id)
        try profile.validate()
        try store.updateCard(profile)
        didCommit()
    }

    /// Expenses on any card that use this Paid with label.
    func expenseCount(paidWith id: UUID) -> Int {
        workspaceExpenses.values.reduce(0) { $0 + $1.filter { $0.paidWithID == id }.count }
    }

    func deleteCard(id: UUID) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try store.deleteCard(id: id)
        didCommit()
    }

    func expenses(for cardID: UUID) throws -> [Expense] { try store.expenses(in: cardID) }
    func expenses(for cardID: UUID, from startDay: String, to endDay: String, limit: Int = 200, offset: Int = 0) throws -> [Expense] {
        try store.expenses(in: cardID, from: startDay, to: endDay, limit: limit, offset: offset)
    }
    func categories(for cardID: UUID) throws -> [ExpenseCategory] { try store.categories(in: cardID) }
    func budgets(for cardID: UUID) throws -> [BudgetVersion] { try store.budgets(in: cardID) }
    func bills(for cardID: UUID) throws -> [Bill] { try store.bills(in: cardID) }
    func billOccurrences(for cardID: UUID) throws -> [BillOccurrence] { try store.billOccurrences(in: cardID) }

    func saveBill(_ bill: Bill, in cardID: UUID? = nil, asOf date: Date = .now) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = cardID ?? bill.cardID
        var bill = bill
        bill.cardID = targetID
        try checkWritable(targetID)
        let cats = try store.categories(in: targetID)
        let prior = try store.bills(in: targetID).first { $0.id == bill.id }
        if let plan, !plan.isPro, bill.isActive, prior?.isActive != true {
            let running = runnable(workspaceBills.values.flatMap { $0 }).filter { $0.isActive && $0.id != bill.id }
            if running.count >= Plan.freeBills { throw PlanError.billLimit }
        }
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

    func deleteBill(_ id: UUID, in cardID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        try checkWritable(cardID ?? activeCardID)
        try store.deleteBill(id, in: cardID ?? activeCardID)
        didCommit()
    }

    /// Nil scope reconciles every card, independent of selection, in one workspace commit.
    func reconcileBills(asOf date: Date = .now, in cardID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targets = try cardID.map { [$0] } ?? store.cards().map(\.id)
        var results: [(UUID, ReconciliationResult)] = []
        for targetID in targets {
            let currentBills = try store.bills(in: targetID)
            let existing = try store.billOccurrences(in: targetID)
            for bill in runnable(currentBills) where bill.isActive {
                let result = BillReconciliationEngine.reconcile(rule: bill, existingOccurrences: existing, asOf: date)
                if !result.newOccurrences.isEmpty || !result.retiredOccurrenceIDs.isEmpty { results.append((targetID, result)) }
            }
        }
        if results.isEmpty {
            // Existing/restored reminders are rebuilt even when no ledger rows change.
            publish(try snapshot(preferredID: activeCardID))
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
                               in cardID: UUID? = nil) throws -> Expense {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = cardID ?? activeCardID
        try checkWritable(targetID)
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
            splits: [.init(categoryID: rule.categoryID, amount: amount)], source: "bill-confirmed",
            createdAt: expenseDate, cardID: targetID)
        occurrence.status = .recorded
        occurrence.expenseID = expense.id
        occurrence.updatedAt = .now
        try performTransaction {
            try store.save(expense, in: targetID)
            try store.saveOccurrence(occurrence, in: targetID)
        }
        return expense
    }

    func skipBillOccurrence(_ occurrenceID: UUID, in cardID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = cardID ?? activeCardID
        try checkWritable(targetID)
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

    func save(_ expense: Expense, in cardID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = cardID ?? expense.cardID ?? activeCardID
        var expense = expense
        expense.cardID = targetID
        try checkPlan([expense], in: targetID)
        let cats = transactionDepth == 0 && targetID == activeCardID ? categories : try store.categories(in: targetID)
        try expense.validate(categories: cats)
        try validateAdmission(replacing: [expense], in: targetID)
        try store.save(expense, in: targetID)
        if transactionDepth == 0 {
            workspaceExpenses[targetID, default: []].removeAll { $0.id == expense.id }
            workspaceExpenses[targetID, default: []].append(expense)
        }
        if transactionDepth == 0, targetID == activeCardID {
            expenses.removeAll { $0.id == expense.id }
            expenses.append(expense)
            expenses.sort { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
        }
        didCommit(refreshSnapshot: false)
    }

    private func validateAdmission(replacing batch: [Expense], in cardID: UUID) throws {
        guard Set(batch.map(\.id)).count == batch.count else { throw EntryError.corruptStore }
        let replacingIDs = Set(batch.map(\.id))
        var total: Int64 = 0
        for (owner, stored) in workspaceExpenses {
            let amounts = stored.filter {
                !(owner == cardID && replacingIDs.contains($0.id))
            }.map(\.amount)
            total = try Money.checkedSum([total, Money.checkedSum(amounts)])
        }
        _ = try Money.checkedSum([total, Money.checkedSum(batch.map(\.amount))])
    }

    func saveExpenses(_ batch: [Expense], in cardID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = cardID ?? activeCardID
        let cats = try store.categories(in: targetID)
        let normalized = try batch.map { expense -> Expense in
            var value = expense
            value.cardID = targetID
            try value.validate(categories: cats)
            return value
        }
        try checkPlan(normalized, in: targetID)
        try validateAdmission(replacing: normalized, in: targetID)
        try performTransaction {
            try store.saveExpenses(normalized, in: targetID)
        }
    }

    func save(_ budget: BudgetVersion, in cardID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = cardID ?? budget.cardID ?? activeCardID
        try checkWritable(targetID)
        var budget = budget
        budget.cardID = targetID
        try budget.validate(categories: try store.categories(in: targetID))
        try store.save(budget, in: targetID)
        if transactionDepth == 0, targetID == activeCardID {
            budgets.removeAll { $0.id == budget.id || $0.effectiveDay == budget.effectiveDay }
            budgets.append(budget)
            budgets.sort { $0.effectiveDay < $1.effectiveDay }
        }
        didCommit()
    }

    func saveCategory(_ category: ExpenseCategory, in cardID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = cardID ?? activeCardID
        try checkWritable(targetID)
        let category = try category.validated(against: store.categories(in: targetID))
        try store.saveCategory(category, in: targetID)
        didCommit()
    }

    func deleteCategory(_ id: UUID, in cardID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = cardID ?? activeCardID
        try checkWritable(targetID)
        guard try !store.expenses(in: targetID).contains(where: { $0.splits.contains(where: { $0.categoryID == id }) }),
              try !store.bills(in: targetID).contains(where: { $0.categoryID == id }),
              try !store.budgets(in: targetID).contains(where: { $0.categoryLimits.contains(where: { $0.categoryID == id }) }) else {
            throw CategoryError.inUse
        }
        try store.deleteCategory(id, in: targetID)
        didCommit()
    }

    @discardableResult
    func record(text: String, date: Date = .now, id: UUID = UUID(), in cardID: UUID? = nil) throws -> Expense {
        let targetID = cardID ?? activeCardID
        let cats = targetID == activeCardID ? categories : try store.categories(in: targetID)
        let parsed = try ExpenseParser.parse(text, categories: cats.filter { !archivedCategoryIDs.contains($0.id) }, rules: categoryRules)
        guard let categoryID = parsed.categoryID else { throw EntryError.missingCategory }
        let expense = Expense(id: id, amount: parsed.amount, day: Day.string(date), note: parsed.note,
            splits: [.init(categoryID: categoryID, amount: parsed.amount)], source: "shortcut-text", createdAt: date, cardID: targetID)
        try save(expense, in: targetID)
        return expense
    }

    @discardableResult
    func record(minorAmount: Int64, categoryID: UUID, note: String? = nil, date: Date = .now,
                id: UUID = UUID(), source: String = "shortcut", in cardID: UUID? = nil) throws -> Expense {
        let targetID = cardID ?? activeCardID
        guard minorAmount > 0, minorAmount <= Money.maximum else { throw EntryError.invalidAmount }
        let cats = targetID == activeCardID ? categories : try store.categories(in: targetID)
        guard cats.contains(where: { $0.id == categoryID }), !archivedCategoryIDs.contains(categoryID) else { throw EntryError.missingCategory }
        let expense = Expense(id: id, amount: minorAmount, day: Day.string(date),
            note: note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            splits: [.init(categoryID: categoryID, amount: minorAmount)],
            source: source, createdAt: date, cardID: targetID)
        try save(expense, in: targetID)
        return expense
    }

    func delete(_ id: UUID, in cardID: UUID? = nil) throws {
        guard !isBlocked else { throw BackupError.recoveryRequired }
        let targetID = cardID ?? activeCardID
        try checkWritable(targetID)
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
            if targetID == activeCardID {
                expenses.removeAll { $0.id == id }
                billOccurrences = resultingOccurrences
            }
        }
        didCommit(refreshSnapshot: false)
    }

    func restoreExpense(_ expense: Expense, occurrences: [BillOccurrence], in cardID: UUID? = nil) throws {
        let owner = cardID ?? expense.cardID ?? activeCardID
        try performTransaction {
            try save(expense, in: owner)
            for occurrence in occurrences {
                guard occurrence.expenseID == expense.id, occurrence.cardID == owner else { throw EntryError.corruptStore }
                try store.saveOccurrence(occurrence, in: owner)
            }
        }
    }
}
