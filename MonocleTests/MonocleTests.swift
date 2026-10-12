import CoreData
import XCTest
@testable import Monocle

final class MonocleTests: XCTestCase {
    func testMoneyParsingIsExactAndRejectsAmbiguity() throws {
        let locale = Locale(identifier: "id_ID")
        XCTAssertEqual(try Money.parse("28k", locale: locale), 2_800_000)
        XCTAssertEqual(try Money.parse("28,5k", locale: locale), 2_850_000)
        XCTAssertEqual(try Money.parse("Rp28.000", locale: locale), 2_800_000)
        for invalid in ["0", "-28000", "28,500", "28.5", "1e6", "coffee", "9999999999999999999", "0,0001k"] {
            XCTAssertThrowsError(try Money.parse(invalid, locale: locale), invalid)
        }
    }

    func testTextParsingNeverChoosesBetweenConflictingCategories() throws {
        let coffee = try ExpenseParser.parse("Coffee 28k", categories: ExpenseCategory.defaults)
        XCTAssertEqual(coffee.amount, 2_800_000)
        XCTAssertEqual(coffee.note, "Coffee")
        XCTAssertEqual(coffee.categoryID, ExpenseCategory.defaults[0].id)
        XCTAssertNil(try ExpenseParser.parse("Coffee taxi 28k", categories: ExpenseCategory.defaults).categoryID)
        XCTAssertNil(try ExpenseParser.parse("Something 28k", categories: ExpenseCategory.defaults).categoryID)
        XCTAssertThrowsError(try ExpenseParser.parse("Coffee 28k 30k", categories: ExpenseCategory.defaults))
    }
    func testSplitValidationAndDateValidation() throws {
        let a = ExpenseCategory.defaults[0].id
        let b = ExpenseCategory.defaults[1].id
        var expense = Expense(amount: 10000, day: "2026-09-07", note: "", splits: [.init(categoryID: a, amount: 4000), .init(categoryID: b, amount: 6000)])
        try expense.validate(categories: ExpenseCategory.defaults)
        expense.splits[1].amount = 6001
        XCTAssertThrowsError(try expense.validate(categories: ExpenseCategory.defaults))
        expense.splits[1].amount = 6000
        expense.day = "2026-02-30"
        XCTAssertThrowsError(try expense.validate(categories: ExpenseCategory.defaults))
    }
    func testMonthEndClampingAndLeapYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let february = try XCTUnwrap(Day.date("2024-02-29", calendar: calendar))
        let leap = Cycle.containing(february, startDay: 31, calendar: calendar)
        XCTAssertEqual(Day.string(leap.start, calendar: calendar), "2024-02-29")
        XCTAssertEqual(Day.string(leap.end, calendar: calendar), "2024-03-31")
        let ordinary = Cycle.containing(try XCTUnwrap(Day.date("2026-02-27", calendar: calendar)), startDay: 31, calendar: calendar)
        XCTAssertEqual(Day.string(ordinary.start, calendar: calendar), "2026-01-31")
        XCTAssertEqual(Day.string(ordinary.end, calendar: calendar), "2026-02-28")
    }
    func testEffectiveBudgetHistoryPreservesPeriodsAcrossStartDayChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let september = try XCTUnwrap(Day.date("2026-09-08", calendar: calendar))
        let original = BudgetVersion.initial(overallLimit: 450_000_000, startDay: 1, date: september, calendar: calendar)
        XCTAssertEqual(original.effectiveDay, "2026-09-01")
        let changed = BudgetVersion(id: UUID(), effectiveDay: "2026-10-01", overallLimit: 500_000_000, startDay: 25,
                                    transitionEndDay: "2026-10-25")
        let history = [original, changed]
        XCTAssertEqual(BudgetHistory.period(containing: try XCTUnwrap(Day.date("2026-09-30", calendar: calendar)), budgets: history, calendar: calendar)?.budget, original)
        let transition = try XCTUnwrap(BudgetHistory.period(containing: try XCTUnwrap(Day.date("2026-10-10", calendar: calendar)), budgets: history, calendar: calendar))
        XCTAssertEqual(Day.string(transition.cycle.start, calendar: calendar), "2026-10-01")
        XCTAssertEqual(Day.string(transition.cycle.end, calendar: calendar), "2026-10-25")
        XCTAssertTrue(transition.isTransition)
        let next = try XCTUnwrap(BudgetHistory.period(containing: try XCTUnwrap(Day.date("2026-10-25", calendar: calendar)), budgets: history, calendar: calendar))
        XCTAssertEqual(Day.string(next.cycle.start, calendar: calendar), "2026-10-25")
        XCTAssertEqual(Day.string(next.cycle.end, calendar: calendar), "2026-11-25")
    }
    @MainActor
    func testStoreRoundTripUpsertAndInvalidSavePreservation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Test.sqlite")
        var expense = Expense(amount: 2_800_000, day: "2026-09-07", note: "Coffee", splits: [.init(categoryID: ExpenseCategory.defaults[0].id, amount: 2_800_000)])
        do {
            let store = try ExpenseRepository(url: url)
            try store.prepareSampleCard()
            try store.save(expense)
            try store.save(expense)
            XCTAssertEqual(try store.expenses().count, 1)
            expense.note = "Morning coffee"
            try store.save(expense)
            var invalid = expense; invalid.amount += 100
            XCTAssertThrowsError(try store.save(invalid))
            XCTAssertEqual(try store.expenses().first?.note, "Morning coffee")
            for persistentStore in store.container.persistentStoreCoordinator.persistentStores {
                try store.container.persistentStoreCoordinator.remove(persistentStore)
            }
        }
        let reopened = try ExpenseRepository(url: url)
        XCTAssertEqual(try reopened.expenses(), [expense])
        try reopened.delete(expense.id)
        XCTAssertTrue(try reopened.expenses().isEmpty)
        try reopened.prepareSampleCard()
        XCTAssertTrue(try reopened.expenses().isEmpty, "An empty book must not trigger reseeding")
        for persistentStore in reopened.container.persistentStoreCoordinator.persistentStores {
            try reopened.container.persistentStoreCoordinator.remove(persistentStore)
        }
    }
    @MainActor
    func testBudgetHistoryPersistsAndUpsertsByEffectiveDay() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Test.sqlite")
        let store = try ExpenseRepository(url: url)
        try store.prepareSampleCard()
        let budget = BudgetVersion(effectiveDay: "2026-09-01", overallLimit: 450_000_000, startDay: 1)
        try store.save(budget)
        var updated = budget; updated.overallLimit = 500_000_000
        try store.save(updated)
        XCTAssertEqual(try store.budgets(), [updated])
        for persistentStore in store.container.persistentStoreCoordinator.persistentStores {
            try store.container.persistentStoreCoordinator.remove(persistentStore)
        }
        let reopened = try ExpenseRepository(url: url)
        XCTAssertEqual(try reopened.budgets(), [updated])
        for persistentStore in reopened.container.persistentStoreCoordinator.persistentStores {
            try reopened.container.persistentStoreCoordinator.remove(persistentStore)
        }
    }
    @MainActor
    func testV1StoreMigratesWithoutLosingExpenses() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Test.sqlite")
        let bundle = Bundle(for: ExpenseRepository.self)
        let modelURL = try XCTUnwrap(bundle.url(forResource: "Monocle", withExtension: "momd")).appendingPathComponent("MonocleV1.mom")
        let oldModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: modelURL))
        let oldContainer = NSPersistentContainer(name: "MonocleV1", managedObjectModel: oldModel)
        try oldContainer.persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil)
        let context = oldContainer.viewContext
        let card = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
        card.setValue(Card.demo.id, forKey: "id"); card.setValue(Card.demo.name, forKey: "name")
        let category = NSEntityDescription.insertNewObject(forEntityName: "CategoryRecord", into: context)
        category.setValue(ExpenseCategory.defaults[0].id, forKey: "id"); category.setValue("Food & Drink", forKey: "name")
        category.setValue("cup.and.saucer", forKey: "symbol"); category.setValue(card, forKey: "book")
        let expense = NSEntityDescription.insertNewObject(forEntityName: "ExpenseRecord", into: context)
        expense.setValue(UUID(), forKey: "id"); expense.setValue(Int64(2_800_000), forKey: "amount")
        expense.setValue("2026-09-08", forKey: "day"); expense.setValue("Coffee", forKey: "note")
        expense.setValue("manual", forKey: "source"); expense.setValue(Date.now, forKey: "createdAt"); expense.setValue(card, forKey: "book")
        let split = NSEntityDescription.insertNewObject(forEntityName: "AllocationRecord", into: context)
        split.setValue(Int64(2_800_000), forKey: "amount"); split.setValue(category, forKey: "category"); split.setValue(expense, forKey: "expense")
        try context.save()
        for persistentStore in oldContainer.persistentStoreCoordinator.persistentStores {
            try oldContainer.persistentStoreCoordinator.remove(persistentStore)
        }
        let migrated = try ExpenseRepository(url: url)
        XCTAssertEqual(try migrated.expenses().count, 1)
        try migrated.prepareInitialBudget(settings: PrototypeSettings())
        XCTAssertEqual(try migrated.budgets().count, 1)
        for persistentStore in migrated.container.persistentStoreCoordinator.persistentStores {
            try migrated.container.persistentStoreCoordinator.remove(persistentStore)
        }
    }
    func testAmountInputGroupsThousandsAndKeepsDecimalsHiddenUntilTyped() {
        let us = Locale(identifier: "en_US"), id = Locale(identifier: "id_ID")
        XCTAssertEqual(Money.groupedInput("134273645", locale: us, code: "JPY"), "134,273,645")
        XCTAssertEqual(Money.groupedInput("134.273.645", locale: id, code: "IDR"), "134.273.645")
        XCTAssertEqual(Money.groupedInput("1,234", locale: us, code: "USD"), "1,234")
        XCTAssertEqual(Money.groupedInput("1234.", locale: us, code: "USD"), "1,234.")
        XCTAssertEqual(Money.groupedInput("1234.567", locale: us, code: "USD"), "1,234.56")
        XCTAssertEqual(Money.groupedInput("1234,5", locale: id, code: "USD"), "1.234,5")
        XCTAssertEqual(Money.groupedInput("1234.5", locale: us, code: "JPY"), "1,234", "whole-unit currencies drop decimals")
        XCTAssertEqual(Money.groupedInput("28k", locale: us, code: "IDR"), "28k")
        XCTAssertEqual(Money.groupedInput("", locale: us, code: "IDR"), "")
        XCTAssertEqual(try Money.parse(Money.groupedInput("1234567.5", locale: us, code: "USD"), locale: us, code: "USD"), 123_456_750)
    }
    func testReportingEquivalentNeedsOnlyAmountAndRate() {
        var draft = ExpenseDraft()
        draft.currency = "JPY"; draft.amount = "1000"; draft.rate = "112.99"
        XCTAssertEqual(draft.reportingEquivalent(reporting: "IDR"), 11_299_000)
        draft.rate = ""
        XCTAssertNil(draft.reportingEquivalent(reporting: "IDR"))
        draft.currency = nil; draft.rate = "112.99"
        XCTAssertNil(draft.reportingEquivalent(reporting: "IDR"), "not foreign")
    }
    func testDraftSurvivesCodingAndIdentity() throws {
        var draft = ExpenseDraft()
        draft.amount = "28000"
        draft.categoryID = ExpenseCategory.defaults[0].id
        draft.splitParts = [
            .init(categoryID: ExpenseCategory.defaults[0].id, amount: "12000"),
            .init(categoryID: ExpenseCategory.defaults[1].id, amount: "16000")
        ]
        let restored = try JSONDecoder().decode(ExpenseDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored, draft)
        XCTAssertEqual(try restored.expense().splits, [.init(categoryID: ExpenseCategory.defaults[0].id, amount: 1_200_000), .init(categoryID: ExpenseCategory.defaults[1].id, amount: 1_600_000)])
    }
    func testOlderDraftWithoutSplitFieldsStillOpens() throws {
        struct OlderDraft: Codable {
            var id = UUID(); var amount = "28000"; var categoryID = ExpenseCategory.defaults[0].id
            var note = "Coffee"; var date = Date.now; var text = ""; var mode = "Keypad"
            var editing = false; var createdAt = Date.now; var source = "manual"
        }
        let restored = try JSONDecoder().decode(ExpenseDraft.self, from: JSONEncoder().encode(OlderDraft()))
        XCTAssertFalse(restored.isSplit)
        XCTAssertEqual(try restored.expense().splits, [.init(categoryID: ExpenseCategory.defaults[0].id, amount: 2_800_000)])
    }
}
