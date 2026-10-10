import XCTest
@testable import Monocle

@MainActor
final class BackupTests: XCTestCase {
    private func fixture() -> CardBackup {
        let categories = ExpenseCategory.defaults
        var draft = ExpenseDraft(); draft.note = "unfinished"
        var settings = PrototypeSettings(); settings.appLockTimeout = .fiveMinutes
        let budget = BudgetVersion(id: UUID(uuidString: "40000000-0000-0000-0000-000000000002")!, effectiveDay: "2026-09-01", overallLimit: 450_000_000, startDay: 1, categoryLimits: [.init(categoryID: categories[0].id, limit: 100_000_000)])
        return CardBackup(categories: categories, expenses: [Expense(amount: 10000, day: "2026-09-08", note: "Split", allocations: [.init(categoryID: categories[0].id, amount: 4000), .init(categoryID: categories[1].id, amount: 6000)])], draft: draft, settings: settings, budgets: [budget])
    }
    func testRoundTripPreservesIDsSplitsDraftAndSettings() throws {
        let original = fixture()
        let decoded = try CardBackup.decode(original.encoded())
        XCTAssertEqual(decoded.expenses, original.expenses)
        XCTAssertEqual(decoded.draft, original.draft)
        XCTAssertEqual(decoded.categories, original.categories)
        XCTAssertEqual(decoded.settings, original.settings)
        XCTAssertEqual(decoded.budgets, original.budgets)
        XCTAssertEqual(decoded.total, 10000)
        try withStore { repository, state, service, directory in
            let backup = BackupService(directory: directory, repository: repository, state: state, expenses: service)
            try backup.restore(decoded, currentDraft: ExpenseDraft(), settings: PrototypeSettings())
            XCTAssertEqual(try repository.expenses(), original.expenses)
            XCTAssertEqual(try state.loadDraft(), original.draft)
            XCTAssertEqual(try state.loadSettings(), original.settings)
            XCTAssertEqual(try repository.budgets(), original.budgets)
            XCTAssertTrue(FileManager.default.fileExists(atPath: backup.safetyURL.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("restore-journal.json").path))
        }
    }
    func testInvalidBackupsAreRejected() throws {
        var bad = fixture(); bad.formatVersion = 99
        XCTAssertThrowsError(try bad.validate())
        bad = fixture(); bad.expenses.append(bad.expenses[0])
        XCTAssertThrowsError(try bad.validate())
        bad = fixture(); bad.expenses[0].allocations[0].categoryID = UUID()
        XCTAssertThrowsError(try bad.validate())
        bad = fixture(); bad.expenses[0].amount += 1
        XCTAssertThrowsError(try bad.validate())
        bad = fixture(); bad.settings.startDay = 32
        XCTAssertThrowsError(try bad.validate())
        bad = fixture(); bad.draft.categoryID = UUID()
        XCTAssertThrowsError(try bad.validate())
        XCTAssertThrowsError(try CardBackup.decode(Data("broken".utf8)))
    }
    func testFormatTwoBackupWithoutBudgetHistoryGetsAnInitialBudgetOnRestore() throws {
        var legacy = fixture()
        legacy.formatVersion = 2
        legacy.budgets = []
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacy.encoded()) as? [String: Any])
        object.removeValue(forKey: "budgets")
        let decoded = try CardBackup.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(decoded.budgets.isEmpty)
        try withStore { repository, state, service, directory in
            let backup = BackupService(directory: directory, repository: repository, state: state, expenses: service)
            try backup.restore(decoded, currentDraft: ExpenseDraft(), settings: PrototypeSettings())
            XCTAssertEqual(try repository.budgets().count, 1)
        }
    }
    func testEachActivationFailureRollsBackCompleteState() throws {
        for stage in BackupService.Stage.allCases {
            try withStore { repository, state, service, directory in
                let original = fixture()
                try repository.replace(with: original)
                try state.saveDraft(original.draft); try state.saveSettings(original.settings)
                try service.reload()
                let backup = BackupService(directory: directory, repository: repository, state: state, expenses: service)
                backup.fault = { if $0 == stage { throw BackupError.invalid } }
                var candidate = original; candidate.expenses = []; candidate.draft = ExpenseDraft(); candidate.settings.startDay = 15
                XCTAssertThrowsError(try backup.restore(candidate, currentDraft: original.draft, settings: original.settings))
                XCTAssertEqual(try repository.expenses(), original.expenses)
                XCTAssertEqual(try state.loadDraft(), original.draft)
                XCTAssertEqual(try state.loadSettings(), original.settings)
                XCTAssertEqual(service.expenses, original.expenses)
            }
        }
    }
    func testStartupRecoversInterruptedRestoreAndEmptyCardDoesNotReseed() throws {
        try withStore { repository, state, service, directory in
            var original = fixture(); original.expenses = []
            try original.encoded().write(to: directory.appendingPathComponent("restore-journal.json"))
            try repository.replace(with: fixture())
            try BackupService.recoverIfNeeded(directory: directory, repository: repository, state: state)
            try SampleCardSeeder.seedIfNeeded(repository: repository, directory: directory)
            XCTAssertTrue(try repository.expenses().isEmpty)
            XCTAssertEqual(try state.loadDraft(), original.draft)
            try service.reload()
            XCTAssertTrue(service.expenses.isEmpty)
        }
    }
    func testRejectedCandidateLeavesExistingCardUntouched() throws {
        try withStore { repository, state, service, directory in
            let original = fixture(); try repository.replace(with: original); try service.reload()
            var invalid = original; invalid.categories = []
            let backup = BackupService(directory: directory, repository: repository, state: state, expenses: service)
            XCTAssertThrowsError(try backup.restore(invalid, currentDraft: original.draft, settings: original.settings))
            XCTAssertEqual(try repository.expenses(), original.expenses)
            XCTAssertFalse(FileManager.default.fileExists(atPath: backup.safetyURL.path))
        }
    }
    func testSafetyBackupFailureDoesNotTouchActiveData() throws {
        try withStore { repository, state, service, directory in
            let original = fixture(); try repository.replace(with: original); try service.reload()
            let backup = BackupService(directory: directory, repository: repository, state: state, expenses: service)
            try FileManager.default.createDirectory(at: backup.safetyURL, withIntermediateDirectories: true)
            var candidate = original; candidate.expenses = []
            XCTAssertThrowsError(try backup.restore(candidate, currentDraft: original.draft, settings: original.settings))
            XCTAssertEqual(try repository.expenses(), original.expenses)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("restore-journal.json").path))
        }
    }
    func testStartingEmptyRealCardKeepsCategoriesAndCreatesRecoverableSafetyBackup() throws {
        try withStore { repository, state, service, directory in
            let original = fixture()
            try repository.replace(with: original)
            try state.saveDraft(original.draft); try state.saveSettings(original.settings)
            var preferences = WorkspacePreferences()
            preferences.allActivitiesScope = true
            try state.saveWorkspacePreferences(preferences)
            let bill = BillRule(cardID: Card.demo.id, name: "Internet", amount: 10000,
                                categoryID: original.categories[0].id, recurrence: .monthly(day: 1))
            try repository.saveBill(bill)
            try service.reload()

            let backup = BackupService(directory: directory, repository: repository, state: state, expenses: service)
            let settings = try backup.startEmptyRealCard(named: "Farchan's expenses", currentDraft: original.draft, settings: original.settings)

            XCTAssertEqual(settings.card.name, "Farchan's expenses")
            XCTAssertEqual(settings.card.kind, .real)
            XCTAssertTrue(try repository.expenses().isEmpty)
            XCTAssertEqual(try repository.categories(), original.categories.sorted { $0.id.uuidString < $1.id.uuidString })
            XCTAssertFalse(try state.loadDraft().hasContent)
            let safety = try WorkspaceBackup.decode(Data(contentsOf: backup.safetyURL))
            XCTAssertEqual(safety.cards.first?.expenses, original.expenses)
            XCTAssertEqual(safety.cards.first?.bills, [bill])
            XCTAssertTrue(safety.preferences.allActivitiesScope)
            let realBackup = try backup.snapshot(draft: ExpenseDraft(), settings: settings)
            XCTAssertEqual(realBackup.formatVersion, 3)
            XCTAssertEqual(realBackup.cardKind, CardKind.real.rawValue)
            try realBackup.validate()
            let preview = try backup.preview(data: realBackup.encoded())
            XCTAssertEqual(preview.cardID, realBackup.cardID)
            XCTAssertEqual(preview.settings, realBackup.settings)
            XCTAssertEqual(preview.categories, realBackup.categories)
        }
    }

    func testRealCardRenamePreservesExportAndRecords() throws {
        try withStore { repository, state, service, directory in
            let original = fixture()
            try repository.replace(with: original)
            var settings = original.settings
            settings.card = try Card.real(named: "Before")
            try repository.startEmptyRealCard(settings.card)
            let expense = Expense(amount: 10000, day: "2026-09-08", note: "Coffee", allocations: [.init(categoryID: original.categories[0].id, amount: 10000)])
            try repository.save(expense); try state.saveSettings(settings); try service.reload()

            let backup = BackupService(directory: directory, repository: repository, state: state, expenses: service)
            let renamed = try backup.renameRealCard(to: "After", currentDraft: ExpenseDraft(), settings: settings)
            XCTAssertEqual(renamed.card.id, settings.card.id)
            XCTAssertEqual(renamed.card.name, "After")
            XCTAssertEqual(try repository.expenses(), [expense])
            XCTAssertEqual(try backup.snapshot(draft: ExpenseDraft(), settings: renamed).cardName, "After")
        }
    }
    func testRecoveryAfterClosingAndReopeningDiskStore() throws {
        try withStore { repository, state, _, directory in
            let original = fixture()
            try original.encoded().write(to: directory.appendingPathComponent("restore-journal.json"))
            var partial = original; partial.expenses = []; partial.settings.startDay = 15
            try repository.replace(with: partial); try state.saveSettings(partial.settings)
            for store in repository.container.persistentStoreCoordinator.persistentStores { try repository.container.persistentStoreCoordinator.remove(store) }
            let reopened = try ExpenseRepository(url: directory.appendingPathComponent("Monocle.sqlite"))
            defer { for store in reopened.container.persistentStoreCoordinator.persistentStores { try? reopened.container.persistentStoreCoordinator.remove(store) } }
            try BackupService.recoverIfNeeded(directory: directory, repository: reopened, state: state)
            XCTAssertEqual(try reopened.expenses(), original.expenses)
            XCTAssertEqual(try state.loadSettings(), original.settings)
            XCTAssertEqual(try state.loadDraft(), original.draft)
        }
    }
    func testMalformedJournalIsRetainedAndFailsClosed() throws {
        try withStore { repository, state, _, directory in
            let original = fixture(); try repository.replace(with: original)
            let journal = directory.appendingPathComponent("restore-journal.json")
            let corrupt = Data("corrupt journal".utf8); try corrupt.write(to: journal)
            XCTAssertThrowsError(try BackupService.recoverIfNeeded(directory: directory, repository: repository, state: state))
            XCTAssertEqual(try Data(contentsOf: journal), corrupt)
            XCTAssertEqual(try repository.expenses(), original.expenses)
        }
    }
    private func withStore(_ run: (ExpenseRepository, FileLocalStateStore, ExpenseService, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = try ExpenseRepository(url: directory.appendingPathComponent("Monocle.sqlite"))
        defer {
            for store in repository.container.persistentStoreCoordinator.persistentStores { try? repository.container.persistentStoreCoordinator.remove(store) }
            try? FileManager.default.removeItem(at: directory)
        }
        try repository.prepareSampleCard()
        let state = FileLocalStateStore(directory: directory)
        let service = try ExpenseService(store: repository)
        try run(repository, state, service, directory)
    }
}

extension BackupTests {
    func testWorkspaceRestoresEveryCardsDraft() throws {
        try withStore { repository, state, service, directory in
            let second = try repository.createCard(named: "Second")
            try service.reload()
            var firstDraft = ExpenseDraft(); firstDraft.note = "first draft"; firstDraft.cardID = Card.demo.id
            var secondDraft = ExpenseDraft(); secondDraft.note = "second draft"; secondDraft.cardID = second.id
            try state.saveDraft(firstDraft, for: Card.demo.id)
            try state.saveDraft(secondDraft, for: second.id)
            let backups = BackupService(directory: directory, repository: repository, state: state, expenses: service)
            let snapshot = try backups.workspaceSnapshot(currentDraft: secondDraft, settings: PrototypeSettings())
            try state.saveDraft(ExpenseDraft(), for: second.id)
            try backups.restoreWorkspace(snapshot, currentDraft: firstDraft, settings: PrototypeSettings())
            XCTAssertEqual(try state.loadDraft(for: second.id).note, "second draft")
            XCTAssertEqual(try state.loadDraft(for: Card.demo.id).note, "first draft")
        }
    }

    func testWorkspaceRejectsArtworkTraversalAndOrphanOccurrences() throws {
        var workspace = WorkspaceBackup(singleCard: fixture())
        workspace.cardArtworks = ["../settings.json": Data("bad".utf8)]
        XCTAssertThrowsError(try workspace.validate())
        workspace.cardArtworks = nil
        workspace.cards[0].billOccurrences = [BillOccurrence(billRuleID: UUID(), cardID: workspace.cards[0].card.id, dueDay: "2026-09-01")]
        XCTAssertThrowsError(try workspace.validate())
    }

    func testWorkspaceRejectsCrossCardRecords() throws {
        var workspace = WorkspaceBackup(singleCard: fixture())
        workspace.cards[0].expenses[0].cardID = UUID()
        XCTAssertThrowsError(try workspace.validate())

        workspace = WorkspaceBackup(singleCard: fixture())
        workspace.cards[0].draft?.cardID = UUID()
        XCTAssertThrowsError(try workspace.validate())

        workspace = WorkspaceBackup(singleCard: fixture())
        workspace.cards[0].budgets[0].cardID = UUID()
        XCTAssertThrowsError(try workspace.validate())
    }
}
