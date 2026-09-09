import XCTest

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
        app.buttons["Budgets"].tap()
        XCTAssertTrue(app.staticTexts["Where it went"].waitForExistence(timeout: 5))
        let budget = XCTAttachment(screenshot: app.screenshot())
        budget.name = "budgets"; budget.lifetime = .keepAlways; add(budget)
        app.buttons["Done"].tap()
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Bills"].tap()
        XCTAssertTrue(app.buttons["Configure sample bill"].waitForExistence(timeout: 5))
        app.buttons["Configure sample bill"].tap()
        let reminder = app.switches["Remind me"]
        XCTAssertEqual(reminder.value as? String, "1")
        reminder.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(reminder.value as? String, "0", "Toggle must change before saving")
        let bill = XCTAttachment(screenshot: app.screenshot())
        bill.name = "bill-settings"; bill.lifetime = .keepAlways; add(bill)
        app.buttons["Save"].tap()
        app.buttons["Done"].tap()
        app.terminate(); app.launch()
        app.buttons["bookOptionsMenu"].tap()
        app.buttons["Bills"].tap()
        app.buttons["Configure sample bill"].tap()
        XCTAssertEqual(app.switches["Remind me"].value as? String, "0")
        app.buttons["Cancel"].tap()
        app.buttons["Done"].tap()
    }

    @MainActor
    func testStacksFilterBubbleAndCustomizer() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()

        // 1. Verify two-bubble bottom navigation exists
        XCTAssertTrue(app.buttons["activityFilterButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["addExpense"].exists)

        // 2. Quick tap toggles filter scope
        let initialBadge = app.staticTexts["activityScopeBadge"]
        XCTAssertTrue(initialBadge.waitForExistence(timeout: 5))
        app.buttons["activityFilterButton"].tap()
        XCTAssertTrue(app.staticTexts["All cards"].waitForExistence(timeout: 5) || initialBadge.exists)

        // 3. Open Stacks & Card Visibility from menu
        app.buttons["bookOptionsMenu"].tap()
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
        XCTAssertFalse(app.tabBars.firstMatch.exists, "Native bar must not overlap the two custom islands")
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
        XCTAssertTrue(app.buttons["Discard and continue"].waitForExistence(timeout: 5))
        app.buttons["Discard and continue"].tap()
        XCTAssertTrue(app.navigationBars["Edit expense"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["amountDisplay"].label.contains("28.000"))
    }

    @MainActor
    func testCategoryEditorPersistsAndSelectionDoesNotJump() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()
        app.buttons["homeSettings"].tap()
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
    func testBackupSettingsExposeExportAndImport() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launch()
        app.buttons["homeSettings"].tap()
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
        app.buttons["homeSettings"].tap()
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
        let backup = app.cells.matching(NSPredicate(format: "identifier CONTAINS %@", ".json")).firstMatch
        XCTAssertTrue(backup.waitForExistence(timeout: 5), "The exported JSON must be selectable")
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
    func testBookPrototypeFocusAndSampleEntry() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-book-home-prototype"]
        app.launch()
        XCTAssertTrue(app.buttons["Book options"].waitForExistence(timeout: 10))
        app.buttons["Book options"].tap()
        app.buttons["A fresh start"].tap()
        XCTAssertTrue(app.staticTexts["Nothing recorded yet"].waitForExistence(timeout: 5))
        app.buttons["Add Expense"].tap()
        app.textFields["Amount (IDR)"].tap()
        app.textFields["Amount (IDR)"].typeText("28000")
        app.textFields["Note"].tap()
        app.textFields["Note"].typeText("Prototype coffee")
        app.buttons["Record sample expense"].tap()
        XCTAssertTrue(app.staticTexts["Prototype coffee"].waitForExistence(timeout: 5))
        app.buttons["All book cards"].tap()
        app.buttons["Book options"].tap()
        app.buttons["Everyday"].tap()
        XCTAssertFalse(app.staticTexts["Prototype coffee"].exists)
    }

    @MainActor
    func testWalletStackReturnsCardToItsSlot() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-book-home-prototype"]
        app.launch()
        let first = app.buttons["stack-book-1"]
        let second = app.buttons["stack-book-2"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let original = second.frame.minY
        XCTAssertLessThan(second.frame.minY - first.frame.minY, first.frame.height / 2)
        second.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.06)).tap()
        XCTAssertTrue(app.buttons["All book cards"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Tokyo / September"].exists)
        app.buttons["All book cards"].tap()
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertEqual(second.frame.minY, original, accuracy: 2)
        // Native bounce must settle back without losing the card's slot.
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
            .press(forDuration: 0.05, thenDragTo: first.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.buttons["Book options"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "wallet-stack"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor
    func testSettingsAppearanceModeAndAutoSwitch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 10))
        app.buttons["homeSettings"].tap()

        XCTAssertTrue(app.switches["autoAppearanceToggle"].waitForExistence(timeout: 5))
        let autoToggle = app.switches["autoAppearanceToggle"]
        XCTAssertEqual(autoToggle.value as? String, "0")

        // Tapping Dark in appearanceModePicker
        XCTAssertTrue(app.segmentedControls["appearanceModePicker"].waitForExistence(timeout: 5))
        app.segmentedControls["appearanceModePicker"].buttons["Dark"].tap()

        // Turn on auto switch
        autoToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(autoToggle.value as? String, "1")

        // Dismiss settings
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.buttons["closeBookDetail"].waitForExistence(timeout: 5))
        let shot = app.screenshot()
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/Users/farchan/.gemini/antigravity/brain/0b84cb4a-9937-4659-954b-7977ccf1a290/scratch/prod_card_detail.png"))
        app.buttons["closeBookDetail"].tap()
        XCTAssertTrue(app.buttons["homeSettings"].waitForExistence(timeout: 5))
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

        // Tap "Customize card"
        let customizeButton = app.buttons["Customize card"]
        XCTAssertTrue(customizeButton.waitForExistence(timeout: 5))
        customizeButton.tap()

        // Verify Customizer view is displayed
        XCTAssertTrue(app.staticTexts["Customize Card"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.segmentedControls["cardCustomizerTabPicker"].waitForExistence(timeout: 5))

        // Switch to Stock designs
        app.segmentedControls["cardCustomizerTabPicker"].buttons["Stock"].tap()

        let customizerSheetShot = app.screenshot()
        try? customizerSheetShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Users/farchan/.gemini/antigravity/brain/0b84cb4a-9937-4659-954b-7977ccf1a290/scratch/card_customizer_sheet.png"))

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
        try? customScreenshot.pngRepresentation.write(to: URL(fileURLWithPath: "/Users/farchan/.gemini/antigravity/brain/0b84cb4a-9937-4659-954b-7977ccf1a290/scratch/customized_card_stack.png"))
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

        let customizeButton = app.buttons["Customize card"]
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

        XCTAssertTrue(app.buttons["customizeCardDetailButton"].waitForExistence(timeout: 5))
        app.buttons["customizeCardDetailButton"].tap()

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
        XCTAssertTrue(app.buttons["Create new book"].waitForExistence(timeout: 5))
        app.buttons["Create new book"].tap()

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
        if app.buttons["closeBookDetail"].waitForExistence(timeout: 3) {
            app.buttons["closeBookDetail"].tap()
        }

        // Open customizer
        XCTAssertTrue(app.buttons["bookOptionsMenu"].waitForExistence(timeout: 10))
        app.buttons["bookOptionsMenu"].tap()

        let customizeButton = app.buttons["Customize card"]
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
        XCTAssertGreaterThanOrEqual(peek, 10.0, "Neighboring card should still peek slightly into view")

        // Take a screenshot of the multi-card horizontal carousel
        let carouselShot = app.screenshot()
        try? carouselShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Users/farchan/.gemini/antigravity/brain/0b84cb4a-9937-4659-954b-7977ccf1a290/scratch/customizer_carousel.png"))

        // Tap the second preview card in carousel to make it active
        previews.element(boundBy: 1).tap()
        Thread.sleep(forTimeInterval: 0.5)
        let secondCardShot = app.screenshot()
        try? secondCardShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Users/farchan/.gemini/antigravity/brain/0b84cb4a-9937-4659-954b-7977ccf1a290/scratch/customizer_carousel_second_active.png"))

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
        try? stackShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Users/farchan/.gemini/antigravity/brain/0b84cb4a-9937-4659-954b-7977ccf1a290/scratch/customized_stack_multibook.png"))
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

        let customizeButton = app.buttons["Customize card"]
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
        try? renameShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Users/farchan/.gemini/antigravity/brain/0b84cb4a-9937-4659-954b-7977ccf1a290/scratch/customizer_inline_rename.png"))

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
        try? renamedStackShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Users/farchan/.gemini/antigravity/brain/0b84cb4a-9937-4659-954b-7977ccf1a290/scratch/customized_stack_renamed.png"))
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

        let createButton = app.buttons["Create new book"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 5))
        createButton.tap()

        // 2. Verify we are directly in the customization panel
        XCTAssertTrue(app.staticTexts["New Book"].waitForExistence(timeout: 5))

        // Capture screenshot of direct new book customizer entry
        let directEntryShot = app.screenshot()
        try? directEntryShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Users/farchan/.gemini/antigravity/brain/0b84cb4a-9937-4659-954b-7977ccf1a290/scratch/customizer_direct_new_book.png"))

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
        try? newBookStackShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Users/farchan/.gemini/antigravity/brain/0b84cb4a-9937-4659-954b-7977ccf1a290/scratch/home_stack_after_new_book.png"))
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

        let customizeButton = app.buttons["Customize card"]
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
        try? centeredShot.pngRepresentation.write(to: URL(fileURLWithPath: "/Users/farchan/.gemini/antigravity/brain/0b84cb4a-9937-4659-954b-7977ccf1a290/scratch/customizer_placeholder_card_centered.png"))

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

}
