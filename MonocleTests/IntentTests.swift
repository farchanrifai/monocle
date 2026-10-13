import XCTest
import AppIntents
@testable import Monocle

@MainActor
final class IntentTests: XCTestCase {
    private func makeTestModel() throws -> (ExpenseRepository, ExpenseService, AppModel) {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let repo = try ExpenseRepository(inMemory: true)
        try repo.prepareSampleCard()
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

    func testWorkspacePreferencesShortcutOrderSerializationAndValidation() throws {
        var prefs = WorkspacePreferences()
        XCTAssertEqual(prefs.shortcutInputOrder, [.card, .category, .note, .amount])

        // Reorder
        prefs.shortcutInputOrder = [.amount, .note, .category, .card]

        let encoder = JSONEncoder()
        let data = try encoder.encode(prefs)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WorkspacePreferences.self, from: data)
        XCTAssertEqual(decoded.shortcutInputOrder, [.amount, .note, .category, .card])

        prefs.shortcutInputOrder = [.card, .card]
        let invalid = try decoder.decode(WorkspacePreferences.self, from: encoder.encode(prefs))
        XCTAssertEqual(invalid.shortcutInputOrder, [.card, .card], "Preserve malformed evidence instead of rewriting it")
        XCTAssertThrowsError(try invalid.validate(cards: [], categoriesByCard: [:]))
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
        let cards = try store.cards()
        guard let firstCard = cards.first else {
            XCTFail("Expected at least one book")
            return
        }

        let cats = model.activeCategories(for: firstCard.id)
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

        let cards = try store.cards()
        let card = cards[0]
        let cardEntity = CardEntity(card)

        let activeCats = model.activeCategories(for: card.id)
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
        let expenses = try store.expenses(in: card.id)
        XCTAssertEqual(expenses.count, 1)
        let saved = expenses[0]
        XCTAssertEqual(saved.amount, 55_000_00)
        XCTAssertEqual(saved.note, "Iced Latte")
        XCTAssertEqual(saved.splits.first?.categoryID.uuidString, categoryEntity.id)
        XCTAssertEqual(saved.cardID, card.id)
    }

    func testAddExpenseIntentRevalidatesCategoryAfterCardResolution() async throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleCard()
        let sampleCategories = try store.categories(in: Card.demo.id)
        let allowed = try XCTUnwrap(sampleCategories.first)
        let invalid = try XCTUnwrap(sampleCategories.dropFirst().first)
        let second = try store.createCard(named: "Only Food", initialCategories: [GlobalCategory(category: allowed)])
        let service = try ExpenseService(store: store)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let model = AppModel(expenses: service, state: FileLocalStateStore(directory: tempDir))
        AppEnvironment.shared.model = model
        AppEnvironment.shared.expenses = service

        var intent = AddExpenseIntent()
        intent.amount = 10_000
        intent.category = ExpenseCategoryEntity(invalid)
        intent.card = CardEntity(second)
        intent.note = "Lunch"

        _ = try await intent.perform()

        let saved = try XCTUnwrap(try store.expenses(in: second.id).first)
        XCTAssertEqual(saved.splits.first?.categoryID, allowed.id)
    }

    func testSpendingSummaryAndBudgetIntentsAnswerFromTheSameToolsAsChat() async throws {
        let (store, service, model) = try makeTestModel()
        AppEnvironment.shared.model = model
        AppEnvironment.shared.expenses = service
        let card = try store.cards()[0]
        let category = try XCTUnwrap(model.activeCategories(for: card.id).first)
        try service.record(amountInRupiah: 28_000, categoryID: category.id, note: "Kopi", in: card.id)
        try service.record(amountInRupiah: 12_000, categoryID: category.id, note: "Roti", in: card.id)

        let summary = try AskAnswers.summary(period: .thisMonth, scope: AskAnswers.scopeName(card: CardEntity(card), stack: nil), model: model)
        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.total.display, Money.format(40_000_00))

        let all = try AskAnswers.summary(period: .thisMonth, scope: nil, model: model)
        XCTAssertEqual(all.total.display, summary.total.display, "No scope means everything")

        var intent = SpendingSummaryIntent()
        intent.card = CardEntity(card)
        _ = try await intent.perform()

        XCTAssertThrowsError(try AskAnswers.summary(period: .thisMonth, scope: "card:Nope", model: model), "An unknown card is an error, not a zero")
        _ = try await BudgetLeftIntent().perform()
    }

    func testAskMonocleNeedsChatOnAndNeverSavesAProposal() async throws {
        let (_, service, model) = try makeTestModel()
        AppEnvironment.shared.model = model
        AppEnvironment.shared.expenses = service
        UserDefaults.standard.removeObject(forKey: "chatEnabled")
        var intent = AskMonocleIntent()
        intent.question = "how much this month?"
        do { _ = try await intent.perform(); XCTFail("chat is off") } catch AskError.chatOff {}

        let proposal = Expense(amount: 28_000_00, day: "2026-10-13", note: "Kopi", splits: [], source: "chat", createdAt: .now)
        XCTAssertEqual(AskMonocleIntent.spoken([.text("Hi"), .proposal(proposal)]), "Hi I prepared a change. Open Monocle to confirm it.")
        XCTAssertEqual(AskMonocleIntent.spoken([]), "No answer.")
    }
}
