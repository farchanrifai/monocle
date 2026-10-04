import XCTest
@testable import Monocle

final class BackendFinancialTests: XCTestCase {
    func testIncompleteSplitShowsKnownSubtotalButCannotBeRecorded() throws {
        var draft = ExpenseDraft(); draft.amount = "28000"
        draft.splitAllocations = [
            .init(categoryID: ExpenseCategory.defaults[0].id, amount: "28000"),
            .init(categoryID: ExpenseCategory.defaults[1].id, amount: "")
        ]
        XCTAssertEqual(try draft.resolvedAllocatedAmount(), 2_800_000)
        XCTAssertThrowsError(try draft.expense())
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func expense(amount: Int64 = 150, day: String = "2026-10-01", category: UUID = ExpenseCategory.defaults[0].id, bookID: UUID? = nil) -> Expense {
        Expense(amount: amount, day: day, note: "Original", allocations: [.init(categoryID: category, amount: amount)], bookID: bookID)
    }

    func testExactAggregateAdmissionBoundary() throws {
        XCTAssertEqual(try Money.checkedSum(Array(repeating: Money.maximum, count: 1_024)), 9_216_000_000_000_000_000)
        XCTAssertThrowsError(try Money.checkedSum(Array(repeating: Money.maximum, count: 1_025)))
        XCTAssertEqual(try Money.checkedScale(Int64.max, numerator: 1), Int64.max)
        XCTAssertEqual(try Money.checkedScale(Int64.max, numerator: 2, denominator: 2), Int64.max)
    }

    func testForecastOverflowIsExplicitAndTotalRemainsExact() throws {
        let values = (0..<34).map { _ in expense(amount: Money.maximum) }
        let now = try XCTUnwrap(Day.date("2026-10-01", calendar: utc))
        let report = AnalyticsReport.build(data: .init(expenses: values), horizon: .thisMonth, calendar: utc, now: now)
        XCTAssertEqual(report.metrics.totalSpend, 306_000_000_000_000_000)
        XCTAssertNil(report.metrics.projectedPeriodTotal)
        XCTAssertNil(report.errorMessage)
    }

    func testTinyBudgetCannotOverflowPacePercentage() throws {
        let now = try XCTUnwrap(Day.date("2026-10-01", calendar: utc))
        let values = (0..<1_024).map { _ in expense(amount: Money.maximum) }
        let budget = BudgetVersion(effectiveDay: "2026-10-01", overallLimit: 1, startDay: 1)
        let report = AnalyticsReport.build(data: .init(expenses: values, budgets: [budget]), horizon: .thisCycle, calendar: utc, now: now)
        XCTAssertEqual(report.metrics.paceStatus, .beyondRange)
    }

    func testOversizedReportShowsUnavailableInsteadOfClippedTotal() throws {
        let values = (0..<1_025).map { _ in expense(amount: Money.maximum) }
        let report = AnalyticsReport.build(data: .init(expenses: values), horizon: .thisMonth, calendar: utc,
                                           now: try XCTUnwrap(Day.date("2026-10-01", calendar: utc)))
        XCTAssertNotNil(report.errorMessage)
        XCTAssertTrue(report.dailyPoints.isEmpty)
        XCTAssertTrue(AnalyticsEngine.calculateCategoryDistribution(expenses: values, categories: ExpenseCategory.defaults).isEmpty)
    }

    func testNoteOnlyEditAndDraftRoundTripPreserveFractionalMinorUnits() throws {
        let original = expense()
        var draft = ExpenseDraft(expense: original)
        draft.note = "Only note changed"
        draft = try JSONDecoder().decode(ExpenseDraft.self, from: JSONEncoder().encode(draft))
        let edited = try draft.expense()
        XCTAssertEqual(edited.amount, 150)
        XCTAssertEqual(edited.allocations, original.allocations)
        XCTAssertEqual(edited.note, "Only note changed")
        draft.amount = "2"
        XCTAssertEqual(try draft.expense().amount, 200)
        draft.amount = "2.50"
        XCTAssertThrowsError(try draft.expense())
    }

    func testSplitCategoryEditPreservesUnchangedFractionalAmounts() throws {
        var original = expense(amount: 250)
        original.allocations = [.init(categoryID: ExpenseCategory.defaults[0].id, amount: 125),
                                .init(categoryID: ExpenseCategory.defaults[1].id, amount: 125)]
        var draft = ExpenseDraft(expense: original)
        draft.splitAllocations[1].categoryID = ExpenseCategory.defaults[2].id
        let edited = try draft.expense()
        XCTAssertEqual(edited.amount, 250)
        XCTAssertEqual(edited.allocations.map(\.amount), [125, 125])
        try edited.validate(categories: ExpenseCategory.defaults)
    }

    func testEditableSplitTotalsUseCheckedArithmetic() throws {
        var draft = ExpenseDraft(expense: expense(amount: Money.maximum))
        draft.splitAllocations = (0..<1_025).map { _ in
            DraftAllocation(categoryID: ExpenseCategory.defaults[0].id, amount: Money.digits(Money.maximum))
        }
        XCTAssertThrowsError(try draft.resolvedAllocatedAmount())
    }

    func testCSVPreservesExactFractionsAndSplitsRoundTrip() throws {
        var original = expense(amount: 275)
        original.allocations = [.init(categoryID: ExpenseCategory.defaults[0].id, amount: 125),
                                .init(categoryID: ExpenseCategory.defaults[1].id, amount: 150)]
        let content = CSVExportGenerator.generate(expenses: [original], categories: ExpenseCategory.defaults)
        let table = try CSVTokenizer.parse(content: content)
        XCTAssertEqual(table[1][4], "2.75")
        XCTAssertTrue(table[1][3].contains("1.25"))
        let mapping = CSVImportParser.detectColumnMapping(headers: table[0])
        let rows = CSVImportParser.processRows(rawRows: table, hasHeader: true, mapping: mapping, targetBookID: UUID(),
                                               categories: ExpenseCategory.defaults, defaultCategoryID: ExpenseCategory.defaults[2].id, existingExpenses: [])
        let imported = try XCTUnwrap(rows.first?.parsedExpense)
        XCTAssertEqual(imported.amount, original.amount)
        XCTAssertEqual(imported.allocations, original.allocations)
    }

    func testMalformedCSVQuotesFailAtTheirRecord() {
        for content in ["Date,Amount\n2026-10-01,\"150\n2026-10-02,200", "Date,Amount\n2026-10-01,1\"50", "Date,Amount\n2026-10-01,\"150\"tail"] {
            XCTAssertThrowsError(try CSVTokenizer.parse(content: content)) { error in
                XCTAssertEqual((error as? CSVParseError)?.record, 2)
            }
        }
    }

    func testCSVQuotedWhitespaceAndMultilineArePreserved() throws {
        let rows = try CSVTokenizer.parse(content: "Date,Amount,Note\r\n2026-10-01,2.75,\"  line one\r\nline \"\"two\"\"  \"\r\n")
        XCTAssertEqual(rows[1][2], "  line one\r\nline \"two\"  ")
    }

    func testCSVLimitsAreEnforcedDuringParsing() {
        XCTAssertThrowsError(try CSVTokenizer.parse(content: "A,B\n1,2\n3,4", maximumRecords: 2))
        XCTAssertThrowsError(try CSVTokenizer.parse(content: "A\n\"12345\"", maximumFieldBytes: 4))
    }

    func testCSVPreviewSumOverflowHasNoPlausibleTotal() {
        let rows = (0..<1_025).map { CSVImportRow(rowNumber: $0 + 1, rawValues: [], parsedExpense: expense(amount: Money.maximum)) }
        let summary = CSVImportParser.summarize(rows: rows)
        XCTAssertNil(summary.totalSpending)
        XCTAssertEqual(summary.validRows, 1_025)
    }

    func testStorageAndReportingIgnorePreferredCalendarIdentifier() throws {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = utc.timeZone
        let now = try XCTUnwrap(Day.date("2026-10-05", calendar: utc))
        XCTAssertEqual(Day.string(now, calendar: buddhist), "2026-10-05")
        XCTAssertEqual(Day.date("2026-10-05", calendar: buddhist), now)
        let range = AnalyticsEngine.dateRange(for: .thisMonth, calendar: buddhist, now: now)
        XCTAssertEqual(range.startDay, "2026-10-01")
        XCTAssertEqual(range.endDay, "2026-10-31")
    }

    func testDraftCivilDayOverridesTravelShiftedPickerInstant() throws {
        let intendedDay = "2026-10-05"
        var draft = ExpenseDraft(expense: expense(day: intendedDay))
        let encoded = try JSONEncoder().encode(draft)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        // The same old Date instant can show a different date after crossing time zones.
        object["date"] = try XCTUnwrap(Day.date("2026-10-06", calendar: utc)).timeIntervalSinceReferenceDate
        let restored = try JSONDecoder().decode(ExpenseDraft.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored.civilDay, intendedDay)
        XCTAssertEqual(Day.string(restored.date), intendedDay)
        XCTAssertEqual(try restored.expense().day, intendedDay)
        draft.date = try XCTUnwrap(Day.date("2026-10-07"))
        XCTAssertEqual(try draft.expense().day, "2026-10-07")
    }

    func testBudgetTransitionUsesInclusiveStartAndExclusiveEnd() throws {
        let budget = BudgetVersion(effectiveDay: "2026-10-01", overallLimit: 100_000, startDay: 25, transitionEndDay: "2026-10-25")
        let period = try XCTUnwrap(BudgetHistory.period(containing: XCTUnwrap(Day.date("2026-10-01", calendar: utc)), budgets: [budget], calendar: utc))
        XCTAssertEqual(utc.component(.hour, from: period.cycle.start), 0)
        XCTAssertTrue(period.cycle.contains(expense(day: "2026-10-01")))
        // Expense days are local; compare civil boundaries explicitly for UTC test fixture.
        XCTAssertEqual(Day.string(period.cycle.end, calendar: utc), "2026-10-25")
    }

    func testScopedCardReportUsesItsBudgetAndAggregateUsesCalendarMonth() throws {
        let now = try XCTUnwrap(Day.date("2026-10-05", calendar: utc))
        let cardBudget = BudgetVersion(effectiveDay: "2026-09-25", overallLimit: 1_000, startDay: 25)
        let selected = AnalyticsReport.build(data: .init(expenses: [expense(day: "2026-09-28")], budgets: [cardBudget]), horizon: .thisCycle, calendar: utc, now: now)
        XCTAssertEqual(selected.range.startDay, "2026-09-25")
        XCTAssertEqual(selected.metrics.totalSpend, 150)
        XCTAssertEqual(selected.period?.budget.overallLimit, 1_000)
        let aggregate = AnalyticsReport.build(data: .init(expenses: [expense(day: "2026-09-28")]), horizon: .thisCycle, calendar: utc, now: now)
        XCTAssertEqual(aggregate.range.startDay, "2026-10-01")
        XCTAssertNil(aggregate.period)
        XCTAssertNil(aggregate.metrics.paceStatus)
    }

    func testAnalyticsLargeFixtureProducesOneCompleteReport() throws {
        let now = try XCTUnwrap(Day.date("2026-10-05", calendar: utc))
        for count in [10_000, 50_000] {
            let values = (0..<count).map { index in expense(amount: Int64(index % 100 + 1), category: ExpenseCategory.defaults[index % 6].id) }
            let started = Date()
            let report = AnalyticsReport.build(data: .init(expenses: values, categories: ExpenseCategory.defaults), horizon: .thisMonth, calendar: utc, now: now)
            XCTAssertEqual(report.metrics.transactionCount, count)
            XCTAssertEqual(report.metrics.totalSpend, try Money.checkedSum(values.map(\.amount)))
            XCTAssertEqual(report.categoryPoints.count, 6)
            print("Analytics fixture records=\(count) durationSeconds=\(Date().timeIntervalSince(started))")
        }
    }
}
