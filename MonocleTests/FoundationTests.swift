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
    func save(_ expense: Expense) throws {
        if failWrites { throw EntryError.corruptStore }
        values.removeAll { $0.id == expense.id }
        values.append(expense)
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
