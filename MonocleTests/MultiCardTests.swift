import XCTest
import SwiftUI
@testable import Monocle

@MainActor
final class MultiCardTests: XCTestCase {
    func testTwoCardsRemainStrictlyIsolated() throws {
        let store = try ExpenseRepository(inMemory: true)
        let cardA = try store.createCard(named: "Daily Expenses")
        let cardB = try store.createCard(named: "Tokyo Vacation")

        let catsA = try store.categories(in: cardA.id)
        let catsB = try store.categories(in: cardB.id)
        let catA = catsA[0]
        let catB = catsB[1]

        let expA = Expense(id: UUID(), amount: 50_000_00, day: "2026-09-08", note: "Lunch",
                           splits: [.init(categoryID: catA.id, amount: 50_000_00)],
                           cardID: cardA.id)
        let expB = Expense(id: UUID(), amount: 120_000_00, day: "2026-09-08", note: "Train pass",
                           splits: [.init(categoryID: catB.id, amount: 120_000_00)],
                           cardID: cardB.id)
        try store.save(expA, in: cardA.id)
        try store.save(expB, in: cardB.id)

        let budgetA = BudgetVersion.initial(overallLimit: 2_000_000_00, startDay: 1, cardID: cardA.id)
        let budgetB = BudgetVersion.initial(overallLimit: 10_000_000_00, startDay: 15, cardID: cardB.id)
        try store.save(budgetA, in: cardA.id)
        try store.save(budgetB, in: cardB.id)

        // Verify isolation
        let expInA = try store.expenses(in: cardA.id)
        let expInB = try store.expenses(in: cardB.id)
        XCTAssertEqual(expInA.count, 1)
        XCTAssertEqual(expInA.first?.id, expA.id)
        XCTAssertEqual(expInB.count, 1)
        XCTAssertEqual(expInB.first?.id, expB.id)

        let budgetsInA = try store.budgets(in: cardA.id)
        let budgetsInB = try store.budgets(in: cardB.id)
        XCTAssertEqual(budgetsInA.first?.overallLimit, 2_000_000_00)
        XCTAssertEqual(budgetsInB.first?.overallLimit, 10_000_000_00)
    }

    func testCardLifecycleRenameAndDelete() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let card = try store.createCard(named: "Project Alpha")
        XCTAssertEqual(try store.cards().count, 2) // default sample card + new card

        try store.renameCard(id: card.id, to: "Project Beta")
        let updated = try store.cards().first { $0.id == card.id }
        XCTAssertEqual(updated?.name, "Project Beta")

        try store.deleteCard(id: card.id)
        XCTAssertEqual(try store.cards().count, 1)
        XCTAssertFalse(try store.cards().contains(where: { $0.id == card.id }))
    }

    func testFormatFourWorkspaceRoundTrip() throws {
        let store = try ExpenseRepository(inMemory: true)
        let cardA = try store.createCard(named: "Home")
        let catA = ExpenseCategory(id: UUID(), name: "Groceries", symbol: "cart")
        try store.saveCategory(catA, in: cardA.id)
        let expA = Expense(id: UUID(), amount: 75_000_00, day: "2026-09-08", note: "Supermarket",
                           splits: [.init(categoryID: catA.id, amount: 75_000_00)], cardID: cardA.id)
        try store.save(expA, in: cardA.id)

        let items = [
            CardBackupItem(card: cardA, categories: [catA], expenses: [expA],
                           budgets: [BudgetVersion.initial(overallLimit: 5_000_000_00, startDay: 1, cardID: cardA.id)],
                           draft: nil)
        ]
        let prefs = WorkspacePreferences(visibleCardIDs: [cardA.id], cardOrder: [cardA.id], allActivitiesScope: true, visualDirection: "Instrument")
        let workspace = WorkspaceBackup(formatVersion: 4, exportedAt: .now, currency: "IDR", minorUnitScale: 2,
                                        cards: items, preferences: prefs, settings: PrototypeSettings())
        try workspace.validate()

        let encoded = try workspace.encoded()
        let decoded = try WorkspaceBackup.decode(encoded)
        XCTAssertEqual(decoded.formatVersion, 4)
        XCTAssertEqual(decoded.cards.count, 1)
        XCTAssertEqual(decoded.cards[0].card.name, "Home")
        XCTAssertEqual(decoded.cards[0].expenses.first?.amount, 75_000_00)
        XCTAssertEqual(decoded.preferences.visualDirection, "Instrument")

        // Restore into a fresh store
        let freshStore = try ExpenseRepository(inMemory: true)
        try freshStore.replace(with: decoded)
        let restoredCards = try freshStore.cards()
        XCTAssertTrue(restoredCards.contains(where: { $0.id == cardA.id }))
        let restoredExpenses = try freshStore.expenses(in: cardA.id)
        XCTAssertEqual(restoredExpenses.count, 1)
        XCTAssertEqual(restoredExpenses[0].id, expA.id)
    }

    func testLegacyFormatThreeSingleCardDecodesAsWorkspace() throws {
        let cat = ExpenseCategory.defaults[0]
        let exp = Expense(amount: 25_000_00, day: "2026-09-08", note: "Coffee",
                          splits: [.init(categoryID: cat.id, amount: 25_000_00)])
        let budget = BudgetVersion.initial(overallLimit: 5_000_000_00, startDay: 1)
        let singleCardBackup = CardBackup(categories: [cat], expenses: [exp], draft: ExpenseDraft(), settings: PrototypeSettings(), budgets: [budget])
        let data = try singleCardBackup.encoded()

        // Decode as WorkspaceBackup (Format 5+ upgrade)
        let workspace = try WorkspaceBackup.decode(data)
        XCTAssertGreaterThanOrEqual(workspace.formatVersion, 5)
        XCTAssertEqual(workspace.cards.count, 1)
        XCTAssertEqual(workspace.cards[0].expenses.count, 1)
        XCTAssertEqual(workspace.cards[0].expenses[0].id, exp.id)
        XCTAssertEqual(workspace.cards[0].categories[0].id, cat.id)
    }

    func testVisualDirectionPersistsAndDecodes() throws {
        var prefs = WorkspacePreferences()
        XCTAssertEqual(prefs.direction, .light)
        XCTAssertEqual(prefs.visualDirection, "Light")
        XCTAssertFalse(prefs.autoAppearance)

        prefs.autoAppearance = true
        XCTAssertTrue(prefs.autoAppearance)

        prefs.direction = .instrument
        XCTAssertEqual(prefs.visualDirection, "Instrument")
        XCTAssertEqual(prefs.direction, .instrument)

        prefs.direction = .ledger
        XCTAssertEqual(prefs.visualDirection, "Ledger")
        XCTAssertEqual(prefs.direction, .ledger)

        prefs.direction = .signal
        XCTAssertEqual(prefs.visualDirection, "Signal")
        XCTAssertEqual(prefs.direction, .signal)

        prefs.direction = .light
        XCTAssertEqual(prefs.visualDirection, "Light")
        XCTAssertEqual(prefs.direction, .light)

        let encoded = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(WorkspacePreferences.self, from: encoded)
        XCTAssertEqual(decoded.direction, .light)
        XCTAssertEqual(decoded.visualDirection, "Light")
        XCTAssertTrue(decoded.autoAppearance)

        // Backward compatibility: decoding older JSON without autoAppearance
        let legacyJSON = """
        {
            "visibleBookIDs": [],
            "bookOrder": [],
            "allActivitiesScope": false,
            "visualDirection": "Instrument"
        }
        """.data(using: .utf8)!
        let legacyDecoded = try JSONDecoder().decode(WorkspacePreferences.self, from: legacyJSON)
        XCTAssertEqual(legacyDecoded.direction, .instrument)
        XCTAssertFalse(legacyDecoded.autoAppearance)
    }

    func testAppModelAppearanceModesAndAutoSwitch() throws {
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let expenseService = try ExpenseService(store: repo)
        let model = AppModel(expenses: expenseService, state: state)

        // Default: Light mode, auto switch is false
        XCTAssertEqual(model.visualDirection, .light)
        XCTAssertEqual(model.manualAppearance, .light)
        XCTAssertFalse(model.autoAppearance)
        XCTAssertEqual(model.preferredColorScheme, .light)
        XCTAssertEqual(model.effectiveDirection(for: .light), .light)
        XCTAssertEqual(model.effectiveDirection(for: .dark), .light)

        // Switch to Dark mode manually
        model.manualAppearance = .dark
        XCTAssertEqual(model.visualDirection, .instrument)
        XCTAssertEqual(model.manualAppearance, .dark)
        XCTAssertFalse(model.autoAppearance)
        XCTAssertEqual(model.preferredColorScheme, .dark)
        XCTAssertEqual(model.effectiveDirection(for: .light), .instrument)
        XCTAssertEqual(model.effectiveDirection(for: .dark), .instrument)

        // Switch back to Light mode manually
        model.manualAppearance = .light
        XCTAssertEqual(model.visualDirection, .light)
        XCTAssertEqual(model.manualAppearance, .light)
        XCTAssertFalse(model.autoAppearance)
        XCTAssertEqual(model.preferredColorScheme, .light)

        // Enable Auto switch
        model.autoAppearance = true
        XCTAssertTrue(model.autoAppearance)
        XCTAssertNil(model.preferredColorScheme) // nil lets iOS system control color scheme
        XCTAssertEqual(model.effectiveDirection(for: .light), .light)
        XCTAssertEqual(model.effectiveDirection(for: .dark), .instrument)

        // Changing visual direction manually turns off auto appearance
        model.visualDirection = .signal
        XCTAssertFalse(model.autoAppearance)
        XCTAssertEqual(model.visualDirection, .signal)
        XCTAssertEqual(model.manualAppearance, .dark)
        XCTAssertEqual(model.preferredColorScheme, .dark)
    }

    func testCardCustomizationColorAndLuminance() {
        XCTAssertTrue(CardPalette.isDark(hex: "#000000"))
        XCTAssertTrue(CardPalette.isDark(hex: "#212124"))
        XCTAssertFalse(CardPalette.isDark(hex: "#FFFFFF"))
        XCTAssertFalse(CardPalette.isDark(hex: "#D6F061"))

        let color = Color(red: 1.0, green: 0.0, blue: 0.0)
        let hex = CardPalette.hexString(from: color)
        XCTAssertEqual(hex, "#FF0000")

        // Text tone auto vs overrides
        let lightAuto = CardCustomization(style: .palette(index: 2), textTone: .auto) // Acid Lime is bright
        XCTAssertEqual(CardPalette.resolvedTextColor(for: lightAuto), .black)

        let darkAuto = CardCustomization(style: .palette(index: 8), textTone: .auto) // Obsidian is dark
        XCTAssertEqual(CardPalette.resolvedTextColor(for: darkAuto), .white)

        let lightManual = CardCustomization(style: .palette(index: 2), textTone: .light)
        XCTAssertEqual(CardPalette.resolvedTextColor(for: lightManual), .white)

        let darkManual = CardCustomization(style: .palette(index: 8), textTone: .dark)
        XCTAssertEqual(CardPalette.resolvedTextColor(for: darkManual), .black)

        let stockSunset = CardCustomization(style: .stock(.sunsetHeat), textTone: .auto)
        XCTAssertEqual(CardPalette.resolvedTextColor(for: stockSunset), .white)

        let stockParchment = CardCustomization(style: .stock(.warmParchment), textTone: .auto)
        XCTAssertEqual(CardPalette.resolvedTextColor(for: stockParchment), .black)

        let photoCustom = CardCustomization(style: .customPhoto(filename: "card.jpg"), textTone: .auto)
        XCTAssertEqual(CardPalette.resolvedTextColor(for: photoCustom), .white)
    }

    func testCardCustomizationPersistenceAndRoundTrip() throws {
        let cardID = UUID()
        var prefs = WorkspacePreferences()
        XCTAssertTrue(prefs.cardCustomizations.isEmpty)

        let custom = CardCustomization(style: .stock(.auroraBorealis), textTone: .light)
        prefs.cardCustomizations[cardID] = custom

        let encoded = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(WorkspacePreferences.self, from: encoded)

        XCTAssertEqual(decoded.cardCustomizations[cardID]?.style, .stock(.auroraBorealis))
        XCTAssertEqual(decoded.cardCustomizations[cardID]?.textTone, .light)

        // Test customColor
        prefs.cardCustomizations[cardID] = CardCustomization(style: .customColor(hex: "#123456"), textTone: .auto)
        let enc2 = try JSONEncoder().encode(prefs)
        let dec2 = try JSONDecoder().decode(WorkspacePreferences.self, from: enc2)
        XCTAssertEqual(dec2.cardCustomizations[cardID]?.style, .customColor(hex: "#123456"))

        // Test customPhoto
        prefs.cardCustomizations[cardID] = CardCustomization(style: .customPhoto(filename: "artwork-\(cardID).jpg"), textTone: .dark)
        let enc3 = try JSONEncoder().encode(prefs)
        let dec3 = try JSONDecoder().decode(WorkspacePreferences.self, from: enc3)
        XCTAssertEqual(dec3.cardCustomizations[cardID]?.style, .customPhoto(filename: "artwork-\(cardID).jpg"))
        XCTAssertEqual(dec3.cardCustomizations[cardID]?.textTone, .dark)
    }

    func testCardArtworkStoreSaveLoadDelete() throws {
        let testID = UUID()
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
        let testImage = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
        let rawData = testImage.jpegData(compressionQuality: 0.9)!

        let filename = try CardArtworkStore.shared.saveArtwork(rawData, for: testID)
        XCTAssertTrue(filename.contains(testID.uuidString))

        let loaded = CardArtworkStore.shared.loadArtwork(filename: filename)
        XCTAssertNotNil(loaded)

        let data = CardArtworkStore.shared.loadArtworkData(filename: filename)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)

        CardArtworkStore.shared.deleteArtwork(filename: filename)
        XCTAssertNil(CardArtworkStore.shared.loadArtwork(filename: filename))
    }

    func testFormatFiveWorkspaceRoundTripWithCardArtworkAndCustomizations() throws {
        let store = try ExpenseRepository(inMemory: true)
        let cardA = try store.createCard(named: "Trip to Paris")
        let catA = ExpenseCategory(id: UUID(), name: "Museums", symbol: "airplane")
        try store.saveCategory(catA, in: cardA.id)
        let expA = Expense(id: UUID(), amount: 350_000_00, day: "2026-09-08", note: "Louvre Ticket",
                           splits: [.init(categoryID: catA.id, amount: 350_000_00)], cardID: cardA.id)
        try store.save(expA, in: cardA.id)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50))
        let sampleImage = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        }
        let sampleData = sampleImage.jpegData(compressionQuality: 0.8)!
        let photoFilename = "sample-\(cardA.id.uuidString).jpg"

        var prefs = WorkspacePreferences(visibleCardIDs: [cardA.id], cardOrder: [cardA.id])
        prefs.cardCustomizations[cardA.id] = CardCustomization(style: .customPhoto(filename: photoFilename), textTone: .auto)

        let items = [
            CardBackupItem(card: cardA, categories: [catA], expenses: [expA], budgets: [], draft: nil)
        ]
        let workspace = WorkspaceBackup(
            formatVersion: 5,
            exportedAt: .now,
            currency: "IDR",
            minorUnitScale: 2,
            cards: items,
            preferences: prefs,
            settings: PrototypeSettings(),
            cardArtworks: [photoFilename: sampleData]
        )
        try workspace.validate()

        let encoded = try workspace.encoded()
        let decoded = try WorkspaceBackup.decode(encoded)

        XCTAssertEqual(decoded.formatVersion, 5)
        XCTAssertEqual(decoded.cards.count, 1)
        XCTAssertEqual(decoded.preferences.cardCustomizations[cardA.id]?.style, .customPhoto(filename: photoFilename))
        XCTAssertEqual(decoded.cardArtworks?[photoFilename], sampleData)

        // Restore into fresh store and verify artwork import
        let freshStore = try ExpenseRepository(inMemory: true)
        try freshStore.replace(with: decoded)

        let loadedArtwork = CardArtworkStore.shared.loadArtwork(filename: photoFilename)
        XCTAssertNotNil(loadedArtwork)

        // Clean up
        CardArtworkStore.shared.deleteArtwork(filename: photoFilename)
    }

    func testStacksAndAlwaysHiddenFiltering() throws {
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
        let daily = try repo.createCard(named: "Daily")
        let travel = try repo.createCard(named: "Tokyo Travel")
        let shopping = try repo.createCard(named: "Shopping")
        let oldTrip = try repo.createCard(named: "Old Bali Trip")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let expenseService = try ExpenseService(store: repo)
        let model = AppModel(expenses: expenseService, state: state)

        // Add expense to each card using card-scoped categories
        let catDaily = try repo.categories(in: daily.id)[0]
        let catTravel = try repo.categories(in: travel.id)[0]
        let catShopping = try repo.categories(in: shopping.id)[0]
        let catOldTrip = try repo.categories(in: oldTrip.id)[0]
        try repo.save(Expense(id: UUID(), amount: 10_000_00, day: "2026-09-10", note: "Daily Coffee", splits: [.init(categoryID: catDaily.id, amount: 10_000_00)], cardID: daily.id), in: daily.id)
        try repo.save(Expense(id: UUID(), amount: 50_000_00, day: "2026-09-10", note: "Sushi", splits: [.init(categoryID: catTravel.id, amount: 50_000_00)], cardID: travel.id), in: travel.id)
        try repo.save(Expense(id: UUID(), amount: 30_000_00, day: "2026-09-10", note: "Souvenir", splits: [.init(categoryID: catShopping.id, amount: 30_000_00)], cardID: shopping.id), in: shopping.id)
        try repo.save(Expense(id: UUID(), amount: 99_000_00, day: "2026-09-10", note: "Old Resort", splits: [.init(categoryID: catOldTrip.id, amount: 99_000_00)], cardID: oldTrip.id), in: oldTrip.id)

        // Fixture writes bypass the command service; reload publishes their committed state.
        try model.reload()

        // 1. Create Travel Stack with travel & shopping cards
        let travelStack = try model.createStack(name: "Tokyo Trip", icon: "airplane", cardIDs: [travel.id, shopping.id])
        XCTAssertEqual(model.activeStackID, travelStack.id)
        XCTAssertEqual(model.filterScope, StackFilterScope.activeStack)
        let inCurrent: [UUID] = model.cardsInCurrentStack.map { $0.id }
        XCTAssertEqual(inCurrent, [travel.id, shopping.id])
        let onDeck: [UUID] = model.homeDeckCards.map { $0.id }
        XCTAssertEqual(onDeck, [travel.id, shopping.id])

        // Activities in active stack should only contain Sushi & Souvenir (not Daily Coffee or Old Resort)
        let stackActivities = model.activities(selectedCardID: nil, allCards: false)
        XCTAssertEqual(stackActivities.count, 2)
        XCTAssertTrue(stackActivities.contains(where: { $0.note == "Sushi" }))
        XCTAssertTrue(stackActivities.contains(where: { $0.note == "Souvenir" }))
        XCTAssertFalse(stackActivities.contains(where: { $0.note == "Daily Coffee" }))
        XCTAssertFalse(stackActivities.contains(where: { $0.note == "Old Resort" }))

        // 2. Switch to All Cards
        model.toggleFilterScope()
        XCTAssertEqual(model.filterScope, StackFilterScope.allCards)
        XCTAssertTrue(model.homeDeckCards.contains(where: { $0.id == oldTrip.id }))
        let allBeforeArchive = model.activities(selectedCardID: nil, allCards: true)
        XCTAssertTrue(allBeforeArchive.contains(where: { $0.note == "Old Resort" }))

        // 3. Mark Old Bali Trip as Always Hidden (Archive)
        model.setCardAlwaysHidden(id: oldTrip.id, isHidden: true)
        XCTAssertTrue(model.alwaysHiddenCardIDs.contains(oldTrip.id))
        XCTAssertFalse(model.unhiddenCards.contains(where: { $0.id == oldTrip.id }))
        XCTAssertFalse(model.homeDeckCards.contains(where: { $0.id == oldTrip.id }))

        // In All Activities, Old Resort MUST NEVER appear
        let allAfterArchive = model.activities(selectedCardID: nil, allCards: true)
        XCTAssertFalse(allAfterArchive.contains(where: { $0.note == "Old Resort" }))
        XCTAssertTrue(allAfterArchive.contains(where: { $0.note == "Daily Coffee" }))

        // But when viewing that card explicitly (via top menu), it is accessible
        let oldTripDirect = model.activities(selectedCardID: oldTrip.id, allCards: false)
        XCTAssertEqual(oldTripDirect.count, 1)
        XCTAssertEqual(oldTripDirect.first?.note, "Old Resort")

        // 4. A card belongs to one stack: putting Shopping in Daily moves it out of Tokyo Trip
        let dailyStack = try model.createStack(name: "Home Daily", icon: "house", cardIDs: [daily.id, shopping.id])
        model.setActiveStack(id: dailyStack.id)
        let inDaily: [UUID] = model.cardsInCurrentStack.map { $0.id }
        XCTAssertEqual(inDaily, [daily.id, shopping.id])
        XCTAssertEqual(model.stacks.first { $0.id == travelStack.id }?.cardIDs, [travel.id])

        // 5. Delete stack
        model.deleteStack(id: travelStack.id)
        XCTAssertFalse(model.stacks.contains(where: { $0.id == travelStack.id }))
        XCTAssertTrue(model.cards.contains(where: { $0.id == travel.id })) // Card itself still exists!
    }

    func testEachCardKeepsOneStackAndStackBudgetSumsCardsOrUsesCap() throws {
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
        let tokyo = try repo.createCard(named: "Tokyo")
        let bali = try repo.createCard(named: "Bali")
        try repo.save(BudgetVersion.initial(overallLimit: 20_000_000_00, startDay: 1, cardID: tokyo.id), in: tokyo.id)
        try repo.save(BudgetVersion.initial(overallLimit: 5_000_000_00, startDay: 10, cardID: bali.id), in: bali.id)
        var goal = BudgetVersion.initial(overallLimit: 9_000_000_00, startDay: 1, cardID: Card.demo.id)
        goal.totalUntilDay = "2099-12-31"
        try repo.save(goal, in: Card.demo.id)

        // A workspace saved before the rule: Bali sits in two stacks.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let travel = Stack(name: "Travel", cardIDs: [tokyo.id, bali.id, Card.demo.id])
        let beach = Stack(name: "Beach", cardIDs: [bali.id])
        try state.saveWorkspacePreferences(WorkspacePreferences(stacks: [travel, beach], activeStackID: travel.id))
        let model = AppModel(expenses: try ExpenseService(store: repo), state: state)
        XCTAssertNil(model.startupError)
        XCTAssertEqual(model.stacks.map(\.cardIDs), [[tokyo.id, bali.id, Card.demo.id], []])
        XCTAssertEqual(try state.loadWorkspacePreferences().stacks.map(\.cardIDs), model.stacks.map(\.cardIDs))

        // Sum of the cards' monthly budgets; the "Total until" goal budget doesn't count.
        let saved = try XCTUnwrap(model.stacks.first)
        XCTAssertEqual(model.stackBudgetLimit(saved), 25_000_000_00)
        let report = AnalyticsReport.build(data: model.reportingData(for: .stack(id: saved.id, name: saved.name)), horizon: .thisCycle)
        XCTAssertEqual(report.period?.budget.overallLimit, 25_000_000_00)
        XCTAssertEqual(report.period?.cycle.start, Cycle.containing(.now, startDay: 1).start)

        // A cap replaces the sum, and moving a card through updateStack takes it out of Travel.
        var beachEdit = try XCTUnwrap(model.stacks.last)
        beachEdit.cardIDs = [bali.id]; beachEdit.capLimit = 3_000_000_00
        try model.updateStack(beachEdit)
        XCTAssertEqual(model.stacks.first?.cardIDs, [tokyo.id, Card.demo.id])
        XCTAssertEqual(model.stackBudgetLimit(try XCTUnwrap(model.stacks.last)), 3_000_000_00)
        XCTAssertNil(Stack(name: "Empty").budgetLimit(cardLimits: []))
    }

    func testSavingAnotherCardsBudgetLeavesTheActiveCardAlone() throws {
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
        let other = try repo.createCard(named: "Tokyo")
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let model = AppModel(expenses: try ExpenseService(store: repo), state: FileLocalStateStore(directory: tempDir))
        try model.saveBudget(overallLimit: 3_000_000_00, startDay: 1, categoryLimits: [], applyToNextCycle: false)
        let activeBefore = model.activeBudget, settingsBefore = model.settings.budget

        try model.saveBudget(overallLimit: 7_000_000_00, startDay: 1, categoryLimits: [], applyToNextCycle: false, cardID: other.id)

        XCTAssertEqual(model.budgetPeriod(for: other.id).budget.overallLimit, 7_000_000_00)
        XCTAssertEqual(model.activeBudget, activeBefore)
        XCTAssertEqual(model.settings.budget, settingsBefore)
    }

    func testTotalUntilBudgetIsOnePeriodAndSwitchingBackReplacesIt() throws {
        // Domain: one period from the start through the last day, including after it ends.
        let goal = BudgetVersion(effectiveDay: "2026-10-01", overallLimit: 10_000_000_00, startDay: 1, totalUntilDay: "2027-03-31")
        let during = try XCTUnwrap(BudgetHistory.period(containing: XCTUnwrap(Day.date("2026-12-15")), budgets: [goal]))
        XCTAssertEqual(Day.string(during.cycle.start), "2026-10-01")
        XCTAssertEqual(Day.string(during.cycle.end), "2027-04-01")
        XCTAssertTrue(during.cycle.contains(Expense(amount: 1, day: "2027-03-31", note: "", splits: [])))
        XCTAssertFalse(during.cycle.contains(Expense(amount: 1, day: "2027-04-01", note: "", splits: [])))
        // After the last day the goal no longer applies: the earlier cycle budget returns, or none.
        let afterDate = try XCTUnwrap(Day.date("2027-05-01"))
        XCTAssertNil(BudgetHistory.period(containing: afterDate, budgets: [goal]))
        let monthly = BudgetVersion(effectiveDay: "2026-09-01", overallLimit: 3_000_000_00, startDay: 1)
        let back = try XCTUnwrap(BudgetHistory.period(containing: afterDate, budgets: [monthly, goal]))
        XCTAssertEqual(back.budget.overallLimit, 3_000_000_00)
        XCTAssertEqual(Day.string(back.cycle.start), "2027-05-01")
        var backwards = goal; backwards.totalUntilDay = "2026-09-30"
        XCTAssertThrowsError(try backwards.validate(categories: []))

        // App: save a goal, then go back to monthly from the same start.
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let model = AppModel(expenses: try ExpenseService(store: repo), state: FileLocalStateStore(directory: tempDir))
        try model.saveBudget(overallLimit: 3_000_000_00, startDay: 1, categoryLimits: [], applyToNextCycle: false)
        let lastDay = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 45, to: .now))
        try model.saveBudget(overallLimit: 25_000_000_00, startDay: 1, categoryLimits: [], applyToNextCycle: false, totalUntil: lastDay)
        XCTAssertEqual(model.activeBudget.totalUntilDay, Day.string(lastDay, calendar: .current))
        XCTAssertEqual(model.activeBudget.overallLimit, 25_000_000_00)
        XCTAssertEqual(Day.string(model.cycle.end), Day.string(try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: lastDay))))
        XCTAssertEqual(model.budgetHistory.count, 1)
        try model.saveBudget(overallLimit: 4_000_000_00, startDay: 1, categoryLimits: [], applyToNextCycle: false)
        XCTAssertNil(model.activeBudget.totalUntilDay)
        XCTAssertEqual(model.budgetHistory.count, 1)
        XCTAssertThrowsError(try model.saveBudget(overallLimit: 1_00, startDay: 1, categoryLimits: [], applyToNextCycle: false,
                                                  totalUntil: XCTUnwrap(Calendar.current.date(byAdding: .day, value: -60, to: .now))))
    }

    func testPaidWithLabelsDefaultsFormFieldsAndBreakdown() throws {
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let model = AppModel(expenses: try ExpenseService(store: repo), state: FileLocalStateStore(directory: tempDir))
        let cardID = model.activeCardID

        // Labels: names are unique ignoring case.
        let bca = try model.savePaymentMethod(PaymentMethod(name: "  BCA debit ", kind: .bank))
        XCTAssertEqual(bca.name, "BCA debit")
        XCTAssertThrowsError(try model.savePaymentMethod(PaymentMethod(name: "bca DEBIT"))) { XCTAssertEqual($0 as? PaymentMethodError, .duplicateName) }
        let cash = try model.savePaymentMethod(PaymentMethod(name: "Cash", kind: .cash))

        // The card default pre-fills a new expense, which saves with it.
        try model.setDefaultPaidWith(bca.id, for: cardID)
        XCTAssertEqual(model.cards.first { $0.id == cardID }?.defaultPaidWithID, bca.id)
        model.draft = ExpenseDraft(); model.draft.cardID = cardID
        model.prefillDraftDefaults()
        XCTAssertEqual(model.draft.paidWithID, bca.id)
        model.draft.amount = "28000"; model.draft.categoryID = model.activeCategories.first?.id
        XCTAssertTrue(model.saveDraft())
        let saved = try XCTUnwrap(model.expenses.first)
        XCTAssertEqual(saved.paidWithID, bca.id)

        // A label in use can't be deleted; an unused one can, and clears card defaults pointing at it.
        XCTAssertThrowsError(try model.deletePaymentMethod(id: bca.id)) { XCTAssertEqual($0 as? PaymentMethodError, .inUse(1)) }
        try model.setDefaultPaidWith(cash.id, for: cardID)
        try model.deletePaymentMethod(id: cash.id)
        XCTAssertNil(model.cards.first { $0.id == cardID }?.defaultPaidWithID)
        XCTAssertEqual(model.paymentMethods.map(\.name), ["BCA debit"])

        // A label that vanished while a draft was open is dropped instead of saved dangling.
        var stale = saved; stale.id = UUID(); stale.paidWithID = UUID()
        try model.save(stale)
        XCTAssertNil(try repo.expenses(in: cardID).first { $0.id == stale.id }?.paidWithID)

        // Form fields: Paid with and Currency start hidden; toggles persist.
        XCTAssertFalse(model.isEntryFieldShown(.paidWith))
        XCTAssertTrue(model.isEntryFieldShown(.date))
        model.setEntryField(.paidWith, shown: true); model.setEntryField(.note, shown: false)
        XCTAssertTrue(model.isEntryFieldShown(.paidWith)); XCTAssertFalse(model.isEntryFieldShown(.note))
        XCTAssertEqual(Set(try FileLocalStateStore(directory: tempDir).loadWorkspacePreferences().hiddenEntryFields), [.currency, .note])

        // Detail lines: default order until moved; the moved order persists.
        XCTAssertEqual(model.entryRowOrder, [.category, .card, .paidWith, .note, .date])
        model.moveEntryRows(from: IndexSet(integer: 4), to: 0)
        XCTAssertEqual(model.entryRowOrder, [.date, .category, .card, .paidWith, .note])
        XCTAssertEqual(try FileLocalStateStore(directory: tempDir).loadWorkspacePreferences().entryRowOrder, [.date, .category, .card, .paidWith, .note])

        // Breakdown: per label, with "Not set" for the rest; empty when nothing has a label.
        let totals = AnalyticsEngine.paidWithTotals([saved, stale], methods: model.paymentMethods)
        XCTAssertEqual(totals.map(\.name), ["BCA debit", "Not set"])
        var plain = stale; plain.paidWithID = nil
        XCTAssertTrue(AnalyticsEngine.paidWithTotals([plain], methods: model.paymentMethods).isEmpty)
    }

    func testStackCardReorderingAndFrontCard() throws {
        let store = try ExpenseRepository(inMemory: true)
        let b1 = try store.createCard(named: "Card 1")
        let b2 = try store.createCard(named: "Card 2")
        let b3 = try store.createCard(named: "Card 3")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let expenseService = try ExpenseService(store: store)
        let model = AppModel(expenses: expenseService, state: state)

        let stack = try model.createStack(name: "Test Stack", icon: "folder", cardIDs: [b1.id, b2.id, b3.id])
        model.setActiveStack(id: stack.id)

        let initialIDs: [UUID] = model.cardsInCurrentStack.map { $0.id }
        XCTAssertEqual(initialIDs, [b1.id, b2.id, b3.id])
        XCTAssertEqual(model.cardsInCurrentStack.first?.id, b1.id)

        if let idx = model.stacks.firstIndex(where: { $0.id == stack.id }) {
            model.stacks[idx].cardIDs = [b3.id, b1.id, b2.id]
            model.persistWorkspacePreferences()
        }

        let reorderedIDs: [UUID] = model.cardsInCurrentStack.map { $0.id }
        XCTAssertEqual(reorderedIDs, [b3.id, b1.id, b2.id])
        XCTAssertEqual(model.cardsInCurrentStack.first?.id, b3.id)
    }

    func testMoveCardToFrontAndReorderCards() throws {
        let store = try ExpenseRepository(inMemory: true)
        let b1 = try store.createCard(named: "Card 1")
        let b2 = try store.createCard(named: "Card 2")
        let b3 = try store.createCard(named: "Card 3")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let expenseService = try ExpenseService(store: store)
        let model = AppModel(expenses: expenseService, state: state)

        let stack = try model.createStack(name: "Test Stack", icon: "folder", cardIDs: [b1.id, b2.id, b3.id])
        model.setActiveStack(id: stack.id)
        model.filterScope = .activeStack

        // In active stack: move b3 to front
        model.moveCardToFront(b3.id)
        XCTAssertEqual(model.cardsInCurrentStack.map(\.id), [b3.id, b1.id, b2.id])
        XCTAssertEqual(model.visibleCards.first?.id, b3.id)

        // In active stack: reorder cards
        model.reorderCardsInCurrentStack(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(model.cardsInCurrentStack.map(\.id), [b2.id, b3.id, b1.id])

        // In allCards mode: move b1 to front
        model.filterScope = .allCards
        model.moveCardToFront(b1.id)
        XCTAssertEqual(model.orderedCards.first?.id, b1.id)
    }

    func testPreferredEntryModePersistenceAndOpenEntry() throws {
        let store = try ExpenseRepository(inMemory: true)
        let card = try store.createCard(named: "Main Card")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let expenseService = try ExpenseService(store: store)
        let model = AppModel(expenses: expenseService, state: state)

        // Default should be keypad
        XCTAssertEqual(model.preferredEntryMode, .keypad)
        model.openEntry(for: card.id)
        XCTAssertEqual(model.draft.mode, .keypad)
        XCTAssertFalse(model.draft.editing)

        // Switch preferred mode to text
        model.preferredEntryMode = .text
        XCTAssertEqual(model.preferredEntryMode, .text)

        // Reopen entry
        model.openEntry(for: card.id)
        XCTAssertEqual(model.draft.mode, .text)

        // Verify persistence across new AppModel instance
        let newModel = AppModel(expenses: expenseService, state: state)
        XCTAssertEqual(newModel.preferredEntryMode, .text)
        newModel.openEntry(for: card.id)
        XCTAssertEqual(newModel.draft.mode, .text)
    }

    func testGlobalCategoryCatalogInitialization() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)

        XCTAssertFalse(model.globalCategories.isEmpty)
        XCTAssertTrue(model.globalCategories.contains(where: { $0.name == "Food & Drink" }))
    }

    func testCategoryMetadataUpdatePropagatesToAllActiveCards() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)

        let cardA = try model.createCard(named: "Card A")
        let cardB = try model.createCard(named: "Card B")

        guard let foodCat = model.globalCategories.first(where: { $0.name == "Food & Drink" }) else {
            XCTFail("Missing Food & Drink category")
            return
        }

        // Rename and update icon
        var updated = foodCat
        updated.name = "Dining Out"
        updated.symbol = "fork.knife"
        try model.saveGlobalCategory(updated, activeCardIDs: Set([cardA.id, cardB.id]))

        let catsA = try store.categories(in: cardA.id)
        let catsB = try store.categories(in: cardB.id)

        XCTAssertTrue(catsA.contains(where: { $0.id == foodCat.id && $0.name == "Dining Out" && $0.symbol == "fork.knife" }))
        XCTAssertTrue(catsB.contains(where: { $0.id == foodCat.id && $0.name == "Dining Out" && $0.symbol == "fork.knife" }))
    }

    func testBidirectionalActivation() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)

        let cardA = try model.createCard(named: "Personal")
        let cardB = try model.createCard(named: "Work")

        guard let firstCat = model.globalCategories.first else {
            XCTFail("No global categories")
            return
        }

        // Both active initially
        XCTAssertTrue(model.isCategoryActive(firstCat.id, on: cardA.id))
        XCTAssertTrue(model.isCategoryActive(firstCat.id, on: cardB.id))

        // Deactivate on Work card
        try model.setCategory(firstCat.id, active: false, for: cardB.id)

        XCTAssertTrue(model.isCategoryActive(firstCat.id, on: cardA.id))
        XCTAssertFalse(model.isCategoryActive(firstCat.id, on: cardB.id))
        XCTAssertFalse(model.activeCategoryIDs(for: cardB.id).contains(firstCat.id))

        // Activate back on Work card
        try model.setCategory(firstCat.id, active: true, for: cardB.id)
        XCTAssertTrue(model.isCategoryActive(firstCat.id, on: cardB.id))
        XCTAssertTrue(model.activeCategoryIDs(for: cardB.id).contains(firstCat.id))
    }

    func testCreateCardWithSelectedCategories() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)

        let selected = Array(model.globalCategories.prefix(2))
        let selectedIDs = Set(selected.map(\.id))

        let newCard = try model.createCard(named: "Minimal Card", selectedCategoryIDs: selectedIDs)
        let activeIDs = model.activeCategoryIDs(for: newCard.id)

        XCTAssertEqual(activeIDs.count, 2)
        XCTAssertEqual(activeIDs, selectedIDs)
    }

    func testCreateCategoryWithCardAssignment() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)

        let card1 = try model.createCard(named: "Card 1")
        let card2 = try model.createCard(named: "Card 2")

        let customCat = GlobalCategory(name: "Gaming", symbol: "gamecontroller", defaultActiveForNewCards: false)
        try model.saveGlobalCategory(customCat, activeCardIDs: Set([card1.id]))

        XCTAssertTrue(model.isCategoryActive(customCat.id, on: card1.id))
        XCTAssertFalse(model.isCategoryActive(customCat.id, on: card2.id))

        let cats1 = try store.categories(in: card1.id)
        let cats2 = try store.categories(in: card2.id)
        XCTAssertTrue(cats1.contains(where: { $0.id == customCat.id }))
        XCTAssertFalse(cats2.contains(where: { $0.id == customCat.id }))
    }

    func testClearActiveCardExpensesPreservesCategoriesAndCard() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)
        let backups = BackupService(directory: tempDir, repository: store, state: state, expenses: service)
        model.backups = backups

        let card = try model.createCard(named: "Trip Card")
        XCTAssertTrue(model.selectCard(card.id))

        let categories = model.categories
        let exp = Expense(id: UUID(), amount: 45_000_00, day: Day.string(.now), note: "Taxi",
                          splits: [.init(categoryID: categories[0].id, amount: 45_000_00)],
                          cardID: card.id)
        try model.save(exp)
        XCTAssertEqual(model.expenses.count, 1)

        try model.clearActiveCardExpenses()

        XCTAssertEqual(model.expenses.count, 0)
        XCTAssertEqual(model.categories.count, categories.count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backups.safetyURL.path))
    }

    func testSelectingCardsSwapsAndPreservesPerCardDrafts() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let second = try store.createCard(named: "Travel")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = FileLocalStateStore(directory: directory)
        var travelDraft = ExpenseDraft()
        travelDraft.note = "Train"
        try state.saveDraft(travelDraft, for: second.id)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)
        model.draft.note = "Coffee"
        model.draft.cardID = Card.demo.id

        XCTAssertTrue(model.selectCard(second.id))
        XCTAssertEqual(model.draft.note, "Train")
        XCTAssertEqual(try state.loadDraft(for: Card.demo.id).note, "Coffee")

        XCTAssertTrue(model.selectCard(Card.demo.id))
        XCTAssertEqual(model.draft.note, "Coffee")
    }

    func testClearAllTransactionsAcrossMultipleCards() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)
        let backups = BackupService(directory: tempDir, repository: store, state: state, expenses: service)
        model.backups = backups

        let card1 = try model.createCard(named: "Card A")
        let card2 = try model.createCard(named: "Card B")

        let exp1 = Expense(id: UUID(), amount: 30_000_00, day: Day.string(.now), note: "Card1 Exp",
                           splits: [.init(categoryID: model.categories[0].id, amount: 30_000_00)],
                           cardID: card1.id)
        let exp2 = Expense(id: UUID(), amount: 50_000_00, day: Day.string(.now), note: "Card2 Exp",
                           splits: [.init(categoryID: model.categories[0].id, amount: 50_000_00)],
                           cardID: card2.id)
        try store.save(exp1, in: card1.id)
        try store.save(exp2, in: card2.id)

        try model.clearAllTransactions()

        XCTAssertEqual(try store.expenses(in: card1.id).count, 0)
        XCTAssertEqual(try store.expenses(in: card2.id).count, 0)
        XCTAssertEqual(try store.cards().count, 3) // Sample card + Card A + Card B
    }

    func testResetAllDataCreatesFreshRealCardAndSafetyBackup() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)
        let backups = BackupService(directory: tempDir, repository: store, state: state, expenses: service)
        model.backups = backups

        _ = try model.createCard(named: "Extra Card 1")
        _ = try model.createCard(named: "Extra Card 2")
        XCTAssertEqual(model.cards.count, 3)

        try model.resetAllData(cardName: "Personal Wallet")

        XCTAssertEqual(model.cards.count, 1)
        XCTAssertEqual(model.cards.first?.name, "Personal Wallet")
        XCTAssertEqual(model.cards.first?.kind, .real)
        XCTAssertEqual(model.expenses.count, 0)
        XCTAssertEqual(model.bills.count, 0)
        XCTAssertEqual(model.categories.count, ExpenseCategory.defaults.count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backups.safetyURL.path))

        let safetyData = try Data(contentsOf: backups.safetyURL)
        let decodedWorkspace = try? WorkspaceBackup.decode(safetyData)
        XCTAssertNotNil(decodedWorkspace)
        XCTAssertEqual(decodedWorkspace?.cards.count, 3)
    }

    func testDailyLedgerStressKeepsHundredsOfWritesIsolatedAcrossCards() throws {
        let store = try ExpenseRepository(inMemory: true)
        let cards = try (1...3).map { try store.createCard(named: "Stress Card \($0)") }
        var expectedTotals: [UUID: Int64] = [:]

        for (cardIndex, card) in cards.enumerated() {
            let category = try XCTUnwrap(store.categories(in: card.id).first)
            var total: Int64 = 0
            var ids: [UUID] = []
            for entryIndex in 0..<250 {
                let id = UUID()
                let amount = Int64((cardIndex + 1) * 10_000 + entryIndex)
                try store.save(
                    Expense(id: id, amount: amount, day: "2026-09-19", note: "Entry \(entryIndex)",
                            splits: [.init(categoryID: category.id, amount: amount)], cardID: card.id),
                    in: card.id
                )
                ids.append(id)
                total += amount
            }

            for entryIndex in stride(from: 0, to: 250, by: 25) {
                let amount = Int64((cardIndex + 1) * 10_000 + entryIndex + 500)
                try store.save(
                    Expense(id: ids[entryIndex], amount: amount, day: "2026-09-19", note: "Updated \(entryIndex)",
                            splits: [.init(categoryID: category.id, amount: amount)], cardID: card.id),
                    in: card.id
                )
                total += 500
            }

            for entryIndex in stride(from: 0, to: 250, by: 50) {
                try store.delete(ids[entryIndex])
                total -= Int64((cardIndex + 1) * 10_000 + entryIndex + 500)
            }
            expectedTotals[card.id] = total
        }

        let service = try ExpenseService(store: store)
        for index in 0..<150 {
            let card = cards[index % cards.count]
            try service.selectCard(card.id)
            XCTAssertEqual(service.activeCardID, card.id)
            XCTAssertEqual(service.expenses.count, 245)
        }

        for card in cards {
            let expenses = try store.expenses(in: card.id)
            XCTAssertEqual(expenses.count, 245)
            XCTAssertEqual(expenses.reduce(Int64(0)) { $0 + $1.amount }, try XCTUnwrap(expectedTotals[card.id]))
            XCTAssertTrue(expenses.allSatisfy { $0.cardID == card.id })
            XCTAssertEqual(Set(expenses.map(\.id)).count, expenses.count)
        }
    }
}
