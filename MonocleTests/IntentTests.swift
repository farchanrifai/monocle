import XCTest
import AppIntents
@testable import Monocle

@MainActor
final class IntentTests: XCTestCase {
    private func makeTestModel() throws -> (ExpenseRepository, ExpenseService, AppModel) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleBook()
        let state = FileLocalStateStore(directory: tempDir)
        let service = try ExpenseService(store: repo)
        let model = AppModel(expenses: service, state: state)
        return (repo, service, model)
    }

    func testShortcutInputFieldPropertiesAndOrdering() {
        let all: [ShortcutInputField] = ShortcutInputField.allCases
        XCTAssertEqual(all.count, 4)
        XCTAssertTrue(all.contains { $0 == .card })
        XCTAssertTrue(all.contains { $0 == .category })
        XCTAssertTrue(all.contains { $0 == .note })
        XCTAssertTrue(all.contains { $0 == .amount })

        // Verify display names and symbols
        XCTAssertEqual(ShortcutInputField.card.displayName, "Card / Account")
        XCTAssertEqual(ShortcutInputField.category.displayName, "Category")
        XCTAssertEqual(ShortcutInputField.note.displayName, "Short Note")
        XCTAssertEqual(ShortcutInputField.amount.displayName, "Amount (IDR)")
        XCTAssertFalse(ShortcutInputField.card.systemImage.isEmpty)
        XCTAssertFalse(ShortcutInputField.category.systemImage.isEmpty)
    }

    func testShortcutPromptOrderPresets() {
        let cardFirst = ShortcutPromptOrder.cardCategoryNoteAmount.fields
        XCTAssertEqual(cardFirst, [.card, .category, .note, .amount])

        let amountFirst = ShortcutPromptOrder.amountCardCategoryNote.fields
        XCTAssertEqual(amountFirst, [.amount, .card, .category, .note])

        let amountCategoryFirst = ShortcutPromptOrder.amountCategoryCardNote.fields
        XCTAssertEqual(amountCategoryFirst, [.amount, .category, .card, .note])

        let amountNoteFirst = ShortcutPromptOrder.amountNoteCategoryCard.fields
        XCTAssertEqual(amountNoteFirst, [.amount, .note, .category, .card])
    }

    func testWorkspacePreferencesShortcutOrderSerializationAndSanitization() throws {
        var prefs = WorkspacePreferences()
        XCTAssertEqual(prefs.shortcutInputOrder, [.card, .category, .note, .amount])

        // Reorder
        prefs.shortcutInputOrder = [.amount, .note, .category, .card]

        let encoder = JSONEncoder()
        let data = try encoder.encode(prefs)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WorkspacePreferences.self, from: data)
        XCTAssertEqual(decoded.shortcutInputOrder, [.amount, .note, .category, .card])
    }

    func testAppModelShortcutOrderCustomization() throws {
        let (store, _, model) = try makeTestModel()

        // Default order
        XCTAssertEqual(model.shortcutInputOrder, [.card, .category, .note, .amount])

        // Customize order
        let newOrder: [ShortcutInputField] = [.category, .card, .amount, .note]
        model.shortcutInputOrder = newOrder
        XCTAssertEqual(model.shortcutInputOrder, newOrder)

        // Verify activeCategories(for:) filters properly
        let books = try store.books()
        guard let firstBook = books.first else {
            XCTFail("Expected at least one book")
            return
        }

        let cats = model.activeCategories(for: firstBook.id)
        XCTAssertFalse(cats.isEmpty)
    }

    func testEntityQueries() async throws {
        let (_, service, model) = try makeTestModel()
        AppEnvironment.shared.model = model
        AppEnvironment.shared.expenses = service

        // Card query
        let cardQuery = CardEntityQuery()
        let cards = try await cardQuery.allEntities()
        XCTAssertFalse(cards.isEmpty)

        // Category query
        let catQuery = ExpenseCategoryEntityQuery()
        let cats = try await catQuery.allEntities()
        XCTAssertFalse(cats.isEmpty)
    }

    func testAddExpenseIntentExecutionWithAllParameters() async throws {
        let (store, service, model) = try makeTestModel()
        AppEnvironment.shared.model = model
        AppEnvironment.shared.expenses = service

        let books = try store.books()
        let book = books[0]
        let cardEntity = CardEntity(book)

        let activeCats = model.activeCategories(for: book.id)
        let categoryEntity = ExpenseCategoryEntity(activeCats[0])

        var intent = AddExpenseIntent()
        intent.amount = 55_000
        intent.category = categoryEntity
        intent.card = cardEntity
        intent.note = "Iced Latte"
        intent.inputOrder = .cardCategoryNoteAmount

        let result = try await intent.perform()
        XCTAssertNotNil(result)

        // Verify saved expense
        let expenses = try store.expenses(in: book.id)
        XCTAssertEqual(expenses.count, 1)
        let saved = expenses[0]
        XCTAssertEqual(saved.amount, 55_000_00)
        XCTAssertEqual(saved.note, "Iced Latte")
        XCTAssertEqual(saved.allocations.first?.categoryID.uuidString, categoryEntity.id)
        XCTAssertEqual(saved.bookID, book.id)
    }
}
