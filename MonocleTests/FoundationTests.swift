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
}

@MainActor
private final class TestExpenseStore: ExpenseStore {
    var values: [Expense] = []
    var budgetValues: [BudgetVersion] = []
    var failWrites = false
    var failReads = false
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
}

@MainActor
private final class TestAuthenticator: DeviceAuthenticating {
    func authenticate(reason: String) async -> Result<Void, AppLockError> { .success(()) }
}
