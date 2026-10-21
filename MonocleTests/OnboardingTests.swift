import XCTest
@testable import Monocle

/// First launch: the currency is set without exchange rates, then the user's card is made.
@MainActor
final class OnboardingTests: XCTestCase {
    private var model: AppModel!
    private var tempDir: URL!

    override func setUp() async throws {
        UserDefaults.standard.removeObject(forKey: "onboarded")
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try SampleCardSeeder.seedIfNeeded(repository: repo, directory: tempDir)
        try repo.prepareInitialBudget(settings: PrototypeSettings())
        model = AppModel(expenses: try ExpenseService(store: repo), state: FileLocalStateStore(directory: tempDir))
        try model.reload()
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: "onboarded")
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testCurrencyScalesTheSampleCardInsteadOfConverting() throws {
        let coffee = try XCTUnwrap(model.expenses(for: Card.demo.id).first { $0.note == "Morning coffee" })
        XCTAssertEqual(coffee.amount, 28_000_00)
        try model.setUpCurrency("USD")
        XCTAssertEqual(model.reportingCurrency, "USD")
        let scaled = try XCTUnwrap(model.expenses(for: Card.demo.id).first { $0.id == coffee.id })
        XCTAssertEqual(scaled.amount, 175, "Rp28.000 reads as $1.75")
        XCTAssertNil(scaled.originalCurrency, "sample data is rewritten, not marked as foreign")
        XCTAssertEqual(scaled.splits.map(\.amount), [175])
        XCTAssertEqual(model.settings.budget, 281_25)
    }

    func testFinishingMakesTheRealCardAndCanHideTheSample() throws {
        XCTAssertTrue(model.needsOnboarding)
        try model.finishOnboarding(cardName: "  Daily  ", keepSample: false)
        let card = try XCTUnwrap(model.cards.first { $0.kind == .real })
        XCTAssertEqual(card.name, "Daily")
        XCTAssertEqual(model.activeCardID, card.id)
        XCTAssertTrue(model.hiddenCardIDs.contains(Card.demo.id))
        XCTAssertFalse(model.needsOnboarding)
        XCTAssertThrowsError(try model.setUpCurrency("EUR"), "the no-rates shortcut is only for a workspace without real data")
    }
}
