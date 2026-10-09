import XCTest
@testable import MonocleMac

final class MonocleMacTests: XCTestCase {
    func testMoneyFormattingLoadsSharedDomain() {
        XCTAssertEqual(Money.format(28_000_00, locale: Locale(identifier: "id_ID")), "Rp28.000")
    }

    func testWorkspaceBackupRoundTripPreservesMacShortcutsAndSharedData() throws {
        let book = BookProfile.sample
        let category = ExpenseCategory.defaults[0]
        let expense = Expense(amount: 28_000_00, day: "2026-09-22", note: "Coffee", allocations: [.init(categoryID: category.id, amount: 28_000_00)], bookID: book.id)
        let bill = BillRule(bookID: book.id, name: "Internet", amount: 500_000_00, categoryID: category.id, recurrence: .monthly(day: 5))
        let preferences = WorkspacePreferences(visibleBookIDs: [book.id], bookOrder: [book.id], macShortcutBindings: [MacCommandID.commandBar.rawValue: .init("p", modifiers: [.command, .shift])])
        let backup = WorkspaceBackup(books: [
            BookBackupItem(book: book, categories: [category], expenses: [expense], budgets: [.initial(overallLimit: 1_000_000_00, startDay: 1, bookID: book.id)], draft: ExpenseDraft(), bills: [bill], billOccurrences: [])
        ], preferences: preferences)

        let decoded = try WorkspaceBackup.decode(backup.encoded())

        XCTAssertEqual(decoded, backup)
        XCTAssertEqual(decoded.preferences.macShortcutBindings[MacCommandID.commandBar.rawValue]?.displayName, "⇧⌘P")
    }

    func testOldPreferencesDecodeWithNoMacBindings() throws {
        let decoded = try JSONDecoder().decode(WorkspacePreferences.self, from: Data("{}".utf8))
        XCTAssertTrue(decoded.macShortcutBindings.isEmpty)
    }

    @MainActor
    func testShortcutValidationRejectsReservedAndDuplicateBindings() throws {
        let state = MacAppState(model: .shared)
        XCTAssertThrowsError(try state.validate(.init("q", modifiers: .command), for: .newExpense))
        XCTAssertThrowsError(try state.validate(.init("k", modifiers: .command), for: .newExpense))
        XCTAssertNoThrow(try state.validate(.init("e", modifiers: [.command, .shift]), for: .newExpense))
    }

    func testDefaultShortcutsAreUnique() {
        XCTAssertEqual(Set(KeyChord.defaults.values).count, KeyChord.defaults.count)
    }

    @MainActor
    func testInspectorExpenseLookupRefreshesAfterSaveAndDelete() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try ExpenseRepository(inMemory: true)
        try repository.prepareSampleBook()
        let model = AppModel(expenses: try ExpenseService(store: repository), state: FileLocalStateStore(directory: directory))
        let category = try XCTUnwrap(model.categories.first)
        var expense = Expense(amount: 1_000_00, day: "2026-09-23", note: "Before",
                              allocations: [.init(categoryID: category.id, amount: 1_000_00)], bookID: model.activeBookID)

        try model.save(expense)
        XCTAssertEqual(model.expense(id: expense.id)?.note, "Before")
        expense.note = "After"
        try model.save(expense)
        XCTAssertEqual(model.expense(id: expense.id)?.note, "After")
        model.delete(expense)
        XCTAssertNil(model.expense(id: expense.id))
    }

    func testActivityRowsBuildFilterAndSortLargeLedgerQuickly() {
        let book = BookProfile.sample
        let food = ExpenseCategory.defaults[0]
        let expenses = (0..<20_000).map { (i: Int) -> Expense in
            let amount = Int64(i + 1) * 100
            let day = String(format: "2026-%02d-%02d", i % 12 + 1, i % 28 + 1)
            let note = i % 2 == 0 ? "Coffee \(i)" : ""
            return Expense(amount: amount, day: day, note: note, allocations: [Allocation(categoryID: food.id, amount: amount)], bookID: book.id)
        }
        let start = Date()
        let rows = MacExpenseRow.make(expenses, bookNames: [book.id: book.name], categoryName: { $0 == food.id ? food.name : nil })
        let coffee = MacExpenseRow.filter(rows, query: " coffee ", sortOrder: [])
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.5) // was rebuilt on every window refresh before memoizing

        XCTAssertEqual(rows.count, 20_000)
        XCTAssertEqual(rows[1].title, food.name) // empty note falls back to category
        XCTAssertEqual(rows[0].book, book.name)
        XCTAssertEqual(coffee.count, 10_000)
        XCTAssertTrue(zip(coffee, coffee.dropFirst()).allSatisfy { $0.day >= $1.day })
        let byAmount = MacExpenseRow.filter(rows, query: "", sortOrder: [KeyPathComparator(\.amountMinor)])
        XCTAssertEqual(byAmount.first?.amountMinor, 100)
    }
}
