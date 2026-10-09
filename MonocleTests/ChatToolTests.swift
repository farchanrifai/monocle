import XCTest
@testable import Monocle

@MainActor
final class ChatToolTests: XCTestCase {
    private var model: AppModel!
    private var repo: ExpenseRepository!
    private var daily: BookProfile!
    private var travel: BookProfile!
    private var trip: CardStack!
    private var tempDir: URL!
    private let now = Day.date("2026-09-15")!

    override func setUp() async throws {
        repo = try ExpenseRepository(inMemory: true)
        daily = try repo.createBook(named: "Daily")
        travel = try repo.createBook(named: "Tokyo Travel")
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

    func testProposeBuildsUnsavedExpenseOnScopeCardInMinorUnits() throws {
        let before = try repo.expenses(in: travel.id).count
        let outcome = run("propose_expense", ["amount": 28000, "category": "food & DRINK", "note": " Kopi "], scope: tripScope)

        XCTAssertFalse(outcome.isError, outcome.json)
        let expense = try XCTUnwrap(outcome.proposal)
        XCTAssertEqual(expense.amount, 2_800_000)
        XCTAssertEqual(expense.allocations.map(\.amount), [2_800_000])
        XCTAssertEqual(expense.bookID, travel.id, "Active card is outside the Trip stack, so the stack's first card is the target")
        XCTAssertEqual(expense.source, "chat")
        XCTAssertEqual(expense.note, "Kopi")
        XCTAssertEqual(expense.day, "2026-09-15")
        XCTAssertEqual(json(outcome)["status"] as? String, "shown_to_user")
        XCTAssertEqual(try repo.expenses(in: travel.id).count, before, "Proposals never write")
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
        XCTAssertEqual(outcome.proposal?.bookID, travel.id)
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
        XCTAssertNotNil(outcome.chart)

        let byCard = run("get_summary", ["period": "this_month", "group_by": "card", "scope": "all_cards"])
        XCTAssertNil(byCard.chart)
        XCTAssertEqual(Set((json(byCard)["groups"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }), ["Daily", "Tokyo Travel"])
    }

    func testComparePeriodsComputesDeltas() throws {
        let result = json(run("compare_periods", ["period_a": "last_month", "period_b": "this_month", "scope": "card:Daily"]))
        XCTAssertEqual(rupiah(result["total_a"]), 60_000)
        XCTAssertEqual(rupiah(result["total_b"]), 73_000)
        XCTAssertEqual(rupiah(result["change"]), 13_000)
    }

    // MARK: - get_budget_status / list_cards

    func testBudgetStatusWithAndWithoutBudget() throws {
        XCTAssertEqual(json(run("get_budget_status", ["card": "Tokyo Travel"]))["has_budget"] as? Bool, false)

        let food = try category("Food & Drink", in: daily)
        var budget = BudgetVersion.initial(overallLimit: 100_000_00, startDay: 1, date: now, bookID: daily.id)
        budget.categoryLimits = [CategoryBudget(categoryID: food.id, limit: 50_000_00)]
        try repo.save(budget, in: daily.id)
        try model.reload()

        let result = json(run("get_budget_status", ["card": "Daily"]))
        XCTAssertEqual(result["has_budget"] as? Bool, true)
        XCTAssertEqual(rupiah(result["spent"]), 73_000)
        XCTAssertEqual(rupiah(result["remaining"]), 27_000)
        let category = try XCTUnwrap((result["categories"] as? [[String: Any]])?.first)
        XCTAssertEqual(rupiah(category["remaining"]), -23_000, "Over-budget categories report a negative remainder")
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

    // MARK: - Helpers

    private var tripScope: AnalyticsFilterScope { .stack(id: trip.id, name: trip.name) }

    private func run(_ name: String, _ input: [String: Any], scope: AnalyticsFilterScope = .allCards) -> ToolExecutor.Outcome {
        let data = try! JSONSerialization.data(withJSONObject: input)
        return ToolExecutor(model: model, scope: scope, now: now).run(name, input: data)
    }

    private func json(_ outcome: ToolExecutor.Outcome) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(outcome.json.utf8))) as? [String: Any] ?? [:]
    }

    private func rupiah(_ amount: Any?) -> Int64? { ((amount as? [String: Any])?["rupiah"] as? NSNumber)?.int64Value }

    private func category(_ name: String, in book: BookProfile) throws -> ExpenseCategory {
        try XCTUnwrap(try repo.categories(in: book.id).first { $0.name == name })
    }

    private func save(_ rupiah: Int64, _ day: String, _ note: String, _ category: ExpenseCategory, _ book: BookProfile) throws {
        let minor = rupiah * 100
        try repo.save(Expense(amount: minor, day: day, note: note, allocations: [.init(categoryID: category.id, amount: minor)], bookID: book.id), in: book.id)
    }
}
