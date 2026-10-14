import XCTest
@testable import Monocle

@MainActor
final class LunaSnapshotTests: XCTestCase {
    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/luna-snapshot-v1.json")
    }

    private func id(_ n: Int) -> UUID { UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")! }

    /// Fixed inputs through the real mapping code. The same file is validated by Luna's server tests (`luna-server/test`).
    func testGoldenSnapshotMatchesFixture() throws {
        let now = Day.date("2026-10-14")!
        let card = Card(id: id(1), name: "Main", currency: "IDR")
        let bill = Bill(id: id(2), cardID: card.id, name: "Rent", amount: 250_000_000, categoryID: id(9), recurrence: .monthly(day: 20), recordingMode: .pending)
        let occurrences = [
            BillOccurrence(id: id(3), billRuleID: bill.id, cardID: card.id, dueDay: "2026-09-20", status: .recorded),
            BillOccurrence(id: id(4), billRuleID: bill.id, cardID: card.id, dueDay: "2026-10-20", status: .pending),
            BillOccurrence(id: id(5), billRuleID: bill.id, cardID: card.id, dueDay: "2025-01-20", status: .recorded), // outside the window
        ]
        let status = BudgetStatus(
            subject: .card(card.id), currency: "IDR", cycle: Cycle(start: Day.date("2026-10-01")!, end: Day.date("2026-11-01")!),
            limit: 800_000_000, spent: 310_000_000, isGoal: false, isTransition: false, pace: .accelerated(percentage: 12),
            projected: 900_000_000, lines: [BudgetLine(id: id(9), name: "Food", limit: 200_000_000, spent: 90_000_000)], approximate: false)
        let food = Expense(id: id(6), amount: 5_000_000, day: "2026-10-03", note: "NOT SENT", splits: [.init(categoryID: id(9), amount: 5_000_000)], cardID: card.id)
        let snapshot = LunaSnapshot(
            storeID: "store-1", revision: 1_791_972_000_000, generatedAt: "2026-10-14T10:00:00Z",
            categories: ["bills", "budgets", "summary"], cards: [.init(id: card.id.uuidString, name: card.name, currency: "IDR")],
            bills: [.init(bill, occurrences: occurrences, now: now)],
            budgets: [.init(name: "Main", status: status)],
            summary: [.init(card: card.id, currency: "IDR", month: "2026-10", expenses: [food], categoryNames: [id(9): "Food"], amount: { $0.amount })])
        let json = String(decoding: try LunaSnapshot.encoder.encode(snapshot), as: UTF8.self)
        XCTAssertFalse(json.contains("NOT SENT"))
        XCTAssertFalse(json.contains("2025-01-20"))
        XCTAssertTrue(json.contains("\"minor_unit_scale\":100") && json.contains("\"due_day\":\"2026-10-20\"") && json.contains("\"store_id\":\"store-1\""))
        if ProcessInfo.processInfo.environment["WRITE_LUNA_FIXTURE"] != nil {
            try json.write(to: fixtureURL, atomically: true, encoding: .utf8)
            return XCTFail("Fixture written; rerun without WRITE_LUNA_FIXTURE")
        }
        XCTAssertEqual(json, try String(contentsOf: fixtureURL, encoding: .utf8))
    }

    func testSnapshotFromTheLiveModelNeverCarriesNotesAndHonorsTheParts() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
        let service = try ExpenseService(store: repo)
        let model = AppModel(expenses: service, state: FileLocalStateStore(directory: tempDir))
        let card = try XCTUnwrap(model.cards.first)
        let category = try XCTUnwrap(try service.categories(for: card.id).first)
        try service.save(Expense(amount: 12_300, day: Day.string(.now), note: "SECRET-NOTE-123", splits: [.init(categoryID: category.id, amount: 12_300)], cardID: card.id), in: card.id)

        let all = LunaSnapshot.build(model: model, storeID: "s", share: Set(LunaSnapshot.Part.allCases))
        let json = String(decoding: try LunaSnapshot.encoder.encode(all), as: UTF8.self)
        XCTAssertFalse(json.contains("SECRET-NOTE-123"))
        XCTAssertTrue(json.contains("\"summary\"") && json.contains("12300"))
        XCTAssertGreaterThanOrEqual(all.cards.count, 1)

        let billsOnly = LunaSnapshot.build(model: model, storeID: "s", share: [.bills])
        let small = String(decoding: try LunaSnapshot.encoder.encode(billsOnly), as: UTF8.self)
        XCTAssertEqual(billsOnly.categories, ["bills"])
        XCTAssertFalse(small.contains("\"budgets\"") || small.contains("\"summary\""))
    }
}
