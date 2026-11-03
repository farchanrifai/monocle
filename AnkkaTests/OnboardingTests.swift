import XCTest
@testable import Ankka

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

    func testFinishingMakesTheRealCardAndDeletesTheSample() throws {
        XCTAssertTrue(model.needsOnboarding)
        try model.finishOnboarding(cardName: "  Daily  ")
        let card = try XCTUnwrap(model.cards.first { $0.kind == .real })
        XCTAssertEqual(card.name, "Daily")
        XCTAssertEqual(model.activeCardID, card.id)
        XCTAssertEqual(model.cards.map(\.id), [card.id], "Try the demo replaces the Sample card")
        XCTAssertFalse(model.needsOnboarding)
        XCTAssertThrowsError(try model.setUpCurrency("EUR"), "the no-rates shortcut is only for a workspace without real data")
    }

    func testASampleCardTheUserWroteToIsHiddenNotDeleted() throws {
        let category = try XCTUnwrap(model.activeCategories(for: Card.demo.id).first)
        let mine = Expense(amount: 5_000, day: Day.string(.now), note: "Mine", splits: [.init(categoryID: category.id, amount: 5_000)], cardID: Card.demo.id)
        try model.save(mine)
        try model.finishOnboarding(cardName: "Daily")
        XCTAssertTrue(model.cards.contains { $0.id == Card.demo.id }, "the user's entry stays")
        XCTAssertFalse(model.unhiddenCards.contains { $0.id == Card.demo.id })
    }

    func testTheDemoIsDatedFromTodayAndLeavesTheRealCardsAlone() throws {
        let before = model.cards.map(\.id)
        model.startDemo()
        let demo = try XCTUnwrap(model.demo)
        let folder = try XCTUnwrap(demo.demoDirectory)
        XCTAssertTrue(demo.isDemo)
        XCTAssertTrue(demo.isPro, "every feature to look at")
        XCTAssertEqual(demo.cards.count, 4)
        let yesterday = Day.string(Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(demo.allExpenses().map(\.day).max()), yesterday, "made from today, whenever it is opened")
        XCTAssertEqual(model.cards.map(\.id), before)

        model.endDemo()
        XCTAssertNil(model.demo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path), "Exit throws the copy away")
    }

    func testFinishingAgainOnFreeReusesTheCardInsteadOfHittingTheLimit() throws {
        model.pro = ProStore(defaults: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)), listen: false)
        XCTAssertFalse(model.isPro)
        try model.finishOnboarding(cardName: "Daily")
        try model.finishOnboarding(cardName: "Everyday")
        let real = model.cards.filter { $0.kind == .real }
        XCTAssertEqual(real.map(\.name), ["Everyday"])
    }
}

/// Free keeps writing to its card; new stacks, stack caps and CSV import are Pro on every path.
@MainActor
final class FreePlanGateTests: XCTestCase {
    func testFreeCanArrangeStacksButNotAddStacksCapsOrImport() throws {
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = AppModel(expenses: try ExpenseService(store: repo), state: FileLocalStateStore(directory: dir))
        model.pro = ProStore(defaults: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)), listen: false)
        XCTAssertFalse(model.isPro)
        let card = try model.createCard(named: "Daily")

        var renamed = model.stacks
        renamed[0].name = "Everyday"
        XCTAssertNoThrow(try model.saveStackConfiguration(renamed, activeStackID: model.activeStackID, alwaysHiddenIDs: []))
        XCTAssertThrowsError(try model.saveStackConfiguration(model.stacks + [Stack(name: "Trip")], activeStackID: model.activeStackID, alwaysHiddenIDs: [])) {
            XCTAssertEqual($0 as? PlanError, .stacks)
        }
        var capped = model.stacks
        capped[0].capLimit = 500_00
        XCTAssertThrowsError(try model.saveStackConfiguration(capped, activeStackID: model.activeStackID, alwaysHiddenIDs: [])) {
            XCTAssertEqual($0 as? PlanError, .stackBudget)
        }
        let category = try XCTUnwrap(model.activeCategories(for: card.id).first)
        let row = Expense(amount: 100_00, day: Day.string(.now), note: "csv", splits: [.init(categoryID: category.id, amount: 100_00)], source: "csv", cardID: card.id)
        XCTAssertThrowsError(try model.importExpenses([row], to: card.id)) { XCTAssertEqual($0 as? PlanError, .csvImport) }
        XCTAssertEqual(model.stacks.map(\.name), ["Everyday"])
        XCTAssertTrue(model.expenses(for: card.id).isEmpty)
    }

    func testAddOnALockedCardOpensThePaywallFirst() throws {
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = AppModel(expenses: try ExpenseService(store: repo), state: FileLocalStateStore(directory: dir))
        let cards = [try model.createCard(named: "Daily"), try model.createCard(named: "Travel")] // made on Pro
        model.pro = ProStore(defaults: try XCTUnwrap(UserDefaults(suiteName: UUID().uuidString)), listen: false) // lapsed
        let locked = try XCTUnwrap(cards.first { model.isLocked($0.id) })
        let kept = try XCTUnwrap(cards.first { !model.isLocked($0.id) })
        XCTAssertFalse(model.isLocked(Card.demo.id))

        model.openEntry(for: locked.id)
        XCTAssertFalse(model.showEntry)
        XCTAssertEqual(model.paywall, PlanError.lockedCard.localizedDescription)
        model.paywall = nil
        model.openEntry(for: kept.id)
        XCTAssertTrue(model.showEntry)
    }
}

/// The intro's rolling numbers land on the amounts they show, in rupiah and in dollars.
final class IntroMoneyTests: XCTestCase {
    func testOdometersLandOnTheAmountsTheyShow() {
        func digits(_ text: String) -> [Int] { text.compactMap(\.wholeNumberValue) }
        func shown(_ targets: [Double]) -> [Int] { targets.map { (Int($0) - 1) % 10 } }
        func value(_ digits: [Int]) -> Int { digits.reduce(0) { $0 * 10 + $1 } }
        for money in [IntroMoney.rupiah, .dollar] {
            XCTAssertEqual(shown(money.dailyTargets), digits(money.dailyTotal), money.dailyTotal)
            XCTAssertEqual(shown(money.baliTargets), digits(money.baliTotal), money.baliTotal)
            XCTAssertEqual(shown(money.chipTargets), digits(money.chipAmount), money.chipAmount)
            XCTAssertEqual(shown(money.convertedTargets), digits(money.converted), money.converted)
            XCTAssertEqual(shown(money.leftTargets), digits(money.left), money.left)
            XCTAssertEqual(value(shown(money.dailyAfterChip)) - value(shown(money.dailyTargets)), value(digits(money.chipAmount)),
                           "Daily rolls up by the chip's amount")
            XCTAssertTrue(zip(money.dailyTargets, money.dailyAfterChip).allSatisfy { $0 <= $1 }, "wheels only roll forward")
            let all = money.dailyTargets + money.dailyAfterChip + money.baliTargets + money.chipTargets + money.convertedTargets + money.leftTargets
            XCTAssertTrue(all.allSatisfy { (1...30).contains($0) }, "every target is a glyph on the wheel")
        }
    }
}
