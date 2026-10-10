import Foundation
import XCTest
@testable import Monocle

@MainActor
final class BackendModelTests: XCTestCase {
    private func fixture() throws -> (URL, ExpenseRepository, ExpenseService, FileLocalStateStore) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = try ExpenseRepository(url: directory.appendingPathComponent("Test.sqlite"))
        try repository.prepareSampleCard()
        let state = FileLocalStateStore(directory: directory)
        var preferences = WorkspacePreferences()
        preferences.globalCategories = GlobalCategory.defaults
        try state.saveWorkspacePreferences(preferences)
        return (directory, repository, try ExpenseService(store: repository), state)
    }

    func testCommittedRealCardSaveClearsOnlyItsDurableDraft() throws {
        let (directory, _, service, state) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = try service.createCard(named: "Real")
        var sampleDraft = ExpenseDraft()
        sampleDraft.cardID = Card.demo.id; sampleDraft.amount = "99"
        try state.saveDraft(sampleDraft, for: Card.demo.id)
        var realDraft = ExpenseDraft()
        realDraft.cardID = real.id; realDraft.amount = "1500"; realDraft.categoryID = ExpenseCategory.defaults[0].id
        try state.saveDraft(realDraft, for: real.id)
        let model = AppModel(expenses: service, state: state, draft: realDraft)
        XCTAssertNil(model.startupError)
        XCTAssertTrue(model.saveDraft())
        XCTAssertEqual(try state.loadDraft(for: Card.demo.id), sampleDraft)
        let cleared = try state.loadDraft(for: real.id)
        XCTAssertFalse(cleared.hasContent)
        XCTAssertEqual(cleared.cardID, real.id)
        XCTAssertNotEqual(cleared.id, realDraft.id)
        XCTAssertEqual(try service.expenses(for: real.id).count, 1)
    }

    func testDraftCleanupFailureStillReportsCommittedSave() throws {
        let (directory, _, service, state) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = try service.createCard(named: "Real")
        var draft = ExpenseDraft()
        draft.cardID = real.id; draft.amount = "1500"; draft.categoryID = ExpenseCategory.defaults[0].id
        let failing = FailingModelState(base: state)
        let model = AppModel(expenses: service, state: failing, draft: draft)
        failing.failClearedDraft = real.id
        XCTAssertTrue(model.saveDraft())
        XCTAssertFalse(model.showEntry)
        XCTAssertTrue(model.error?.contains("Expense saved") == true)
        XCTAssertEqual(try service.expenses(for: real.id).map(\.id), [draft.id])
    }

    func testMalformedWorkspacePreferencesArePreservedAndBlockInitialization() throws {
        let (directory, repository, service, state) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("{broken workspace".utf8)
        let url = directory.appendingPathComponent("workspace.json")
        try bytes.write(to: url)
        let before = try repository.categories()
        let model = AppModel(expenses: service, state: state)
        XCTAssertNotNil(model.startupError)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try repository.categories(), before)
    }

    func testDirectServiceCommitInvalidatesWarmedInactiveCardCache() throws {
        let (directory, _, service, state) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = try service.createCard(named: "Shortcut card")
        let model = AppModel(expenses: service, state: state)
        XCTAssertEqual(model.expenses(for: real.id).count, 0)
        _ = model.activities(selectedCardID: nil, allCards: true)
        let amount: Int64 = 15_000
        let expense = Expense(amount: amount, day: Day.string(.now), note: "", splits: [.init(categoryID: ExpenseCategory.defaults[0].id, amount: amount)], cardID: real.id)
        try service.save(expense)
        XCTAssertEqual(model.expenses(for: real.id).map(\.id), [expense.id])
        XCTAssertTrue(model.activities(selectedCardID: nil, allCards: true).contains(where: { $0.id == expense.id }))
    }

    func testCardCreationPreferenceFailureRollsBackDiskAndMemory() throws {
        let (directory, repository, service, state) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let failing = FailingModelState(base: state)
        let backups = BackupService(directory: directory, repository: repository, state: failing, expenses: service)
        let model = AppModel(expenses: service, state: failing, backups: backups)
        let before = model.workspacePreferences
        failing.failNextWorkspaceWrite = true
        XCTAssertThrowsError(try model.createCard(named: "Must roll back"))
        XCTAssertEqual(try repository.cards().count, 1)
        XCTAssertEqual(model.cards.count, 1)
        XCTAssertEqual(model.workspacePreferences, before)
        XCTAssertEqual(try state.loadWorkspacePreferences(), before)
        XCTAssertFalse(backups.requiresRecovery)
    }

    func testFailedPresentationCommandKeepsPriorStackVisibilityAndOrder() throws {
        let (directory, _, service, state) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = try service.createCard(named: "Real")
        let failing = FailingModelState(base: state)
        let model = AppModel(expenses: service, state: failing)
        let before = model.workspacePreferences
        failing.failNextWorkspaceWrite = true
        model.setCardAlwaysHidden(id: real.id, isHidden: true)
        XCTAssertEqual(model.workspacePreferences, before)
        XCTAssertFalse(model.alwaysHiddenCardIDs.contains(real.id))
        XCTAssertNotNil(model.error)
        failing.failNextWorkspaceWrite = true
        model.moveCardToFront(real.id)
        XCTAssertEqual(model.workspacePreferences, before)
        XCTAssertEqual(try state.loadWorkspacePreferences(), before)
    }

    func testCategoryMigrationWithoutRecoveryCoordinatorRestoresAllLocalStateOnFailure() throws {
        let (directory, repository, service, state) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = try service.createCard(named: "Real")
        let category = ExpenseCategory.defaults[0]
        try repository.saveCategory(.init(id: category.id, name: "Travel snack", symbol: category.symbol), in: real.id)
        try service.reload()
        var sampleDraft = ExpenseDraft(); sampleDraft.cardID = Card.demo.id; sampleDraft.categoryID = category.id
        var realDraft = ExpenseDraft(); realDraft.cardID = real.id; realDraft.categoryID = category.id
        try state.saveDraft(sampleDraft, for: Card.demo.id)
        try state.saveDraft(realDraft, for: real.id)
        try state.saveWorkspacePreferences(WorkspacePreferences())
        let before = try repository.categories(in: real.id)
        let failing = FailingModelState(base: state)
        failing.failNextWorkspaceWrite = true
        let model = AppModel(expenses: service, state: failing, draft: sampleDraft)
        XCTAssertNotNil(model.startupError)
        XCTAssertEqual(try repository.categories(in: real.id), before)
        XCTAssertEqual(try state.loadDraft(for: real.id), realDraft)
        XCTAssertEqual(try state.loadDraft(for: Card.demo.id), sampleDraft)
        XCTAssertTrue(try state.loadWorkspacePreferences().globalCategories.isEmpty)
    }

    func testRestoreAppliesPermanentHiddenStateAndLockImmediately() throws {
        let (directory, repository, service, state) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backups = BackupService(directory: directory, repository: repository, state: state, expenses: service)
        let model = AppModel(expenses: service, state: state, backups: backups)
        var candidate = try backups.workspaceSnapshot(currentDraft: model.draft, settings: model.settings)
        candidate.preferences.alwaysHiddenCardIDs = [Card.demo.id]
        candidate.settings.appLockTimeout = .fiveMinutes
        try model.restoreWorkspaceBackup(candidate)
        XCTAssertEqual(model.alwaysHiddenCardIDs, [Card.demo.id])
        XCTAssertTrue(model.reportingData(for: .stack(id: model.stacks[0].id, name: model.stacks[0].name)).cards.isEmpty)
        XCTAssertEqual(model.appLock.timeout, .fiveMinutes)
        XCTAssertTrue(model.appLock.needsAuthentication)
        model.autoAppearance = true
        XCTAssertEqual(try state.loadWorkspacePreferences().alwaysHiddenCardIDs, [Card.demo.id])
    }

    func testMalformedSettingsBlockInitializationWithoutReplacingFilesOrCategories() throws {
        let (directory, repository, service, state) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var invalid = PrototypeSettings(); invalid.budget = 0; invalid.startDay = 32
        try state.saveSettings(invalid)
        let settingsURL = directory.appendingPathComponent("settings.json")
        let originalBytes = try Data(contentsOf: settingsURL)
        let originalCategories = try repository.categories()
        let model = AppModel(expenses: service, state: state, settings: invalid)
        XCTAssertNotNil(model.startupError)
        XCTAssertEqual(try Data(contentsOf: settingsURL), originalBytes)
        XCTAssertEqual(try repository.categories(), originalCategories)
    }

    func testRenamingAndDeletingSettingsCardPreservesGlobalRulesAndPortableRecovery() throws {
        let (directory, repository, service, state) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        var settings = PrototypeSettings()
        let rule = CategoryRule(id: UUID(), keyword: "coffee", categoryID: ExpenseCategory.defaults[0].id)
        settings.categoryRules = [rule]
        settings.archivedCategoryIDs = [ExpenseCategory.defaults[1].id]
        try state.saveSettings(settings)
        let backups = BackupService(directory: directory, repository: repository, state: state, expenses: service)
        var legacyDraft = ExpenseDraft(); legacyDraft.categoryID = ExpenseCategory.defaults[0].id
        let model = AppModel(expenses: service, state: state, draft: legacyDraft, settings: settings, backups: backups)
        let real = try model.createCard(named: "Real", selectedCategoryIDs: [])
        try model.renameCard(id: Card.demo.id, to: "Renamed sample")
        XCTAssertEqual(try state.loadSettings().card.name, "Renamed sample")
        try backups.workspaceSnapshot(currentDraft: model.draft, settings: model.settings).validate()
        try model.deleteCard(id: Card.demo.id)
        XCTAssertEqual(model.settings.card.id, real.id)
        XCTAssertEqual(model.draft.cardID, real.id)
        XCTAssertNil(model.draft.categoryID)
        XCTAssertEqual(model.settings.categoryRules, [rule])
        XCTAssertEqual(model.settings.archivedCategoryIDs, settings.archivedCategoryIDs)
        XCTAssertTrue(try repository.categories(in: real.id).isEmpty)
        let snapshot = try backups.workspaceSnapshot(currentDraft: model.draft, settings: model.settings)
        try snapshot.validate()
        try WorkspaceBackup.decode(Data(contentsOf: backups.safetyURL)).validate()
        let reopened = try ExpenseRepository(url: directory.appendingPathComponent("Test.sqlite"))
        let reopenedModel = AppModel(expenses: try ExpenseService(store: reopened), state: state, settings: try state.loadSettings())
        XCTAssertNil(reopenedModel.startupError)
        XCTAssertEqual(reopenedModel.settings.categoryRules, [rule])
    }

    func testLegacyStaleCardMetadataNormalizesButVersionSevenRejectsIt() throws {
        let (directory, repository, service, state) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let backups = BackupService(directory: directory, repository: repository, state: state, expenses: service)
        var candidate = try backups.workspaceSnapshot(currentDraft: ExpenseDraft(), settings: PrototypeSettings())
        candidate.settings.card.name = "Stale name"
        XCTAssertThrowsError(try candidate.validate())
        candidate.formatVersion = 6
        XCTAssertEqual(try candidate.normalized().settings.card, .demo)
        let model = AppModel(expenses: service, state: state, settings: candidate.settings)
        XCTAssertNil(model.startupError)
        XCTAssertEqual(model.settings.card, .demo)
    }

    func testWidgetMissingCorruptAndPreviousDayStatesContainNoSampleSpending() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNotNil(WidgetSnapshotStore.loadSnapshot(from: url).unavailableReason)
        try Data("bad JSON".utf8).write(to: url)
        XCTAssertEqual(WidgetSnapshotStore.loadSnapshot(from: url).todaySpending.totalSpent, 0)
        var snapshot = WidgetSnapshot.sample
        snapshot.updatedAt = Day.calendar.date(byAdding: .day, value: -1, to: .now)!
        try WidgetSnapshotStore.writeSnapshot(snapshot, to: url)
        let loaded = WidgetSnapshotStore.loadSnapshot(from: url)
        XCTAssertNotNil(loaded.unavailableReason)
        XCTAssertTrue(loaded.todaySpending.recentTransactions.isEmpty)
        snapshot.updatedAt = .now
        snapshot.reportingDay = Day.string(Day.calendar.date(byAdding: .day, value: -1, to: .now)!)
        try WidgetSnapshotStore.writeSnapshot(snapshot, to: url)
        XCTAssertNotNil(WidgetSnapshotStore.loadSnapshot(from: url).unavailableReason, "A fresh timestamp cannot validate totals for another civil day")
    }

    func testMissingSeedMarkerNeverSeedsARealCard() throws {
        let (directory, repository, service, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let real = try service.createCard(named: "Real")
        try repository.deleteCard(id: Card.demo.id)
        try SampleCardSeeder.seedIfNeeded(repository: repository, directory: directory)
        XCTAssertTrue(try repository.expenses(in: real.id).isEmpty)
    }
}

@MainActor
private final class FailingModelState: LocalStateStore {
    let base: FileLocalStateStore
    var failClearedDraft: UUID?
    var failNextWorkspaceWrite = false
    init(base: FileLocalStateStore) { self.base = base }
    func loadDraft() throws -> ExpenseDraft { try base.loadDraft() }
    func saveDraft(_ value: ExpenseDraft) throws { try saveDraft(value, for: value.cardID ?? Card.demo.id) }
    func loadDraft(for cardID: UUID) throws -> ExpenseDraft { try base.loadDraft(for: cardID) }
    func saveDraft(_ value: ExpenseDraft, for cardID: UUID) throws {
        if cardID == failClearedDraft, !value.hasContent { throw CocoaError(.fileWriteNoPermission) }
        try base.saveDraft(value, for: cardID)
    }
    func loadSettings() throws -> PrototypeSettings { try base.loadSettings() }
    func saveSettings(_ value: PrototypeSettings) throws { try base.saveSettings(value) }
    func loadWorkspacePreferences() throws -> WorkspacePreferences { try base.loadWorkspacePreferences() }
    func saveWorkspacePreferences(_ value: WorkspacePreferences) throws {
        if failNextWorkspaceWrite { failNextWorkspaceWrite = false; throw CocoaError(.fileWriteNoPermission) }
        try base.saveWorkspacePreferences(value)
    }
}
