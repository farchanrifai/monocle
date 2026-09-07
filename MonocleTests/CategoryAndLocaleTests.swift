import XCTest
@testable import Monocle

final class CategoryAndLocaleTests: XCTestCase {
    func testSystemStyleSeparatorsRemainExact() throws {
        let us = Locale(identifier: "en_US")
        let id = Locale(identifier: "id_ID")
        XCTAssertEqual(Money.format(2_800_050, currency: false, locale: us), "28,000.5")
        XCTAssertEqual(Money.format(2_800_050, currency: false, locale: id), "28.000,5")
        XCTAssertEqual(try Money.parse("28,000", locale: us), 2_800_000)
        XCTAssertEqual(try Money.parse("28.000", locale: id), 2_800_000)
        XCTAssertEqual(try Money.parse("28.5k", locale: us), 2_850_000)
        XCTAssertEqual(try Money.parse("28,5k", locale: id), 2_850_000)
        XCTAssertThrowsError(try Money.parse("28,5k", locale: us))
        XCTAssertThrowsError(try Money.parse("28.5k", locale: id))
        XCTAssertThrowsError(try Money.parse("2,80,000", locale: us))
        XCTAssertThrowsError(try Money.parse("28.50", locale: us), "Fractional rupiah entry remains unsupported")
    }

    @MainActor
    func testCategoryEditsKeepHistoryAndDeleteGuardsAtStoreBoundary() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
        let service = try ExpenseService(store: store)
        var category = ExpenseCategory(id: UUID(), name: "Pets", symbol: "pawprint")
        try service.saveCategory(category)
        let expense = Expense(amount: 10000, day: "2026-09-08", note: "Vet", allocations: [.init(categoryID: category.id, amount: 10000)])
        try service.save(expense)
        category.name = "Pet care"
        try service.saveCategory(category)
        XCTAssertEqual(try store.expenses(), [expense])
        XCTAssertEqual(try store.categories().first(where: { $0.id == category.id })?.name, "Pet care")
        XCTAssertThrowsError(try service.deleteCategory(category.id))
        XCTAssertThrowsError(try store.deleteCategory(category.id))
        try service.delete(expense.id)
        try service.deleteCategory(category.id)
        XCTAssertFalse(try store.categories().contains(where: { $0.id == category.id }))
    }

    @MainActor
    func testDuplicateAndInvalidCategoryDoesNotMutateStore() throws {
        let store = try ExpenseRepository(inMemory: true)
        try store.prepareSampleBook()
        let before = try store.categories()
        XCTAssertThrowsError(try store.saveCategory(.init(id: UUID(), name: "  food & drink  ", symbol: "bag")))
        XCTAssertThrowsError(try store.saveCategory(.init(id: UUID(), name: " ", symbol: "bag")))
        XCTAssertThrowsError(try store.saveCategory(.init(id: UUID(), name: "Pets", symbol: "made.up.icon")))
        XCTAssertEqual(try store.categories(), before)
    }
}
