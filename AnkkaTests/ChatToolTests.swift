import XCTest
@testable import Ankka

@MainActor
final class ChatToolTests: XCTestCase {
    private var model: AppModel!
    private var repo: ExpenseRepository!
    private var daily: Card!
    private var travel: Card!
    private var trip: Stack!
    private var tempDir: URL!
    private let now = Day.date("2026-09-15")!

    override func setUp() async throws {
        repo = try ExpenseRepository(inMemory: true)
        daily = try repo.createCard(named: "Daily")
        travel = try repo.createCard(named: "Tokyo Travel")
        let food = try category("Food & Drink", in: daily)
        let transport = try category("Transport", in: travel)
        let travelFood = try category("Food & Drink", in: travel)
        try save(45_000, "2026-09-14", "Lunch at work", food, daily)
        try save(28_000, "2026-09-15", "Kopi", food, daily)
        try save(120_000, "2026-09-10", "Sushi dinner", travelFood, travel)
        try save(32_000, "2026-09-11", "Train", transport, travel)
        try save(60_000, "2026-08-20", "August lunch", food, daily)

        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        model = AppModel(expenses: try ExpenseService(store: repo), state: FileLocalStateStore(directory: tempDir))
        try model.reload()
        trip = try model.createStack(name: "Trip", icon: "airplane", cardIDs: [travel.id])
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - propose_expense

    func testAmountsAreConvertedByTheAppAsTheUserWroteThem() throws {
        let rupiah: [(String, Decimal)] = [("28rb", 28_000), ("28 ribu", 28_000), ("100k", 100_000), ("1,5jt", 1_500_000), ("2 juta", 2_000_000),
                                           ("Rp28.000", 28_000), ("28.000", 28_000), ("Rp 1.250.000", 1_250_000), ("45000", 45_000)]
        for (text, value) in rupiah { XCTAssertEqual(ToolExecutor.amount(text, code: "IDR"), value, text) }
        let dollars: [(String, Decimal)] = [("$4.50", 4.5), ("4,50", 4.5), ("1,234.50", 1234.5), ("12", 12), ("28k", 28_000)]
        for (text, value) in dollars { XCTAssertEqual(ToolExecutor.amount(text, code: "USD"), value, text) }
        XCTAssertNil(ToolExecutor.amount("kopi", code: "IDR"))
        XCTAssertNil(ToolExecutor.amount("0rb", code: "IDR"))

        let proposed = run("propose_expense", ["amount": "1,5jt", "category": "Food & Drink", "note": "Katering"], scope: .card(id: daily.id, name: daily.name))
        XCTAssertEqual(proposed.proposal?.amount, 150_000_000, proposed.json)
        let split = run("propose_expense", ["amount": "50rb", "note": "Pasar", "split": [["category": "Food & Drink", "amount": "30rb"], ["category": "Transport", "amount": "20rb"]]],
                        scope: .card(id: daily.id, name: daily.name))
        XCTAssertEqual(split.proposal?.splits.map(\.amount), [3_000_000, 2_000_000], split.json)
    }

    func testOfflineReaderAddsPurchasesWithoutAModel() throws {
        let scope = AnalyticsFilterScope.card(id: daily.id, name: daily.name)
        let names = Dictionary(try repo.categories(in: daily.id).map { ($0.id, $0.name) }) { first, _ in first }
        func read(_ text: String) -> [(note: String, amount: Int64, category: String, day: String)] {
            OfflineReader.read(text, model: model, scope: scope, now: now).compactMap {
                guard case .proposal(let e) = $0 else { return nil }
                return (e.note, e.amount, names[e.splits[0].categoryID] ?? "?", e.day)
            }
        }
        let three = read("kopi 28rb, bensin 100 rb kemarin; parkir 5rb")
        XCTAssertEqual(three.map(\.note), ["Kopi", "Bensin", "Parkir"])
        XCTAssertEqual(three.map(\.amount), [2_800_000, 10_000_000, 500_000])
        XCTAssertEqual(three.map(\.category), ["Food & Drink", "Transport", "Transport"])
        XCTAssertEqual(three.map(\.day), ["2026-09-15", "2026-09-14", "2026-09-15"])
        XCTAssertEqual(read("roti 15rb dan susu 20rb").count, 2, "dan between two amounts is two purchases")
        XCTAssertEqual(read("fish and chips 50rb").map(\.note), ["Fish and chips"], "one amount stays one purchase")
        XCTAssertEqual(read("Lunch at work 45rb").first?.category, "Food & Drink", "the user's own past choice")
        XCTAssertTrue(read("berapa pengeluaran bulan ini?").isEmpty, "a question isn't an expense")
        XCTAssertTrue(read("pasar 50rb: 30rb makan").isEmpty, "two amounts in one piece is left to the assistant")
    }

    func testProposeUsesTheCategoryTheUserGaveThisPurchaseBefore() throws {
        let scope = AnalyticsFilterScope.card(id: daily.id, name: daily.name)
        let input = try JSONSerialization.data(withJSONObject: ["amount": 28000, "category": "Transport", "note": "kopi"])
        let food = try category("Food & Drink", in: daily), transport = try category("Transport", in: daily)

        let guessed = ToolExecutor(model: model, scope: scope, now: now, userText: "kopi 28rb").run("propose_expense", input: input)
        XCTAssertEqual(guessed.proposal?.splits.map(\.categoryID), [food.id], "Kopi was Food & Drink before, whatever the model guessed")
        XCTAssertEqual(json(guessed)["category"] as? String, "Food & Drink", "the model hears the category it'll be")

        let named = ToolExecutor(model: model, scope: scope, now: now, userText: "kopi 28rb #Transport").run("propose_expense", input: input)
        XCTAssertEqual(named.proposal?.splits.map(\.categoryID), [transport.id], "a category the user names wins")

        let context = ChatAgent.context(ToolExecutor(model: model, scope: scope, now: now), now: now)
        XCTAssertTrue(context.contains("Kopi → Food & Drink"), context)
    }

    func testProposeBuildsUnsavedExpenseOnScopeCardInMinorUnits() throws {
        let before = try repo.expenses(in: travel.id).count
        let outcome = run("propose_expense", ["amount": 28000, "category": "food & DRINK", "note": " Kopi "], scope: tripScope)

        XCTAssertFalse(outcome.isError, outcome.json)
        let expense = try XCTUnwrap(outcome.proposal)
        XCTAssertEqual(expense.amount, 2_800_000)
        XCTAssertEqual(expense.splits.map(\.amount), [2_800_000])
        XCTAssertEqual(expense.cardID, travel.id, "Active card is outside the Trip stack, so the stack's first card is the target")
        XCTAssertEqual(expense.source, "chat")
        XCTAssertEqual(expense.note, "Kopi")
        XCTAssertEqual(expense.day, "2026-09-15")
        XCTAssertEqual(json(outcome)["status"] as? String, "shown_to_user")
        XCTAssertEqual(try repo.expenses(in: travel.id).count, before, "Proposals never write")
    }

    /// Typed in the card's currency, then converted to the reporting currency like the Add screen does.
    func testProposeReadsDecimalsInTheCardsCurrency() async throws {
        var usd = travel!; usd.currency = "USD"
        try repo.updateCard(usd)
        try model.reload()
        model.rates = ExchangeRates(source: OneRate(), fileURL: nil)
        let reporting = model.reportingCurrency
        XCTAssertNotEqual(reporting, "USD")
        let outcome = await proposeFetchingRate(["amount": 4.5, "category": "Transport", "note": "Bus"], scope: tripScope)
        XCTAssertFalse(outcome.isError, outcome.json)
        XCTAssertEqual(outcome.proposal?.originalAmount, 450)
        XCTAssertEqual(outcome.proposal?.originalCurrency, "USD")
        XCTAssertEqual(outcome.proposal?.amount, try Money.convert(450, rate: 100, to: reporting))
        let split = await proposeFetchingRate(["amount": 10, "split": [["category": "Transport", "amount": 2.25], ["category": "Food & Drink", "amount": 7.75]]], scope: tripScope)
        XCTAssertEqual(split.proposal?.originalAmount, 1000, split.json)
        XCTAssertEqual(split.proposal?.splits.map(\.amount), [try Money.convert(225, rate: 100, to: reporting), try Money.convert(775, rate: 100, to: reporting)])
        XCTAssertTrue(run("propose_expense", ["amount": 0.001, "category": "Transport"], scope: tripScope).isError, "rounds to zero")
    }

    func testProposeRejectsBadInputWithUsableMessages() throws {
        XCTAssertTrue(run("propose_expense", ["amount": 0, "category": "Transport"]).isError)
        XCTAssertTrue(run("propose_expense", ["amount": Money.maximum, "category": "Transport"]).isError)
        XCTAssertTrue(run("propose_expense", ["amount": 1000, "category": "Transport", "day": "2026-02-30"]).isError)
        XCTAssertTrue(run("propose_expense", ["category": "Transport"]).isError, "amount is required")

        let unknown = run("propose_expense", ["amount": 1000, "category": "Pets"])
        XCTAssertTrue(unknown.isError)
        XCTAssertTrue((json(unknown)["error"] as? String ?? "").contains("Transport"), "Error lists valid categories so Claude can retry")

        let card = run("propose_expense", ["amount": 1000, "category": "Transport", "card": "Nope"])
        XCTAssertTrue((json(card)["error"] as? String ?? "").contains("Tokyo Travel"))
        XCTAssertNil(unknown.proposal)
    }

    func testProposeHonorsNamedCardAndDay() throws {
        let outcome = run("propose_expense", ["amount": 100000, "category": "Transport", "card": "tokyo travel", "day": "2026-09-14"])
        XCTAssertEqual(outcome.proposal?.cardID, travel.id)
        XCTAssertEqual(outcome.proposal?.day, "2026-09-14")
    }

    // MARK: - query_expenses

    func testQueryReturnsNewestFirstWithAppComputedTotal() throws {
        let result = json(run("query_expenses", ["period": "this_month", "scope": "all_cards"]))
        XCTAssertEqual(result["count"] as? Int, 4)
        XCTAssertEqual(rupiah(result["total"]), 225_000)
        let rows = try XCTUnwrap(result["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.map { $0["note"] as? String }, ["Kopi", "Lunch at work", "Train", "Sushi dinner"])
        XCTAssertEqual(rows.first?["card"] as? String, "Daily")
        XCTAssertEqual(result["has_more"] as? Bool, false)
    }

    func testQueryFiltersByCategoryTextScopeAndPages() throws {
        let food = json(run("query_expenses", ["period": "this_month", "scope": "all_cards", "category": "food & drink"]))
        XCTAssertEqual(rupiah(food["total"]), 193_000)

        let sushi = json(run("query_expenses", ["period": "this_month", "scope": "all_cards", "text": "SUSHI"]))
        XCTAssertEqual(sushi["count"] as? Int, 1)

        let stack = json(run("query_expenses", ["period": "this_month"], scope: tripScope))
        XCTAssertEqual(rupiah(stack["total"]), 152_000, "Default scope is the chat's stack")

        let page = json(run("query_expenses", ["period": "this_month", "scope": "all_cards", "limit": 1, "offset": 1]))
        XCTAssertEqual((page["rows"] as? [[String: Any]])?.first?["note"] as? String, "Lunch at work")
        XCTAssertEqual(page["has_more"] as? Bool, true)
        XCTAssertEqual(rupiah(page["total"]), 225_000, "Total covers every match, not just the page")

        let range = json(run("query_expenses", ["start": "2026-08-01", "end": "2026-08-31", "scope": "card:Daily"]))
        XCTAssertEqual(range["count"] as? Int, 1)
    }

    func testQueryRejectsUnknownCategoryScopeAndHalfRanges() throws {
        XCTAssertTrue((json(run("query_expenses", ["category": "Pets", "scope": "all_cards"]))["error"] as? String ?? "").contains("Food & Drink"))
        XCTAssertTrue((json(run("query_expenses", ["scope": "Mars"]))["error"] as? String ?? "").contains("Trip"))
        XCTAssertTrue(run("query_expenses", ["start": "2026-09-01"]).isError)
        XCTAssertTrue(run("query_expenses", ["start": "2026-09-10", "end": "2026-09-01"]).isError)
        XCTAssertTrue(run("query_expenses", ["period": "next_year"]).isError)

        // The default stack is named "Daily", like the Daily card: ambiguous names must not silently pick one.
        XCTAssertTrue((json(run("query_expenses", ["scope": "Daily"]))["error"] as? String ?? "").contains("card:Daily"))
        XCTAssertFalse(run("query_expenses", ["scope": "stack:Daily"]).isError)
    }

    // MARK: - get_summary / compare_periods

    func testSummaryGroupsMatchReportAndCarryChart() throws {
        let outcome = run("get_summary", ["period": "this_month", "scope": "all_cards"])
        let result = json(outcome)
        XCTAssertEqual(rupiah(result["total"]), 225_000)
        let groups = try XCTUnwrap(result["groups"] as? [[String: Any]])
        XCTAssertEqual(groups.first?["name"] as? String, "Food & Drink")
        XCTAssertEqual(rupiah(groups.first?["amount"]), 193_000)
        XCTAssertEqual(outcome.chart?.style, .donut)
        XCTAssertEqual(outcome.chart?.items.first?.value, 193_000_00)

        let byCard = run("get_summary", ["period": "this_month", "group_by": "card", "scope": "all_cards"])
        XCTAssertEqual(byCard.chart?.style, .bars)
        XCTAssertEqual(run("get_summary", ["period": "this_month", "group_by": "day"]).chart?.style, .trend)
        XCTAssertEqual(Set((json(byCard)["groups"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }), ["Daily", "Tokyo Travel"])
    }

    func testSummaryByPaidWithAndWeekday() throws {
        let byWeekday = run("get_summary", ["period": "this_month", "group_by": "weekday", "scope": "all_cards"])
        let days = try XCTUnwrap(json(byWeekday)["groups"] as? [[String: Any]])
        XCTAssertEqual(days.count, 7, "Every weekday is listed, empty ones too")
        XCTAssertEqual(days.reduce(Int64(0)) { $0 + (rupiah($1["amount"]) ?? 0) }, 225_000)
        XCTAssertEqual(byWeekday.chart?.style, .bars)

        let byPaidWith = run("get_summary", ["period": "this_month", "group_by": "paid_with", "scope": "all_cards"])
        let groups = try XCTUnwrap(json(byPaidWith)["groups"] as? [[String: Any]])
        XCTAssertEqual(groups.map { $0["name"] as? String }, ["Not set"])
        XCTAssertEqual(rupiah(groups.first?["amount"]), 225_000)
        XCTAssertEqual(run("get_summary", ["period": "this_month", "group_by": "day"]).chart?.average, 15_000_00, "225k over 15 days")
    }

    func testInsightsOverviewPaceMonthAndTop() throws {
        let overview = run("get_insights", ["kind": "overview", "scope": "all_cards"])
        let result = json(overview)
        XCTAssertEqual(rupiah(result["total"]), 225_000)
        XCTAssertEqual(result["count"] as? Int, 4)
        XCTAssertEqual(result["top_category"] as? String, "Food & Drink")
        XCTAssertEqual(overview.chart?.style, .stats)
        XCTAssertEqual(overview.chart?.stats?.first?.value, Money.format(225_000_00))

        let month = run("get_insights", ["kind": "month_over_month", "scope": "card:Daily"])
        XCTAssertEqual(rupiah(json(month)["this_month_so_far"]), 73_000)
        XCTAssertEqual(rupiah(json(month)["last_month_total"]), 60_000)
        XCTAssertEqual(month.chart?.style, .cumulative)

        let top = run("get_insights", ["kind": "top_expenses", "scope": "all_cards"])
        let rows = try XCTUnwrap(json(top)["rows"] as? [[String: Any]])
        XCTAssertEqual(rows.first?["note"] as? String, "Sushi dinner")
        XCTAssertEqual(top.chart?.items.map(\.value), [120_000_00, 45_000_00, 32_000_00, 28_000_00])

        XCTAssertNil(json(run("get_insights", ["kind": "pace", "scope": "card:Daily"]))["budget"], "No budget, no pace line")
        try repo.save(BudgetVersion.initial(overallLimit: 300_000_00, startDay: 1, date: now, cardID: daily.id), in: daily.id)
        try model.reload()
        let pace = run("get_insights", ["kind": "pace", "scope": "card:Daily"])
        XCTAssertEqual(rupiah(json(pace)["budget"]), 300_000)
        XCTAssertEqual(pace.chart?.style, .pace)
        XCTAssertEqual(pace.chart?.items.last(where: { $0.isFuture != true })?.value, 73_000_00)

        let history = run("get_insights", ["kind": "budget_history", "scope": "card:Daily"])
        XCTAssertEqual(json(history)["has_budget"] as? Bool, true)
        XCTAssertEqual(history.chart?.style, .budget)
        XCTAssertEqual(history.chart?.items.first?.value, 73_000_00, "Newest cycle first")
    }

    func testComparePeriodsComputesDeltas() throws {
        let result = json(run("compare_periods", ["period_a": "last_month", "period_b": "this_month", "scope": "card:Daily"]))
        XCTAssertEqual(rupiah(result["total_a"]), 60_000)
        XCTAssertEqual(rupiah(result["total_b"]), 73_000)
        XCTAssertEqual(rupiah(result["change"]), 13_000)

        let reversed = json(run("compare_periods", ["period_a": "this_month", "period_b": "last_month", "scope": "card:Daily"]))
        XCTAssertEqual(rupiah(reversed["change"]), 13_000, "Periods are ordered earlier → later whichever way they're asked")
        XCTAssertEqual(reversed["period_a"] as? String, result["period_a"] as? String)
        XCTAssertTrue((reversed["summary"] as? String)?.hasPrefix("Spending went up by") == true)

        let chart = run("compare_periods", ["period_a": "this_month", "period_b": "last_month", "scope": "card:Daily"]).chart
        XCTAssertEqual(chart?.series, ["Last month", "This month"], "Chart reads earlier → later too")
        XCTAssertEqual(chart?.items.first?.label, "Total")
        XCTAssertEqual(chart?.items.first?.reference, 60_000_00)
    }

    // MARK: - get_budget_status / list_cards

    func testBudgetStatusWithAndWithoutBudget() throws {
        XCTAssertEqual(json(run("get_budget_status", ["card": "Tokyo Travel"]))["has_budget"] as? Bool, false)

        let food = try category("Food & Drink", in: daily)
        var budget = BudgetVersion.initial(overallLimit: 100_000_00, startDay: 1, date: now, cardID: daily.id)
        budget.categoryLimits = [CategoryBudget(categoryID: food.id, limit: 50_000_00)]
        try repo.save(budget, in: daily.id)
        try model.reload()

        let result = json(run("get_budget_status", ["card": "Daily"]))
        XCTAssertEqual(result["has_budget"] as? Bool, true)
        XCTAssertEqual(rupiah(result["spent"]), 73_000)
        XCTAssertEqual(rupiah(result["remaining"]), 27_000)
        let category = try XCTUnwrap((result["categories"] as? [[String: Any]])?.first)
        XCTAssertEqual(rupiah(category["remaining"]), -23_000, "Over-budget categories report a negative remainder")
        let chart = run("get_budget_status", ["card": "Daily"]).chart
        XCTAssertEqual(chart?.style, .budget)
        XCTAssertEqual(chart?.items.map(\.label), ["Overall", "Food & Drink"])
        XCTAssertEqual(chart?.items.last?.value, 73_000_00)
        XCTAssertEqual(chart?.items.last?.reference, 50_000_00)
    }

    func testBudgetStatusForThePreviousCycle() throws {
        XCTAssertEqual(json(run("get_budget_status", ["card": "Daily", "cycle": "previous"]))["has_budget"] as? Bool, false)

        try repo.save(BudgetVersion.initial(overallLimit: 100_000_00, startDay: 1, date: Day.date("2026-07-10")!, cardID: daily.id), in: daily.id)
        try model.reload()

        let result = json(run("get_budget_status", ["card": "Daily", "cycle": "previous"]))
        XCTAssertEqual(result["cycle_start"] as? String, "2026-08-01")
        XCTAssertEqual(result["cycle_end"] as? String, "2026-08-31")
        XCTAssertEqual(rupiah(result["spent"]), 60_000)
        XCTAssertEqual(rupiah(json(run("get_budget_status", ["card": "Daily"]))["spent"]), 73_000, "Current cycle is unchanged")
    }

    func testListCardsShowsStacksAndScope() throws {
        let result = json(run("list_cards", [:], scope: tripScope))
        XCTAssertEqual(result["scope"] as? String, "Stack: Trip")
        XCTAssertEqual(result["default_card"] as? String, "Tokyo Travel")
        XCTAssertTrue((result["cards"] as? [String] ?? []).contains("Daily"))
        let stacks = result["stacks"] as? [[String: Any]] ?? []
        XCTAssertEqual(stacks.first { $0["name"] as? String == "Trip" }?["cards"] as? [String], ["Tokyo Travel"])
        XCTAssertTrue(run("no_such_tool", [:]).isError)
    }

    func testProposeSplitMustAddUpToTheAmount() throws {
        let split: [[String: Any]] = [["category": "Food & Drink", "amount": 30000], ["category": "shopping", "amount": 20000]]
        let outcome = run("propose_expense", ["amount": 50000, "split": split, "note": "Pasar"])
        XCTAssertFalse(outcome.isError, outcome.json)
        let expense = try XCTUnwrap(outcome.proposal)
        XCTAssertEqual(expense.splits.map(\.amount), [3_000_000, 2_000_000])
        XCTAssertEqual(Set(expense.splits.map(\.categoryID)).count, 2)

        let mismatch = run("propose_expense", ["amount": 60000, "split": split])
        XCTAssertTrue((json(mismatch)["error"] as? String ?? "").contains("add up"), mismatch.json)
        XCTAssertTrue(run("propose_expense", ["amount": 30000, "split": [split[0]]]).isError, "One part is not a split")
        XCTAssertTrue(run("propose_expense", ["amount": 50000, "split": split, "category": "Transport"]).isError, "Not both")
        XCTAssertTrue(run("propose_expense", ["amount": 60000, "split": [split[0], split[0]]]).isError, "Duplicate category")
        XCTAssertTrue(run("propose_expense", ["amount": 50000]).isError, "Category or split required")
    }

    func testEditCanSplitAndResplit() throws {
        let kopi = try kopiID()
        let split: [[String: Any]] = [["category": "Food & Drink", "amount": 20000], ["category": "Shopping", "amount": 10000]]
        let edit = run("propose_edit", ["id": kopi, "amount": 30000, "split": split])
        XCTAssertEqual(edit.change?.updated?.splits.map(\.amount), [2_000_000, 1_000_000], edit.json)
        XCTAssertTrue(run("propose_edit", ["id": kopi, "split": split]).isError, "Split must match the unchanged Rp28.000")
    }

    // MARK: - propose_bill / list_bills

    func testProposeBillDefaultsToTodayAndConfirmModeWithoutSaving() throws {
        let outcome = run("propose_bill", ["name": " Netflix ", "amount": 186000, "category": "Leisure", "frequency": "monthly", "card": "Daily"])
        XCTAssertFalse(outcome.isError, outcome.json)
        let bill = try XCTUnwrap(outcome.bill)
        XCTAssertEqual(bill.name, "Netflix")
        XCTAssertEqual(bill.amount, 18_600_000)
        XCTAssertEqual(bill.recurrence, .monthly(day: 15), "now is 2026-09-15")
        XCTAssertEqual(bill.recordingMode, .pending)
        XCTAssertTrue(bill.hasReminder)
        XCTAssertEqual(bill.cardID, daily.id)
        XCTAssertTrue(try repo.bills(in: daily.id).isEmpty, "Proposals never write")

        let weekly = run("propose_bill", ["name": "Laundry", "amount": 50000, "category": "Home", "frequency": "weekly",
                                          "weekday": 2, "record": "automatic", "reminder": false])
        XCTAssertEqual(weekly.bill?.recurrence, .weekly(weekday: 2))
        XCTAssertEqual(weekly.bill?.recordingMode, .automatic)
        XCTAssertEqual(weekly.bill?.hasReminder, false)

        XCTAssertTrue(run("propose_bill", ["name": "X", "amount": 1000, "category": "Home", "frequency": "monthly", "day": 32]).isError)
        XCTAssertTrue(run("propose_bill", ["name": "", "amount": 1000, "category": "Home", "frequency": "monthly"]).isError)
        XCTAssertTrue(run("propose_bill", ["name": "X", "amount": 0, "category": "Home", "frequency": "monthly"]).isError)
    }

    func testSavedBillIsListed() throws {
        let session = ChatSession()
        let bill = try XCTUnwrap(run("propose_bill", ["name": "Rent", "amount": 3000000, "category": "Home", "frequency": "monthly", "day": 1, "card": "Daily"]).bill)
        session.rows = [ChatRow(kind: .bill(bill, .pending))]
        session.resolveBill(session.rows[0].id, bill, as: .saved, model: model)
        XCTAssertEqual(session.rows[0].kind, .bill(bill, .saved))
        XCTAssertEqual(try repo.bills(in: daily.id).map(\.name), ["Rent"])

        let rows = try XCTUnwrap(json(run("list_bills", [:]))["bills"] as? [[String: Any]])
        XCTAssertEqual(rows.map { $0["name"] as? String }, ["Rent"])
        XCTAssertEqual(rupiah(rows.first?["amount"]), 3_000_000)
        XCTAssertEqual(rows.first?["schedule"] as? String, "Monthly on day 1")
    }

    // MARK: - propose_edit / propose_delete

    func testEditProposesOnlyGivenFieldsAndNeverWrites() throws {
        let kopi = try kopiID()
        let unknown = run("propose_edit", ["id": kopi, "amount": 30000, "category": "Pets"])
        XCTAssertTrue((json(unknown)["error"] as? String ?? "").contains("Food & Drink"), "Error lists valid categories")

        let edit = run("propose_edit", ["id": kopi, "amount": 30000, "note": "Kopi susu"])
        XCTAssertFalse(edit.isError, edit.json)
        let change = try XCTUnwrap(edit.change)
        let updated = try XCTUnwrap(change.updated)
        XCTAssertEqual(updated.id, change.original.id)
        XCTAssertEqual(updated.amount, 3_000_000)
        XCTAssertEqual(updated.splits.map(\.amount), [3_000_000], "Single allocation follows the amount")
        XCTAssertEqual(updated.note, "Kopi susu")
        XCTAssertEqual(updated.day, change.original.day)
        XCTAssertEqual(rupiah((json(edit)["before"] as? [String: Any])?["amount"]), 28_000)
        XCTAssertEqual(rupiah((json(edit)["after"] as? [String: Any])?["amount"]), 30_000)
        XCTAssertEqual(try repo.expenses(in: daily.id).first { $0.id.uuidString == kopi }?.amount, 2_800_000, "Proposals never write")

        XCTAssertTrue(run("propose_edit", ["id": kopi]).isError, "Nothing to change")
        XCTAssertTrue(run("propose_edit", ["id": kopi, "day": "2026-02-30"]).isError)
        XCTAssertTrue(run("propose_edit", ["id": UUID().uuidString, "amount": 1000]).isError)
        XCTAssertTrue(run("propose_edit", ["id": "latest", "amount": 1000]).isError)
    }

    func testEditRefusesAmountOrCategoryChangeOnSplitButAllowsNote() throws {
        let food = try category("Food & Drink", in: daily), shopping = try category("Shopping", in: daily)
        let split = Expense(amount: 10_000_00, day: "2026-09-12", note: "Market",
                            splits: [.init(categoryID: food.id, amount: 6_000_00), .init(categoryID: shopping.id, amount: 4_000_00)], cardID: daily.id)
        try model.save(split)
        XCTAssertTrue(run("propose_edit", ["id": split.id.uuidString, "amount": 12000]).isError)
        XCTAssertEqual(run("propose_edit", ["id": split.id.uuidString, "note": "Pasar"]).change?.updated?.splits, split.splits)
    }

    func testDeleteProposesWithoutDeleting() throws {
        let kopi = try kopiID()
        let outcome = run("propose_delete", ["id": kopi])
        XCTAssertFalse(outcome.isError, outcome.json)
        XCTAssertNil(outcome.change?.updated)
        XCTAssertEqual(outcome.change?.original.id.uuidString, kopi)
        XCTAssertNotNil(try repo.expenses(in: daily.id).first { $0.id.uuidString == kopi })
    }

    func testConfirmedChangesApplyAndUndoAndStaleCardsAreRefused() throws {
        let session = ChatSession()
        let kopi = try kopiID()
        let edit = try XCTUnwrap(run("propose_edit", ["id": kopi, "amount": 30000]).change)
        let delete = try XCTUnwrap(run("propose_delete", ["id": kopi]).change)
        session.rows = [ChatRow(kind: .change(edit, .pending)), ChatRow(kind: .change(delete, .pending))]
        let (editRow, deleteRow) = (session.rows[0].id, session.rows[1].id)
        func stored() -> Expense? { model.expenses(for: daily.id).first { $0.id.uuidString == kopi } }

        session.resolveChange(editRow, edit, as: .saved, model: model)
        XCTAssertEqual(stored()?.amount, 3_000_000)
        XCTAssertEqual(session.rows[0].kind, .change(edit, .saved))

        // The delete card still shows the old Rp28.000 snapshot: refuse instead of deleting what the user now has.
        session.resolveChange(deleteRow, delete, as: .saved, model: model)
        XCTAssertNotNil(stored())
        XCTAssertEqual(session.rows[1].kind, .change(delete, .pending))
        guard case .error = session.rows.last?.kind else { return XCTFail("Expected a stale-card error row") }

        session.resolveChange(editRow, edit, as: .undone, model: model)
        XCTAssertEqual(stored()?.amount, 2_800_000)

        session.resolveChange(deleteRow, delete, as: .saved, model: model)
        XCTAssertNil(stored())
        session.resolveChange(deleteRow, delete, as: .undone, model: model)
        XCTAssertEqual(stored(), delete.original)
    }

    private func kopiID() throws -> String {
        let rows = try XCTUnwrap(json(run("query_expenses", ["period": "this_month", "text": "kopi"]))["rows"] as? [[String: Any]])
        return try XCTUnwrap(rows.first?["id"] as? String)
    }

    // MARK: - Helpers

    func testProposeConvertsANamedCurrencyAtTheDaysRate() async throws {
        let reporting = model.reportingCurrency
        XCTAssertNotEqual(reporting, "JPY")
        model.rates = ExchangeRates(source: OneRate(), fileURL: nil)
        let executor = ToolExecutor(model: model, scope: .allCards, now: now)
        let input = try JSONSerialization.data(withJSONObject: ["amount": 340, "currency": "jpy", "category": "Transport", "note": "Taxi", "card": "Tokyo Travel"])
        XCTAssertTrue(executor.run("propose_expense", input: input).isError, "no rate yet")

        await executor.fetchRate(for: "propose_expense", input: input)
        let outcome = executor.run("propose_expense", input: input)
        let expense = try XCTUnwrap(outcome.proposal, outcome.json)
        XCTAssertEqual(expense.originalAmount, 34_000, "minor units, hundredths in every currency")
        XCTAssertEqual(expense.originalCurrency, "JPY")
        XCTAssertEqual(expense.amount, try Money.convert(34_000, rate: 100, to: reporting))
        XCTAssertEqual(expense.splits.map(\.amount), [expense.amount])
        XCTAssertEqual(expense.cardID, travel.id)
        XCTAssertTrue(run("propose_expense", ["amount": 3, "currency": "dollars", "category": "Transport"]).isError)
    }

    func testSiriLogSavesWhatTheModelProposesAndSpeaksItsQuestion() async throws {
        let proposal = try XCTUnwrap(run("propose_expense", ["amount": 28000, "category": "Food & Drink", "note": "Kopi", "card": "Daily"]).proposal)
        let before = try repo.expenses(in: daily.id).count
        let saved = try await AssistantLog.save("kopi 28rb on daily", card: nil, model: model, agent: ScriptedAgent([.text("Added."), .proposal(proposal)]))
        XCTAssertEqual(saved?.expenses.map(\.id), [proposal.id])
        XCTAssertEqual(try repo.expenses(in: daily.id).count, before + 1)

        do {
            _ = try await AssistantLog.save("kopi", card: nil, model: model, agent: ScriptedAgent([.text("How much was it?")]))
            XCTFail("a question is Siri's answer")
        } catch { XCTAssertEqual(error.localizedDescription, "How much was it?") }
        let fallback = try await AssistantLog.save("kopi", card: nil, model: model, agent: ScriptedAgent([.error("Offline")]))
        XCTAssertNil(fallback, "an error hands over to the app's own reader")
    }

    func testSiriLogSavesBillsUsesTheShortcutsCategoryAndSavesAllOrNothing() async throws {
        let transport = try category("Transport", in: daily)
        let kopi = try XCTUnwrap(run("propose_expense", ["amount": 28000, "category": "Food & Drink", "note": "Kopi", "card": "Daily"]).proposal)
        let bill = try XCTUnwrap(run("propose_bill", ["name": "Spotify", "amount": 55000, "category": "Food & Drink", "frequency": "monthly", "day": 5, "card": "Daily"]).bill)
        let saved = try await AssistantLog.save("kopi 28rb, spotify 55rb every month", card: nil, category: ExpenseCategoryEntity(transport), model: model,
                                                agent: ScriptedAgent([.proposal(kopi), .bill(bill)]))
        XCTAssertEqual(saved?.expenses.first?.splits.map(\.categoryID), [transport.id], "the Shortcut's Category wins")
        XCTAssertEqual(try repo.expenses(in: daily.id).first { $0.id == kopi.id }?.splits.map(\.categoryID), [transport.id])
        XCTAssertTrue(try repo.bills(in: daily.id).contains { $0.id == bill.id }, "a repeat said to Siri is saved as a bill")

        let before = try repo.expenses(in: daily.id).count
        let roti = try XCTUnwrap(run("propose_expense", ["amount": 15000, "category": "Food & Drink", "note": "Roti", "card": "Daily"]).proposal)
        var broken = roti; broken.id = UUID(); broken.splits = [Split(categoryID: UUID(), amount: broken.amount)]
        do {
            _ = try await AssistantLog.save("roti and more", card: nil, model: model, agent: ScriptedAgent([.proposal(roti), .proposal(broken)]))
            XCTFail("the second one can't be saved")
        } catch {}
        XCTAssertEqual(try repo.expenses(in: daily.id).count, before, "nothing stays when one fails")

        let existing = try XCTUnwrap(repo.expenses(in: daily.id).first)
        let change = try XCTUnwrap(run("propose_delete", ["id": existing.id.uuidString]).change)
        do {
            _ = try await AssistantLog.save("delete my coffee", card: nil, model: model, agent: ScriptedAgent([.change(change)]))
            XCTFail("changes go to the chat")
        } catch { XCTAssertTrue(error.localizedDescription.contains("chat")) }
    }

    private var tripScope: AnalyticsFilterScope { .stack(id: trip.id, name: trip.name) }

    private func run(_ name: String, _ input: [String: Any], scope: AnalyticsFilterScope = .allCards) -> ToolExecutor.Outcome {
        let data = try! JSONSerialization.data(withJSONObject: input)
        return ToolExecutor(model: model, scope: scope, now: now).run(name, input: data)
    }

    private func proposeFetchingRate(_ input: [String: Any], scope: AnalyticsFilterScope) async -> ToolExecutor.Outcome {
        let data = try! JSONSerialization.data(withJSONObject: input)
        let executor = ToolExecutor(model: model, scope: scope, now: now)
        await executor.fetchRate(for: "propose_expense", input: data)
        return executor.run("propose_expense", input: data)
    }

    private func json(_ outcome: ToolExecutor.Outcome) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(outcome.json.utf8))) as? [String: Any] ?? [:]
    }

    private func rupiah(_ amount: Any?) -> Int64? { ((amount as? [String: Any])?["value"] as? NSNumber)?.int64Value }

    private func category(_ name: String, in card: Card) throws -> ExpenseCategory {
        try XCTUnwrap(try repo.categories(in: card.id).first { $0.name == name })
    }

    private func save(_ rupiah: Int64, _ day: String, _ note: String, _ category: ExpenseCategory, _ card: Card) throws {
        let minor = rupiah * 100
        try repo.save(Expense(amount: minor, day: day, note: note, splits: [.init(categoryID: category.id, amount: minor)], cardID: card.id), in: card.id)
    }
}

/// The same rate, 100, on the day asked for.
private struct OneRate: RateSource {
    func rates(from: String, to: String, start: String, end: String) async throws -> [String: Decimal] { [end: 100] }
}

/// A chat model that always replies the same.
@MainActor
private final class ScriptedAgent: ChatBackend {
    let outputs: [ChatAgent.Output]
    init(_ outputs: [ChatAgent.Output]) { self.outputs = outputs }
    func note(_ text: String) {}
    func reset() {}
    func send(_ text: String, scope: AnalyticsFilterScope, now: Date) async -> [ChatAgent.Output] { outputs }
}
