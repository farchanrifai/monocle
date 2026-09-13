import XCTest
@testable import Monocle

final class SearchTests: XCTestCase {
    private var testBookID: UUID!
    private var testBook2ID: UUID!
    private var testCatFoodID: UUID!
    private var testCatBillsID: UUID!

    override func setUp() {
        super.setUp()
        testBookID = UUID()
        testBook2ID = UUID()
        testCatFoodID = UUID()
        testCatBillsID = UUID()
    }

    func testTextQueryMatchesNoteCaseInsensitive() {
        let expense1 = Expense(id: UUID(), amount: 28_000 * 100, day: Day.string(Date()), categoryID: testCatFoodID, note: "Fore Coffee Latte", bookID: testBookID)
        let expense2 = Expense(id: UUID(), amount: 15_000 * 100, day: Day.string(Date()), categoryID: testCatFoodID, note: "Roti Bakar", bookID: testBookID)

        let query = "coffee"
        XCTAssertTrue(expense1.note.lowercased().contains(query))
        XCTAssertFalse(expense2.note.lowercased().contains(query))
    }

    func testAmountPresetFiltering() {
        let expSmall = Expense(id: UUID(), amount: 25_000 * 100, day: Day.string(Date()), categoryID: testCatFoodID, note: "Snack", bookID: testBookID)
        let expMedium = Expense(id: UUID(), amount: 75_000 * 100, day: Day.string(Date()), categoryID: testCatFoodID, note: "Dinner", bookID: testBookID)
        let expLarge = Expense(id: UUID(), amount: 350_000 * 100, day: Day.string(Date()), categoryID: testCatBillsID, note: "Electricity", bookID: testBookID)

        // Under 50k (< 50,000 * 100)
        XCTAssertTrue(expSmall.amount < 50_000 * 100)
        XCTAssertFalse(expMedium.amount < 50_000 * 100)
        XCTAssertFalse(expLarge.amount < 50_000 * 100)

        // 50k to 200k
        XCTAssertFalse(expSmall.amount >= 50_000 * 100 && expSmall.amount <= 200_000 * 100)
        XCTAssertTrue(expMedium.amount >= 50_000 * 100 && expMedium.amount <= 200_000 * 100)
        XCTAssertFalse(expLarge.amount >= 50_000 * 100 && expLarge.amount <= 200_000 * 100)

        // Over 200k
        XCTAssertFalse(expSmall.amount > 200_000 * 100)
        XCTAssertFalse(expMedium.amount > 200_000 * 100)
        XCTAssertTrue(expLarge.amount > 200_000 * 100)
    }

    func testDatePresetFiltering() {
        let cal = Calendar.current
        let now = Date()

        let todayStr = Day.string(now)
        let todayExpense = Expense(id: UUID(), amount: 50_000 * 100, day: todayStr, categoryID: testCatFoodID, note: "Lunch", bookID: testBookID)

        XCTAssertEqual(todayExpense.day, Day.string(now))
        XCTAssertTrue(cal.isDateInToday(todayExpense.date))

        if let lastMonthDate = cal.date(byAdding: .month, value: -1, to: now) {
            let lastMonthStr = Day.string(lastMonthDate)
            let lastMonthExpense = Expense(id: UUID(), amount: 50_000 * 100, day: lastMonthStr, categoryID: testCatFoodID, note: "Past Lunch", bookID: testBookID)

            XCTAssertTrue(cal.isDate(lastMonthExpense.date, equalTo: lastMonthDate, toGranularity: .month))
            XCTAssertFalse(cal.isDate(lastMonthExpense.date, equalTo: now, toGranularity: .month))
        }
    }

    func testSubtotalAndCardGroupingArithmetic() {
        let exp1 = Expense(id: UUID(), amount: 45_000 * 100, day: Day.string(Date()), categoryID: testCatFoodID, note: "Coffee", bookID: testBookID)
        let exp2 = Expense(id: UUID(), amount: 35_000 * 100, day: Day.string(Date()), categoryID: testCatFoodID, note: "Iced Tea", bookID: testBookID)
        let exp3 = Expense(id: UUID(), amount: 120_000 * 100, day: Day.string(Date()), categoryID: testCatFoodID, note: "Dinner", bookID: testBook2ID)

        let book1Expenses = [exp1, exp2]
        let book1Subtotal = book1Expenses.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(book1Subtotal, 80_000 * 100)

        let book2Expenses = [exp3]
        let book2Subtotal = book2Expenses.reduce(0) { $0 + $1.amount }
        XCTAssertEqual(book2Subtotal, 120_000 * 100)

        let grandTotal = book1Subtotal + book2Subtotal
        XCTAssertEqual(grandTotal, 200_000 * 100)
    }

    func testCategoryAllocationFilterMatchesSingleAndSplitAllocations() {
        let single = Expense(id: UUID(), amount: 50_000 * 100, day: Day.string(Date()), categoryID: testCatFoodID, note: "Burger", bookID: testBookID)

        let split = Expense(
            id: UUID(),
            amount: 100_000 * 100,
            day: Day.string(Date()),
            note: "Combo",
            allocations: [
                Allocation(categoryID: testCatFoodID, amount: 60_000 * 100),
                Allocation(categoryID: testCatBillsID, amount: 40_000 * 100)
            ],
            bookID: testBookID
        )

        // Matching testCatFoodID
        let foodMatches = [single, split].filter {
            $0.categoryID == testCatFoodID || $0.allocations.contains { $0.categoryID == testCatFoodID }
        }
        XCTAssertEqual(foodMatches.count, 2)

        // Matching testCatBillsID
        let billsMatches = [single, split].filter {
            $0.categoryID == testCatBillsID || $0.allocations.contains { $0.categoryID == testCatBillsID }
        }
        XCTAssertEqual(billsMatches.count, 1)
        XCTAssertEqual(billsMatches.first?.id, split.id)
    }
}
