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

    func testAPIKeyRoundTripsThroughSandboxedKeychain() throws {
        try XCTSkipIf(APIKeyStore.read() != nil, "A real key is saved; leave it alone")
        defer { APIKeyStore.delete() }
        XCTAssertTrue(APIKeyStore.save("sk-ant-test"))
        XCTAssertEqual(APIKeyStore.read(), "sk-ant-test")
        APIKeyStore.delete()
        XCTAssertNil(APIKeyStore.read())
    }

    @MainActor func testBulkDeleteAndRecategorizeUndoAsOneStep() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = try ExpenseRepository(inMemory: true)
        try repository.prepareSampleBook()
        let model = AppModel(expenses: try ExpenseService(store: repository), state: FileLocalStateStore(directory: directory))
        let state = MacAppState(model: model)
        let (first, second) = (model.categories[0], model.categories[1])
        let expenses = (1...3).map { index in
            Expense(amount: Int64(index) * 1_000_00, day: "2026-10-0\(index)", note: "Bulk \(index)",
                    allocations: [.init(categoryID: first.id, amount: Int64(index) * 1_000_00)], bookID: model.activeBookID)
        }
        for expense in expenses { try model.save(expense) }
        let undo = UndoManager(); undo.groupsByEvent = false
        func step(_ work: () -> Void) { undo.beginUndoGrouping(); work(); undo.endUndoGrouping() }

        XCTAssertTrue(state.sharedCategories(for: expenses).contains { $0.id == second.id })
        step { state.recategorize(expenses, to: second.id, undoManager: undo) }
        XCTAssertEqual(expenses.map { model.expense(id: $0.id)?.allocations.first?.categoryID }, Array(repeating: second.id, count: 3))
        undo.undo()
        XCTAssertEqual(expenses.map { model.expense(id: $0.id)?.allocations.first?.categoryID }, Array(repeating: first.id, count: 3))
        undo.redo()
        XCTAssertEqual(model.expense(id: expenses[0].id)?.allocations.first?.categoryID, second.id)

        state.inspect(MacInspectorSelection(expenseIDs: Set(expenses.map(\.id))))
        XCTAssertEqual(state.inspectorSelection, .expenses(Set(expenses.map(\.id))))
        step { state.delete(expenses, undoManager: undo) }
        XCTAssertNil(state.inspectorSelection, "Deleting the selection clears the inspector")
        XCTAssertTrue(expenses.allSatisfy { model.expense(id: $0.id) == nil })
        undo.undo()
        XCTAssertTrue(expenses.allSatisfy { model.expense(id: $0.id) != nil }, "One undo restores every deleted expense")
        undo.redo()
        XCTAssertTrue(expenses.allSatisfy { model.expense(id: $0.id) == nil })
    }
}
