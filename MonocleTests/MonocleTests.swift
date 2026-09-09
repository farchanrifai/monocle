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
        var expense = Expense(amount: 10000, day: "2026-09-07", note: "", allocations: [.init(categoryID: a, amount: 4000), .init(categoryID: b, amount: 6000)])
        try expense.validate(categories: ExpenseCategory.defaults)
        expense.allocations[1].amount = 6001
        XCTAssertThrowsError(try expense.validate(categories: ExpenseCategory.defaults))
        expense.allocations[1].amount = 6000
        expense.day = "2026-02-30"
        XCTAssertThrowsError(try expense.validate(categories: ExpenseCategory.defaults))
    }
    func testMonthEndClampingAndLeapYear() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let february = try XCTUnwrap(Day.date("2024-02-29", calendar: calendar))
        let leap = BudgetCycle.containing(february, startDay: 31, calendar: calendar)
        XCTAssertEqual(Day.string(leap.start, calendar: calendar), "2024-02-29")
        XCTAssertEqual(Day.string(leap.end, calendar: calendar), "2024-03-31")
        let ordinary = BudgetCycle.containing(try XCTUnwrap(Day.date("2026-02-27", calendar: calendar)), startDay: 31, calendar: calendar)
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
        var expense = Expense(amount: 2_800_000, day: "2026-09-07", note: "Coffee", allocations: [.init(categoryID: ExpenseCategory.defaults[0].id, amount: 2_800_000)])
        do {
            let store = try ExpenseRepository(url: url)
            try store.prepareSampleBook()
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
        try reopened.prepareSampleBook()
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
        try store.prepareSampleBook()
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
        let book = NSEntityDescription.insertNewObject(forEntityName: "Book", into: context)
        book.setValue(BookProfile.sample.id, forKey: "id"); book.setValue(BookProfile.sample.name, forKey: "name")
        let category = NSEntityDescription.insertNewObject(forEntityName: "CategoryRecord", into: context)
        category.setValue(ExpenseCategory.defaults[0].id, forKey: "id"); category.setValue("Food & Drink", forKey: "name")
        category.setValue("cup.and.saucer", forKey: "symbol"); category.setValue(book, forKey: "book")
        let expense = NSEntityDescription.insertNewObject(forEntityName: "ExpenseRecord", into: context)
        expense.setValue(UUID(), forKey: "id"); expense.setValue(Int64(2_800_000), forKey: "amount")
        expense.setValue("2026-09-08", forKey: "day"); expense.setValue("Coffee", forKey: "note")
        expense.setValue("manual", forKey: "source"); expense.setValue(Date.now, forKey: "createdAt"); expense.setValue(book, forKey: "book")
        let allocation = NSEntityDescription.insertNewObject(forEntityName: "AllocationRecord", into: context)
        allocation.setValue(Int64(2_800_000), forKey: "amount"); allocation.setValue(category, forKey: "category"); allocation.setValue(expense, forKey: "expense")
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
    func testDraftSurvivesCodingWithInputModeAndIdentity() throws {
        var draft = ExpenseDraft()
        draft.amount = "28000"; draft.text = "Coffee 28k"; draft.mode = .text
        draft.categoryID = ExpenseCategory.defaults[0].id
        draft.splitAllocations = [
            .init(categoryID: ExpenseCategory.defaults[0].id, amount: "12000"),
            .init(categoryID: ExpenseCategory.defaults[1].id, amount: "16000")
        ]
        let restored = try JSONDecoder().decode(ExpenseDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored, draft)
        XCTAssertEqual(try restored.expense().allocations, [.init(categoryID: ExpenseCategory.defaults[0].id, amount: 1_200_000), .init(categoryID: ExpenseCategory.defaults[1].id, amount: 1_600_000)])
    }
    func testOlderDraftWithoutSplitFieldsStillOpens() throws {
        struct OlderDraft: Codable {
            var id = UUID(); var amount = "28000"; var categoryID = ExpenseCategory.defaults[0].id
            var note = "Coffee"; var date = Date.now; var text = ""; var mode = EntryMode.keypad
            var editing = false; var createdAt = Date.now; var source = "manual"
        }
        let restored = try JSONDecoder().decode(ExpenseDraft.self, from: JSONEncoder().encode(OlderDraft()))
        XCTAssertFalse(restored.isSplit)
        XCTAssertEqual(try restored.expense().allocations, [.init(categoryID: ExpenseCategory.defaults[0].id, amount: 2_800_000)])
    }
}
