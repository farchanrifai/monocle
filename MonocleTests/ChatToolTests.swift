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

        let reversed = json(run("compare_periods", ["period_a": "this_month", "period_b": "last_month", "scope": "card:Daily"]))
        XCTAssertEqual(rupiah(reversed["change"]), 13_000, "Periods are ordered earlier → later whichever way they're asked")
        XCTAssertEqual(reversed["period_a"] as? String, result["period_a"] as? String)
        XCTAssertTrue((reversed["summary"] as? String)?.hasPrefix("Spending went up by") == true)
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

    func testProposeSplitMustAddUpToTheAmount() throws {
        let split: [[String: Any]] = [["category": "Food & Drink", "amount": 30000], ["category": "shopping", "amount": 20000]]
        let outcome = run("propose_expense", ["amount": 50000, "split": split, "note": "Pasar"])
        XCTAssertFalse(outcome.isError, outcome.json)
        let expense = try XCTUnwrap(outcome.proposal)
        XCTAssertEqual(expense.allocations.map(\.amount), [3_000_000, 2_000_000])
        XCTAssertEqual(Set(expense.allocations.map(\.categoryID)).count, 2)

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
        XCTAssertEqual(edit.change?.updated?.allocations.map(\.amount), [2_000_000, 1_000_000], edit.json)
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
        XCTAssertEqual(bill.bookID, daily.id)
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
        XCTAssertEqual(updated.allocations.map(\.amount), [3_000_000], "Single allocation follows the amount")
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
                            allocations: [.init(categoryID: food.id, amount: 6_000_00), .init(categoryID: shopping.id, amount: 4_000_00)], bookID: daily.id)
        try model.save(split)
        XCTAssertTrue(run("propose_edit", ["id": split.id.uuidString, "amount": 12000]).isError)
        XCTAssertEqual(run("propose_edit", ["id": split.id.uuidString, "note": "Pasar"]).change?.updated?.allocations, split.allocations)
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
