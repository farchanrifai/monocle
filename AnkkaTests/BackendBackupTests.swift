import XCTest
import UIKit
@testable import Ankka

@MainActor
final class BackendBackupTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_790_899_200)

    private func workspace(cardCount: Int = 1, expenseCount: Int = 1) -> WorkspaceBackup {
        let categories = ExpenseCategory.defaults
        var items: [CardBackupItem] = []
        for index in 0..<cardCount {
            let profile = index == 0 ? Card.demo : Card(name: "Card \(index)", colorIndex: index % CardPalette.standard.count)
            var draft = ExpenseDraft()
            draft.cardID = profile.id; draft.date = date; draft.createdAt = date
            let expenses = index == 0 ? (0..<expenseCount).map { value in
                Expense(amount: 100, day: "2026-10-01", note: "Record \(value)",
                        splits: [.init(categoryID: categories[0].id, amount: 100)], createdAt: date, cardID: profile.id)
            } : []
            let budget = BudgetVersion.initial(overallLimit: 450_000_000, startDay: 1, date: date, cardID: profile.id)
            items.append(CardBackupItem(card: profile, categories: categories, expenses: expenses, budgets: [budget], draft: draft, bills: [], billOccurrences: []))
        }
        let preferences = WorkspacePreferences(visibleCardIDs: items.map(\.card.id), cardOrder: items.map(\.card.id), globalCategories: GlobalCategory.defaults)
        return WorkspaceBackup(formatVersion: 7, exportedAt: date, cards: items, preferences: preferences)
    }

    private func withStore(_ run: (ExpenseRepository, FileLocalStateStore, ExpenseService, BackupService, CardArtworkStore, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("backend-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let repository = try ExpenseRepository(url: directory.appendingPathComponent("Ankka.sqlite"))
        defer {
            for store in repository.container.persistentStoreCoordinator.persistentStores { try? repository.container.persistentStoreCoordinator.remove(store) }
            try? FileManager.default.removeItem(at: directory)
        }
        try repository.prepareSampleCard()
        let state = FileLocalStateStore(directory: directory)
        let expenses = try ExpenseService(store: repository)
        let artwork = CardArtworkStore(directory: directory.appendingPathComponent("artwork", isDirectory: true))
        let backups = BackupService(directory: directory, repository: repository, state: state, expenses: expenses, artworkStore: artwork)
        try run(repository, state, expenses, backups, artwork, directory)
    }

    private func seed(_ workspace: WorkspaceBackup, repository: ExpenseRepository, state: FileLocalStateStore, artwork: CardArtworkStore) throws {
        try repository.replace(with: workspace, importArtworks: false)
        for item in workspace.cards { try state.saveDraft(item.draft!, for: item.card.id) }
        try state.saveSettings(workspace.settings)
        try state.saveWorkspacePreferences(workspace.preferences)
        for (filename, data) in workspace.cardArtworks ?? [:] { try artwork.importArtworkData(data, filename: filename) }
    }

    func testCompoundInvalidFileGraphRollsBackBeforeCandidatePublication() throws {
        try withStore { repository, state, expenses, backups, artwork, directory in
            let original = workspace()
            try seed(original, repository: repository, state: state, artwork: artwork)
            try expenses.reload()
            let before = expenses.expenses
            XCTAssertThrowsError(try backups.withRecovery(currentDraft: original.cards[0].draft!, settings: original.settings) {
                try repository.clearExpenses(in: Card.demo.id)
                var broken = original.preferences; broken.cardOrder = [UUID()]
                try state.saveWorkspacePreferences(broken)
            })
            XCTAssertEqual(expenses.expenses, before)
            XCTAssertEqual(try repository.expenses(), before)
            XCTAssertEqual(try state.loadWorkspacePreferences(), original.preferences)
            XCTAssertFalse(backups.requiresRecovery)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("restore-journal.json").path))
        }
    }

    func testEveryDestructiveRetryPreservesUnresolvedJournalAndSafetyBytes() throws {
        try withStore { repository, state, expenses, backups, artwork, directory in
            let original = workspace()
            try seed(original, repository: repository, state: state, artwork: artwork)
            try expenses.reload()
            backups.fault = { if $0 == .settingsWritten { throw BackupError.invalid } }
            backups.recoveryFault = { throw BackupError.invalid }
            let draft = original.cards[0].draft!
            var candidate = original
            candidate.settings.startDay = 15
            candidate.cards[0].expenses = []
            XCTAssertThrowsError(try backups.restoreWorkspace(candidate, currentDraft: draft, settings: original.settings))
            XCTAssertEqual(try state.loadSettings().startDay, 15) // deliberately unresolved partial JSON state
            XCTAssertTrue(backups.requiresRecovery)
            let journalURL = directory.appendingPathComponent("restore-journal.json")
            let journal = try Data(contentsOf: journalURL)
            let safety = try Data(contentsOf: backups.safetyURL)
            let attempts: [() throws -> Void] = [
                { try backups.clearExpenses(currentDraft: draft, settings: original.settings) },
                { _ = try backups.resetAllData(cardName: "New", currentDraft: draft, settings: original.settings) },
                { _ = try backups.startEmptyRealCard(named: "New", currentDraft: draft, settings: original.settings) },
                { _ = try backups.renameRealCard(to: "Renamed", currentDraft: draft, settings: original.settings) },
                { try backups.restoreWorkspace(original, currentDraft: draft, settings: original.settings) },
                { try backups.withRecovery(currentDraft: draft, settings: original.settings) { try state.saveSettings(PrototypeSettings()) } }
            ]
            for attempt in attempts {
                XCTAssertThrowsError(try attempt())
                XCTAssertEqual(try Data(contentsOf: journalURL), journal)
                XCTAssertEqual(try Data(contentsOf: backups.safetyURL), safety)
            }
            try BackupService.recoverIfNeeded(directory: directory, repository: repository, state: state, artworkStore: artwork)
            XCTAssertEqual(try repository.expenses(in: Card.demo.id), original.cards[0].expenses)
            XCTAssertFalse(FileManager.default.fileExists(atPath: journalURL.path))
            XCTAssertEqual(try state.loadSettings(), original.settings)
        }
    }

    func testVersionSevenLargeWorkspaceExportsRestoresClearsAndRecoversAfterReopen() throws {
        try withStore { repository, state, expenses, backups, artwork, directory in
            let original = workspace(cardCount: 101, expenseCount: 10_001)
            try seed(original, repository: repository, state: state, artwork: artwork)
            try expenses.reload()
            let data = try backups.workspaceSnapshot(currentDraft: original.cards[0].draft!, settings: original.settings).encoded()
            let decoded = try WorkspaceBackup.decode(data)
            XCTAssertEqual(decoded.cards.count, 101)
            XCTAssertEqual(decoded.cards.first(where: { $0.card.id == Card.demo.id })?.expenses.count, 10_001)
            let preview = try backups.previewWorkspace(data: data)
            XCTAssertEqual(try preview.canonical(), try decoded.canonical())
            try backups.clearExpenses(currentDraft: original.cards[0].draft!, settings: original.settings)
            XCTAssertTrue(try repository.expenses(in: Card.demo.id).isEmpty)
            XCTAssertEqual(try WorkspaceBackup.decode(Data(contentsOf: backups.safetyURL)).cards.first(where: { $0.card.id == Card.demo.id })?.expenses.count, 10_001)
            // A process stopped after clear must recover the complete old workspace.
            try data.write(to: directory.appendingPathComponent("restore-journal.json"), options: .atomic)
            for store in repository.container.persistentStoreCoordinator.persistentStores { try repository.container.persistentStoreCoordinator.remove(store) }
            let reopened = try ExpenseRepository(url: directory.appendingPathComponent("Ankka.sqlite"))
            defer { for store in reopened.container.persistentStoreCoordinator.persistentStores { try? reopened.container.persistentStoreCoordinator.remove(store) } }
            try BackupService.recoverIfNeeded(directory: directory, repository: reopened, state: state, artworkStore: artwork)
            XCTAssertEqual(try reopened.cards().count, 101)
            XCTAssertEqual(try reopened.expenses(in: Card.demo.id).count, 10_001)
            let reopenedService = try ExpenseService(store: reopened)
            let reopenedBackups = BackupService(directory: directory, repository: reopened, state: state, expenses: reopenedService, artworkStore: artwork)
            let freshSettings = try reopenedBackups.resetAllData(cardName: "Fresh", currentDraft: original.cards[0].draft!, settings: original.settings)
            XCTAssertEqual(try reopened.cards().count, 1)
            XCTAssertEqual(try WorkspaceBackup.decode(Data(contentsOf: reopenedBackups.safetyURL)).cards.count, 101)
            try reopenedBackups.restoreWorkspace(decoded, currentDraft: state.loadDraft(for: freshSettings.card.id), settings: freshSettings)
            XCTAssertEqual(try reopened.cards().count, 101)
            XCTAssertEqual(try reopened.expenses(in: Card.demo.id).count, 10_001)
        }
    }

    func testWorkspaceRejectsIncompleteFinancialAndPreferenceGraphsBeforeWritingRecoveryFiles() throws {
        try withStore { repository, state, expenses, backups, artwork, _ in
            let original = workspace()
            try seed(original, repository: repository, state: state, artwork: artwork)
            try expenses.reload()
            var invalid: [WorkspaceBackup] = []
            var value = original; value.cards[0].card.colorIndex = Int.min; invalid.append(value)
            value = original; value.cards[0].budgets.append(value.cards[0].budgets[0]); invalid.append(value)
            value = original; var budget = value.cards[0].budgets[0]; budget.id = UUID(); value.cards[0].budgets.append(budget); invalid.append(value)
            value = original; value.settings.startDay = 32; invalid.append(value)
            value = original; value.settings.budget = 0; invalid.append(value)
            value = original; value.settings.archivedCategoryIDs = [UUID()]; invalid.append(value)
            value = original; value.preferences.cardOrder = [UUID()]; invalid.append(value)
            value = original; value.preferences.visibleCardIDs.append(value.preferences.visibleCardIDs[0]); invalid.append(value)
            value = original; value.preferences.activeStackID = UUID(); invalid.append(value)
            value = original; value.preferences.cardInactiveCategoryIDs[Card.demo.id] = [UUID()]; invalid.append(value)
            value = original; value.preferences.cardCustomizations[Card.demo.id] = .init(style: .palette(index: Int.min)); invalid.append(value)
            value = original; value.preferences.shortcutInputOrder = [.card, .card, .note, .amount]; invalid.append(value)
            value = original; value.preferences.globalCategories.append(value.preferences.globalCategories[0]); invalid.append(value)
            value = original; value.cards[0].draft?.splitParts = [.init(categoryID: UUID(), amount: "1")]; invalid.append(value)
            value = original; value.cards[0].expenses[0].createdAt = Date(timeIntervalSince1970: .infinity); invalid.append(value)
            let rule = Bill(cardID: Card.demo.id, name: "Bill", amount: 100, categoryID: ExpenseCategory.defaults[0].id, recurrence: .monthly(day: 1), createdAt: date)
            value = original; value.cards[0].bills = [rule]
            value.cards[0].billOccurrences = [BillOccurrence(billRuleID: rule.id, cardID: rule.cardID, dueDay: "2026-10-01", status: .recorded)]
            invalid.append(value)
            value.cards[0].billOccurrences = [BillOccurrence(billRuleID: rule.id, cardID: rule.cardID, dueDay: "2026-10-01"), BillOccurrence(billRuleID: rule.id, cardID: rule.cardID, dueDay: "2026-10-01")]
            invalid.append(value)
            for candidate in invalid {
                XCTAssertThrowsError(try backups.restoreWorkspace(candidate, currentDraft: original.cards[0].draft!, settings: original.settings))
                XCTAssertFalse(FileManager.default.fileExists(atPath: backups.safetyURL.path))
                XCTAssertEqual(try repository.expenses(in: Card.demo.id), original.cards[0].expenses)
            }
        }
    }

    func testLegacySampleSettingsAreExplicitlyNormalizedAndPreviewReadsEveryComponent() throws {
        try withStore { _, _, _, backups, _, _ in
            var original = workspace()
            original.formatVersion = 6
            let real = Card(name: "Real", colorIndex: 3)
            original.cards[0].card = real
            original.cards[0].expenses[0].cardID = real.id
            original.cards[0].budgets[0].cardID = real.id
            original.cards[0].draft?.cardID = real.id
            original.preferences = WorkspacePreferences(visibleCardIDs: [real.id], cardOrder: [real.id])
            let preview = try backups.previewWorkspace(data: original.encoded())
            XCTAssertEqual(preview.settings.card, real)
            XCTAssertEqual(preview.cards[0].card.colorIndex, 3)
            XCTAssertEqual(try preview.canonical(), try original.canonical())
        }
    }

    func testMissingCorruptOversizedAndTraversalArtworkFailWithoutLiveMutation() throws {
        try withStore { repository, state, expenses, backups, artwork, _ in
            var original = workspace()
            original.preferences.cardCustomizations[Card.demo.id] = .init(style: .customPhoto(filename: "photo.png"))
            try state.saveWorkspacePreferences(original.preferences)
            XCTAssertThrowsError(try backups.workspaceSnapshot(currentDraft: original.cards[0].draft!, settings: original.settings))
            var candidates: [WorkspaceBackup] = [original]
            var value = original; value.cardArtworks = ["photo.png": Data("bad image".utf8)]; candidates.append(value)
            value = original; value.cardArtworks = ["photo.png": image(width: CardArtworkStore.maximumDimension + 1, height: 1)]; candidates.append(value)
            value = original; value.preferences.cardCustomizations[Card.demo.id] = .init(style: .customPhoto(filename: "../photo.png")); candidates.append(value)
            for candidate in candidates { XCTAssertThrowsError(try backups.previewWorkspace(data: candidate.encoded())) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: artwork.artworkDirectory.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: backups.safetyURL.path))
            XCTAssertTrue(try repository.expenses(in: Card.demo.id).isEmpty)
            XCTAssertFalse(expenses.isBlocked)
        }
    }

    func testRawArtworkStreamAboveTenMiBRoundTripsLosslessly() throws {
        var original = workspace(cardCount: 3)
        let bytes = noisyImage()
        XCTAssertLessThan(bytes.count, CardArtworkStore.maximumAssetBytes)
        XCTAssertGreaterThan(bytes.count * 3, CardBackup.maximumBytes)
        original.cardArtworks = [:]
        for index in original.cards.indices {
            let filename = "photo-\(index).png"
            original.preferences.cardCustomizations[original.cards[index].card.id] = .init(style: .customPhoto(filename: filename))
            original.cardArtworks?[filename] = bytes
        }
        let data = try original.encoded()
        XCTAssertGreaterThan(data.count, CardBackup.maximumBytes)
        let decoded = try WorkspaceBackup.decode(data)
        XCTAssertEqual(decoded.cardArtworks, original.cardArtworks)
        XCTAssertEqual(try decoded.canonical(), try original.canonical())
        try withStore { repository, state, expenses, backups, artwork, _ in
            try seed(original, repository: repository, state: state, artwork: artwork)
            try expenses.reload()
            let exported = try backups.workspaceSnapshot(currentDraft: original.cards[0].draft!, settings: original.settings).encoded()
            XCTAssertGreaterThan(exported.count, CardBackup.maximumBytes)
            let fresh = try backups.resetAllData(cardName: "Fresh", currentDraft: original.cards[0].draft!, settings: original.settings)
            let safety = try WorkspaceBackup.decode(Data(contentsOf: backups.safetyURL))
            XCTAssertEqual(safety.cardArtworks, original.cardArtworks)
            try backups.restoreWorkspace(decoded, currentDraft: state.loadDraft(for: fresh.card.id), settings: fresh)
            XCTAssertEqual(try state.loadWorkspacePreferences(), original.preferences)
            for (filename, expected) in original.cardArtworks! { XCTAssertEqual(artwork.loadArtworkData(filename: filename), expected) }
        }
    }

    func testPartialArtworkWriteFailureRollsBackDatabasePreferencesAndOriginalBytes() throws {
        try withStore { repository, state, expenses, backups, artwork, _ in
            var original = workspace(cardCount: 2)
            let old = image(width: 10, height: 10)
            original.cardArtworks = ["a.png": old, "b.png": old]
            for (index, name) in ["a.png", "b.png"].enumerated() {
                original.preferences.cardCustomizations[original.cards[index].card.id] = .init(style: .customPhoto(filename: name))
            }
            try seed(original, repository: repository, state: state, artwork: artwork)
            try expenses.reload()
            var candidate = original
            candidate.cards[0].expenses = []
            candidate.cardArtworks = ["a.png": image(width: 20, height: 20), "b.png": image(width: 30, height: 30)]
            var writes = 0
            artwork.writeFault = { _ in writes += 1; if writes == 2 { throw BackupError.invalid } }
            XCTAssertThrowsError(try backups.restoreWorkspace(candidate, currentDraft: original.cards[0].draft!, settings: original.settings))
            XCTAssertFalse(backups.requiresRecovery)
            XCTAssertEqual(try repository.expenses(in: Card.demo.id), original.cards[0].expenses)
            XCTAssertEqual(try state.loadWorkspacePreferences(), original.preferences)
            XCTAssertEqual(artwork.loadArtworkData(filename: "a.png"), old)
            XCTAssertEqual(artwork.loadArtworkData(filename: "b.png"), old)
        }
    }

    func testStartupPreferenceValidationRejectsInvalidCardMetadata() throws {
        var card = Card.demo
        card.colorIndex = Int.min
        XCTAssertThrowsError(try WorkspacePreferences().validate(cards: [card], categoriesByCard: [card.id: ExpenseCategory.defaults]))
        card = .demo; card.name = "\u{0000}"
        XCTAssertThrowsError(try WorkspacePreferences().validate(cards: [card], categoriesByCard: [card.id: ExpenseCategory.defaults]))
    }

    func testRecordStreamRejectsTruncationAndTrailingFrames() throws {
        let data = try workspace().encoded()
        XCTAssertThrowsError(try WorkspaceBackup.decode(data.dropLast()))
        var trailing = data; trailing.append(0)
        XCTAssertThrowsError(try WorkspaceBackup.decode(trailing))
        var length = Data("MONOCLE-BACKUP-7\n".utf8); length.append(Data(repeating: 0xff, count: 8))
        XCTAssertThrowsError(try WorkspaceBackup.decode(length))
    }

    func testFormatEightCarriesModelBFieldsThroughFileAndStore() throws {
        var original = workspace(cardCount: 2)
        original.formatVersion = WorkspaceBackup.currentFormat
        let method = PaymentMethod(name: "BCA debit")
        let tripID = original.cards[1].card.id
        original.preferences.paymentMethods = [method]
        original.preferences.hiddenEntryFields = [.note]
        original.preferences.stacks = [Stack(name: "Travel", cardIDs: [tripID], capLimit: 2_500_000_000, capStartDay: 5)]
        original.cards[1].card.currency = "IDR"
        original.cards[1].card.spendingCurrency = "JPY"
        original.cards[1].card.defaultPaidWithID = method.id
        original.cards[0].expenses[0].paidWithID = method.id
        original.cards[0].expenses[0].originalAmount = 120_000
        original.cards[0].expenses[0].originalCurrency = "JPY"
        original.cards[0].expenses[0].rate = "0.0009"
        original.cards[0].expenses[0].rateSource = .manual
        original.cards[0].budgets[0].totalUntilDay = "2026-12-31"

        let data = try original.encoded()
        XCTAssertTrue(data.starts(with: Data("MONOCLE-BACKUP-8\n".utf8)))
        let decoded = try WorkspaceBackup.decode(data)
        XCTAssertEqual(decoded.formatVersion, 8)
        XCTAssertEqual(try decoded.canonical(), try original.canonical())

        try withStore { repository, state, _, backups, artwork, _ in
            try seed(original, repository: repository, state: state, artwork: artwork)
            XCTAssertEqual(try repository.cards().first { $0.id == tripID }, original.cards[1].card)
            XCTAssertEqual(try repository.expenses(in: Card.demo.id), original.cards[0].expenses)
            XCTAssertEqual(try repository.budgets(in: Card.demo.id).first?.totalUntilDay, "2026-12-31")
            let snapshot = try backups.workspaceSnapshot(currentDraft: original.cards[0].draft!, settings: original.settings)
            XCTAssertEqual(snapshot.formatVersion, 8)
            XCTAssertEqual(snapshot.preferences, original.preferences)
        }

        // Older files still read, and broken references are refused.
        XCTAssertEqual(try WorkspaceBackup.decode(workspace().encoded()).formatVersion, 7)
        var dangling = original; dangling.preferences.paymentMethods = []
        XCTAssertThrowsError(try dangling.encoded())
        var mismatch = original; mismatch.currency = "USD"
        XCTAssertThrowsError(try mismatch.encoded())
        var halfForeign = original; halfForeign.cards[0].expenses[0].rate = nil
        XCTAssertThrowsError(try halfForeign.encoded())
    }

    func testEditingKeepsPaidWithAndCurrencyAndReconvertsANewAmount() throws {
        let method = UUID(), food = ExpenseCategory.defaults[0].id, transport = ExpenseCategory.defaults[1].id
        // ¥100 at Rp107.5 = Rp10,750.
        let expense = Expense(amount: 1_075_000, day: "2026-10-01", note: "Ramen", splits: [.init(categoryID: food, amount: 1_075_000)],
                              createdAt: date, cardID: Card.demo.id, paidWithID: method,
                              originalAmount: 10_000, originalCurrency: "JPY", rate: "107.5", rateSource: .manual)
        var draft = ExpenseDraft(expense: expense)
        XCTAssertEqual(draft.currency, "JPY")
        XCTAssertEqual(draft.amount, "100")
        XCTAssertEqual(try draft.expense(reporting: "IDR"), expense)
        draft.amount = "200"
        let changed = try draft.expense(reporting: "IDR")
        XCTAssertEqual(changed.paidWithID, method)
        XCTAssertEqual(changed.originalAmount, 20_000)
        XCTAssertEqual(changed.amount, 2_150_000)

        // A foreign split converts each part and still adds up exactly; editing brings the parts back in yen.
        var split = ExpenseDraft()
        split.currency = "JPY"; split.rate = "113.59"; split.rateSource = .fetched; split.amount = "1000"
        split.splitParts = [.init(categoryID: food, amount: "333"), .init(categoryID: transport, amount: "667")]
        let saved = try split.expense(reporting: "IDR")
        XCTAssertEqual(saved.amount, 11_359_000)
        XCTAssertEqual(Money.sum(saved.splits.map(\.amount)), saved.amount)
        XCTAssertEqual(ExpenseDraft(expense: saved).splitParts.map(\.amount), ["333", "667"])

        // Without a rate a foreign draft refuses to save.
        split.rate = ""
        XCTAssertThrowsError(try split.expense(reporting: "IDR"))
    }

    private func image(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }.pngData()!
    }

    private func noisyImage() -> Data {
        let width = 1_200, height = 1_200
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        var random: UInt32 = 0x12345678
        for index in pixels.indices where index % 4 != 3 {
            random ^= random << 13; random ^= random >> 17; random ^= random << 5
            pixels[index] = UInt8(truncatingIfNeeded: random)
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return UIImage(cgImage: image).pngData()!
    }
}
