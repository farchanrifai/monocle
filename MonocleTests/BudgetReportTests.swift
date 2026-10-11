import XCTest
@testable import Monocle

final class BudgetReportTests: XCTestCase {
    private let food = ExpenseCategory.defaults[0], transport = ExpenseCategory.defaults[1]
    private var now: Date { Day.date("2026-10-11")! }

    private func expense(_ amount: Int64, _ day: String, _ category: ExpenseCategory? = nil) -> Expense {
        Expense(amount: amount, day: day, note: "", splits: [.init(categoryID: (category ?? food).id, amount: amount)])
    }

    private func input(_ card: Card = Card(name: "Daily"), budgets: [BudgetVersion], expenses: [Expense], currency: String = "IDR",
                       amount: ((Expense) -> Int64)? = nil) -> BudgetCardInput {
        BudgetCardInput(card: card, budgets: budgets, expenses: expenses, categories: [food, transport], currency: currency, amount: amount ?? { $0.amount })
    }

    func testCardStatusSpentPaceProjectionAndCategories() throws {
        var budget = BudgetVersion(effectiveDay: "2026-10-01", overallLimit: 3_100_00, startDay: 1)
        budget.categoryLimits = [.init(categoryID: food.id, limit: 1_000_00)]
        let status = try XCTUnwrap(BudgetReport.card(
            input(budgets: [budget], expenses: [expense(400_00, "2026-10-02"), expense(600_00, "2026-10-10", transport), expense(999_00, "2026-09-30")]),
            now: now))
        XCTAssertEqual(status.limit, 3_100_00)
        XCTAssertEqual(status.spent, 1_000_00)                 // September expense is outside the cycle
        XCTAssertEqual(status.remaining, 2_100_00)
        XCTAssertEqual(status.projected, 281_818)              // 100000 over 11 of 31 days, scaled from the total, not the daily average
        XCTAssertEqual(status.pace, .underPace(percentage: 9)) // expected 310000 * 11/31 = 110000
        XCTAssertEqual(status.lines.map(\.name), ["Food & Drink", "Transport"])   // limited category first
        XCTAssertEqual(status.lines.map(\.spent), [400_00, 600_00])
        XCTAssertEqual(status.lines.first?.limit, 1_000_00)
        XCTAssertNil(status.lines.last?.limit)
    }

    func testNoBudgetGivesNoStatus() {
        XCTAssertNil(BudgetReport.card(input(budgets: [], expenses: []), now: now))
    }

    func testCardHistoryWalksVersionsOldestFirst() throws {
        let old = BudgetVersion(effectiveDay: "2026-08-01", overallLimit: 1_000_00, startDay: 1)
        let new = BudgetVersion(effectiveDay: "2026-10-01", overallLimit: 2_000_00, startDay: 1)
        let rows = BudgetReport.cardHistory(
            input(budgets: [old, new], expenses: [expense(1_500_00, "2026-08-15"), expense(900_00, "2026-09-02"), expense(100_00, "2026-10-05")]),
            count: 6, now: now)
        XCTAssertEqual(rows.map(\.limit), [1_000_00, 1_000_00, 2_000_00])        // stops where the budget history starts
        XCTAssertEqual(rows.map(\.spent), [1_500_00, 900_00, 100_00])
        XCTAssertEqual(rows.map(\.isOver), [true, false, false])
        XCTAssertEqual(rows.map(\.isCurrent), [false, false, true])
        XCTAssertEqual(BudgetReport.cardHistory(input(budgets: [old, new], expenses: []), count: 2, now: now).count, 2)
    }

    func testExpiredGoalHistoryDoesNotRepeatTheGoal() throws {
        let monthly = BudgetVersion(effectiveDay: "2026-07-01", overallLimit: 1_000_00, startDay: 1)
        let goal = BudgetVersion(effectiveDay: "2026-08-01", overallLimit: 5_000_00, startDay: 1, totalUntilDay: "2026-09-30")
        let rows = BudgetReport.cardHistory(input(budgets: [monthly, goal], expenses: [expense(700_00, "2026-08-10"), expense(800_00, "2026-09-20")]),
                                            count: 6, now: now)
        // July (monthly), Aug-Sep (one goal period), Oct (monthly again).
        XCTAssertEqual(rows.map(\.limit), [1_000_00, 5_000_00, 1_000_00])
        XCTAssertEqual(rows.map(\.isGoal), [false, true, false])
        XCTAssertEqual(rows[1].spent, 1_500_00)
    }

    // MARK: Stack

    private func stackInput(cap: Int64? = nil, cards: [BudgetCardInput], reporting: String = "IDR") -> BudgetStackInput {
        BudgetStackInput(stack: Stack(name: "Home", cardIDs: cards.map(\.card.id), capLimit: cap), cards: cards, reportingCurrency: reporting,
                         convert: { amount, from, to in from == "USD" && to == "IDR" ? amount * 16_000 : nil })
    }

    func testStackSumsCardBudgetsAndSkipsGoals() throws {
        let a = input(Card(name: "A"), budgets: [BudgetVersion(effectiveDay: "2026-01-01", overallLimit: 1_000_00, startDay: 1)], expenses: [expense(250_00, "2026-10-03")])
        let b = input(Card(name: "B"), budgets: [BudgetVersion(effectiveDay: "2026-01-01", overallLimit: 2_000_00, startDay: 1)], expenses: [expense(100_00, "2026-10-04")])
        let goal = input(Card(name: "Goal"), budgets: [BudgetVersion(effectiveDay: "2026-09-01", overallLimit: 9_000_00, startDay: 1, totalUntilDay: "2027-01-31")],
                         expenses: [expense(50_00, "2026-10-05")])
        let status = try XCTUnwrap(BudgetReport.stack(stackInput(cards: [a, b, goal]), now: now))
        XCTAssertEqual(status.limit, 3_000_00)
        XCTAssertEqual(status.spent, 400_00)                   // the goal card still counts as spending
        XCTAssertEqual(status.lines.map(\.name), ["A", "B", "Goal"])
        XCTAssertNil(status.lines[2].limit)
        XCTAssertFalse(status.approximate)

        let capped = try XCTUnwrap(BudgetReport.stack(stackInput(cap: 500_00, cards: [a, b]), now: now))
        XCTAssertEqual(capped.limit, 500_00)
    }

    func testStackConvertsForeignBudgetAndFlagsIt() throws {
        let usd = input(Card(name: "Trip", currency: "USD"), budgets: [BudgetVersion(effectiveDay: "2026-01-01", overallLimit: 10_00, startDay: 1)],
                        expenses: [expense(8_000_00, "2026-10-03")], currency: "USD", amount: { _ in 5_00 })
        let status = try XCTUnwrap(BudgetReport.stack(stackInput(cards: [usd]), now: now))
        XCTAssertEqual(status.limit, 160_000_00)
        XCTAssertEqual(status.spent, 8_000_00)                 // reporting amounts
        XCTAssertEqual(status.lines.first?.spent, 5_00)        // card currency
        XCTAssertTrue(status.approximate)
    }

    func testStackHistoryUsesBudgetsThatAppliedThen() throws {
        let a = input(Card(name: "A"), budgets: [BudgetVersion(effectiveDay: "2026-08-01", overallLimit: 1_000_00, startDay: 1),
                                                 BudgetVersion(effectiveDay: "2026-10-01", overallLimit: 1_500_00, startDay: 1)],
                      expenses: [expense(300_00, "2026-09-05"), expense(100_00, "2026-10-05")])
        let rows = BudgetReport.stackHistory(stackInput(cards: [a]), count: 6, now: now)
        XCTAssertEqual(rows.map(\.limit), [1_000_00, 1_000_00, 1_500_00])
        XCTAssertEqual(rows.map(\.spent), [0, 300_00, 100_00])
        XCTAssertEqual(rows.last?.isCurrent, true)
    }
}
