import XCTest
@testable import Anka

final class AnalyticsTests: XCTestCase {

    // MARK: - Daily Spend Points & Zero-Gap Continuity

    func testDailySpendPointsZeroGapContinuity() {
        let calendar = Calendar.current
        guard let day1 = Day.date("2026-09-01"),
              let day5 = Day.date("2026-09-05") else {
            XCTFail("Failed to create dates")
            return
        }

        let catID = UUID()
        let exp1 = Expense(
            id: UUID(),
            amount: 50_000_00,
            day: "2026-09-01",
            note: "Groceries",
            splits: [.init(categoryID: catID, amount: 50_000_00)],
            source: "manual",
            createdAt: day1
        )
        let exp2 = Expense(
            id: UUID(),
            amount: 70_000_00,
            day: "2026-09-05",
            note: "Dinner",
            splits: [.init(categoryID: catID, amount: 70_000_00)],
            source: "manual",
            createdAt: day5
        )

        let points = AnalyticsEngine.calculateDailySpendPoints(
            expenses: [exp1, exp2],
            startDate: day1,
            endDate: day5,
            calendar: calendar,
            now: day5
        )

        // Must have exactly 5 points for Days 1, 2, 3, 4, 5
        XCTAssertEqual(points.count, 5)

        // Day 1
        XCTAssertEqual(points[0].day, "2026-09-01")
        XCTAssertEqual(points[0].amount, 50_000_00)
        XCTAssertEqual(points[0].cumulativeAmount, 50_000_00)
        XCTAssertEqual(points[0].transactionCount, 1)

        // Day 2: Zero spend, flatlines cumulative
        XCTAssertEqual(points[1].day, "2026-09-02")
        XCTAssertEqual(points[1].amount, 0)
        XCTAssertEqual(points[1].cumulativeAmount, 50_000_00)
        XCTAssertEqual(points[1].transactionCount, 0)

        // Day 3: Zero spend
        XCTAssertEqual(points[2].day, "2026-09-03")
        XCTAssertEqual(points[2].amount, 0)
        XCTAssertEqual(points[2].cumulativeAmount, 50_000_00)

        // Day 4: Zero spend
        XCTAssertEqual(points[3].day, "2026-09-04")
        XCTAssertEqual(points[3].amount, 0)
        XCTAssertEqual(points[3].cumulativeAmount, 50_000_00)

        // Day 5: Rp 70.000 spend, cumulative reaches Rp 120.000
        XCTAssertEqual(points[4].day, "2026-09-05")
        XCTAssertEqual(points[4].amount, 70_000_00)
        XCTAssertEqual(points[4].cumulativeAmount, 120_000_00)
        XCTAssertEqual(points[4].transactionCount, 1)
    }

    // MARK: - Cumulative Budget Pace

    func testCumulativeSpendAndLinearBudgetPace() {
        let calendar = Calendar.current
        guard let day1 = Day.date("2026-09-01"),
              let day10 = Day.date("2026-09-10") else {
            XCTFail("Failed to create dates")
            return
        }

        let overallBudget: Int64 = 1_000_000_00 // Rp 1,000,000
        let points = AnalyticsEngine.calculateDailySpendPoints(
            expenses: [],
            startDate: day1,
            endDate: day10,
            overallBudgetLimit: overallBudget,
            calendar: calendar,
            now: day10
        )

        XCTAssertEqual(points.count, 10)

        // Target on day 1: (1_000_000_00 * 1) / 10 = 100_000_00
        XCTAssertEqual(points[0].targetCumulativeAmount, 100_000_00)

        // Target on day 5: 500_000_00
        XCTAssertEqual(points[4].targetCumulativeAmount, 500_000_00)

        // Target on day 10: 1_000_000_00
        XCTAssertEqual(points[9].targetCumulativeAmount, 1_000_000_00)
    }

    // MARK: - Time Horizon Slicing

    func testTimeHorizonDateRanges() {
        let calendar = Calendar.current
        guard let fixedNow = Day.date("2026-09-15") else {
            XCTFail("Failed to parse fixed date")
            return
        }

        // This Month
        let thisMonth = AnalyticsEngine.dateRange(for: .thisMonth, calendar: calendar, now: fixedNow)
        XCTAssertEqual(thisMonth.startDay, "2026-09-01")
        XCTAssertEqual(thisMonth.endDay, "2026-09-30")

        // Last Month
        let lastMonth = AnalyticsEngine.dateRange(for: .lastMonth, calendar: calendar, now: fixedNow)
        XCTAssertEqual(lastMonth.startDay, "2026-08-01")
        XCTAssertEqual(lastMonth.endDay, "2026-08-31")

        // Last 30 Days
        let last30 = AnalyticsEngine.dateRange(for: .last30Days, calendar: calendar, now: fixedNow)
        XCTAssertEqual(last30.endDay, "2026-09-15")
        XCTAssertEqual(last30.startDay, "2026-08-17")

        // Year to Date
        let ytd = AnalyticsEngine.dateRange(for: .yearToDate, calendar: calendar, now: fixedNow)
        XCTAssertEqual(ytd.startDay, "2026-01-01")
        XCTAssertEqual(ytd.endDay, "2026-09-15")
    }

    // MARK: - Month-over-Month Velocity

    func testMonthOverMonthComparison() {
        let calendar = Calendar.current
        guard let fixedNow = Day.date("2026-09-10") else {
            XCTFail("Failed to parse fixed date")
            return
        }

        let catID = UUID()
        // Last month: August 5 spent 100k, August 15 spent 200k
        let expAug1 = Expense(id: UUID(), amount: 100_000_00, day: "2026-08-05", note: "Aug 5", splits: [.init(categoryID: catID, amount: 100_000_00)], source: "manual", createdAt: fixedNow)
        let expAug2 = Expense(id: UUID(), amount: 200_000_00, day: "2026-08-15", note: "Aug 15", splits: [.init(categoryID: catID, amount: 200_000_00)], source: "manual", createdAt: fixedNow)

        // This month: September 5 spent 150k
        let expSep1 = Expense(id: UUID(), amount: 150_000_00, day: "2026-09-05", note: "Sep 5", splits: [.init(categoryID: catID, amount: 150_000_00)], source: "manual", createdAt: fixedNow)

        let points = AnalyticsEngine.calculateMonthOverMonthComparison(
            expenses: [expAug1, expAug2, expSep1],
            calendar: calendar,
            now: fixedNow
        )

        XCTAssertFalse(points.isEmpty)

        // Day 5 check:
        // Sep 5 should be 150k
        let day5 = points.first { $0.dayIndex == 5 }
        XCTAssertEqual(day5?.currentPeriodCumulative, 150_000_00)
        XCTAssertEqual(day5?.previousPeriodCumulative, 100_000_00)

        // Day 10 check:
        // Sep 10 (today) should still be 150k
        let day10 = points.first { $0.dayIndex == 10 }
        XCTAssertEqual(day10?.currentPeriodCumulative, 150_000_00)
        XCTAssertEqual(day10?.previousPeriodCumulative, 100_000_00)

        // Day 15 check:
        // Sep 15 is in the future relative to Sep 10, so currentPeriodCumulative is nil
        let day15 = points.first { $0.dayIndex == 15 }
        XCTAssertNil(day15?.currentPeriodCumulative)
        XCTAssertEqual(day15?.previousPeriodCumulative, 300_000_00) // 100k + 200k
    }

    // MARK: - Category Distribution

    func testCategoryDistributionAndPercentages() {
        let cat1 = ExpenseCategory(id: UUID(), name: "Dining", symbol: "fork.knife")
        let cat2 = ExpenseCategory(id: UUID(), name: "Transport", symbol: "car")
        let categories = [cat1, cat2]

        let exp1 = Expense(id: UUID(), amount: 75_000_00, day: "2026-09-01", note: "Lunch", splits: [.init(categoryID: cat1.id, amount: 75_000_00)], source: "manual")
        let exp2 = Expense(id: UUID(), amount: 25_000_00, day: "2026-09-02", note: "Taxi", splits: [.init(categoryID: cat2.id, amount: 25_000_00)], source: "manual")

        let points = AnalyticsEngine.calculateCategoryDistribution(
            expenses: [exp1, exp2],
            categories: categories
        )

        XCTAssertEqual(points.count, 2)
        // First is Dining with 75%
        XCTAssertEqual(points[0].categoryName, "Dining")
        XCTAssertEqual(points[0].amount, 75_000_00)
        XCTAssertEqual(points[0].percentage, 0.75, accuracy: 0.001)
        XCTAssertEqual(points[0].transactionCount, 1)

        // Second is Transport with 25%
        XCTAssertEqual(points[1].categoryName, "Transport")
        XCTAssertEqual(points[1].amount, 25_000_00)
        XCTAssertEqual(points[1].percentage, 0.25, accuracy: 0.001)

        // Percentage sum must be 1.0
        let sumPct = points.reduce(0.0) { $0 + $1.percentage }
        XCTAssertEqual(sumPct, 1.0, accuracy: 0.001)
    }

    // MARK: - Cross-Card Distribution

    func testCrossCardDistribution() {
        let b1 = Card(id: UUID(), name: "Personal", colorIndex: 0)
        let b2 = Card(id: UUID(), name: "Work", colorIndex: 1)

        let exp1 = Expense(id: UUID(), amount: 100_000_00, day: "2026-09-01", note: "P1", splits: [], source: "manual", cardID: b1.id)
        let exp2 = Expense(id: UUID(), amount: 300_000_00, day: "2026-09-02", note: "W1", splits: [], source: "manual", cardID: b2.id)

        let distribution = AnalyticsEngine.calculateCardDistribution(
            expensesByCard: [b1.id: [exp1], b2.id: [exp2]],
            cards: [b1, b2]
        )

        XCTAssertEqual(distribution.count, 2)
        // Work is top with 75%
        XCTAssertEqual(distribution[0].cardName, "Work")
        XCTAssertEqual(distribution[0].amount, 300_000_00)
        XCTAssertEqual(distribution[0].percentage, 0.75, accuracy: 0.001)

        // Personal is second with 25%
        XCTAssertEqual(distribution[1].cardName, "Personal")
        XCTAssertEqual(distribution[1].amount, 100_000_00)
        XCTAssertEqual(distribution[1].percentage, 0.25, accuracy: 0.001)
    }

    // MARK: - Metrics & Spending Pace

    func testSpendingMetricsAndPace() {
        guard let sDate = Day.date("2026-09-01"),
              let eDate = Day.date("2026-09-30") else {
            XCTFail("Failed to parse dates")
            return
        }

        // Daily points for 10 days: 10k each day -> 100k total
        var points: [DailySpendPoint] = []
        var running: Int64 = 0
        for i in 1...10 {
            running += 10_000_00
            let dayStr = String(format: "2026-09-%02d", i)
            points.append(DailySpendPoint(
                day: dayStr,
                date: Day.date(dayStr)!,
                amount: 10_000_00,
                cumulativeAmount: running,
                targetCumulativeAmount: nil,
                transactionCount: 1
            ))
        }

        // 1. Budget of 600k for 30 days -> expected pace at day 10 is 200k.
        // Actual spend is 100k -> 50% under pace!
        let metricsUnder = AnalyticsEngine.calculateMetrics(
            dailyPoints: points,
            categoryPoints: [],
            startDate: sDate,
            endDate: eDate,
            overallBudgetLimit: 600_000_00
        )

        XCTAssertEqual(metricsUnder.totalSpend, 100_000_00)
        XCTAssertEqual(metricsUnder.dailyAverage, 10_000_00)
        XCTAssertEqual(metricsUnder.projectedPeriodTotal, 300_000_00) // 10k * 30 days
        XCTAssertEqual(metricsUnder.paceStatus, .underPace(percentage: 50))

        // 2. Budget of 300k for 30 days -> expected pace at day 10 is 100k.
        // Actual spend is 100k -> exactly on track!
        let metricsOnTrack = AnalyticsEngine.calculateMetrics(
            dailyPoints: points,
            categoryPoints: [],
            startDate: sDate,
            endDate: eDate,
            overallBudgetLimit: 300_000_00
        )

        XCTAssertEqual(metricsOnTrack.paceStatus, .onTrack)

        // 3. Budget of 150k for 30 days -> expected pace at day 10 is 50k.
        // Actual spend is 100k -> 100% accelerated!
        let metricsOver = AnalyticsEngine.calculateMetrics(
            dailyPoints: points,
            categoryPoints: [],
            startDate: sDate,
            endDate: eDate,
            overallBudgetLimit: 150_000_00
        )

        XCTAssertEqual(metricsOver.paceStatus, .accelerated(percentage: 100))
        XCTAssertEqual(metricsOver.paceStatus?.label, "100% above budget pace")
    }
}

extension AnalyticsTests {
    func testCycleAnalyticsExcludesNextCycleBoundary() throws {
        let start = try XCTUnwrap(Day.date("2026-09-01"))
        let end = try XCTUnwrap(Day.date("2026-10-01"))
        let range = AnalyticsEngine.dateRange(for: .thisCycle, currentCycle: Cycle(start: start, end: end))
        XCTAssertEqual(range.startDay, "2026-09-01")
        XCTAssertEqual(range.endDay, "2026-09-30")
    }

    func testFutureBudgetPaceContinuity() throws {
        let calendar = Calendar.current
        let day1 = try XCTUnwrap(Day.date("2026-09-01"))
        let day5 = try XCTUnwrap(Day.date("2026-09-05"))
        let day30 = try XCTUnwrap(Day.date("2026-09-30"))

        let catID = UUID()
        let exp = Expense(
            id: UUID(),
            amount: 100_000_00,
            day: "2026-09-02",
            note: "Groceries",
            splits: [.init(categoryID: catID, amount: 100_000_00)],
            source: "manual",
            createdAt: day1
        )

        let overallBudget: Int64 = 3_000_000_00 // Rp 3M
        let points = AnalyticsEngine.calculateDailySpendPoints(
            expenses: [exp],
            startDate: day1,
            endDate: day30,
            overallBudgetLimit: overallBudget,
            calendar: calendar,
            now: day5
        )

        // Must cover all 30 days of the cycle
        XCTAssertEqual(points.count, 30)

        // Days 1..5: elapsed / non-future
        for i in 0..<5 {
            XCTAssertFalse(points[i].isFuture)
            XCTAssertNotNil(points[i].cumulativeAmount)
            XCTAssertNotNil(points[i].targetCumulativeAmount)
        }
        XCTAssertEqual(points[1].amount, 100_000_00)
        XCTAssertEqual(points[4].cumulativeAmount, 100_000_00)

        // Days 6..30: future points (actual spend nil, target pace intact)
        for i in 5..<30 {
            XCTAssertTrue(points[i].isFuture)
            XCTAssertNil(points[i].cumulativeAmount)
            XCTAssertNotNil(points[i].targetCumulativeAmount)
        }
        // Day 30 target reaches full budget
        XCTAssertEqual(points[29].targetCumulativeAmount, overallBudget)
    }

    func testUnallocatedAndArchivedCategoryReconciliation() {
        let activeCat = ExpenseCategory(id: UUID(), name: "Food", symbol: "fork.knife")
        let archivedCatID = UUID()

        let expAllocated = Expense(id: UUID(), amount: 50_000_00, day: "2026-09-01", note: "Lunch", splits: [.init(categoryID: activeCat.id, amount: 50_000_00)], source: "manual")
        let expUnallocated = Expense(id: UUID(), amount: 30_000_00, day: "2026-09-02", note: "Cash", splits: [], source: "manual")
        let expArchived = Expense(id: UUID(), amount: 20_000_00, day: "2026-09-03", note: "Old", splits: [.init(categoryID: archivedCatID, amount: 20_000_00)], source: "manual")

        let total: Int64 = 50_000_00 + 30_000_00 + 20_000_00
        let points = AnalyticsEngine.calculateCategoryDistribution(
            expenses: [expAllocated, expUnallocated, expArchived],
            categories: [activeCat] // archivedCatID is not present
        )

        XCTAssertEqual(points.count, 3)
        // 1. Food: 50k (50%)
        XCTAssertEqual(points[0].categoryName, "Food")
        XCTAssertEqual(points[0].amount, 50_000_00)
        XCTAssertEqual(points[0].percentage, 0.50, accuracy: 0.001)

        // 2. Uncategorized: 30k (30%)
        XCTAssertEqual(points[1].categoryName, "Uncategorized")
        XCTAssertEqual(points[1].categoryID, AnalyticsEngine.uncategorizedCategoryID)
        XCTAssertEqual(points[1].amount, 30_000_00)
        XCTAssertEqual(points[1].percentage, 0.30, accuracy: 0.001)

        // 3. Other: 20k (20%)
        XCTAssertEqual(points[2].categoryName, "Other")
        XCTAssertEqual(points[2].categoryID, AnalyticsEngine.otherCategoryID)
        XCTAssertEqual(points[2].amount, 20_000_00)
        XCTAssertEqual(points[2].percentage, 0.20, accuracy: 0.001)

        // Sum must equal 100%
        let sum: Int64 = points.reduce(Int64(0)) { $0 + $1.amount }
        XCTAssertEqual(sum, total)
        let sumPct = points.reduce(0.0) { $0 + $1.percentage }
        XCTAssertEqual(sumPct, 1.0, accuracy: 0.001)
    }

    // MARK: - Filter Scope

    func testAnalyticsFilterScopeProperties() {
        let stackID = UUID()
        let stackScope = AnalyticsFilterScope.stack(id: stackID, name: "Everyday")
        XCTAssertTrue(stackScope.isStack)
        XCTAssertFalse(stackScope.isCard)
        XCTAssertFalse(stackScope.isAllCards)
        XCTAssertEqual(stackScope.title, "Everyday")
        XCTAssertEqual(stackScope.subtitle, "Stack")
        XCTAssertEqual(stackScope.icon, "square.stack.3d.up.fill")

        let cardID = UUID()
        let cardScope = AnalyticsFilterScope.card(id: cardID, name: "BCA")
        XCTAssertFalse(cardScope.isStack)
        XCTAssertTrue(cardScope.isCard)
        XCTAssertFalse(cardScope.isAllCards)
        XCTAssertEqual(cardScope.title, "BCA")
        XCTAssertEqual(cardScope.subtitle, "Card")
        XCTAssertEqual(cardScope.icon, "creditcard.fill")

        let allScope = AnalyticsFilterScope.allCards
        XCTAssertFalse(allScope.isStack)
        XCTAssertFalse(allScope.isCard)
        XCTAssertTrue(allScope.isAllCards)
        XCTAssertEqual(allScope.title, "All cards")
        XCTAssertEqual(allScope.subtitle, "All cards")
        XCTAssertEqual(allScope.icon, "rectangle.stack")
    }

    func testProjectionScalesTotalNotRoundedDailyAverage() throws {
        // 100 minor units over 3 of 30 days: 100 * 30 / 3 = 1000, not (100 / 3) * 30 = 990.
        let start = try XCTUnwrap(Day.date("2026-11-01")), end = try XCTUnwrap(Day.date("2026-11-30"))
        var running: Int64 = 0
        let points = (1...3).map { day -> DailySpendPoint in
            let amount: Int64 = day == 1 ? 34 : 33
            running += amount
            let key = "2026-11-0\(day)"
            return DailySpendPoint(day: key, date: Day.date(key)!, amount: amount, cumulativeAmount: running, targetCumulativeAmount: nil, transactionCount: 1)
        }
        let metrics = AnalyticsEngine.calculateMetrics(dailyPoints: points, categoryPoints: [], startDate: start, endDate: end)
        XCTAssertEqual(metrics.projectedPeriodTotal, 1000)
    }
}
