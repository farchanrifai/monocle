import XCTest
@testable import Monocle

final class MonocleTests: XCTestCase {
    func testMoneyParsingIsExactAndRejectsAmbiguity() throws {
        XCTAssertEqual(try Money.parse("28k"), 2_800_000)
        XCTAssertEqual(try Money.parse("28.5k"), 2_850_000)
        XCTAssertEqual(try Money.parse("28,5k"), 2_850_000)
        XCTAssertEqual(try Money.parse("Rp28.000"), 2_800_000)
        for invalid in ["0", "-28000", "28,000", "28.5", "1e6", "coffee", "9999999999999999999", "0.0001k"] {
            XCTAssertThrowsError(try Money.parse(invalid), invalid)
        }
    }
    func testTextParsingNeverChoosesBetweenConflictingCategories() throws {
        let coffee = try ExpenseParser.parse("Coffee 28k", categories: ExpenseCategory.defaults)
        XCTAssertEqual(coffee.amount, 2_800_000)
        XCTAssertEqual(coffee.note, "Coffee")
        XCTAssertEqual(coffee.categoryID, ExpenseCategory.defaults[0].id)
        XCTAssertNil(try ExpenseParser.parse("Coffee taxi 28k", categories: ExpenseCategory.defaults).categoryID)
        XCTAssertNil(try ExpenseParser.parse("Something 28k", categories: ExpenseCategory.defaults).categoryID)
        XCTAssertThrowsError(try ExpenseParser.parse("Coffee 28k 30k", categories: ExpenseCategory.defaults))
    }
    func testSplitValidationAndDateValidation() throws {
        let a = ExpenseCategory.defaults[0].id
        let b = ExpenseCategory.defaults[1].id
        var expense = Expense(amount: 10000, day: "2026-09-07", note: "", allocations: [.init(categoryID: a, amount: 4000), .init(categoryID: b, amount: 6000)])
        try expense.validate(categories: ExpenseCategory.defaults)
        expense.allocations[1].amount = 6001
        XCTAssertThrowsError(try expense.validate(categories: ExpenseCategory.defaults))
        expense.allocations[1].amount = 6000
        expense.day = "2026-02-30"
        XCTAssertThrowsError(try expense.validate(categories: ExpenseCategory.defaults))
    }
    func testMonthEndClampingAndLeapYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let february = try XCTUnwrap(Day.date("2024-02-29", calendar: calendar))
        let leap = BudgetCycle.containing(february, startDay: 31, calendar: calendar)
        XCTAssertEqual(Day.string(leap.start, calendar: calendar), "2024-02-29")
        XCTAssertEqual(Day.string(leap.end, calendar: calendar), "2024-03-31")
        let ordinary = BudgetCycle.containing(try XCTUnwrap(Day.date("2026-02-27", calendar: calendar)), startDay: 31, calendar: calendar)
        XCTAssertEqual(Day.string(ordinary.start, calendar: calendar), "2026-01-31")
        XCTAssertEqual(Day.string(ordinary.end, calendar: calendar), "2026-02-28")
    }
    @MainActor
    func testStoreRoundTripUpsertAndInvalidSavePreservation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Test.sqlite")
        var expense = Expense(amount: 2_800_000, day: "2026-09-07", note: "Coffee", allocations: [.init(categoryID: ExpenseCategory.defaults[0].id, amount: 2_800_000)])
        do {
            let store = try ExpenseRepository(url: url)
            try store.prepareSampleBook()
            try store.save(expense)
            try store.save(expense)
            XCTAssertEqual(try store.expenses().count, 1)
            expense.note = "Morning coffee"
            try store.save(expense)
            var invalid = expense; invalid.amount += 100
            XCTAssertThrowsError(try store.save(invalid))
            XCTAssertEqual(try store.expenses().first?.note, "Morning coffee")
        }
        let reopened = try ExpenseRepository(url: url)
        XCTAssertEqual(try reopened.expenses(), [expense])
        try reopened.delete(expense.id)
        XCTAssertTrue(try reopened.expenses().isEmpty)
        try reopened.prepareSampleBook()
        XCTAssertTrue(try reopened.expenses().isEmpty, "An empty book must not trigger reseeding")
    }
    func testDraftSurvivesCodingWithInputModeAndIdentity() throws {
        var draft = ExpenseDraft()
        draft.amount = "28000"; draft.text = "Coffee 28k"; draft.mode = .text
        draft.categoryID = ExpenseCategory.defaults[0].id
        let restored = try JSONDecoder().decode(ExpenseDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored, draft)
    }
}
