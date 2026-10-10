import XCTest
import SwiftUI
@testable import Monocle

@MainActor
final class MultiBookTests: XCTestCase {
    func testTwoBooksRemainStrictlyIsolated() throws {
        let store = try ExpenseRepository(inMemory: true)
        let bookA = try store.createBook(named: "Daily Expenses")
        let bookB = try store.createBook(named: "Tokyo Vacation")

        let catsA = try store.categories(in: bookA.id)
        let catsB = try store.categories(in: bookB.id)
        let catA = catsA[0]
        let catB = catsB[1]

        let expA = Expense(id: UUID(), amount: 50_000_00, day: "2026-09-08", note: "Lunch",
                           allocations: [.init(categoryID: catA.id, amount: 50_000_00)],
                           bookID: bookA.id)
        let expB = Expense(id: UUID(), amount: 120_000_00, day: "2026-09-08", note: "Train pass",
                           allocations: [.init(categoryID: catB.id, amount: 120_000_00)],
                           bookID: bookB.id)
        try store.save(expA, in: bookA.id)
        try store.save(expB, in: bookB.id)

        let budgetA = BudgetVersion.initial(overallLimit: 2_000_000_00, startDay: 1, bookID: bookA.id)
        let budgetB = BudgetVersion.initial(overallLimit: 10_000_000_00, startDay: 15, bookID: bookB.id)
        try store.save(budgetA, in: bookA.id)
        try store.save(budgetB, in: bookB.id)

        // Verify isolation
        let expInA = try store.expenses(in: bookA.id)
        let expInB = try store.expenses(in: bookB.id)
        XCTAssertEqual(expInA.count, 1)
        XCTAssertEqual(expInA.first?.id, expA.id)
        XCTAssertEqual(expInB.count, 1)
        XCTAssertEqual(expInB.first?.id, expB.id)

        let budgetsInA = try store.budgets(in: bookA.id)
        let budgetsInB = try store.budgets(in: bookB.id)
        XCTAssertEqual(budgetsInA.first?.overallLimit, 2_000_000_00)
        XCTAssertEqual(budgetsInB.first?.overallLimit, 10_000_000_00)
    }

    func testBookLifecycleRenameAndDelete() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
        let book = try store.createBook(named: "Project Alpha")
        XCTAssertEqual(try store.books().count, 2) // default sample book + new book

        try store.renameBook(id: book.id, to: "Project Beta")
        let updated = try store.books().first { $0.id == book.id }
        XCTAssertEqual(updated?.name, "Project Beta")

        try store.deleteBook(id: book.id)
        XCTAssertEqual(try store.books().count, 1)
        XCTAssertFalse(try store.books().contains(where: { $0.id == book.id }))
    }

    func testFormatFourWorkspaceRoundTrip() throws {
        let store = try ExpenseRepository(inMemory: true)
        let bookA = try store.createBook(named: "Home")
        let catA = ExpenseCategory(id: UUID(), name: "Groceries", symbol: "cart")
        try store.saveCategory(catA, in: bookA.id)
        let expA = Expense(id: UUID(), amount: 75_000_00, day: "2026-09-08", note: "Supermarket",
                           allocations: [.init(categoryID: catA.id, amount: 75_000_00)], bookID: bookA.id)
        try store.save(expA, in: bookA.id)

        let items = [
            BookBackupItem(book: bookA, categories: [catA], expenses: [expA],
                           budgets: [BudgetVersion.initial(overallLimit: 5_000_000_00, startDay: 1, bookID: bookA.id)],
                           draft: nil)
        ]
        let prefs = WorkspacePreferences(visibleBookIDs: [bookA.id], bookOrder: [bookA.id], allActivitiesScope: true, visualDirection: "Instrument")
        let workspace = WorkspaceBackup(formatVersion: 4, exportedAt: .now, currency: "IDR", minorUnitScale: 2,
                                        books: items, preferences: prefs, settings: PrototypeSettings())
        try workspace.validate()

        let encoded = try workspace.encoded()
        let decoded = try WorkspaceBackup.decode(encoded)
        XCTAssertEqual(decoded.formatVersion, 4)
        XCTAssertEqual(decoded.books.count, 1)
        XCTAssertEqual(decoded.books[0].book.name, "Home")
        XCTAssertEqual(decoded.books[0].expenses.first?.amount, 75_000_00)
        XCTAssertEqual(decoded.preferences.visualDirection, "Instrument")

        // Restore into a fresh store
        let freshStore = try ExpenseRepository(inMemory: true)
        try freshStore.replace(with: decoded)
        let restoredBooks = try freshStore.books()
        XCTAssertTrue(restoredBooks.contains(where: { $0.id == bookA.id }))
        let restoredExpenses = try freshStore.expenses(in: bookA.id)
        XCTAssertEqual(restoredExpenses.count, 1)
        XCTAssertEqual(restoredExpenses[0].id, expA.id)
    }

    func testLegacyFormatThreeSingleBookDecodesAsWorkspace() throws {
        let cat = ExpenseCategory.defaults[0]
        let exp = Expense(amount: 25_000_00, day: "2026-09-08", note: "Coffee",
                          allocations: [.init(categoryID: cat.id, amount: 25_000_00)])
        let budget = BudgetVersion.initial(overallLimit: 5_000_000_00, startDay: 1)
        let singleBookBackup = BookBackup(categories: [cat], expenses: [exp], draft: ExpenseDraft(), settings: PrototypeSettings(), budgets: [budget])
        let data = try singleBookBackup.encoded()

        // Decode as WorkspaceBackup (Format 5+ upgrade)
        let workspace = try WorkspaceBackup.decode(data)
        XCTAssertGreaterThanOrEqual(workspace.formatVersion, 5)
        XCTAssertEqual(workspace.books.count, 1)
        XCTAssertEqual(workspace.books[0].expenses.count, 1)
        XCTAssertEqual(workspace.books[0].expenses[0].id, exp.id)
        XCTAssertEqual(workspace.books[0].categories[0].id, cat.id)
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
        try repo.prepareSampleBook()
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
        let lightAuto = BookCardCustomization(style: .palette(index: 2), textTone: .auto) // Acid Lime is bright
        XCTAssertEqual(CardPalette.resolvedTextColor(for: lightAuto), .black)

        let darkAuto = BookCardCustomization(style: .palette(index: 8), textTone: .auto) // Obsidian is dark
        XCTAssertEqual(CardPalette.resolvedTextColor(for: darkAuto), .white)

        let lightManual = BookCardCustomization(style: .palette(index: 2), textTone: .light)
        XCTAssertEqual(CardPalette.resolvedTextColor(for: lightManual), .white)

        let darkManual = BookCardCustomization(style: .palette(index: 8), textTone: .dark)
        XCTAssertEqual(CardPalette.resolvedTextColor(for: darkManual), .black)

        let stockSunset = BookCardCustomization(style: .stock(.sunsetHeat), textTone: .auto)
        XCTAssertEqual(CardPalette.resolvedTextColor(for: stockSunset), .white)

        let stockParchment = BookCardCustomization(style: .stock(.warmParchment), textTone: .auto)
        XCTAssertEqual(CardPalette.resolvedTextColor(for: stockParchment), .black)

        let photoCustom = BookCardCustomization(style: .customPhoto(filename: "card.jpg"), textTone: .auto)
        XCTAssertEqual(CardPalette.resolvedTextColor(for: photoCustom), .white)
    }

    func testCardCustomizationPersistenceAndRoundTrip() throws {
        let bookID = UUID()
        var prefs = WorkspacePreferences()
        XCTAssertTrue(prefs.cardCustomizations.isEmpty)

        let custom = BookCardCustomization(style: .stock(.auroraBorealis), textTone: .light)
        prefs.cardCustomizations[bookID] = custom

        let encoded = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(WorkspacePreferences.self, from: encoded)

        XCTAssertEqual(decoded.cardCustomizations[bookID]?.style, .stock(.auroraBorealis))
        XCTAssertEqual(decoded.cardCustomizations[bookID]?.textTone, .light)

        // Test customColor
        prefs.cardCustomizations[bookID] = BookCardCustomization(style: .customColor(hex: "#123456"), textTone: .auto)
        let enc2 = try JSONEncoder().encode(prefs)
        let dec2 = try JSONDecoder().decode(WorkspacePreferences.self, from: enc2)
        XCTAssertEqual(dec2.cardCustomizations[bookID]?.style, .customColor(hex: "#123456"))

        // Test customPhoto
        prefs.cardCustomizations[bookID] = BookCardCustomization(style: .customPhoto(filename: "artwork-\(bookID).jpg"), textTone: .dark)
        let enc3 = try JSONEncoder().encode(prefs)
        let dec3 = try JSONDecoder().decode(WorkspacePreferences.self, from: enc3)
        XCTAssertEqual(dec3.cardCustomizations[bookID]?.style, .customPhoto(filename: "artwork-\(bookID).jpg"))
        XCTAssertEqual(dec3.cardCustomizations[bookID]?.textTone, .dark)
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
        let bookA = try store.createBook(named: "Trip to Paris")
        let catA = ExpenseCategory(id: UUID(), name: "Museums", symbol: "airplane")
        try store.saveCategory(catA, in: bookA.id)
        let expA = Expense(id: UUID(), amount: 350_000_00, day: "2026-09-08", note: "Louvre Ticket",
                           allocations: [.init(categoryID: catA.id, amount: 350_000_00)], bookID: bookA.id)
        try store.save(expA, in: bookA.id)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 50, height: 50))
        let sampleImage = renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 50, height: 50))
        }
        let sampleData = sampleImage.jpegData(compressionQuality: 0.8)!
        let photoFilename = "sample-\(bookA.id.uuidString).jpg"

        var prefs = WorkspacePreferences(visibleBookIDs: [bookA.id], bookOrder: [bookA.id])
        prefs.cardCustomizations[bookA.id] = BookCardCustomization(style: .customPhoto(filename: photoFilename), textTone: .auto)

        let items = [
            BookBackupItem(book: bookA, categories: [catA], expenses: [expA], budgets: [], draft: nil)
        ]
        let workspace = WorkspaceBackup(
            formatVersion: 5,
            exportedAt: .now,
            currency: "IDR",
            minorUnitScale: 2,
            books: items,
            preferences: prefs,
            settings: PrototypeSettings(),
            cardArtworks: [photoFilename: sampleData]
        )
        try workspace.validate()

        let encoded = try workspace.encoded()
        let decoded = try WorkspaceBackup.decode(encoded)

        XCTAssertEqual(decoded.formatVersion, 5)
        XCTAssertEqual(decoded.books.count, 1)
        XCTAssertEqual(decoded.preferences.cardCustomizations[bookA.id]?.style, .customPhoto(filename: photoFilename))
        XCTAssertEqual(decoded.cardArtworks?[photoFilename], sampleData)

        // Restore into fresh store and verify artwork import
        let freshStore = try ExpenseRepository(inMemory: true)
        try freshStore.replace(with: decoded)

        let loadedArtwork = CardArtworkStore.shared.loadArtwork(filename: photoFilename)
        XCTAssertNotNil(loadedArtwork)

        // Clean up
        CardArtworkStore.shared.deleteArtwork(filename: photoFilename)
    }

    func testCardStacksAndAlwaysHiddenFiltering() throws {
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleBook()
        let daily = try repo.createBook(named: "Daily")
        let travel = try repo.createBook(named: "Tokyo Travel")
        let shopping = try repo.createBook(named: "Shopping")
        let oldTrip = try repo.createBook(named: "Old Bali Trip")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let expenseService = try ExpenseService(store: repo)
        let model = AppModel(expenses: expenseService, state: state)

        // Add expense to each book using book-scoped categories
        let catDaily = try repo.categories(in: daily.id)[0]
        let catTravel = try repo.categories(in: travel.id)[0]
        let catShopping = try repo.categories(in: shopping.id)[0]
        let catOldTrip = try repo.categories(in: oldTrip.id)[0]
        try repo.save(Expense(id: UUID(), amount: 10_000_00, day: "2026-09-10", note: "Daily Coffee", allocations: [.init(categoryID: catDaily.id, amount: 10_000_00)], bookID: daily.id), in: daily.id)
        try repo.save(Expense(id: UUID(), amount: 50_000_00, day: "2026-09-10", note: "Sushi", allocations: [.init(categoryID: catTravel.id, amount: 50_000_00)], bookID: travel.id), in: travel.id)
        try repo.save(Expense(id: UUID(), amount: 30_000_00, day: "2026-09-10", note: "Souvenir", allocations: [.init(categoryID: catShopping.id, amount: 30_000_00)], bookID: shopping.id), in: shopping.id)
        try repo.save(Expense(id: UUID(), amount: 99_000_00, day: "2026-09-10", note: "Old Resort", allocations: [.init(categoryID: catOldTrip.id, amount: 99_000_00)], bookID: oldTrip.id), in: oldTrip.id)

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
        let stackActivities = model.activities(selectedBookID: nil, allBooks: false)
        XCTAssertEqual(stackActivities.count, 2)
        XCTAssertTrue(stackActivities.contains(where: { $0.note == "Sushi" }))
        XCTAssertTrue(stackActivities.contains(where: { $0.note == "Souvenir" }))
        XCTAssertFalse(stackActivities.contains(where: { $0.note == "Daily Coffee" }))
        XCTAssertFalse(stackActivities.contains(where: { $0.note == "Old Resort" }))

        // 2. Switch to All Cards
        model.toggleFilterScope()
        XCTAssertEqual(model.filterScope, StackFilterScope.allCards)
        XCTAssertTrue(model.homeDeckCards.contains(where: { $0.id == oldTrip.id }))
        let allBeforeArchive = model.activities(selectedBookID: nil, allBooks: true)
        XCTAssertTrue(allBeforeArchive.contains(where: { $0.note == "Old Resort" }))

        // 3. Mark Old Bali Trip as Always Hidden (Archive)
        model.setCardAlwaysHidden(id: oldTrip.id, isHidden: true)
        XCTAssertTrue(model.alwaysHiddenBookIDs.contains(oldTrip.id))
        XCTAssertFalse(model.unhiddenBooks.contains(where: { $0.id == oldTrip.id }))
        XCTAssertFalse(model.homeDeckCards.contains(where: { $0.id == oldTrip.id }))

        // In All Activities, Old Resort MUST NEVER appear
        let allAfterArchive = model.activities(selectedBookID: nil, allBooks: true)
        XCTAssertFalse(allAfterArchive.contains(where: { $0.note == "Old Resort" }))
        XCTAssertTrue(allAfterArchive.contains(where: { $0.note == "Daily Coffee" }))

        // But when viewing that card explicitly (via top menu), it is accessible
        let oldTripDirect = model.activities(selectedBookID: oldTrip.id, allBooks: false)
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
        XCTAssertTrue(model.books.contains(where: { $0.id == travel.id })) // Book itself still exists!
    }

    func testEachCardKeepsOneStackAndStackBudgetSumsCardsOrUsesCap() throws {
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleBook()
        let tokyo = try repo.createBook(named: "Tokyo")
        let bali = try repo.createBook(named: "Bali")
        try repo.save(BudgetVersion.initial(overallLimit: 20_000_000_00, startDay: 1, bookID: tokyo.id), in: tokyo.id)
        try repo.save(BudgetVersion.initial(overallLimit: 5_000_000_00, startDay: 10, bookID: bali.id), in: bali.id)
        var goal = BudgetVersion.initial(overallLimit: 9_000_000_00, startDay: 1, bookID: BookProfile.sample.id)
        goal.totalUntilDay = "2099-12-31"
        try repo.save(goal, in: BookProfile.sample.id)

        // A workspace saved before the rule: Bali sits in two stacks.
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let travel = CardStack(name: "Travel", cardIDs: [tokyo.id, bali.id, BookProfile.sample.id])
        let beach = CardStack(name: "Beach", cardIDs: [bali.id])
        try state.saveWorkspacePreferences(WorkspacePreferences(stacks: [travel, beach], activeStackID: travel.id))
        let model = AppModel(expenses: try ExpenseService(store: repo), state: state)
        XCTAssertNil(model.startupError)
        XCTAssertEqual(model.stacks.map(\.cardIDs), [[tokyo.id, bali.id, BookProfile.sample.id], []])
        XCTAssertEqual(try state.loadWorkspacePreferences().stacks.map(\.cardIDs), model.stacks.map(\.cardIDs))

        // Sum of the cards' monthly budgets; the "Total until" goal budget doesn't count.
        let saved = try XCTUnwrap(model.stacks.first)
        XCTAssertEqual(model.stackBudgetLimit(saved), 25_000_000_00)
        let report = AnalyticsReport.build(data: model.reportingData(for: .stack(id: saved.id, name: saved.name)), horizon: .thisCycle)
        XCTAssertEqual(report.period?.budget.overallLimit, 25_000_000_00)
        XCTAssertEqual(report.period?.cycle.start, BudgetCycle.containing(.now, startDay: 1).start)

        // A cap replaces the sum, and moving a card through updateStack takes it out of Travel.
        var beachEdit = try XCTUnwrap(model.stacks.last)
        beachEdit.cardIDs = [bali.id]; beachEdit.capLimit = 3_000_000_00
        try model.updateStack(beachEdit)
        XCTAssertEqual(model.stacks.first?.cardIDs, [tokyo.id, BookProfile.sample.id])
        XCTAssertEqual(model.stackBudgetLimit(try XCTUnwrap(model.stacks.last)), 3_000_000_00)
        XCTAssertNil(CardStack(name: "Empty").budgetLimit(cardLimits: []))
    }

    func testTotalUntilBudgetIsOnePeriodAndSwitchingBackReplacesIt() throws {
        // Domain: one period from the start through the last day, including after it ends.
        let goal = BudgetVersion(effectiveDay: "2026-10-01", overallLimit: 10_000_000_00, startDay: 1, totalUntilDay: "2027-03-31")
        let during = try XCTUnwrap(BudgetHistory.period(containing: XCTUnwrap(Day.date("2026-12-15")), budgets: [goal]))
        XCTAssertEqual(Day.string(during.cycle.start), "2026-10-01")
        XCTAssertEqual(Day.string(during.cycle.end), "2027-04-01")
        XCTAssertTrue(during.cycle.contains(Expense(amount: 1, day: "2027-03-31", note: "", allocations: [])))
        XCTAssertFalse(during.cycle.contains(Expense(amount: 1, day: "2027-04-01", note: "", allocations: [])))
        let after = try XCTUnwrap(BudgetHistory.period(containing: XCTUnwrap(Day.date("2027-05-01")), budgets: [goal]))
        XCTAssertEqual(after.cycle, during.cycle)
        var backwards = goal; backwards.totalUntilDay = "2026-09-30"
        XCTAssertThrowsError(try backwards.validate(categories: []))

        // App: save a goal, then go back to monthly from the same start.
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleBook()
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
        try repo.prepareSampleBook()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let model = AppModel(expenses: try ExpenseService(store: repo), state: FileLocalStateStore(directory: tempDir))
        let cardID = model.activeBookID

        // Labels: names are unique ignoring case.
        let bca = try model.savePaymentMethod(PaymentMethod(name: "  BCA debit ", kind: .bank))
        XCTAssertEqual(bca.name, "BCA debit")
        XCTAssertThrowsError(try model.savePaymentMethod(PaymentMethod(name: "bca DEBIT"))) { XCTAssertEqual($0 as? PaymentMethodError, .duplicateName) }
        let cash = try model.savePaymentMethod(PaymentMethod(name: "Cash", kind: .cash))

        // The card default pre-fills a new expense, which saves with it.
        try model.setDefaultPaidWith(bca.id, for: cardID)
        XCTAssertEqual(model.books.first { $0.id == cardID }?.defaultPaidWithID, bca.id)
        model.draft = ExpenseDraft(); model.draft.bookID = cardID
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
        XCTAssertNil(model.books.first { $0.id == cardID }?.defaultPaidWithID)
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

        // Breakdown: per label, with "Not set" for the rest; empty when nothing has a label.
        let totals = AnalyticsEngine.paidWithTotals([saved, stale], methods: model.paymentMethods)
        XCTAssertEqual(totals.map(\.name), ["BCA debit", "Not set"])
        var plain = stale; plain.paidWithID = nil
        XCTAssertTrue(AnalyticsEngine.paidWithTotals([plain], methods: model.paymentMethods).isEmpty)
    }

    func testStackCardReorderingAndFrontCard() throws {
        let store = try ExpenseRepository(inMemory: true)
        let b1 = try store.createBook(named: "Card 1")
        let b2 = try store.createBook(named: "Card 2")
        let b3 = try store.createBook(named: "Card 3")

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

    func testMoveBookToFrontAndReorderCards() throws {
        let store = try ExpenseRepository(inMemory: true)
        let b1 = try store.createBook(named: "Card 1")
        let b2 = try store.createBook(named: "Card 2")
        let b3 = try store.createBook(named: "Card 3")

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
        model.moveBookToFront(b3.id)
        XCTAssertEqual(model.cardsInCurrentStack.map(\.id), [b3.id, b1.id, b2.id])
        XCTAssertEqual(model.visibleBooks.first?.id, b3.id)

        // In active stack: reorder cards
        model.reorderCardsInCurrentStack(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(model.cardsInCurrentStack.map(\.id), [b2.id, b3.id, b1.id])

        // In allCards mode: move b1 to front
        model.filterScope = .allCards
        model.moveBookToFront(b1.id)
        XCTAssertEqual(model.orderedBooks.first?.id, b1.id)
    }

    func testPreferredEntryModePersistenceAndOpenEntry() throws {
        let store = try ExpenseRepository(inMemory: true)
        let book = try store.createBook(named: "Main Card")

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let expenseService = try ExpenseService(store: store)
        let model = AppModel(expenses: expenseService, state: state)

        // Default should be keypad
        XCTAssertEqual(model.preferredEntryMode, .keypad)
        model.openEntry(for: book.id)
        XCTAssertEqual(model.draft.mode, .keypad)
        XCTAssertFalse(model.draft.editing)

        // Switch preferred mode to text
        model.preferredEntryMode = .text
        XCTAssertEqual(model.preferredEntryMode, .text)

        // Reopen entry
        model.openEntry(for: book.id)
        XCTAssertEqual(model.draft.mode, .text)

        // Verify persistence across new AppModel instance
        let newModel = AppModel(expenses: expenseService, state: state)
        XCTAssertEqual(newModel.preferredEntryMode, .text)
        newModel.openEntry(for: book.id)
        XCTAssertEqual(newModel.draft.mode, .text)
    }

    func testGlobalCategoryCatalogInitialization() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
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
        try store.prepareSampleBook()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)

        let bookA = try model.createBook(named: "Card A")
        let bookB = try model.createBook(named: "Card B")

        guard let foodCat = model.globalCategories.first(where: { $0.name == "Food & Drink" }) else {
            XCTFail("Missing Food & Drink category")
            return
        }

        // Rename and update icon
        var updated = foodCat
        updated.name = "Dining Out"
        updated.symbol = "fork.knife"
        try model.saveGlobalCategory(updated, activeBookIDs: Set([bookA.id, bookB.id]))

        let catsA = try store.categories(in: bookA.id)
        let catsB = try store.categories(in: bookB.id)

        XCTAssertTrue(catsA.contains(where: { $0.id == foodCat.id && $0.name == "Dining Out" && $0.symbol == "fork.knife" }))
        XCTAssertTrue(catsB.contains(where: { $0.id == foodCat.id && $0.name == "Dining Out" && $0.symbol == "fork.knife" }))
    }

    func testBidirectionalActivation() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)

        let bookA = try model.createBook(named: "Personal")
        let bookB = try model.createBook(named: "Work")

        guard let firstCat = model.globalCategories.first else {
            XCTFail("No global categories")
            return
        }

        // Both active initially
        XCTAssertTrue(model.isCategoryActive(firstCat.id, on: bookA.id))
        XCTAssertTrue(model.isCategoryActive(firstCat.id, on: bookB.id))

        // Deactivate on Work card
        try model.setCategory(firstCat.id, active: false, for: bookB.id)

        XCTAssertTrue(model.isCategoryActive(firstCat.id, on: bookA.id))
        XCTAssertFalse(model.isCategoryActive(firstCat.id, on: bookB.id))
        XCTAssertFalse(model.activeCategoryIDs(for: bookB.id).contains(firstCat.id))

        // Activate back on Work card
        try model.setCategory(firstCat.id, active: true, for: bookB.id)
        XCTAssertTrue(model.isCategoryActive(firstCat.id, on: bookB.id))
        XCTAssertTrue(model.activeCategoryIDs(for: bookB.id).contains(firstCat.id))
    }

    func testCreateCardWithSelectedCategories() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)

        let selected = Array(model.globalCategories.prefix(2))
        let selectedIDs = Set(selected.map(\.id))

        let newCard = try model.createBook(named: "Minimal Card", selectedCategoryIDs: selectedIDs)
        let activeIDs = model.activeCategoryIDs(for: newCard.id)

        XCTAssertEqual(activeIDs.count, 2)
        XCTAssertEqual(activeIDs, selectedIDs)
    }

    func testCreateCategoryWithCardAssignment() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)

        let card1 = try model.createBook(named: "Card 1")
        let card2 = try model.createBook(named: "Card 2")

        let customCat = GlobalCategory(name: "Gaming", symbol: "gamecontroller", defaultActiveForNewCards: false)
        try model.saveGlobalCategory(customCat, activeBookIDs: Set([card1.id]))

        XCTAssertTrue(model.isCategoryActive(customCat.id, on: card1.id))
        XCTAssertFalse(model.isCategoryActive(customCat.id, on: card2.id))

        let cats1 = try store.categories(in: card1.id)
        let cats2 = try store.categories(in: card2.id)
        XCTAssertTrue(cats1.contains(where: { $0.id == customCat.id }))
        XCTAssertFalse(cats2.contains(where: { $0.id == customCat.id }))
    }

    func testClearActiveCardExpensesPreservesCategoriesAndCard() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)
        let backups = BackupService(directory: tempDir, repository: store, state: state, expenses: service)
        model.backups = backups

        let book = try model.createBook(named: "Trip Card")
        XCTAssertTrue(model.selectBook(book.id))

        let categories = model.categories
        let exp = Expense(id: UUID(), amount: 45_000_00, day: Day.string(.now), note: "Taxi",
                          allocations: [.init(categoryID: categories[0].id, amount: 45_000_00)],
                          bookID: book.id)
        try model.save(exp)
        XCTAssertEqual(model.expenses.count, 1)

        try model.clearActiveCardExpenses()

        XCTAssertEqual(model.expenses.count, 0)
        XCTAssertEqual(model.categories.count, categories.count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backups.safetyURL.path))
    }

    func testSelectingCardsSwapsAndPreservesPerCardDrafts() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
        let second = try store.createBook(named: "Travel")
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
        model.draft.bookID = BookProfile.sample.id

        XCTAssertTrue(model.selectBook(second.id))
        XCTAssertEqual(model.draft.note, "Train")
        XCTAssertEqual(try state.loadDraft(for: BookProfile.sample.id).note, "Coffee")

        XCTAssertTrue(model.selectBook(BookProfile.sample.id))
        XCTAssertEqual(model.draft.note, "Coffee")
    }

    func testClearAllTransactionsAcrossMultipleCards() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)
        let backups = BackupService(directory: tempDir, repository: store, state: state, expenses: service)
        model.backups = backups

        let card1 = try model.createBook(named: "Card A")
        let card2 = try model.createBook(named: "Card B")

        let exp1 = Expense(id: UUID(), amount: 30_000_00, day: Day.string(.now), note: "Card1 Exp",
                           allocations: [.init(categoryID: model.categories[0].id, amount: 30_000_00)],
                           bookID: card1.id)
        let exp2 = Expense(id: UUID(), amount: 50_000_00, day: Day.string(.now), note: "Card2 Exp",
                           allocations: [.init(categoryID: model.categories[0].id, amount: 50_000_00)],
                           bookID: card2.id)
        try store.save(exp1, in: card1.id)
        try store.save(exp2, in: card2.id)

        try model.clearAllTransactions()

        XCTAssertEqual(try store.expenses(in: card1.id).count, 0)
        XCTAssertEqual(try store.expenses(in: card2.id).count, 0)
        XCTAssertEqual(try store.books().count, 3) // Sample book + Card A + Card B
    }

    func testResetAllDataCreatesFreshRealCardAndSafetyBackup() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: store)
        let model = AppModel(expenses: service, state: state)
        let backups = BackupService(directory: tempDir, repository: store, state: state, expenses: service)
        model.backups = backups

        _ = try model.createBook(named: "Extra Card 1")
        _ = try model.createBook(named: "Extra Card 2")
        XCTAssertEqual(model.books.count, 3)

        try model.resetAllData(cardName: "Personal Wallet")

        XCTAssertEqual(model.books.count, 1)
        XCTAssertEqual(model.books.first?.name, "Personal Wallet")
        XCTAssertEqual(model.books.first?.kind, .real)
        XCTAssertEqual(model.expenses.count, 0)
        XCTAssertEqual(model.bills.count, 0)
        XCTAssertEqual(model.categories.count, ExpenseCategory.defaults.count)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backups.safetyURL.path))

        let safetyData = try Data(contentsOf: backups.safetyURL)
        let decodedWorkspace = try? WorkspaceBackup.decode(safetyData)
        XCTAssertNotNil(decodedWorkspace)
        XCTAssertEqual(decodedWorkspace?.books.count, 3)
    }

    func testDailyLedgerStressKeepsHundredsOfWritesIsolatedAcrossCards() throws {
        let store = try ExpenseRepository(inMemory: true)
        let books = try (1...3).map { try store.createBook(named: "Stress Card \($0)") }
        var expectedTotals: [UUID: Int64] = [:]

        for (bookIndex, book) in books.enumerated() {
            let category = try XCTUnwrap(store.categories(in: book.id).first)
            var total: Int64 = 0
            var ids: [UUID] = []
            for entryIndex in 0..<250 {
                let id = UUID()
                let amount = Int64((bookIndex + 1) * 10_000 + entryIndex)
                try store.save(
                    Expense(id: id, amount: amount, day: "2026-09-19", note: "Entry \(entryIndex)",
                            allocations: [.init(categoryID: category.id, amount: amount)], bookID: book.id),
                    in: book.id
                )
                ids.append(id)
                total += amount
            }

            for entryIndex in stride(from: 0, to: 250, by: 25) {
                let amount = Int64((bookIndex + 1) * 10_000 + entryIndex + 500)
                try store.save(
                    Expense(id: ids[entryIndex], amount: amount, day: "2026-09-19", note: "Updated \(entryIndex)",
                            allocations: [.init(categoryID: category.id, amount: amount)], bookID: book.id),
                    in: book.id
                )
                total += 500
            }

            for entryIndex in stride(from: 0, to: 250, by: 50) {
                try store.delete(ids[entryIndex])
                total -= Int64((bookIndex + 1) * 10_000 + entryIndex + 500)
            }
            expectedTotals[book.id] = total
        }

        let service = try ExpenseService(store: store)
        for index in 0..<150 {
            let book = books[index % books.count]
            try service.selectBook(book.id)
            XCTAssertEqual(service.activeBookID, book.id)
            XCTAssertEqual(service.expenses.count, 245)
        }

        for book in books {
            let expenses = try store.expenses(in: book.id)
            XCTAssertEqual(expenses.count, 245)
            XCTAssertEqual(expenses.reduce(Int64(0)) { $0 + $1.amount }, try XCTUnwrap(expectedTotals[book.id]))
            XCTAssertTrue(expenses.allSatisfy { $0.bookID == book.id })
            XCTAssertEqual(Set(expenses.map(\.id)).count, expenses.count)
        }
    }
}
