import CoreData
import UIKit
import XCTest
@testable import Ankka

/// iCloud sync without CloudKit: the repair, the lenient reads and the settings files, on in-memory stores that
/// hold what two devices would have made while apart.
@MainActor
final class CloudSyncTests: XCTestCase {
    private func insert(_ entity: String, _ values: [String: Any?], in repository: ExpenseRepository) -> NSManagedObject {
        let row = NSEntityDescription.insertNewObject(forEntityName: entity, into: repository.context)
        for (key, value) in values { row.setValue(value, forKey: key) }
        return row
    }

    private func expenseRow(_ id: UUID, amount: Int64, splits: [(NSManagedObject?, Int64)], source: String = "manual",
                            in book: NSManagedObject, _ repository: ExpenseRepository) -> NSManagedObject {
        let row = insert("ExpenseRecord", ["id": id, "amount": amount, "day": "2026-11-02", "note": "", "source": source,
                                           "createdAt": Date.now, "book": book], in: repository)
        for (category, value) in splits { _ = insert("AllocationRecord", ["amount": value, "category": category, "expense": row], in: repository) }
        return row
    }

    private let recordName: (NSManagedObject) -> String? = { $0.objectID.uriRepresentation().absoluteString }

    func testBillIDsAreTheSameOnEveryDevice() {
        let rule = Bill(cardID: UUID(), name: "Rent", amount: 100, categoryID: UUID(), recurrence: .monthly(day: 1),
                        recordingMode: .automatic, createdAt: Date.now.addingTimeInterval(-70 * 86_400))
        let first = BillReconciliationEngine.reconcile(rule: rule, existingOccurrences: [])
        let second = BillReconciliationEngine.reconcile(rule: rule, existingOccurrences: [])
        XCTAssertFalse(first.autoExpenses.isEmpty)
        XCTAssertEqual(first.newOccurrences.map(\.id), second.newOccurrences.map(\.id))
        XCTAssertEqual(first.autoExpenses.map(\.id), second.autoExpenses.map(\.id))
        XCTAssertEqual(Set(first.newOccurrences.map(\.id)).count, first.newOccurrences.count)
        XCTAssertEqual(Array(UUID.stable("x").uuidString)[14], "5")
    }

    func testRepairMergesTwoDevicesSampleCardsAndKeepsEveryExpense() throws {
        let repository = try ExpenseRepository(inMemory: true)
        try repository.prepareSampleCard()
        let shared = UUID(), onlyB = UUID()
        let foodA = try XCTUnwrap(repository.categories(in: Card.demo.id).first)
        try repository.save(Expense(id: shared, amount: 500, day: "2026-11-02", note: "Coffee",
                                    splits: [.init(categoryID: foodA.id, amount: 500)]), in: Card.demo.id)
        // Device B seeded the same Sample card and categories, then added an expense of its own.
        let bookB = insert("Book", ["id": Card.demo.id, "name": Card.demo.name, "colorIndex": 0], in: repository)
        let categoriesB = ExpenseCategory.defaults.map {
            insert("CategoryRecord", ["id": $0.id, "name": $0.name, "symbol": $0.symbol, "book": bookB], in: repository)
        }
        _ = expenseRow(shared, amount: 500, splits: [(categoriesB[0], 500)], in: bookB, repository)
        _ = expenseRow(onlyB, amount: 900, splits: [(categoriesB[1], 900)], in: bookB, repository)
        try repository.context.save()

        XCTAssertFalse(try repository.repairSyncDuplicates { _ in nil }, "waits until every copy has reached iCloud")
        XCTAssertTrue(try repository.repairSyncDuplicates(recordName: recordName))

        XCTAssertEqual(try repository.cards().map(\.id), [Card.demo.id])
        XCTAssertEqual(try repository.categories(in: Card.demo.id).count, ExpenseCategory.defaults.count)
        XCTAssertEqual(Set(try repository.expenses(in: Card.demo.id).map(\.id)), [shared, onlyB]) // strict read passes
        XCTAssertFalse(try repository.repairSyncDuplicates(recordName: recordName))
    }

    func testRepairKeepsOneRecordedBillAndDropsTheOtherDevicesExpense() throws {
        let repository = try ExpenseRepository(inMemory: true)
        let card = try repository.createCard(named: "Daily")
        let category = try XCTUnwrap(repository.categories(in: card.id).first)
        let bill = Bill(cardID: card.id, name: "Rent", amount: 700, categoryID: category.id, recurrence: .monthly(day: 1))
        try repository.saveBill(bill, in: card.id)
        let older = UUID(), newer = UUID()
        for id in [older, newer] {
            try repository.save(Expense(id: id, amount: 700, day: "2026-11-01", note: "Rent", splits: [.init(categoryID: category.id, amount: 700)],
                                        source: "bill-automatic", cardID: card.id), in: card.id)
        }
        let rule = try XCTUnwrap(repository.objects("BillRuleRecord").first)
        for (expenseID, age) in [(older, 60.0), (newer, 0.0)] {
            _ = insert("BillOccurrenceRecord", ["id": UUID(), "dueDay": "2026-11-01", "status": "recorded", "expenseID": expenseID,
                                                "createdAt": Date.now, "updatedAt": Date.now.addingTimeInterval(-age), "rule": rule], in: repository)
        }
        try repository.context.save()

        XCTAssertTrue(try repository.repairSyncDuplicates(recordName: recordName))

        let occurrences = try repository.billOccurrences(in: card.id)
        XCTAssertEqual(occurrences.map(\.expenseID), [newer])
        XCTAssertEqual(try repository.expenses(in: card.id).map(\.id), [newer])
    }

    func testSyncedReadsSkipIncompleteRowsInsteadOfFailing() throws {
        let repository = try ExpenseRepository(inMemory: true)
        let card = try repository.createCard(named: "Daily")
        let book = try repository.cardRow(for: card.id)
        let categories = try repository.objects("CategoryRecord")
        let complete = UUID(), mixed = UUID()
        _ = expenseRow(complete, amount: 300, splits: [(categories[0], 300)], in: book, repository)
        _ = expenseRow(UUID(), amount: 200, splits: [(nil, 200)], in: book, repository) // its category hasn't arrived
        _ = expenseRow(mixed, amount: 300, splits: [(categories[0], 100), (categories[1], 300)], in: book, repository) // two edits' splits
        for limit: Int64 in [1_000, 2_000] {
            _ = insert("BudgetRecord", ["id": UUID(), "effectiveDay": "2026-11-01", "overallLimit": limit, "startDay": 1, "book": book], in: repository)
        }
        try repository.context.save()

        XCTAssertThrowsError(try repository.expenses(in: card.id))
        repository.partialGraph = true
        let expenses = try repository.expenses(in: card.id)
        XCTAssertEqual(Set(expenses.map(\.id)), [complete, mixed])
        XCTAssertEqual(expenses.first { $0.id == mixed }?.splits.map(\.amount), [300])
        XCTAssertEqual(try repository.budgets(in: card.id).count, 1)
    }

    func testSettingsFilesSyncButAppLockAndOpenCardStayOnTheDevice() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "sync-\(UUID().uuidString)"))
        let repository = try ExpenseRepository(inMemory: true)
        let artworks = CardArtworkStore(directory: directory.appendingPathComponent("art"))
        let files = CloudFileSync(repository: repository, directory: directory, artworks: artworks, defaults: defaults)
        files.enabled = true
        let state = FileLocalStateStore(directory: directory)

        // Device A's preferences are already in iCloud; this device has its own.
        var remote = WorkspacePreferences(); remote.reportingCurrency = "EUR"
        try repository.saveSyncedFile(CloudFileSync.workspace, data: JSONEncoder().encode(remote), modifiedAt: Date(timeIntervalSince1970: 1_000))
        var local = WorkspacePreferences(); local.reportingCurrency = "USD"
        try state.saveWorkspacePreferences(local)
        var settings = PrototypeSettings(); settings.appLockTimeout = .immediately; settings.startDay = 5
        try state.saveSettings(settings)
        let pixel = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { _ in }.pngData())
        try repository.saveSyncedFile(CloudFileSync.artworkPrefix + "card-photo.png", data: pixel, modifiedAt: .now)

        try files.upload(CloudFileSync.settings, data: Data()) // before the first import nothing goes up
        XCTAssertNil(try repository.syncedFiles()[CloudFileSync.settings])
        try files.adopt()
        XCTAssertEqual(try state.loadWorkspacePreferences().reportingCurrency, "EUR", "iCloud's copy wins on a new device")
        XCTAssertNotNil(artworks.loadArtworkData(filename: "card-photo.png"))
        let uploaded = try XCTUnwrap(repository.syncedFiles()[CloudFileSync.settings])
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: uploaded.data) as? [String: Any])
        XCTAssertNil(object["appLockTimeout"]); XCTAssertNil(object["book"]); XCTAssertEqual(object["startDay"] as? Int, 5)

        // Device A changes the start day later; this device keeps its own App Lock.
        var other = PrototypeSettings(); other.startDay = 9
        try repository.saveSyncedFile(CloudFileSync.settings, data: CloudFileSync.sharedSettings(JSONEncoder().encode(other)), modifiedAt: .now.addingTimeInterval(60))
        XCTAssertTrue(try files.pull())
        XCTAssertEqual(try state.loadSettings().startDay, 9)
        XCTAssertEqual(try state.loadSettings().appLockTimeout, .immediately)
        XCTAssertFalse(try files.pull())

        // A copy this version can't read stays in iCloud and leaves the local file alone.
        try repository.saveSyncedFile(CloudFileSync.workspace, data: Data("not json".utf8), modifiedAt: .now.addingTimeInterval(120))
        XCTAssertFalse(try files.pull())
        XCTAssertEqual(try state.loadWorkspacePreferences().reportingCurrency, "EUR")
    }
}
