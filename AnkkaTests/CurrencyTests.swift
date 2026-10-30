import XCTest
@testable import Ankka

/// Fixed daily rates for every day of a requested range: "JPY>IDR" → 113.
private struct FixedRates: RateSource {
    let table: [String: Decimal]
    func rates(from: String, to: String, start: String, end: String) async throws -> [String: Decimal] {
        guard let rate = table["\(from)>\(to)"], var day = Day.date(start), let last = Day.date(end) else { throw RateError.unavailable }
        var result: [String: Decimal] = [:]
        while day <= last {
            result[Day.string(day)] = rate
            day = Day.calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return result
    }
}

@MainActor
final class CurrencyTests: XCTestCase {
    override func tearDown() { Money.reportingCurrency = "IDR"; super.tearDown() }

    func testMoneyFormatsParsesAndConvertsPerCurrency() throws {
        XCTAssertEqual(Money.format(2_800_000), "Rp28,000")
        XCTAssertEqual(Money.format(1_200_000, code: "JPY"), "¥12,000")
        XCTAssertEqual(Money.format(4_050, code: "USD"), "$40.50")
        XCTAssertEqual(try Money.parse("40.50", locale: Locale(identifier: "en_US"), code: "USD"), 4_050)
        XCTAssertThrowsError(try Money.parse("40.50", locale: Locale(identifier: "en_US"), code: "JPY"))
        XCTAssertEqual(try Money.parse("¥12,000", locale: Locale(identifier: "en_US"), code: "JPY"), 1_200_000)
        XCTAssertEqual(try Money.parse("28k", locale: Locale(identifier: "en_US")), 2_800_000)
        // ¥12,000 at Rp113.59 = Rp1,363,080; $40.50 at Rp16,300 = Rp660,150.
        XCTAssertEqual(try Money.convert(1_200_000, rate: Decimal(string: "113.59")!, to: "IDR"), 136_308_000)
        XCTAssertEqual(try Money.convert(4_050, rate: 16_300, to: "IDR"), 66_015_000)
        // Rp1,000 at 0.0000613 USD rounds to cents: $0.06.
        XCTAssertEqual(try Money.convert(100_000, rate: Decimal(string: "0.0000613")!, to: "USD"), 6)
        XCTAssertEqual(Money.fractionDigits("IDR"), 0)
        XCTAssertEqual(Money.fractionDigits("USD"), 2)
    }

    func testRatesUseNearestEarlierCachedDay() async throws {
        let rates = ExchangeRates(source: FixedRates(table: ["JPY>IDR": 113]), fileURL: nil)
        XCTAssertNil(rates.cachedRate(from: "JPY", to: "IDR", on: "2026-10-10"))
        let rate = try await rates.rate(from: "JPY", to: "IDR", on: "2026-10-10")
        XCTAssertEqual(rate, 113)
        XCTAssertEqual(rates.cachedRate(from: "JPY", to: "IDR", on: "2026-10-12"), 113) // within a week of a cached day
        XCTAssertNil(rates.cachedRate(from: "JPY", to: "IDR", on: "2026-11-01"))
        XCTAssertEqual(rates.cachedRate(from: "IDR", to: "IDR", on: "2026-11-01"), 1)
        do { _ = try await rates.rate(from: "USD", to: "IDR", on: "2026-10-10"); XCTFail("no USD rate") } catch {}
    }

    private func makeModel() throws -> (AppModel, ExpenseRepository, URL) {
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel(expenses: try ExpenseService(store: repo), state: FileLocalStateStore(directory: dir))
        model.rates = ExchangeRates(source: FixedRates(table: ["JPY>IDR": 100, "IDR>JPY": Decimal(string: "0.01")!,
                                                               "IDR>USD": Decimal(string: "0.0001")!, "JPY>USD": Decimal(string: "0.01")!]), fileURL: nil)
        return (model, repo, dir)
    }

    func testCardCurrencyTotalsSpendingPromptAndBudgetConversion() async throws {
        let (model, _, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cardID = model.activeCardID
        try model.saveBudget(overallLimit: 2_000_000_00, startDay: 1, categoryLimits: [], applyToNextCycle: false)

        // Paid ¥1,000 at Rp100 on a rupiah card: the row shows yen, the card Rp100,000, and the app offers JPY.
        model.draft = ExpenseDraft(); model.draft.cardID = cardID
        model.draft.currency = "JPY"; model.draft.amount = "1000"; model.draft.categoryID = model.activeCategories.first?.id
        await model.refreshDraftRate()
        XCTAssertEqual(model.draft.rateSource, .fetched)
        XCTAssertTrue(model.saveDraft())
        let saved = try XCTUnwrap(model.expenses.first)
        XCTAssertEqual(saved.amount, 10_000_000)
        XCTAssertEqual(saved.paidText, "¥1,000")
        XCTAssertEqual(model.spent, 10_000_000)
        XCTAssertEqual(model.spendingCurrencySuggestion?.code, "JPY")

        await model.acceptSpendingCurrencySuggestion()
        XCTAssertEqual(model.cards.first { $0.id == cardID }?.spendingCurrency, "JPY")
        model.draft = ExpenseDraft(); model.draft.cardID = cardID
        model.prefillDraftDefaults()
        XCTAssertEqual(model.draft.currency, "JPY")

        // Budget currency → JPY: the budget converts at today's rate and totals read in yen.
        try await model.setCardCurrencies(budget: "JPY", spending: nil, for: cardID)
        XCTAssertEqual(model.activeCardCurrency, "JPY")
        XCTAssertEqual(model.activeBudget.overallLimit, 2_000_000) // Rp2,000,000 → ¥20,000
        XCTAssertEqual(model.spent, 100_000) // the ¥1,000 actually paid
        XCTAssertNil(model.cards.first { $0.id == cardID }?.spendingCurrency) // same as budget currency
    }

    func testAcrossCardsSpendingUsesEachExpensesOwnRateNotTodays() async throws {
        let (model, _, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cardID = model.activeCardID
        let category = try XCTUnwrap(model.activeCategories.first?.id)
        try model.saveBudget(overallLimit: 2_000_000_00, startDay: 1, categoryLimits: [], applyToNextCycle: false)
        try await model.setCardCurrencies(budget: "JPY", spending: nil, for: cardID)
        // ¥1,000 typed at a manual Rp120 (today's cached rate is Rp100): the ledger keeps Rp120,000.
        let yen = Expense(amount: 12_000_000, day: Day.string(.now), note: "Ramen", splits: [.init(categoryID: category, amount: 12_000_000)], cardID: cardID,
                          originalAmount: 100_000, originalCurrency: "JPY", rate: "120", rateSource: .manual)
        try model.save(yen)
        let across = model.budgetLinesAcrossCards()
        XCTAssertTrue(across.approximate, "the limit still converts at today's rate")
        let line = try XCTUnwrap(across.lines.first { $0.id == cardID })
        XCTAssertEqual(line.spent, 12_000_000, "spending is what was actually recorded in rupiah, not ¥1,000 at today's rate (Rp100,000)")
        XCTAssertEqual(line.limit, 2_000_000_00, "¥20,000 back at today's Rp100")
    }

    func testReportingCurrencyChangeReconvertsHistoryKeepsManualRatesAndConvertsBudgets() async throws {
        let (model, repo, dir) = try makeModel()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cardID = model.activeCardID
        let category = try XCTUnwrap(model.activeCategories.first?.id)
        try model.saveBudget(overallLimit: 5_000_000_00, startDay: 1, categoryLimits: [], applyToNextCycle: false)
        let stack = try model.createStack(name: "Everyday", cardIDs: [cardID])
        var capped = stack; capped.capLimit = 3_000_000_00; try model.updateStack(capped)
        // Rp50,000 paid in rupiah, and ¥1,000 typed at a manual Rp120.
        let rupiah = Expense(amount: 5_000_000, day: "2026-10-01", note: "Lunch", splits: [.init(categoryID: category, amount: 5_000_000)], cardID: cardID)
        let yen = Expense(amount: 12_000_000, day: "2026-10-02", note: "Ramen", splits: [.init(categoryID: category, amount: 12_000_000)], cardID: cardID,
                          originalAmount: 100_000, originalCurrency: "JPY", rate: "120", rateSource: .manual)
        try model.save(rupiah); try model.save(yen)

        try await model.changeReportingCurrency(to: "USD")
        XCTAssertEqual(model.reportingCurrency, "USD")
        XCTAssertEqual(Money.reportingCurrency, "USD")
        let stored = Dictionary(uniqueKeysWithValues: try repo.expenses(in: cardID).map { ($0.note, $0) })
        // Rp50,000 × 0.0001 = $5.00, kept as paid in IDR.
        XCTAssertEqual(stored["Lunch"]?.amount, 500)
        XCTAssertEqual(stored["Lunch"]?.originalCurrency, "IDR")
        XCTAssertEqual(stored["Lunch"]?.originalAmount, 5_000_000)
        // Manual Rp120 per yen chained through IDR→USD: 0.012 USD per yen, ¥1,000 = $12.00.
        XCTAssertEqual(stored["Ramen"]?.amount, 1_200)
        XCTAssertEqual(stored["Ramen"]?.rateSource, .manual)
        XCTAssertEqual(stored["Ramen"]?.originalAmount, 100_000)
        // Budget and stack cap convert at today's rate: Rp5,000,000 → $500, Rp3,000,000 → $300.
        XCTAssertEqual(model.activeBudget.overallLimit, 50_000)
        XCTAssertEqual(model.stacks.first { $0.id == stack.id }?.capLimit, 30_000)

        // Back to rupiah: the rupiah expense returns to exactly what was paid.
        model.rates = ExchangeRates(source: FixedRates(table: ["USD>IDR": 10_000, "JPY>IDR": 100]), fileURL: nil)
        try await model.changeReportingCurrency(to: "IDR")
        let back = Dictionary(uniqueKeysWithValues: try repo.expenses(in: cardID).map { ($0.note, $0) })
        XCTAssertEqual(back["Lunch"]?.amount, 5_000_000)
        XCTAssertNil(back["Lunch"]?.originalCurrency)
        XCTAssertEqual(back["Ramen"]?.originalCurrency, "JPY")
    }
}
