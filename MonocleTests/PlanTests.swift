import XCTest
@testable import Monocle

/// Free/Pro rules as ExpenseService enforces them (docs/planning/app-store-release.md).
@MainActor
final class PlanTests: XCTestCase {
    private var repo: ExpenseRepository!
    private var service: ExpenseService!

    override func setUp() async throws {
        repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
        service = try ExpenseService(store: repo)
    }

    private func expense(_ minor: Int64 = 28_000_00, on card: UUID, source: String = "manual") throws -> Expense {
        let category = try XCTUnwrap(try repo.categories(in: card).first)
        return Expense(amount: minor, day: "2026-10-01", note: "Kopi", splits: [.init(categoryID: category.id, amount: minor)], source: source, cardID: card)
    }

    private func bill(_ name: String, on card: UUID, createdAt: Date) throws -> Bill {
        let category = try XCTUnwrap(try repo.categories(in: card).first)
        return Bill(cardID: card, name: name, amount: 10_000_00, categoryID: category.id, recurrence: .monthly(day: 1),
                    recordingMode: .pending, hasReminder: false, createdAt: createdAt)
    }

    func testFreeAllowsOneRealCardAndProAllowsMore() throws {
        service.plan = Plan(isPro: false)
        let first = try service.createCard(named: "Daily")
        XCTAssertEqual(first.kind, .real)
        XCTAssertThrowsError(try service.createCard(named: "Travel")) { XCTAssertEqual($0 as? PlanError, .cardLimit) }
        service.plan = Plan(isPro: true)
        XCTAssertNoThrow(try service.createCard(named: "Travel"))
    }

    func testAfterDowngradeOnlyTheKeptCardTakesWrites() throws {
        let daily = try service.createCard(named: "Daily")
        let travel = try service.createCard(named: "Travel")
        service.plan = Plan(isPro: false, keptCardID: travel.id)
        XCTAssertThrowsError(try service.save(try expense(on: daily.id))) { XCTAssertEqual($0 as? PlanError, .lockedCard) }
        XCTAssertNoThrow(try service.save(try expense(on: travel.id)))
        XCTAssertNoThrow(try service.save(try expense(on: Card.demo.id)), "the Sample card is never locked")
        XCTAssertThrowsError(try service.renameCard(id: daily.id, to: "Old")) { XCTAssertEqual($0 as? PlanError, .lockedCard) }
        XCTAssertNoThrow(try service.deleteCard(id: daily.id), "a locked card can still be deleted")

        service.plan = Plan(isPro: false)
        XCTAssertEqual(service.plan?.keptCard(in: service.cards), travel.id, "with no choice, the first remaining real card is kept")
    }

    func testFreeRunsThreeBillsAndFreezesTheRest() throws {
        let daily = try service.createCard(named: "Daily")
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let bills = try (0..<4).map { try bill("Bill \($0)", on: daily.id, createdAt: start.addingTimeInterval(Double($0) * 60)) }
        for bill in bills { try service.saveBill(bill) }

        let plan = Plan(isPro: false)
        XCTAssertEqual(plan.frozenBills(try service.bills(for: daily.id), cards: service.cards), [bills[3].id], "the three oldest keep running")
        service.plan = plan
        XCTAssertThrowsError(try service.saveBill(try bill("Fifth", on: daily.id, createdAt: .now))) { XCTAssertEqual($0 as? PlanError, .billLimit) }
        var paused = bills[0]; paused.isActive = false
        try service.saveBill(paused)
        XCTAssertTrue(plan.frozenBills(try service.bills(for: daily.id), cards: service.cards).isEmpty, "pausing one lets the fourth run")
        XCTAssertNoThrow(try service.saveBill(bills[1]), "editing a running bill is not a new one")
    }

    func testSampleCardTakesTenUserEntriesOnAnyPlan() throws {
        service.plan = Plan(isPro: true)
        let entries = try (0..<Plan.sampleEntries).map { _ in try expense(on: Card.demo.id) }
        for entry in entries { try service.save(entry) }
        XCTAssertNoThrow(try service.save(try expense(on: Card.demo.id, source: "sample")), "seeded entries don't count")
        XCTAssertThrowsError(try service.save(try expense(on: Card.demo.id))) { XCTAssertEqual($0 as? PlanError, .sampleLimit) }
        var edited = entries[0]; edited.note = "Teh"
        XCTAssertNoThrow(try service.save(edited), "editing an entry is not a new one")
        try service.delete(entries[1].id, in: Card.demo.id)
        XCTAssertNoThrow(try service.save(try expense(on: Card.demo.id)), "deleting frees a slot")
    }

    func testForeignCurrencyIsPro() throws {
        let daily = try service.createCard(named: "Daily")
        var abroad = try expense(on: daily.id)
        abroad.originalAmount = 1_000_00; abroad.originalCurrency = "JPY"; abroad.rate = "28"; abroad.rateSource = .manual
        service.plan = Plan(isPro: false)
        XCTAssertThrowsError(try service.save(abroad)) { XCTAssertEqual($0 as? PlanError, .foreignCurrency) }
        service.plan = Plan(isPro: true)
        try service.save(abroad)
        service.plan = Plan(isPro: false)
        abroad.note = "Ramen"
        XCTAssertNoThrow(try service.save(abroad), "an expense saved in another currency on Pro stays editable")
    }

    func testNoPlanLeavesEveryWriteOpen() throws {
        XCTAssertNil(service.plan)
        _ = try service.createCard(named: "One")
        XCTAssertNoThrow(try service.createCard(named: "Two"))
        for _ in 0...Plan.sampleEntries { try service.save(try expense(on: Card.demo.id)) }
    }

    func testFreeChatAnswersFiveQuestionsADayButEveryProposal() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString))
        let answer: [ChatAgent.Output] = [.text("Rp28.000 so far.")]
        for _ in 0..<Plan.freeQuestionsPerDay {
            XCTAssertEqual(ChatSession.limitQuestions(answer, isPro: false, today: "2026-10-22", defaults: defaults), answer)
        }
        guard case .notice? = ChatSession.limitQuestions(answer, isPro: false, today: "2026-10-22", defaults: defaults).first else { return XCTFail() }
        let proposal: [ChatAgent.Output] = [.proposal(try expense(on: Card.demo.id))]
        XCTAssertEqual(ChatSession.limitQuestions(proposal, isPro: false, today: "2026-10-22", defaults: defaults), proposal, "adding is unlimited")
        XCTAssertEqual(ChatSession.limitQuestions(answer, isPro: true, today: "2026-10-22", defaults: defaults), answer)
        XCTAssertEqual(ChatSession.limitQuestions(answer, isPro: false, today: "2026-10-23", defaults: defaults), answer, "the count resets daily")
        let failure: [ChatAgent.Output] = [.error("busy")]
        XCTAssertEqual(ChatSession.limitQuestions(failure, isPro: false, today: "2026-10-23", defaults: defaults), failure)
    }
}
