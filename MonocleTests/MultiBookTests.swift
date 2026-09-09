import XCTest
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

        // Decode as WorkspaceBackup (Format 4 upgrade)
        let workspace = try WorkspaceBackup.decode(data)
        XCTAssertEqual(workspace.formatVersion, 4)
        XCTAssertEqual(workspace.books.count, 1)
        XCTAssertEqual(workspace.books[0].expenses.count, 1)
        XCTAssertEqual(workspace.books[0].expenses[0].id, exp.id)
        XCTAssertEqual(workspace.books[0].categories[0].id, cat.id)
    }

    func testVisualDirectionPersistsAndDecodes() throws {
        var prefs = WorkspacePreferences()
        XCTAssertEqual(prefs.direction, .light)
        XCTAssertEqual(prefs.visualDirection, "Light")

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
    }
}
