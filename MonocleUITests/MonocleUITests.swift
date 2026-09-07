import XCTest

final class MonocleUITests: XCTestCase {
    @MainActor
    func testKeypadDraftSurvivesInterruptionAndRecords() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["addExpense"].waitForExistence(timeout: 10))
        app.buttons["addExpense"].tap()
        app.buttons["key-2"].tap(); app.buttons["key-8"].tap(); app.buttons["key-000"].tap()
        app.buttons["category-Food & Drink"].tap()
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

    @MainActor
    func testKeypadFitsAndManyCategoriesStayCompact() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["MONOCLE_MANY_CATEGORIES"] = "1"
        app.launch()
        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "home-011"; home.lifetime = .keepAlways; add(home)
        app.buttons["addExpense"].tap()
        for key in ["000", "0", "delete.left"] {
            let button = app.buttons["key-" + key]
            XCTAssertTrue(button.isHittable)
            XCTAssertLessThanOrEqual(button.frame.maxY, app.buttons["recordExpense"].frame.minY)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        let entry = XCTAttachment(screenshot: app.screenshot())
        entry.name = "entry-011"; entry.lifetime = .keepAlways; add(entry)
        app.buttons["allCategories"].tap()
        let expanded = XCTAttachment(screenshot: app.screenshot())
        expanded.name = "categories-expanded-011"; expanded.lifetime = .keepAlways; add(expanded)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("Other")
        XCTAssertTrue(app.buttons["picker-category-Other"].waitForExistence(timeout: 5))
        let picker = XCTAttachment(screenshot: app.screenshot())
        picker.name = "categories-011"; picker.lifetime = .keepAlways; add(picker)
        app.buttons["picker-category-Other"].tap()
        XCTAssertTrue(app.buttons["category-Other"].waitForExistence(timeout: 5))
        app.buttons["key-1"].tap(); app.buttons["key-000"].tap()
        app.buttons["recordExpense"].tap()
        XCTAssertTrue(app.buttons["expense-"].firstMatch.waitForExistence(timeout: 5))
    }
    @MainActor
    func testCloseConfirmsDiscardAndDoesNotBlockEditing() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launch()
        app.buttons["addExpense"].tap()
        app.buttons["key-2"].tap(); app.buttons["key-8"].tap(); app.buttons["key-000"].tap()
        app.buttons["Close entry"].tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
        app.buttons["Keep editing"].tap()
        XCTAssertTrue(app.staticTexts["amountDisplay"].label.contains("28.000"))
        app.buttons["Close entry"].tap()
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["addExpense"].waitForExistence(timeout: 5))
        app.buttons["expense-Morning coffee"].tap()
        XCTAssertTrue(app.navigationBars["Edit expense"].waitForExistence(timeout: 5))
        app.buttons["key-0"].tap()
        app.buttons["Close entry"].tap()
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["expense-Morning coffee"].label.contains("Rp28.000"))
        app.buttons["expense-Morning coffee"].tap()
        app.buttons["Close entry"].tap()
        XCTAssertTrue(app.buttons["addExpense"].waitForExistence(timeout: 5), "Unmodified edits close without a discard prompt")
    }
    @MainActor
    func testSwipeDownAlsoConfirmsDiscard() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launch()
        app.buttons["addExpense"].tap()
        app.buttons["key-5"].tap()
        let bar = app.navigationBars["New expense"]
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 5))
        app.buttons["Discard"].tap()
        app.buttons["addExpense"].tap()
        XCTAssertEqual(app.staticTexts["amountDisplay"].label, "Amount Rp0")
    }
    @MainActor
    func testRecoveredDraftCanBeDiscardedToOpenAnotherTransaction() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launch()
        app.buttons["addExpense"].tap(); app.buttons["key-5"].tap()
        app.terminate(); app.launch()
        app.buttons["expense-Morning coffee"].tap()
        XCTAssertTrue(app.buttons["Discard and continue"].waitForExistence(timeout: 5))
        app.buttons["Discard and continue"].tap()
        XCTAssertTrue(app.navigationBars["Edit expense"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["amountDisplay"].label.contains("28.000"))
    }

}
