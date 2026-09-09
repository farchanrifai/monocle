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

        // Decode as WorkspaceBackup (Format 5 upgrade)
        let workspace = try WorkspaceBackup.decode(data)
        XCTAssertEqual(workspace.formatVersion, 5)
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

        // 1. Create Travel Stack with travel & shopping cards
        let travelStack = model.createStack(name: "Tokyo Trip", icon: "airplane", cardIDs: [travel.id, shopping.id])
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

        // 4. Multiple stacks: Shopping card can also be in Daily Stack
        let dailyStack = model.createStack(name: "Home Daily", icon: "house", cardIDs: [daily.id, shopping.id])
        model.setActiveStack(id: dailyStack.id)
        let inDaily: [UUID] = model.cardsInCurrentStack.map { $0.id }
        XCTAssertEqual(inDaily, [daily.id, shopping.id])

        // 5. Delete stack
        model.deleteStack(id: travelStack.id)
        XCTAssertFalse(model.stacks.contains(where: { $0.id == travelStack.id }))
        XCTAssertTrue(model.books.contains(where: { $0.id == travel.id })) // Book itself still exists!
    }
}
