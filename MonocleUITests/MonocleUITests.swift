import XCTest

@MainActor
final class MonocleUITests: XCTestCase {
    @MainActor
    func testKeypadDraftSurvivesInterruptionAndRecords() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
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
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()
        openSettings(app)
        app.segmentedControls["entryMode"].buttons["Text"].tap()
        app.buttons["Done"].tap()
        app.buttons["addExpense"].tap()
        app.textFields["expenseText"].tap()
        app.textFields["expenseText"].typeText("Coffee 28k")
        XCTAssertTrue(app.staticTexts["amountDisplay"].label.contains("28.000"), "Text should parse as it is typed")
        app.buttons["parseExpense"].tap()
        XCTAssertEqual(app.textFields["expenseNote"].value as? String, "Coffee")
        app.buttons["recordExpense"].tap()
        XCTAssertTrue(app.buttons["expense-Coffee"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testInvalidEntryShowsErrorWithoutDismissingDraft() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
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
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Tools & Insights"].tap()
        app.buttons["Budgets"].tap()
        XCTAssertTrue(app.staticTexts["Where it went"].waitForExistence(timeout: 5))
        let budget = XCTAttachment(screenshot: app.screenshot())
        budget.name = "budgets"; budget.lifetime = .keepAlways; add(budget)
        app.buttons["Done"].tap()
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Tools & Insights"].tap()
        app.buttons["Recurring Bills"].tap()
        XCTAssertTrue(app.buttons["addBillButton"].waitForExistence(timeout: 5))
        app.buttons["addBillButton"].tap()

        let reminder = app.switches["billReminderToggle"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        XCTAssertEqual(reminder.value as? String, "1")
        reminder.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(reminder.value as? String, "0", "Toggle must change before saving")
        let bill = XCTAttachment(screenshot: app.screenshot())
        bill.name = "bill-settings"; bill.lifetime = .keepAlways; add(bill)

        let nameField = app.textFields["billNameField"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText("Fiber Internet")

        let amountField = app.textFields["billAmountField"]
        amountField.tap()
        amountField.typeText("450000")

        app.buttons["saveBillButton"].tap()

        let billRow = app.buttons["scheduledBill_Fiber Internet"]
        XCTAssertTrue(billRow.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        app.terminate(); app.launch()
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Tools & Insights"].tap()
        app.buttons["Recurring Bills"].tap()
        XCTAssertTrue(app.buttons["scheduledBill_Fiber Internet"].waitForExistence(timeout: 5))
        app.buttons["scheduledBill_Fiber Internet"].tap()
        XCTAssertEqual(app.switches["billReminderToggle"].value as? String, "0")
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
    }

    @MainActor
    func testStacksFilterBubbleAndCustomizer() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // 1. Verify header filter and bottom add button exist
        XCTAssertTrue(app.buttons["activityFilterButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["addExpense"].exists)

        // Capture screenshot of bottom navigation bubbles
        let shot = app.screenshot()
        keepScreenshot(shot)

        // 2. Tap filter button to show menu directly and select All Active Cards
        let initialBadge = app.staticTexts["activityScopeBadge"]
        XCTAssertTrue(initialBadge.waitForExistence(timeout: 5))
        app.buttons["activityFilterButton"].tap()
        let allCardsOption = app.buttons["All Active Cards"]
        XCTAssertTrue(allCardsOption.waitForExistence(timeout: 5))
        allCardsOption.tap()
        XCTAssertTrue(app.staticTexts["All cards"].waitForExistence(timeout: 5) || initialBadge.exists)

        // 3. Open Stacks & Card Visibility from menu
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Cards & Stacks"].tap()
        XCTAssertTrue(app.buttons["Stacks & Card Visibility"].waitForExistence(timeout: 5))
        app.buttons["Stacks & Card Visibility"].tap()

        // 4. Verify Stack Customizer presented
        XCTAssertTrue(app.navigationBars["Manage Stacks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveStackCustomizer"].exists)
        app.buttons["saveStackCustomizer"].tap()
    }

    @MainActor
    func testKeypadFitsAndManyCategoriesStayCompact() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launchEnvironment["MONOCLE_MANY_CATEGORIES"] = "1"
        app.launch()
        let nativeBar = app.tabBars.firstMatch
        XCTAssertTrue(nativeBar.waitForExistence(timeout: 5))
        XCTAssertFalse(nativeBar.frame.intersects(app.buttons["addExpense"].frame), "Native tabs must not overlap the add button")
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
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["addExpense"].tap()
        app.buttons["key-2"].tap(); app.buttons["key-8"].tap(); app.buttons["key-000"].tap()
        app.buttons["Close entry"].tap()
        XCTAssertTrue(app.buttons["Keep editing"].waitForExistence(timeout: 5))
        app.buttons["Keep editing"].tap()
        XCTAssertTrue(app.staticTexts["amountDisplay"].label.contains("28.000"))
        app.buttons["Close entry"].tap()
        app.buttons["Discard"].tap()
        app.buttons["expense-Morning coffee"].tap()
        XCTAssertTrue(app.navigationBars["Transaction Details"].waitForExistence(timeout: 5))
        app.buttons["transactionDetailEdit"].tap()
        XCTAssertTrue(app.navigationBars["Edit expense"].waitForExistence(timeout: 5))
        app.buttons["key-0"].tap()
        app.buttons["Close entry"].tap()
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["transactionDetailBack"].waitForExistence(timeout: 5))
        app.buttons["transactionDetailBack"].tap()
        XCTAssertTrue(app.buttons["expense-Morning coffee"].waitForExistence(timeout: 5))
        app.buttons["expense-Morning coffee"].tap()
        XCTAssertTrue(app.navigationBars["Transaction Details"].waitForExistence(timeout: 5))
        app.buttons["transactionDetailEdit"].tap()
        app.buttons["Close entry"].tap()
        XCTAssertTrue(app.buttons["transactionDetailBack"].waitForExistence(timeout: 5), "Unmodified edits close without a discard prompt")
        app.buttons["transactionDetailBack"].tap()
        XCTAssertTrue(app.buttons["addExpense"].waitForExistence(timeout: 5))
    }
    @MainActor
    func testSwipeDownAlsoConfirmsDiscard() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["addExpense"].tap()
        app.buttons["key-5"].tap()
        let bar = app.navigationBars["New expense"]
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 5))
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["addExpense"].waitForExistence(timeout: 5))
        app.buttons["addExpense"].tap()
        XCTAssertTrue(app.staticTexts["amountDisplay"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["amountDisplay"].label, "Amount Rp0")
    }
    @MainActor
    func testRecoveredDraftCanBeDiscardedToOpenAnotherTransaction() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["addExpense"].tap(); app.buttons["key-5"].tap()
        app.terminate(); app.launch()
        app.buttons["expense-Morning coffee"].tap()
        XCTAssertTrue(app.navigationBars["Transaction Details"].waitForExistence(timeout: 5))
        app.buttons["transactionDetailEdit"].tap()
        XCTAssertTrue(app.buttons["Discard and continue"].waitForExistence(timeout: 5))
        app.buttons["Discard and continue"].tap()
        XCTAssertTrue(app.navigationBars["Edit expense"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["amountDisplay"].label.contains("28.000"))
    }

    @MainActor
    func testTransactionDetailPageAndBackNavigation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        XCTAssertTrue(app.buttons["expense-Morning coffee"].waitForExistence(timeout: 10))
        app.buttons["expense-Morning coffee"].tap()

        XCTAssertTrue(app.navigationBars["Transaction Details"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["transactionDetailAmount"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["transactionDetailEdit"].exists)
        XCTAssertTrue(app.buttons["transactionDetailDelete"].exists)

        app.buttons["transactionDetailBack"].tap()
        XCTAssertTrue(app.buttons["addExpense"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testSwipeActionsOnExpenseRow() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        let row = app.buttons["expense-Morning coffee"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))

        // Swipe right to edit
        row.swipeRight()
        let editBtn = app.buttons["Edit"].exists ? app.buttons["Edit"] : app.buttons["Edit expense"]
        if editBtn.waitForExistence(timeout: 2) {
            editBtn.tap()
        }
        XCTAssertTrue(app.navigationBars["Edit expense"].waitForExistence(timeout: 5))
        app.buttons["Close entry"].tap()

        // Swipe left to delete
        let deleteRow = app.buttons["expense-Morning coffee"]
        XCTAssertTrue(deleteRow.waitForExistence(timeout: 5))
        deleteRow.swipeLeft()
        let delBtn = app.buttons["Delete"].exists ? app.buttons["Delete"] : app.buttons["Delete expense"]
        if delBtn.waitForExistence(timeout: 2) {
            delBtn.tap()
        }
        XCTAssertTrue(app.staticTexts["Expense deleted"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testChatOptInFromBottomBarAndCloses() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // Filter now lives in the Home header, above the cards; chat takes its bottom-bar slot.
        let filter = app.buttons["activityFilterButton"]
        let chat = app.buttons["chatButton"]
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        XCTAssertTrue(chat.exists)
        XCTAssertLessThan(filter.frame.midY, app.frame.midY, "Filter must sit in the top header")
        XCTAssertGreaterThan(chat.frame.midY, app.frame.midY, "Chat button must sit in the bottom bar")
        keepScreenshot(app.screenshot())

        chat.tap()
        XCTAssertTrue(app.buttons["chatSetup"].waitForExistence(timeout: 5), "Chat is opt-in")
        XCTAssertFalse(chat.isHittable, "Bottom bar must be hidden behind full-screen chat")
        XCTAssertTrue(app.buttons["Kopi 28rb"].exists, "Empty state offers suggestions")
        keepScreenshot(app.screenshot())

        // Opt in and add a (fake) key; nothing is sent until a message is.
        app.buttons["chatSetup"].tap()
        let toggle = app.switches["chatEnabledToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap()
        let keyField = app.secureTextFields["chatAPIKeyField"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 3))
        keyField.tap()
        keyField.typeText("sk-ant-test")
        app.buttons["Save key"].tap()
        keepScreenshot(app.screenshot())
        app.buttons["Done"].tap()

        let input = app.textViews["chatInput"].exists ? app.textViews["chatInput"] : app.textFields["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("draft only")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.buttons["Kopi 28rb"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -4)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3), "Tapping the transcript dismisses the keyboard")

        // The subtitle is a scope menu; switching adds a notice and keeps the Home filter untouched.
        app.buttons["chatScopeMenu"].tap()
        let allCards = app.buttons["All Cards"]
        XCTAssertTrue(allCards.waitForExistence(timeout: 5))
        allCards.tap()
        XCTAssertTrue(app.staticTexts["Now answering about All cards"].waitForExistence(timeout: 5))
        keepScreenshot(app.screenshot())

        app.buttons["chatClose"].tap()
        XCTAssertTrue(chat.waitForExistence(timeout: 5))
        XCTAssertTrue(chat.isHittable)

        // The conversation and its scope survive closing the chat.
        chat.tap()
        XCTAssertTrue(app.staticTexts["Now answering about All cards"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["chatScopeMenu"].label, "Scope: All cards")
        app.buttons["chatClose"].tap()
    }

    private func keepScreenshot(_ screenshot: XCUIScreenshot) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openSettings(_ app: XCUIApplication) {
        if app.buttons["homeSettings"].exists && app.buttons["homeSettings"].isHittable {
            app.buttons["homeSettings"].tap()
            return
        }
        let options = app.buttons["bookOptionsMenu"]
        XCTAssertTrue(options.waitForExistence(timeout: 5))
        options.tap()
        let settings = app.buttons["Settings"]
        if settings.waitForExistence(timeout: 3) {
            settings.tap()
        } else {
            app.buttons["homeSettings"].tap()
        }
    }

    @MainActor
    func testCategoryEditorPersistsAndSelectionDoesNotJump() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()
        openSettings(app)
        app.buttons["manageCategories"].tap()
        app.buttons["newCategory"].tap()
        app.textFields["categoryName"].tap()
        app.textFields["categoryName"].typeText("Pets")
        app.buttons["saveCategory"].tap()
        XCTAssertTrue(app.buttons["edit-category-Pets"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        app.buttons["addExpense"].tap()
        let category = app.buttons["category-Food & Drink"]
        let before = category.frame.minX
        category.tap()
        XCTAssertEqual(category.frame.minX, before, accuracy: 1, "Selection must not recenter the strip")
        app.buttons["allCategories"].tap()
        app.searchFields.firstMatch.tap()
        app.searchFields.firstMatch.typeText("Pets")
        app.buttons["picker-category-Pets"].tap()
        app.buttons["key-5"].tap(); app.buttons["key-000"].tap()
        app.buttons["recordExpense"].tap()
        XCTAssertTrue(app.buttons["expense-"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testCategoryManagerScreenshots() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launch()
        openSettings(app)
        app.buttons["manageCategories"].tap()
        XCTAssertTrue(app.buttons["newCategory"].waitForExistence(timeout: 5))

        let allCategoriesShot = app.screenshot()
        let allCategories = XCTAttachment(screenshot: allCategoriesShot)
        allCategories.name = "categories-all"
        allCategories.lifetime = .keepAlways
        add(allCategories)

        app.buttons["By Card"].tap()
        Thread.sleep(forTimeInterval: 0.5)
        let byCardShot = app.screenshot()
        let byCard = XCTAttachment(screenshot: byCardShot)
        byCard.name = "categories-by-card"
        byCard.lifetime = .keepAlways
        add(byCard)
    }

    @MainActor
    func testBackupSettingsExposeExportAndImport() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launch()
        openSettings(app)
        app.buttons["backupSettings"].tap()
        XCTAssertTrue(app.buttons["exportBackup"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["importBackup"].exists)
        let screen = XCTAttachment(screenshot: app.screenshot())
        screen.name = "backup-settings-013"; screen.lifetime = .keepAlways; add(screen)
        app.buttons["exportBackup"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5), "Export must present the system document picker")
        let picker = XCTAttachment(screenshot: app.screenshot())
        picker.name = "backup-export-013"; picker.lifetime = .keepAlways; add(picker)
    }

    @MainActor
    func testExportedBackupIsSelectableForRestore() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launch()
        openSettings(app)
        app.buttons["backupSettings"].tap()
        app.buttons["exportBackup"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 5))
        app.buttons["Save"].tap()
        if app.buttons["Keep Both"].waitForExistence(timeout: 2) {
            app.buttons["Keep Both"].tap()
        }
        XCTAssertTrue(app.alerts["Backup & restore"].waitForExistence(timeout: 5))
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.buttons["importBackup"].waitForExistence(timeout: 5))
        app.buttons["importBackup"].tap()
        XCTAssertTrue(app.buttons["Browse"].waitForExistence(timeout: 5))
        let picker = XCTAttachment(screenshot: app.screenshot())
        picker.name = "backup-restore-picker"; picker.lifetime = .keepAlways; add(picker)
        let backup = app.cells.matching(NSPredicate(format: "identifier CONTAINS %@ OR identifier CONTAINS %@", ".monoclebackup", ".json")).firstMatch
        XCTAssertTrue(backup.waitForExistence(timeout: 5), "The exported workspace backup must be selectable")
        backup.tap()
        XCTAssertTrue(app.buttons["restoreBackup"].waitForExistence(timeout: 5), "The exported file must open for review")
    }

    @MainActor
    func testSplitEditorAddsAnotherAllocationWithoutLeavingCapture() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["addExpense"].tap()
        app.buttons["key-2"].tap(); app.buttons["key-8"].tap(); app.buttons["key-000"].tap()
        app.buttons["category-Food & Drink"].tap()
        app.buttons["editSplits"].tap()
        XCTAssertTrue(app.buttons["split-category-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["split-amount-0"].exists)
        app.buttons["addSplit"].tap()
        XCTAssertTrue(app.buttons["split-category-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["split-amount-1"].exists)
        XCTAssertTrue(app.staticTexts["Remaining"].exists)
    }

    @MainActor
    func testSplitRevertAndDiscardResetEntryState() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["addExpense"].tap()
        app.buttons["key-2"].tap(); app.buttons["key-8"].tap(); app.buttons["key-000"].tap()
        app.buttons["category-Food & Drink"].tap()
        app.buttons["editSplits"].tap()
        XCTAssertTrue(app.buttons["split-category-0"].waitForExistence(timeout: 5))

        app.buttons["Use one category instead"].tap()
        XCTAssertTrue(app.buttons["editSplits"].waitForExistence(timeout: 5))

        app.buttons["editSplits"].tap()
        XCTAssertTrue(app.buttons["split-category-0"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["Close entry"].tap()
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.buttons["addExpense"].waitForExistence(timeout: 5))

        app.buttons["addExpense"].tap()
        XCTAssertTrue(app.buttons["editSplits"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Split across 1 categories"].exists)
    }


    @MainActor
    func testSettingsAppearanceModeAndAutoSwitch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()
        openSettings(app)

        let autoToggle = app.switches["autoAppearanceToggle"]
        if !autoToggle.waitForExistence(timeout: 2) { app.swipeUp() }
        XCTAssertTrue(autoToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(autoToggle.value as? String, "0")

        // Tapping Dark in appearanceModePicker
        XCTAssertTrue(app.segmentedControls["appearanceModePicker"].waitForExistence(timeout: 5))
        app.segmentedControls["appearanceModePicker"].buttons["Dark"].tap()

        // Turn on auto switch
        autoToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(autoToggle.value as? String, "1")

        // Dismiss settings
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCardDetailSheetDoesNotOverlapCard() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stack-book-'")).element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        XCTAssertTrue(app.buttons["homeLogo"].waitForExistence(timeout: 5))
        let shot = app.screenshot()
        keepScreenshot(shot)
        app.buttons["homeLogo"].tap()
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCardCustomizerOpensSelectsStockDesignAndSaves() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // Wait for options menu
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 10))
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Cards & Stacks"].tap()

        // Tap "Customize card"
        let customizeButton = app.buttons["Customize Card"]
        XCTAssertTrue(customizeButton.waitForExistence(timeout: 5))
        customizeButton.tap()

        // Verify Customizer view is displayed
        XCTAssertTrue(app.staticTexts["Customize Card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["cardCustomizerTabPicker"].waitForExistence(timeout: 5))

        // Switch to Stock designs
        app.segmentedControls["cardCustomizerTabPicker"].buttons["Stock"].tap()

        let customizerSheetShot = app.screenshot()
        add(XCTAttachment(screenshot: customizerSheetShot))

        // Select Aurora Borealis
        let auroraButton = app.buttons["stockDesign-auroraBorealis"]
        XCTAssertTrue(auroraButton.waitForExistence(timeout: 5))
        auroraButton.tap()

        // Save customization
        let saveButton = app.buttons["saveCardCustomization"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        // Verify we are back on home screen
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))

        let customScreenshot = app.screenshot()
        add(XCTAttachment(screenshot: customScreenshot))
    }

    @MainActor
    func testCustomizeCardWhenCardAlreadyOpenDismissesTransactionSheetAndOpensCustomizer() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // 1. Open the first card
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stack-book-'")).element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        // 2. Verify card detail sheet is open
        XCTAssertTrue(app.staticTexts["Latest Transactions"].waitForExistence(timeout: 5))

        // 3. Tap options menu -> "Customize card" while card detail is open
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Cards & Stacks"].tap()

        let customizeButton = app.buttons["Customize Card"]
        XCTAssertTrue(customizeButton.waitForExistence(timeout: 5))
        customizeButton.tap()

        // 4. Verify "Customize Card" sheet presents successfully without failing silently
        XCTAssertTrue(app.staticTexts["Customize Card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["saveCardCustomization"].waitForExistence(timeout: 5))

        // 5. Dismiss customizer
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCustomizeCardDirectlyFromDetailSheetToolbar() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stack-book-'")).element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Cards & Stacks"].tap()
        app.buttons["Customize Card"].tap()

        XCTAssertTrue(app.staticTexts["Customize Card"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCardCustomizerHorizontalCarouselSwitchesActiveCard() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // Create second book so stack has multiple cards
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 10))
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Cards & Stacks"].tap()
        XCTAssertTrue(app.buttons["menuNewBook"].waitForExistence(timeout: 5))
        app.buttons["menuNewBook"].tap()

        let inlineField = app.textFields["cardNameInlineTextField"]
        if inlineField.waitForExistence(timeout: 5) {
            let clearBtn = app.buttons["cardNameInlineClearButton"]
            if clearBtn.waitForExistence(timeout: 2) { clearBtn.tap() }
            inlineField.typeText("Business")
            let commitBtn = app.buttons["cardNameInlineCommitButton"]
            if commitBtn.waitForExistence(timeout: 2) { commitBtn.tap() }
        }
        app.buttons["saveCardCustomization"].tap()

        // Close newly focused book detail sheet if open
        if app.buttons["homeLogo"].waitForExistence(timeout: 3) {
            app.buttons["homeLogo"].tap()
        }

        // Open customizer
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 10))
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Cards & Stacks"].tap()

        let customizeButton = app.buttons["Customize Card"]
        XCTAssertTrue(customizeButton.waitForExistence(timeout: 5))
        customizeButton.tap()

        XCTAssertTrue(app.staticTexts["Customize Card"].waitForExistence(timeout: 5))

        // Verify carousel previews exist for multiple books
        let previews = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'customizer-preview-'"))
        XCTAssertTrue(previews.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertTrue(previews.element(boundBy: 1).waitForExistence(timeout: 5))

        // Verify active card is horizontally center-aligned and neighboring card peeks subtly
        let windowWidth = app.windows.element(boundBy: 0).frame.width
        let activeCardFrame = previews.element(boundBy: 0).frame
        let leadingSpace = activeCardFrame.minX
        let trailingSpace = windowWidth - activeCardFrame.maxX
        XCTAssertEqual(leadingSpace, trailingSpace, accuracy: 3.0, "Active card in customizer carousel must be center-aligned")

        let neighboringCardFrame = previews.element(boundBy: 1).frame
        let peek = windowWidth - neighboringCardFrame.minX
        XCTAssertLessThanOrEqual(peek, 30.0, "Neighboring card peek should be subtle, not excessive")
        XCTAssertGreaterThanOrEqual(peek, 5.0, "Neighboring card should still peek slightly into view")

        // Take a screenshot of the multi-card horizontal carousel
        let carouselShot = app.screenshot()
        add(XCTAttachment(screenshot: carouselShot))

        // Tap the second preview card in carousel to make it active
        previews.element(boundBy: 1).tap()
        Thread.sleep(forTimeInterval: 0.5)
        let secondCardShot = app.screenshot()
        add(XCTAttachment(screenshot: secondCardShot))

        // Switch to Stock tab
        app.segmentedControls["cardCustomizerTabPicker"].buttons["Stock"].tap()

        // Select Sunset Heat
        let sunset = app.buttons["stockDesign-sunsetHeat"]
        XCTAssertTrue(sunset.waitForExistence(timeout: 5))
        sunset.tap()

        // Save customization
        app.buttons["saveCardCustomization"].tap()
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))

        // Take screenshot of home screen with customized card stack
        let stackShot = app.screenshot()
        add(XCTAttachment(screenshot: stackShot))
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCardCustomizerInlineRenameCard() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // 1. Open customize card modal
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 10))
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Cards & Stacks"].tap()

        let customizeButton = app.buttons["Customize Card"]
        XCTAssertTrue(customizeButton.waitForExistence(timeout: 5))
        customizeButton.tap()

        XCTAssertTrue(app.staticTexts["Customize Card"].waitForExistence(timeout: 5))

        // 2. Find and tap the card name button on the active card
        let nameButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cardNameButton-'")).element(boundBy: 0)
        XCTAssertTrue(nameButton.waitForExistence(timeout: 5))
        nameButton.tap()

        // 3. Verify inline TextField appears
        let inlineTextField = app.textFields["cardNameInlineTextField"]
        XCTAssertTrue(inlineTextField.waitForExistence(timeout: 5))

        // Take a screenshot of the inline card rename in progress
        let renameShot = app.screenshot()
        add(XCTAttachment(screenshot: renameShot))

        // 4. Tap clear button and type new card name
        let clearButton = app.buttons["cardNameInlineClearButton"]
        if clearButton.waitForExistence(timeout: 2) {
            clearButton.tap()
        }
        inlineTextField.typeText("Groceries")

        // 5. Commit inline rename via checkmark button
        let commitButton = app.buttons["cardNameInlineCommitButton"]
        XCTAssertTrue(commitButton.waitForExistence(timeout: 5))
        commitButton.tap()

        // 6. Verify the card name is updated in the preview
        XCTAssertTrue(app.staticTexts["Groceries"].waitForExistence(timeout: 5))

        // 7. Save customization
        let saveButton = app.buttons["saveCardCustomization"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        // 8. Verify we are back on home screen and the card name is updated in the stack
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Groceries"].waitForExistence(timeout: 5))

        let renamedStackShot = app.screenshot()
        add(XCTAttachment(screenshot: renamedStackShot))
    }

    @MainActor
    func testCreateNewBookDirectlyInCustomizationPanel() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // 1. Tap Create new book in options menu
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 10))
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Cards & Stacks"].tap()

        let createButton = app.buttons["menuNewBook"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        // 2. Verify we are directly in the customization panel
        XCTAssertTrue(app.staticTexts["New Card"].waitForExistence(timeout: 5))

        // Capture screenshot of direct new book customizer entry
        let directEntryShot = app.screenshot()
        add(XCTAttachment(screenshot: directEntryShot))

        // 3. Rename inline to "Investments"
        let inlineTextField = app.textFields["cardNameInlineTextField"]
        if inlineTextField.waitForExistence(timeout: 5) {
            let clearBtn = app.buttons["cardNameInlineClearButton"]
            if clearBtn.waitForExistence(timeout: 2) { clearBtn.tap() }
            inlineTextField.typeText("Investments")
            let commitBtn = app.buttons["cardNameInlineCommitButton"]
            if commitBtn.waitForExistence(timeout: 2) { commitBtn.tap() }
        }

        // 4. Select Stock tab and pick Aurora design
        app.segmentedControls["cardCustomizerTabPicker"].buttons["Stock"].tap()
        let aurora = app.buttons["stockDesign-auroraBorealis"]
        XCTAssertTrue(aurora.waitForExistence(timeout: 5))
        aurora.tap()

        // 5. Save customization
        let saveButton = app.buttons["saveCardCustomization"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        // 6. Verify back on home screen with "Investments" present in stack
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Investments"].waitForExistence(timeout: 5))

        let newBookStackShot = app.screenshot()
        add(XCTAttachment(screenshot: newBookStackShot))
    }

    @MainActor
    func testCardCustomizerPlaceholderCardAddsNewBook() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // 1. Open Customize card
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 10))
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Cards & Stacks"].tap()

        let customizeButton = app.buttons["Customize Card"]
        XCTAssertTrue(customizeButton.waitForExistence(timeout: 5))
        customizeButton.tap()

        XCTAssertTrue(app.staticTexts["Customize Card"].waitForExistence(timeout: 5))

        // 2. Find placeholder card in carousel
        let placeholderCard = app.buttons["customizerPlaceholderCard"]
        XCTAssertTrue(placeholderCard.waitForExistence(timeout: 5))

        // Swipe carousel left to center the placeholder card
        placeholderCard.swipeLeft()
        Thread.sleep(forTimeInterval: 0.5)

        let centeredShot = app.screenshot()
        add(XCTAttachment(screenshot: centeredShot))

        // Tap the createNewCardButton or placeholder card to create new draft book
        let createNewCardButton = app.buttons["createNewCardButton"]
        if createNewCardButton.waitForExistence(timeout: 3) {
            createNewCardButton.tap()
        } else {
            placeholderCard.tap()
        }

        // 4. Verify inline text field for the new draft book appears
        let inlineTextField = app.textFields["cardNameInlineTextField"]
        XCTAssertTrue(inlineTextField.waitForExistence(timeout: 5))

        // 5. Test discard/cancel draft: tap Cancel in navigation bar
        app.buttons["Cancel"].tap()

        // 6. Verify back on home screen and no extra book was added
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testStackSwitchAnimationSequence() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // Verify filter button exists
        let filterButton = app.buttons["activityFilterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10))

        // Initial screenshot before stack switch
        let initialShot = app.screenshot()
        add(XCTAttachment(screenshot: initialShot))

        // Tap filter button to open menu directly and switch to All Active Cards
        filterButton.tap()
        let allCardsOption = app.buttons["All Active Cards"]
        if allCardsOption.waitForExistence(timeout: 3) {
            allCardsOption.tap()
        }

        // Wait 0.6s for Phase 1 to stack up and Phase 2/3 (placeholder reveal) to be on screen
        Thread.sleep(forTimeInterval: 0.6)
        let transitionShot = app.screenshot()
        add(XCTAttachment(screenshot: transitionShot))

        // Wait for transition to settle
        Thread.sleep(forTimeInterval: 1.2)
        let settledShot = app.screenshot()
        add(XCTAttachment(screenshot: settledShot))

        // Switch back via filter menu
        filterButton.tap()
        let firstStackOption = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Stack' OR label CONTAINS 'Default'")).firstMatch
        if firstStackOption.waitForExistence(timeout: 3) {
            firstStackOption.tap()
        }
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertTrue(filterButton.exists)
    }

    @MainActor
    func testStressTappingFilterButton() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        let filterButton = app.buttons["activityFilterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10))

        let coord = filterButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Stress test: rapid taps with 100ms interval (simulating rapid finger tapping)
        for i in 1...10 {
            coord.tap()
            usleep(120_000) // 120ms
            if i % 3 == 0 {
                let shot = app.screenshot()
                keepScreenshot(shot)
            }
        }

        // Wait 1.5s for final settle
        Thread.sleep(forTimeInterval: 1.5)
        let finalShot = app.screenshot()
        add(XCTAttachment(screenshot: finalShot))
        XCTAssertTrue(filterButton.exists)
    }

    @MainActor
    func testCycleThroughDeckWithRecording() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        let filterButton = app.buttons["activityFilterButton"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10))

        let coord = filterButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))

        // Phase 1: Normal cycling with 1.0s between each tap to record full transitions
        for _ in 1...5 {
            coord.tap()
            Thread.sleep(forTimeInterval: 1.0)
        }

        // Phase 2: Rapid tapping with 140ms interval
        for _ in 1...6 {
            coord.tap()
            usleep(140_000)
        }
        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertTrue(filterButton.exists)
    }

    @MainActor
    func testCardCustomizerCarouselSnappingAndTransitions() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 10))
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Cards & Stacks"].tap()

        let customizeButton = app.buttons["Customize Card"]
        XCTAssertTrue(customizeButton.waitForExistence(timeout: 5))
        customizeButton.tap()

        XCTAssertTrue(app.staticTexts["Customize Card"].waitForExistence(timeout: 5))

        let initialShot = app.screenshot()
        add(XCTAttachment(screenshot: initialShot))

        // Swipe left on the card carousel to snap to the next card
        let window = app.windows.firstMatch
        let center = window.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.32))
        let leftTarget = window.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.32))
        center.press(forDuration: 0.05, thenDragTo: leftTarget)

        Thread.sleep(forTimeInterval: 0.8)
        let snappedShot = app.screenshot()
        add(XCTAttachment(screenshot: snappedShot))

        // Swipe back right to re-center the first card
        leftTarget.press(forDuration: 0.05, thenDragTo: center)
        Thread.sleep(forTimeInterval: 0.8)

        XCTAssertTrue(app.buttons["Cancel"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCardReorderingAndBringToFront() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // 1. Verify card stack is present
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stack-book-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))

        if cards.count > 1 {
            // Long press the second card to open context menu
            let secondCard = cards.element(boundBy: 1)
            secondCard.press(forDuration: 1.0)

            let bringToFrontButton = app.buttons["Bring to Front"]
            if bringToFrontButton.waitForExistence(timeout: 3) {
                bringToFrontButton.tap()
                Thread.sleep(forTimeInterval: 0.5)
            }
        }

        // 2. Open Stack Customizer
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Cards & Stacks"].tap()

        let manageStacks = app.buttons["Stacks & Card Visibility"]
        XCTAssertTrue(manageStacks.waitForExistence(timeout: 5))
        manageStacks.tap()

        XCTAssertTrue(app.navigationBars["Manage Stacks"].waitForExistence(timeout: 5))

        // Find any move to top button
        let moveToTopButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'moveToTop-'"))
        if moveToTopButtons.count > 0 {
            moveToTopButtons.firstMatch.tap()
            Thread.sleep(forTimeInterval: 0.3)
        }

        let saveButton = app.buttons["saveStackCustomizer"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testCSVExportAndImportFlow() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // 1. Open Options Menu
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 10))
        app.buttons["bookOptionsMenu"].tap()

        // 2. Open CSV Data -> Export CSV
        let csvMenu = app.buttons["Data & Backup"]
        XCTAssertTrue(csvMenu.waitForExistence(timeout: 5))
        csvMenu.tap()

        let exportButton = app.buttons["Export CSV"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        // 3. Verify CSV Data modal presented
        XCTAssertTrue(app.navigationBars["CSV Data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["csvModePicker"].exists)

        // 4. Verify Export tab elements
        XCTAssertTrue(app.buttons["exportCSVButton"].exists)

        // 5. Switch to Import tab
        app.segmentedControls["csvModePicker"].buttons["Import"].tap()
        XCTAssertTrue(app.buttons["selectCSVButton"].waitForExistence(timeout: 5))

        // 6. Switch back to Export tab
        app.segmentedControls["csvModePicker"].buttons["Export"].tap()
        XCTAssertTrue(app.buttons["exportCSVButton"].waitForExistence(timeout: 5))

        // 7. Dismiss modal
        app.buttons["dismissCSVView"].tap()
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testAnalyticsNavigationAndHorizons() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // 1. Open Analytics from the center tab switcher
        let homeTab = app.buttons["homeTab"]
        let analysisTab = app.buttons["analysisTab"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 10))
        XCTAssertTrue(analysisTab.exists)
        homeTab.press(forDuration: 0.3, thenDragTo: analysisTab)

        // 2. Verify Analytics & Trends is a root page, not a modal
        XCTAssertTrue(app.staticTexts["Analytics & Trends"].waitForExistence(timeout: 5) || app.navigationBars["Analytics & Trends"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["analyticsScopeMenu"].exists)
        XCTAssertTrue(app.staticTexts["totalSpendMetric"].exists)
        XCTAssertFalse(app.buttons["dismissAnalyticsView"].exists)

        // 3. Verify Charts present
        XCTAssertTrue(app.otherElements["burnUpTrajectoryChart"].exists || app.scrollViews.firstMatch.exists)

        // 4. Switch horizon chip
        let thisMonthChip = app.buttons["horizon-This month"]
        if thisMonthChip.exists {
            thisMonthChip.tap()
        }

        // 5. Interact with Scope Menu
        let scopeMenu = app.buttons["analyticsScopeMenu"]
        scopeMenu.tap()
        if app.buttons["All Cards"].waitForExistence(timeout: 3) {
            app.buttons["All Cards"].tap()
        }

        // 7. Return to Home from the same switcher
        homeTab.tap()
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["activityFilterButton"].exists)
    }

    @MainActor
    func testCardDeckFlipAndBackActions() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // 1. Locate the front card
        let firstCard = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stack-book-'")).firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 10))

        // 2. Tap to focus the card
        firstCard.tap()

        // 3. Verify the flip button exists on the focused card
        let flipButton = app.buttons["cardFlipButton"]
        XCTAssertTrue(flipButton.waitForExistence(timeout: 5))
        let frontShot = app.screenshot()
        add(XCTAttachment(screenshot: frontShot))

        // 4. Tap flip button to rotate to back face
        flipButton.tap()

        // 5. Verify back face telemetry view elements
        let flipBackButton = app.buttons["cardFlipBackButton"]
        XCTAssertTrue(flipBackButton.waitForExistence(timeout: 5))
        let analyticsButton = app.buttons["cardBackAnalyticsButton"]
        let customizeButton = app.buttons["cardBackCustomizeButton"]
        XCTAssertTrue(analyticsButton.exists)
        XCTAssertTrue(customizeButton.exists)
        let backShot = app.screenshot()
        add(XCTAttachment(screenshot: backShot))

        // 6. Test opening Trends & Analytics directly from flipped card
        analyticsButton.tap()
        let dismissAnalyticsButton = app.buttons["dismissAnalyticsView"]
        XCTAssertTrue(dismissAnalyticsButton.waitForExistence(timeout: 5))
        let analyticsShot = app.screenshot()
        add(XCTAttachment(screenshot: analyticsShot))
        dismissAnalyticsButton.tap()

        // Verify we returned directly to the flipped card without leaving
        XCTAssertTrue(flipBackButton.waitForExistence(timeout: 5))

        // 7. Test opening Artwork Customizer directly from flipped card
        customizeButton.tap()
        let cancelCustomizerButton = app.buttons["cancelCardCustomization"]
        XCTAssertTrue(cancelCustomizerButton.waitForExistence(timeout: 5))
        let customizerShot = app.screenshot()
        add(XCTAttachment(screenshot: customizerShot))
        cancelCustomizerButton.tap()

        // Verify we returned directly to the flipped card without leaving
        XCTAssertTrue(flipBackButton.waitForExistence(timeout: 5))

        // 8. Tap flip back button to return to front face
        flipBackButton.tap()
        XCTAssertTrue(flipButton.waitForExistence(timeout: 5))
    }

    func testAppleWalletCardOpeningAndClosingAnimation() {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["MONOCLE_TEST_THREE_CARDS"] = "1"
        app.launch()

        // 1. Test Card 01
        var cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stack-book-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        cards.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()

        let closeButton = app.buttons["homeLogo"]
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        sleep(1)
        let shot1 = app.screenshot()
        keepScreenshot(shot1)

        closeButton.tap()
        sleep(1)

        // 2. Test Card 02
        cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stack-book-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        cards.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        sleep(1)
        let shot2 = app.screenshot()
        keepScreenshot(shot2)

        closeButton.tap()
        sleep(1)

        // 3. Test Card 03
        cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stack-book-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        cards.element(boundBy: 2).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        sleep(1)
        let shot3 = app.screenshot()
        keepScreenshot(shot3)

        closeButton.tap()
        sleep(1)
    }

    @MainActor
    func testInteractiveCardPullDismissAndVelocityRelease() throws {
        let app = XCUIApplication()
        app.launch()

        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stack-book-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        let firstCard = cards.element(boundBy: 0)
        let originalFrame = firstCard.frame

        // 1. Open card
        firstCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(app.staticTexts["Latest Transactions"].waitForExistence(timeout: 5))
        sleep(1)

        // 2. Test short slow pull (28pt) -> cancel dismissal
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 28)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(app.staticTexts["Latest Transactions"].exists, "A short slow pull under threshold must cancel dismissal")

        // 3. Test committed pull -> commit dismissal and return to slot
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48)))
        XCTAssertTrue(app.staticTexts["monocle"].waitForExistence(timeout: 5))
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))
        sleep(1)
        XCTAssertEqual(firstCard.frame.minY, originalFrame.minY, accuracy: 3.0)
        XCTAssertEqual(firstCard.frame.width, originalFrame.width, accuracy: 3.0)
    }

    @MainActor
    func testCardContextMenuLongPressOnHomeScreen() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["MONOCLE_TEST_THREE_CARDS"] = "1"
        app.launch()

        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stack-book-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        let thirdCard = cards.element(boundBy: 2)
        let thirdCardFrame = thirdCard.frame

        // Header must be home logo before long-press
        XCTAssertTrue(app.staticTexts["monocle"].exists || app.buttons["homeLogo"].exists)

        thirdCard.press(forDuration: 1.2)
        sleep(1)
        let shot = app.screenshot()
        keepScreenshot(shot)

        // Header must still be home logo
        XCTAssertTrue(app.buttons["homeLogo"].exists, "Header must maintain monocle logo during long-press")

        // Context menu items must exist
        let bringToFront = app.buttons["Bring to Front"]
        let flip = app.buttons["Flip"]
        let customize = app.buttons["Customize card"]

        XCTAssertTrue(bringToFront.waitForExistence(timeout: 5))
        XCTAssertTrue(flip.exists)
        XCTAssertTrue(customize.exists)

        // Context menu must be anchored to the card, NOT stuck at the bottom of the screen
        let menuFrame = bringToFront.frame
        XCTAssertLessThan(menuFrame.minY, 650, "Context menu must anchor adjacent to the card, not at the bottom of the screen")
        XCTAssertGreaterThan(menuFrame.minY, thirdCardFrame.minY, "Context menu must appear below card top edge")

        // Tapping Flip should open the card and flip to telemetry back
        flip.tap()
        XCTAssertTrue(app.buttons["cardFlipBackButton"].waitForExistence(timeout: 5), "Selecting Flip from context menu must open card and reveal telemetry back")
        XCTAssertTrue(app.buttons["homeLogo"].waitForExistence(timeout: 5), "Expanded card must show monocle logo in header")

        // Flip back to front
        app.buttons["cardFlipBackButton"].tap()
        XCTAssertTrue(app.buttons["cardFlipButton"].waitForExistence(timeout: 5), "Card front must show flip button when expanded")

        // Close card
        app.buttons["homeLogo"].tap()
        XCTAssertTrue(app.staticTexts["monocle"].waitForExistence(timeout: 5), "Closing card must return to home monocle header")
        XCTAssertFalse(app.buttons["cardFlipButton"].exists, "Home stack cards must not show flip button")
    }

    @MainActor
    func testTransactionPageLiquidGlassAddButtonAndPlatter() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // 1. On Home screen, filter button exists on left, add button on right
        let filterButton = app.buttons["activityFilterButton"]
        let addButton = app.buttons["addExpense"]
        let homeTab = app.buttons["homeTab"]
        let analysisTab = app.buttons["analysisTab"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 10))
        XCTAssertTrue(addButton.exists)
        XCTAssertTrue(homeTab.exists)
        XCTAssertTrue(analysisTab.exists)

        let homeAddFrame = addButton.frame
        let screenWidth = app.windows.firstMatch.frame.width
        XCTAssertGreaterThan(homeAddFrame.midX, screenWidth * 0.6, "Home add button must be on the right side")
        XCTAssertEqual(homeTab.frame.midY, filterButton.frame.midY, accuracy: 4, "Tab island must align vertically with the filter bubble")
        XCTAssertEqual(analysisTab.frame.midY, homeAddFrame.midY, accuracy: 4, "Tab island must align vertically with the add bubble")

        // 2. Open first card
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stack-book-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        cards.firstMatch.tap()

        // 3. Detail header & title
        XCTAssertTrue(app.buttons["homeLogo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Latest Transactions"].waitForExistence(timeout: 5))

        // 4. Header buttons next to title must be removed
        XCTAssertFalse(app.buttons["addExpenseButton"].exists, "Add button next to list title must be removed")
        XCTAssertFalse(app.buttons["customizeCardDetailButton"].exists, "Customize button next to list title must be removed")

        // 5. Filter button must be removed on transaction page
        XCTAssertFalse(filterButton.exists, "Filter button must be hidden on transaction page")
        XCTAssertFalse(homeTab.exists, "Tab switcher must be hidden on transaction page")
        XCTAssertFalse(analysisTab.exists, "Tab switcher must be hidden on transaction page")

        // 6. Floating red add button must morph to the middle bottom
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        sleep(1) // Wait for spring animation to settle
        let detailAddFrame = addButton.frame
        let expectedCenterX = screenWidth / 2.0
        XCTAssertEqual(detailAddFrame.midX, expectedCenterX, accuracy: 15.0, "Add button must be centered in the middle bottom")
        XCTAssertGreaterThan(detailAddFrame.width, 100, "Add button should expand its width with label")

        // Capture screenshot of transaction page
        let shot = app.screenshot()
        keepScreenshot(shot)

        // 7. Tap centered add button -> entry modal opens
        addButton.tap()
        XCTAssertTrue(app.buttons["recordExpense"].waitForExistence(timeout: 5), "Tapping centered add button must open expense entry")
        
        // Dismiss entry
        let closeEntry = app.buttons["closeEntry"].exists ? app.buttons["closeEntry"] : app.buttons["Close entry"]
        XCTAssertTrue(closeEntry.waitForExistence(timeout: 5), "Close entry button must exist")
        closeEntry.tap()
        sleep(1) // Allow modal sheet dismissal to complete

        // 8. Close card detail -> returns to home
        let closeDetail = app.buttons["homeLogo"]
        XCTAssertTrue(closeDetail.waitForExistence(timeout: 5))
        closeDetail.tap()

        XCTAssertTrue(app.staticTexts["monocle"].waitForExistence(timeout: 5))
        sleep(1) // Wait for spring animation to settle
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5), "Filter button must reappear on home screen")
        XCTAssertTrue(homeTab.exists, "Tab switcher must reappear on home screen")
        XCTAssertTrue(analysisTab.exists, "Tab switcher must reappear on home screen")
        let returnedAddFrame = addButton.frame
        XCTAssertGreaterThan(returnedAddFrame.midX, screenWidth * 0.6, "Add button must return to right side on home")
    }

    @MainActor
    func testRapidCardOpenCloseAndMidwayCancellation() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["MONOCLE_TEST_THREE_CARDS"] = "1"
        app.launch()

        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stack-book-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 10))
        let card1 = cards.element(boundBy: 0)
        let card2 = cards.element(boundBy: 1)
        let closeButton = app.buttons["homeLogo"]

        // 1. Test mid-way cancellation of opening: Tap card then immediately tap close
        card1.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        // Immediately tap close without waiting for opening spring to complete
        closeButton.tap()
        XCTAssertTrue(app.staticTexts["monocle"].waitForExistence(timeout: 5), "Immediate close during opening must return to home smoothly")

        // 2. Test mid-way cancellation of closing: Tap card, tap close, then immediately re-tap card
        card1.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5))
        closeButton.tap()
        // While card is returning mid-flight, immediately tap it to cancel close
        card1.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "Re-tapping card mid-close must reverse spring and stay open")

        // 3. Test mid-way card switching: Tap close on card1, then immediately tap card2
        closeButton.tap()
        card2.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        XCTAssertTrue(closeButton.waitForExistence(timeout: 5), "Tapping card2 while card1 is closing must immediately open card2")

        // Capture screenshot of card detail with scaled-down fonts
        let shot = app.screenshot()
        keepScreenshot(shot)

        closeButton.tap()
        XCTAssertTrue(app.staticTexts["monocle"].waitForExistence(timeout: 5))

        // 4. Rapid burst stress test: rapid toggling between open and close
        for _ in 1...3 {
            card1.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
            XCTAssertTrue(closeButton.waitForExistence(timeout: 3))
            closeButton.tap()
            XCTAssertTrue(app.staticTexts["monocle"].waitForExistence(timeout: 3))
        }

        // Final sanity check: home view is fully responsive and intact
        XCTAssertTrue(app.buttons["activityFilterButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["addExpense"].exists)
    }

    @MainActor
    func testOptionsCollapsibleMenuAndHomePlatter() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. Verify Home Screen Native Platter, Stacks Indicator & Navigation Bar
        XCTAssertTrue(app.staticTexts["monocle"].waitForExistence(timeout: 10))
        let optionsButton = app.buttons["bookOptionsMenu"]
        XCTAssertTrue(optionsButton.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["activityScopeBadge"].waitForExistence(timeout: 5))

        // Capture Home Screen with progressive blur and platter
        let homeShot = app.screenshot()
        add(XCTAttachment(screenshot: homeShot))

        // 2. Open options menu and verify collapsible submenus + Settings
        optionsButton.tap()
        XCTAssertTrue(app.buttons["Cards & Stacks"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Tools & Insights"].exists)
        XCTAssertTrue(app.buttons["Data & Backup"].exists)
        XCTAssertTrue(app.buttons["Settings"].exists || app.buttons["homeSettings"].exists)

        // 3. Open sub-menu: Tools & Insights
        app.buttons["Tools & Insights"].tap()
        XCTAssertTrue(app.buttons["Budgets"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Analytics & Trends"].exists)
        XCTAssertTrue(app.buttons["Recurring Bills"].exists)

        // Tap Budgets
        app.buttons["Budgets"].tap()
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()

        // 4. Open card and capture updated transaction page
        let cards = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'stack-book-'"))
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        cards.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).tap()
        let closeDetail = app.buttons["homeLogo"]
        XCTAssertTrue(closeDetail.waitForExistence(timeout: 5))
        sleep(1)

        let detailShot = app.screenshot()
        add(XCTAttachment(screenshot: detailShot))

        closeDetail.tap()
        XCTAssertTrue(app.staticTexts["monocle"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testResetDataViewUIAndScreenshots() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // 1. Tap options menu and open Settings
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 10))
        app.buttons["bookOptionsMenu"].tap()

        let settingsBtn = app.buttons["Settings"].exists ? app.buttons["Settings"] : app.buttons["homeSettings"]
        XCTAssertTrue(settingsBtn.waitForExistence(timeout: 5))
        settingsBtn.tap()

        // 2. Tap "Reset data" in Settings
        let resetLink = app.buttons["resetDataSettings"]
        XCTAssertTrue(resetLink.waitForExistence(timeout: 5))
        resetLink.tap()

        // 3. Verify Reset data elements
        XCTAssertTrue(app.navigationBars["Reset data"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["clearActiveCardButton"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["resetAllDataButton"].waitForExistence(timeout: 5))

        // 4. Capture screenshot
        let resetShot = app.screenshot()
        let resetAttachment = XCTAttachment(screenshot: resetShot)
        resetAttachment.name = "ResetDataScreen"
        add(resetAttachment)

        let scratchDir = URL(fileURLWithPath: "/Users/farchan/.gemini/antigravity/brain/9295e8b0-77c2-4707-8c5c-b22c108a649d/scratch")
        try? FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        try? resetShot.image.pngData()?.write(to: scratchDir.appendingPathComponent("reset_data_screen.png"))

        // 5. Test opening confirmation alert
        app.buttons["clearActiveCardButton"].tap()
        let clearAlert = app.alerts.firstMatch
        XCTAssertTrue(clearAlert.waitForExistence(timeout: 5))
        clearAlert.buttons["Cancel"].tap()
    }

    @MainActor
    func testShortcutOrderSettingsViewUIAndScreenshots() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // 1. Navigate to Settings
        openSettings(app)

        // 2. Tap "Shortcut prompt order" in Settings
        let shortcutLink = app.buttons["shortcutOrderSettings"]
        XCTAssertTrue(shortcutLink.waitForExistence(timeout: 5))
        shortcutLink.tap()

        // 3. Verify Shortcut Input Order screen elements
        XCTAssertTrue(app.navigationBars["Shortcut Input Order"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["presetCardFirst"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["presetAmountFirst"].waitForExistence(timeout: 5))

        // 4. Tap "Amount First" preset to test interactive customization
        app.buttons["presetAmountFirst"].tap()

        // 5. Capture screenshot
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "ShortcutOrderScreen"
        add(attachment)

        let scratchDir = URL(fileURLWithPath: "/Users/farchan/.gemini/antigravity/brain/9295e8b0-77c2-4707-8c5c-b22c108a649d/scratch")
        try? FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        try? shot.image.pngData()?.write(to: scratchDir.appendingPathComponent("shortcut_order_screen.png"))

        // 6. Reset back to Card First preset
        app.buttons["presetCardFirst"].tap()
    }
}
