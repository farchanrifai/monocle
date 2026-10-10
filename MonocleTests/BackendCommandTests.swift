import XCTest
@testable import Monocle

@MainActor
final class BackendCommandTests: XCTestCase {
    func testPostCommitReadFailureReturnsCreatedIdentityAndRetainsBatchBillCommits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try ExpenseRepository(url: directory.appendingPathComponent("ledger.sqlite"))
        let initial = try repository.createCard(named: "Initial")
        let category = try XCTUnwrap(repository.categories(in: initial.id).first)
        let adapter = PostCommitReadFailingStore(repository: repository)
        let service = try ExpenseService(store: adapter)
        var publications = 0
        service.onCommit = { publications += 1 }
        adapter.failCommittedReads = true
        let created = try service.createCard(named: "Created")
        XCTAssertTrue(try repository.cards().contains { $0.id == created.id })
        XCTAssertTrue(service.cards.contains { $0.id == created.id })
        XCTAssertNotNil(service.projectionRefreshError)
        XCTAssertEqual(publications, 1)
        let value = Expense(amount: 10_000, day: "2026-01-15", note: "Batch",
            allocations: [.init(categoryID: category.id, amount: 10_000)], cardID: initial.id)
        XCTAssertNoThrow(try service.saveExpenses([value], in: initial.id))
        XCTAssertNoThrow(try service.saveExpenses([value], in: initial.id))
        XCTAssertEqual(try repository.expenses(in: initial.id).map(\.id), [value.id])
        let rule = BillRule(cardID: initial.id, name: "Bill", amount: 1_000, categoryID: category.id,
                            recurrence: .monthly(day: 15), hasReminder: false,
                            createdAt: try XCTUnwrap(Day.date("2026-01-01")))
        XCTAssertNoThrow(try service.saveBill(rule, asOf: try XCTUnwrap(Day.date("2026-01-15"))))
        let occurrence = try XCTUnwrap(repository.billOccurrences(in: initial.id).first)
        let confirmed = try service.confirmBillOccurrence(occurrence.id, in: initial.id)
        XCTAssertEqual(try repository.billOccurrences(in: initial.id).first { $0.id == occurrence.id }?.expenseID, confirmed.id)
        adapter.failCommittedReads = false
        try service.reload()
        XCTAssertNil(service.projectionRefreshError)
        XCTAssertEqual(service.expenses.count, 2)
    }

    func testNotificationRebuildRequestsPermissionAndRemovesDeletedWorkspaceRequests() async throws {
        let client = RecordingBillNotificationClient()
        let notifications = BillNotificationService(client: client)
        let cardID = UUID(), categoryID = UUID()
        let day = try XCTUnwrap(Day.date("2026-10-05"))
        let rule = BillRule(cardID: cardID, name: "Rent", amount: 10_000, categoryID: categoryID,
                            recurrence: .monthly(day: 15), hasReminder: true)
        let restored = BillOccurrence(billRuleID: rule.id, cardID: cardID, dueDay: "2026-10-15")
        client.pending["bill-reminder-obsolete"] = nil
        client.existingIDs = ["bill-reminder-obsolete", "other-feature"]
        notifications.reconcile(rules: [rule], occurrences: [restored], asOf: day, requestAuthorization: true)
        await notifications.waitForReconciliation()
        XCTAssertEqual(client.authorizationRequests, 1)
        XCTAssertEqual(notifications.authorization, .authorized)
        XCTAssertEqual(client.pending.count, 1)
        XCTAssertTrue(client.removed.contains("bill-reminder-obsolete"))
        XCTAssertFalse(client.removed.contains("other-feature"))
        notifications.reconcile(rules: [], occurrences: [], asOf: day)
        await notifications.waitForReconciliation()
        XCTAssertTrue(client.pending.isEmpty)
    }

    func testNotificationDenialFailureAndSystemCapacityAreObservable() async throws {
        let client = RecordingBillNotificationClient()
        let notifications = BillNotificationService(client: client)
        let cardID = UUID(), categoryID = UUID()
        let day = try XCTUnwrap(Day.date("2026-10-05"))
        let rule = BillRule(cardID: cardID, name: "Rent", amount: 10_000, categoryID: categoryID,
                            recurrence: .monthly(day: 15))
        let occurrence = BillOccurrence(billRuleID: rule.id, cardID: cardID, dueDay: "2026-10-15")
        client.grantsPermission = false
        notifications.reconcile(rules: [rule], occurrences: [occurrence], asOf: day, requestAuthorization: true)
        await notifications.waitForReconciliation()
        XCTAssertEqual(notifications.authorization, .denied)
        XCTAssertNotNil(notifications.lastError)
        XCTAssertTrue(client.pending.isEmpty)
        client.status = .authorized
        client.failAdds = true
        notifications.reconcile(rules: [rule], occurrences: [occurrence], asOf: day)
        await notifications.waitForReconciliation()
        XCTAssertNotNil(notifications.lastError)
        client.failAdds = false
        client.existingIDs = ["other-feature"]
        let occurrences = (0..<80).map { offset in
            BillOccurrence(billRuleID: rule.id, cardID: cardID,
                dueDay: Day.string(Day.calendar.date(byAdding: .day, value: offset + 10, to: day)!))
        }
        notifications.reconcile(rules: [rule], occurrences: occurrences, asOf: day)
        await notifications.waitForReconciliation()
        XCTAssertEqual(client.pending.count, 63)
        XCTAssertNil(notifications.lastError)
    }
}

@MainActor
private final class RecordingBillNotificationClient: BillNotificationClient {
    var status: BillReminderAuthorization = .notDetermined
    var grantsPermission = true
    var failAdds = false
    var authorizationRequests = 0
    var existingIDs: [String] = []
    var pending: [String: BillReminder] = [:]
    var removed: [String] = []
    func authorization() async -> BillReminderAuthorization { status }
    func requestAuthorization() async throws -> Bool {
        authorizationRequests += 1
        status = grantsPermission ? .authorized : .denied
        return grantsPermission
    }
    func pendingIdentifiers() async -> [String] { Array(Set(existingIDs + Array(pending.keys))) }
    func add(_ reminder: BillReminder) async throws {
        if failAdds { throw EntryError.corruptStore }
        pending[reminder.identifier] = reminder
    }
    func remove(_ identifiers: [String]) {
        removed += identifiers
        existingIDs.removeAll { identifiers.contains($0) }
        for id in identifiers { pending.removeValue(forKey: id) }
    }
}

/// Only the post-commit workspace refresh fails; real SQLite writes still complete.
@MainActor
private final class PostCommitReadFailingStore: ExpenseStore {
    let repository: ExpenseRepository
    var failCommittedReads = false
    private var wrote = false
    private var depth = 0
    init(repository: ExpenseRepository) { self.repository = repository }
    func transaction(_ operation: () throws -> Void) throws {
        let prior = wrote
        depth += 1
        defer { depth -= 1 }
        do { try repository.transaction(operation); wrote = true }
        catch { wrote = prior; throw error }
    }
    func cards() throws -> [Card] {
        if depth == 0 && wrote && failCommittedReads { throw EntryError.corruptStore }
        return try repository.cards()
    }
    func createCard(named name: String) throws -> Card { try createCard(named: name, initialCategories: nil) }
    func createCard(named name: String, initialCategories: [GlobalCategory]?) throws -> Card {
        let card = try repository.createCard(named: name, initialCategories: initialCategories); wrote = true; return card
    }
    func renameCard(id: UUID, to name: String) throws { try repository.renameCard(id: id, to: name); wrote = true }
    func deleteCard(id: UUID) throws { try repository.deleteCard(id: id); wrote = true }
    func categories(in cardID: UUID) throws -> [ExpenseCategory] { try repository.categories(in: cardID) }
    func expenses(in cardID: UUID) throws -> [Expense] { try repository.expenses(in: cardID) }
    func budgets(in cardID: UUID) throws -> [BudgetVersion] { try repository.budgets(in: cardID) }
    func bills(in cardID: UUID) throws -> [BillRule] { try repository.bills(in: cardID) }
    func billOccurrences(in cardID: UUID) throws -> [BillOccurrence] { try repository.billOccurrences(in: cardID) }
    func save(_ expense: Expense, in cardID: UUID) throws { try repository.save(expense, in: cardID); wrote = true }
    func save(_ budget: BudgetVersion, in cardID: UUID) throws { try repository.save(budget, in: cardID); wrote = true }
    func saveBill(_ bill: BillRule, in cardID: UUID) throws { try repository.saveBill(bill, in: cardID); wrote = true }
    func deleteBill(_ id: UUID, in cardID: UUID) throws { try repository.deleteBill(id, in: cardID); wrote = true }
    func saveOccurrence(_ occurrence: BillOccurrence, in cardID: UUID) throws { try repository.saveOccurrence(occurrence, in: cardID); wrote = true }
    func deleteOccurrence(_ id: UUID, in cardID: UUID) throws { try repository.deleteOccurrence(id, in: cardID); wrote = true }
    func saveCategory(_ category: ExpenseCategory, in cardID: UUID) throws { try repository.saveCategory(category, in: cardID); wrote = true }
    func deleteCategory(_ id: UUID, in cardID: UUID) throws { try repository.deleteCategory(id, in: cardID); wrote = true }
    func updateGlobalCategoryMetadata(id: UUID, name: String, symbol: String) throws { try repository.updateGlobalCategoryMetadata(id: id, name: name, symbol: symbol); wrote = true }
    func activateCategory(_ category: GlobalCategory, in cardID: UUID) throws { try repository.activateCategory(category, in: cardID); wrote = true }
    func deactivateCategory(_ categoryID: UUID, in cardID: UUID) throws { try repository.deactivateCategory(categoryID, in: cardID); wrote = true }
    func categoryMigrationMapping(to catalog: [GlobalCategory]) throws -> [UUID: [UUID: UUID]] { try repository.categoryMigrationMapping(to: catalog) }
    func unifyCategoriesToGlobalCatalog(_ catalog: [GlobalCategory]) throws { try repository.unifyCategoriesToGlobalCatalog(catalog); wrote = true }
    func categories() throws -> [ExpenseCategory] { try repository.categories() }
    func expenses() throws -> [Expense] { try repository.expenses() }
    func budgets() throws -> [BudgetVersion] { try repository.budgets() }
    func bills() throws -> [BillRule] { try repository.bills() }
    func billOccurrences() throws -> [BillOccurrence] { try repository.billOccurrences() }
    func save(_ expense: Expense) throws { try repository.save(expense); wrote = true }
    func save(_ budget: BudgetVersion) throws { try repository.save(budget); wrote = true }
    func saveBill(_ bill: BillRule) throws { try repository.saveBill(bill); wrote = true }
    func deleteBill(_ id: UUID) throws { try repository.deleteBill(id); wrote = true }
    func saveOccurrence(_ occurrence: BillOccurrence) throws { try repository.saveOccurrence(occurrence); wrote = true }
    func deleteOccurrence(_ id: UUID) throws { try repository.deleteOccurrence(id); wrote = true }
    func delete(_ id: UUID) throws { try repository.delete(id); wrote = true }
    func delete(_ id: UUID, in cardID: UUID) throws { try repository.delete(id, in: cardID); wrote = true }
    func saveCategory(_ category: ExpenseCategory) throws { try repository.saveCategory(category); wrote = true }
    func deleteCategory(_ id: UUID) throws { try repository.deleteCategory(id); wrote = true }
    func clearExpenses(in cardID: UUID?) throws { try repository.clearExpenses(in: cardID); wrote = true }
}
