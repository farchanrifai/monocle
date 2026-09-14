import XCTest
@testable import Monocle

@MainActor
final class FoundationTests: XCTestCase {
    func testSharedTextCommandUpdatesPresentationAndRetriesByIdentity() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: TestState())
        let id = UUID()
        try service.record(text: "Coffee 28k", id: id)
        try service.record(text: "Coffee 32k", id: id)
        XCTAssertEqual(model.expenses.count, 1)
        XCTAssertEqual(model.expenses.first?.amount, 3_200_000)
        XCTAssertEqual(try store.expenses(), model.expenses)
    }

    func testFailedWriteDoesNotPublishOrClearDraft() throws {
        let store = TestExpenseStore()
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: TestState())
        model.draft.amount = "28000"
        model.draft.categoryID = ExpenseCategory.defaults[0].id
        model.showEntry = true
        store.failWrites = true
        model.saveDraft()
        XCTAssertTrue(model.expenses.isEmpty)
        XCTAssertTrue(model.showEntry)
        XCTAssertEqual(model.draft.amount, "28000")
        XCTAssertNotNil(model.error)
        XCTAssertNil(model.toast)
        XCTAssertEqual(model.saveFeedback, 0)
    }

    func testCommittedSaveDoesNotDependOnFollowupRead() throws {
        let store = TestExpenseStore()
        let service = try ExpenseService(store: store)
        store.failReads = true
        let expense = try service.record(text: "Coffee 28k")
        XCTAssertEqual(service.expenses, [expense])
        XCTAssertEqual(store.values, [expense])
        XCTAssertThrowsError(try service.reload())
        XCTAssertEqual(service.expenses, [expense], "Failed reload preserves the last complete snapshot")
    }

    func testFailedDiscardAndSettingsWritePreserveMemory() throws {
        let service = try ExpenseService(store: TestExpenseStore())
        let state = TestState()
        let model = AppModel(expenses: service, state: state)
        model.draft.note = "Keep me"
        state.failWrites = true
        XCTAssertFalse(model.discardDraft())
        XCTAssertEqual(model.draft.note, "Keep me")
        var settings = model.settings
        settings.startDay = 15
        XCTAssertThrowsError(try model.saveSettings(settings))
        XCTAssertEqual(model.settings.startDay, 1)
    }

    func testBudgetSaveCreatesAnEffectiveTransitionVersion() throws {
        let store = TestExpenseStore()
        let service = try ExpenseService(store: store)
        let state = TestState()
        let model = AppModel(expenses: service, state: state)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = try XCTUnwrap(Day.date("2026-09-08", calendar: calendar))
        try model.saveBudget(overallLimit: 500_000_000, startDay: 1, categoryLimits: [], applyToNextCycle: false, date: date, calendar: calendar)
        try model.saveBudget(overallLimit: 600_000_000, startDay: 25, categoryLimits: [], applyToNextCycle: false, date: date, calendar: calendar)
        let transition = try XCTUnwrap(store.budgetValues.first { $0.startDay == 25 })
        XCTAssertEqual(transition.effectiveDay, "2026-10-01")
        XCTAssertEqual(transition.transitionEndDay, "2026-10-25")
        XCTAssertEqual(model.settings.budget, 600_000_000)
        XCTAssertEqual(model.settings.startDay, 25)
        let transitionDate = try XCTUnwrap(Day.date("2026-10-10", calendar: calendar))
        try model.saveBudget(overallLimit: 650_000_000, startDay: 25, categoryLimits: [], applyToNextCycle: false, date: transitionDate, calendar: calendar)
        let adjusted = try XCTUnwrap(store.budgetValues.first { $0.effectiveDay == "2026-10-01" })
        XCTAssertEqual(adjusted.transitionEndDay, "2026-10-25")
    }

    func testExistingStateEncodingReopensAndCorruptionIsPreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var draft = ExpenseDraft()
        draft.note = "Existing draft"
        let settings = PrototypeSettings()
        // Original prototype encoding, before the storage adapter existed.
        try JSONEncoder().encode(draft).write(to: directory.appendingPathComponent("draft.json"))
        try JSONEncoder().encode(settings).write(to: directory.appendingPathComponent("settings.json"))
        let state = FileLocalStateStore(directory: directory)
        XCTAssertEqual(try state.loadDraft(), draft)
        XCTAssertEqual(try state.loadSettings(), settings)
        let corrupt = Data("invalid document".utf8)
        try corrupt.write(to: directory.appendingPathComponent("draft.json"))
        XCTAssertThrowsError(try state.loadDraft())
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("draft.json")), corrupt)
    }

    func testInvalidShortcutDoesNotWrite() throws {
        let store = TestExpenseStore()
        let service = try ExpenseService(store: store)
        XCTAssertThrowsError(try service.record(text: "Something 28k"))
        XCTAssertTrue(store.values.isEmpty)
        XCTAssertTrue(service.expenses.isEmpty)
    }

    func testStructuredShortcutCommandValidatesLiveCategoryAndRetriesByIdentity() throws {
        let store = TestExpenseStore()
        let service = try ExpenseService(store: store)
        let id = UUID()
        try service.record(amountInRupiah: 28_000, categoryID: ExpenseCategory.defaults[0].id, note: "Coffee", date: Date(timeIntervalSinceReferenceDate: 1_000), id: id)
        try service.record(amountInRupiah: 32_000, categoryID: ExpenseCategory.defaults[0].id, note: "Coffee", date: Date(timeIntervalSinceReferenceDate: 1_000), id: id)
        XCTAssertEqual(service.expenses.count, 1)
        XCTAssertEqual(service.expenses.first?.amount, 3_200_000)
        XCTAssertEqual(service.expenses.first?.note, "Coffee")
        XCTAssertThrowsError(try service.record(amountInRupiah: 0, categoryID: ExpenseCategory.defaults[0].id))
        XCTAssertThrowsError(try service.record(amountInRupiah: 28_000, categoryID: UUID()))
        XCTAssertEqual(service.expenses.count, 1)
    }

    func testArchivingPreservesHistoryButHidesCategoryFromNewCapture() throws {
        let state = TestState()
        let service = try ExpenseService(store: TestExpenseStore())
        let model = AppModel(expenses: service, state: state)
        let category = ExpenseCategory.defaults[0]
        try model.archiveCategory(category)
        XCTAssertFalse(model.activeCategories.contains(category))
        XCTAssertEqual(state.savedSettings?.archivedCategoryIDs, [category.id])
        try model.restoreCategory(category)
        XCTAssertTrue(model.activeCategories.contains(category))
    }

    func testKeywordRuleOverridesStarterParserAndArchivedCategoriesAreRejected() throws {
        let service = try ExpenseService(store: TestExpenseStore())
        let rule = CategoryRule(id: UUID(), keyword: "coffee", categoryID: ExpenseCategory.defaults[1].id)
        service.configure(categoryRules: [rule], archivedCategoryIDs: [])
        XCTAssertEqual(try service.record(text: "Coffee 28k").allocations.first?.categoryID, rule.categoryID)
        service.configure(categoryRules: [rule], archivedCategoryIDs: [rule.categoryID])
        XCTAssertThrowsError(try service.record(text: "Coffee 28k"))
        XCTAssertThrowsError(try service.record(amountInRupiah: 28_000, categoryID: rule.categoryID))
    }

    func testAppLockUsesPrivacyShieldThenHonorsTimeout() async {
        let authenticator = TestAuthenticator()
        let lock = AppLockController(timeout: .oneMinute, authenticator: authenticator)
        XCTAssertTrue(lock.needsAuthentication, "A newly launched locked app must not reveal its book")
        let unlockResult = await lock.unlock()
        XCTAssertNoThrow(try unlockResult.get())
        XCTAssertFalse(lock.blocksContent)

        let left = Date(timeIntervalSinceReferenceDate: 1_000)
        lock.suspend(now: left)
        XCTAssertTrue(lock.blocksContent, "The app switcher must get the shield immediately")
        lock.resume(now: left.addingTimeInterval(59))
        XCTAssertFalse(lock.blocksContent, "Returning within the grace period should not prompt again")

        lock.suspend(now: left.addingTimeInterval(60))
        lock.resume(now: left.addingTimeInterval(120))
        XCTAssertTrue(lock.needsAuthentication)
    }

    func testEnablingAppLockAuthenticatesBeforePersisting() async throws {
        let state = TestState()
        let lock = AppLockController(timeout: nil, authenticator: TestAuthenticator())
        let model = AppModel(expenses: try ExpenseService(store: TestExpenseStore()), state: state, appLock: lock)
        let enableResult = await model.setAppLockTimeout(.fiveMinutes)
        XCTAssertNoThrow(try enableResult.get())
        XCTAssertEqual(model.settings.appLockTimeout, .fiveMinutes)
        XCTAssertEqual(state.savedSettings?.appLockTimeout, .fiveMinutes)
        XCTAssertEqual(lock.timeout, .fiveMinutes)
    }

    func testEditingExpenseUntouchedDoesNotRequireDiscardConfirmation() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: TestState())

        let oldExpense = Expense(
            amount: 50_000_00,
            day: "2026-08-15",
            note: "Historical expense",
            allocations: [.init(categoryID: ExpenseCategory.defaults[0].id, amount: 50_000_00)],
            bookID: BookProfile.sample.id
        )
        try service.save(oldExpense)

        // Open edit for this historical expense
        model.edit(oldExpense)
        XCTAssertTrue(model.showEntry)
        XCTAssertTrue(model.draft.editing)

        // Untouched: must NOT require confirmation
        XCTAssertFalse(model.draftNeedsConfirmation)

        // Change note: now MUST require confirmation
        model.draft.note = "Changed note"
        XCTAssertTrue(model.draftNeedsConfirmation)

        // Revert back: no confirmation needed
        model.draft.note = "Historical expense"
        XCTAssertFalse(model.draftNeedsConfirmation)
    }

    func testCrossBookExpenseEditingUntouchedDoesNotRequireDiscardConfirmation() throws {
        let store = try ExpenseRepository(inMemory: true)
        let book1 = try store.createBook(named: "Card 1")
        let book2 = try store.createBook(named: "Card 2")
        let cats2 = try store.categories(in: book2.id)
        let service = try ExpenseService(store: store)
        try service.selectBook(book1.id)
        let model = AppModel(expenses: service, state: TestState())

        let card2Expense = Expense(
            amount: 75_000_00,
            day: "2026-07-20",
            note: "Card 2 coffee",
            allocations: [.init(categoryID: cats2[0].id, amount: 75_000_00)],
            bookID: book2.id
        )
        try service.save(card2Expense, in: book2.id)

        // Edit expense from card 2 while card 1 is active
        model.edit(card2Expense)
        XCTAssertFalse(model.draftNeedsConfirmation)

        // Change amount
        model.draft.amount = "80000"
        XCTAssertTrue(model.draftNeedsConfirmation)
    }
}

@MainActor
private final class TestExpenseStore: ExpenseStore {
    func transaction(_ operation: () throws -> Void) throws {
        let original = (values, budgetValues, billValues, occurrenceValues)
        do { try operation() }
        catch {
            (values, budgetValues, billValues, occurrenceValues) = original
            throw error
        }
    }
    var values: [Expense] = []
    var budgetValues: [BudgetVersion] = []
    var billValues: [BillRule] = []
    var occurrenceValues: [BillOccurrence] = []
    var failWrites = false
    var failReads = false
    func books() throws -> [BookProfile] { [BookProfile.sample] }
    func createBook(named name: String) throws -> BookProfile { BookProfile(name: name) }
    func renameBook(id: UUID, to name: String) throws {}
    func deleteBook(id: UUID) throws {}

    func categories(in bookID: UUID) throws -> [ExpenseCategory] { try categories() }
    func expenses(in bookID: UUID) throws -> [Expense] { try expenses() }
    func budgets(in bookID: UUID) throws -> [BudgetVersion] { try budgets() }
    func bills(in bookID: UUID) throws -> [BillRule] { try bills() }
    func billOccurrences(in bookID: UUID) throws -> [BillOccurrence] { try billOccurrences() }
    func save(_ expense: Expense, in bookID: UUID) throws { try save(expense) }
    func save(_ budget: BudgetVersion, in bookID: UUID) throws { try save(budget) }
    func saveBill(_ bill: BillRule, in bookID: UUID) throws { try saveBill(bill) }
    func deleteBill(_ id: UUID, in bookID: UUID) throws { try deleteBill(id) }
    func saveOccurrence(_ occurrence: BillOccurrence, in bookID: UUID) throws { try saveOccurrence(occurrence) }
    func deleteOccurrence(_ id: UUID, in bookID: UUID) throws { try deleteOccurrence(id) }
    func saveCategory(_ category: ExpenseCategory, in bookID: UUID) throws { try saveCategory(category) }
    func deleteCategory(_ id: UUID, in bookID: UUID) throws { try deleteCategory(id) }

    func categories() throws -> [ExpenseCategory] {
        if failReads { throw EntryError.corruptStore }
        return ExpenseCategory.defaults
    }
    func expenses() throws -> [Expense] {
        if failReads { throw EntryError.corruptStore }
        return values
    }
    func budgets() throws -> [BudgetVersion] {
        if failReads { throw EntryError.corruptStore }
        return budgetValues
    }
    func bills() throws -> [BillRule] {
        if failReads { throw EntryError.corruptStore }
        return billValues
    }
    func billOccurrences() throws -> [BillOccurrence] {
        if failReads { throw EntryError.corruptStore }
        return occurrenceValues
    }
    func save(_ expense: Expense) throws {
        if failWrites { throw EntryError.corruptStore }
        values.removeAll { $0.id == expense.id }
        values.append(expense)
    }
    func save(_ budget: BudgetVersion) throws {
        if failWrites { throw EntryError.corruptStore }
        budgetValues.removeAll { $0.id == budget.id || $0.effectiveDay == budget.effectiveDay }
        budgetValues.append(budget)
    }
    func saveBill(_ bill: BillRule) throws {
        if failWrites { throw EntryError.corruptStore }
        billValues.removeAll { $0.id == bill.id }
        billValues.append(bill)
    }
    func deleteBill(_ id: UUID) throws {
        if failWrites { throw EntryError.corruptStore }
        billValues.removeAll { $0.id == id }
    }
    func saveOccurrence(_ occurrence: BillOccurrence) throws {
        if failWrites { throw EntryError.corruptStore }
        occurrenceValues.removeAll { $0.id == occurrence.id }
        occurrenceValues.append(occurrence)
    }
    func deleteOccurrence(_ id: UUID) throws {
        if failWrites { throw EntryError.corruptStore }
        occurrenceValues.removeAll { $0.id == id }
    }
    func saveCategory(_ category: ExpenseCategory) throws { throw CategoryError.invalidName }
    func deleteCategory(_ id: UUID) throws { throw CategoryError.inUse }
    func delete(_ id: UUID) throws {
        if failWrites { throw EntryError.corruptStore }
        values.removeAll { $0.id == id }
    }
}

@MainActor
private final class TestState: LocalStateStore {
    var failWrites = false
    var savedSettings: PrototypeSettings?
    func loadDraft() throws -> ExpenseDraft { ExpenseDraft() }
    func loadSettings() throws -> PrototypeSettings { PrototypeSettings() }
    func saveDraft(_ draft: ExpenseDraft) throws { if failWrites { throw EntryError.corruptStore } }
    func saveSettings(_ settings: PrototypeSettings) throws { if failWrites { throw EntryError.corruptStore }; savedSettings = settings }

    func loadDraft(for bookID: UUID) throws -> ExpenseDraft { try loadDraft() }
    func saveDraft(_ draft: ExpenseDraft, for bookID: UUID) throws { try saveDraft(draft) }
    func loadWorkspacePreferences() throws -> WorkspacePreferences { WorkspacePreferences() }
    func saveWorkspacePreferences(_ preferences: WorkspacePreferences) throws { if failWrites { throw EntryError.corruptStore } }
}

@MainActor
private final class TestAuthenticator: DeviceAuthenticating {
    func authenticate(reason: String) async -> Result<Void, AppLockError> { .success(()) }
}

extension FoundationTests {
    func testRepeatedSuspensionDoesNotExtendLockGracePeriod() async {
        let lock = AppLockController(timeout: .oneMinute, authenticator: TestAuthenticator())
        _ = await lock.unlock()
        let start = Date.now
        lock.suspend(now: start)
        lock.suspend(now: start.addingTimeInterval(50))
        lock.resume(now: start.addingTimeInterval(65))
        XCTAssertTrue(lock.needsAuthentication)
    }

    func testCardEntityQueryEnumerableAndMatching() async throws {
        let query = CardEntityQuery()
        let all = try await query.allEntities()
        let suggested = try await query.suggestedEntities()
        XCTAssertEqual(all.count, suggested.count)
        XCTAssertFalse(all.isEmpty)

        let first = all[0]
        let byID = try await query.entities(for: [first.id])
        XCTAssertEqual(byID.count, 1)
        XCTAssertEqual(byID.first?.name, first.name)

        let matched = try await query.entities(matching: String(first.name.prefix(3)))
        XCTAssertTrue(matched.contains(where: { $0.id == first.id }))

        let none = try await query.entities(matching: "NonExistentCardXYZ123")
        XCTAssertTrue(none.isEmpty)
    }

    func testExpenseCategoryEntityQueryEnumerableAndMatching() async throws {
        let query = ExpenseCategoryEntityQuery()
        let all = try await query.allEntities()
        let suggested = try await query.suggestedEntities()
        XCTAssertEqual(all.count, suggested.count)
        XCTAssertFalse(all.isEmpty)

        let first = all[0]
        let byID = try await query.entities(for: [first.id])
        XCTAssertEqual(byID.count, 1)
        XCTAssertEqual(byID.first?.name, first.name)

        let matched = try await query.entities(matching: String(first.name.prefix(3)))
        XCTAssertTrue(matched.contains(where: { $0.id == first.id }))

        let none = try await query.entities(matching: "NonExistentCategoryXYZ123")
        XCTAssertTrue(none.isEmpty)
    }

    func testStructuredShortcutSupportsExplicitCardSelection() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
        let secondCard = try store.createBook(named: "Travel Card")
        let service = try ExpenseService(store: store)

        let secondCardCats = try store.categories(in: secondCard.id)
        XCTAssertFalse(secondCardCats.isEmpty)
        let targetCatID = secondCardCats[0].id

        // Record targeting the second card explicitly
        let exp1 = try service.record(amountInRupiah: 45_000, categoryID: targetCatID, note: "Dinner abroad", in: secondCard.id)
        XCTAssertEqual(exp1.bookID, secondCard.id)
        XCTAssertEqual(exp1.amount, 4_500_000)

        // Record with nil card targets default active book
        let defaultCatID = ExpenseCategory.defaults[0].id
        let exp2 = try service.record(amountInRupiah: 20_000, categoryID: defaultCatID, note: "Coffee", in: nil)
        XCTAssertEqual(exp2.bookID, service.activeBookID)
        XCTAssertEqual(exp2.amount, 2_000_000)

        let card2Expenses = try store.expenses(in: secondCard.id)
        XCTAssertEqual(card2Expenses.count, 1)
        XCTAssertEqual(card2Expenses.first?.note, "Dinner abroad")

        let defaultExpenses = try store.expenses(in: service.activeBookID)
        XCTAssertTrue(defaultExpenses.contains(where: { $0.id == exp2.id }))
    }

    func testSpendingSessionManagerLifecycle() {
        let manager = SpendingSessionManager.shared
        manager.startSession(name: "Test Grocery", bookName: "Personal", budgetLimit: 500_000_00)
        XCTAssertTrue(manager.isSessionActive)
        XCTAssertEqual(manager.sessionName, "Test Grocery")
        XCTAssertEqual(manager.sessionBudgetLimit, 500_000_00)
        XCTAssertEqual(manager.sessionSpent, 0)
        XCTAssertEqual(manager.sessionItemCount, 0)

        manager.endSession()
        XCTAssertFalse(manager.isSessionActive)
    }
}

