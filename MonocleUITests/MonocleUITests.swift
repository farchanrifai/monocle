import XCTest

final class MonocleUITests: XCTestCase {
    @MainActor
    func testKeypadDraftPersistsAcrossRelaunchAndRecords() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["addExpense"].waitForExistence(timeout: 10))
        app.buttons["addExpense"].tap()
        app.buttons["key-2"].tap(); app.buttons["key-8"].tap(); app.buttons["key-000"].tap()
        app.buttons["category-Food & Drink"].tap()
        app.buttons["Close entry"].tap()
        app.terminate(); app.launch()
        app.buttons["addExpense"].tap()
        XCTAssertTrue(app.staticTexts["amountDisplay"].label.contains("28.000"))
        app.buttons["recordExpense"].tap()
        XCTAssertTrue(app.staticTexts["Expense recorded"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testTextEntryAndModeSwitchKeepParsedFields() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launch()
        app.buttons["addExpense"].tap()
        app.segmentedControls["entryMode"].buttons["Text"].tap()
        app.textFields["expenseText"].tap()
        app.textFields["expenseText"].typeText("Coffee 28k")
        XCTAssertTrue(app.staticTexts["amountDisplay"].label.contains("28.000"), "Text should parse as it is typed")
        app.buttons["parseExpense"].tap()
        app.segmentedControls["entryMode"].buttons["Keypad"].tap()
        XCTAssertTrue(app.staticTexts["amountDisplay"].label.contains("28.000"))
        XCTAssertEqual(app.textFields["expenseNote"].value as? String, "Coffee")
        app.buttons["recordExpense"].tap()
        XCTAssertTrue(app.buttons["expense-Coffee"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testInvalidEntryShowsErrorWithoutDismissingDraft() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launch()
        app.buttons["addExpense"].tap()
        app.buttons["key-2"].tap(); app.buttons["key-8"].tap(); app.buttons["key-000"].tap()
        app.buttons["recordExpense"].tap()
        XCTAssertTrue(app.alerts["Check this"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["amountDisplay"].label.contains("28.000"))
        XCTAssertTrue(app.buttons["category-Food & Drink"].exists)
    }

    @MainActor
    func testBudgetAndBillReviewScreensAndSavedReminderChoice() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launch()
        app.tabBars.buttons["Budgets"].tap()
        XCTAssertTrue(app.staticTexts["Where it went"].waitForExistence(timeout: 5))
        let budget = XCTAttachment(screenshot: app.screenshot())
        budget.name = "budgets"; budget.lifetime = .keepAlways; add(budget)
        app.tabBars.buttons["Bills"].tap()
        XCTAssertTrue(app.buttons["Configure sample bill"].waitForExistence(timeout: 5))
        app.buttons["Configure sample bill"].tap()
        let reminder = app.switches["Remind me"]
        XCTAssertEqual(reminder.value as? String, "1")
        reminder.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(reminder.value as? String, "0", "Toggle must change before saving")
        let bill = XCTAttachment(screenshot: app.screenshot())
        bill.name = "bill-settings"; bill.lifetime = .keepAlways; add(bill)
        app.buttons["Save"].tap()
        app.terminate(); app.launch()
        app.tabBars.buttons["Bills"].tap()
        app.buttons["Configure sample bill"].tap()
        XCTAssertEqual(app.switches["Remind me"].value as? String, "0")
    }

}
