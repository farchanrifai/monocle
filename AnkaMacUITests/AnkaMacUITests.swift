import XCTest

@MainActor final class AnkaMacUITests: XCTestCase {
    func testLaunchesMainWindow() {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"] // a crash-restore prompt would block launch
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["newExpense"].exists)
        app.typeKey("f", modifierFlags: .command)
        let search = app.searchFields["searchField"]
        XCTAssertTrue(search.waitForExistence(timeout: 2))
        app.typeText("coffee")
        XCTAssertEqual(search.value as? String, "coffee")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(search.waitForNonExistence(timeout: 2), "Esc clears and collapses the search")
        XCTAssertTrue(app.buttons["searchButton"].exists)
    }

    func testKeyboardCommandsOpenAndDismissNativeOverlays() {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"] // a crash-restore prompt would block launch
        app.launch()

        app.typeKey("k", modifierFlags: .command)
        let commandField = app.textFields["commandBar"]
        XCTAssertTrue(commandField.waitForExistence(timeout: 2))
        let commandBarY = commandField.frame.minY
        app.typeText("Bills")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Go to Bills")).firstMatch.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Go to Overview")).firstMatch.exists)
        XCTAssertEqual(commandField.frame.minY, commandBarY, accuracy: 1)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        XCTAssertTrue(app.textFields["commandBar"].waitForNonExistence(timeout: 2))

        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.textFields["expenseAmount"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.segmentedControls.count, 0)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])

        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(app.textFields["commandBar"].waitForExistence(timeout: 2))
        app.typeText("Quick Add")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        let quickRecord = app.dialogs["anka"]
        XCTAssertTrue(quickRecord.waitForExistence(timeout: 2))
        XCTAssertTrue(quickRecord.textFields["expenseAmount"].exists)
        XCTAssertEqual(quickRecord.segmentedControls.count, 0)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }

    func testActivitySelectionUpdatesInspectorAcrossRows() {
        let app = XCUIApplication()
        app.launchEnvironment["ANKA_TEST_RUN"] = UUID().uuidString
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"] // a crash-restore prompt would block launch
        app.launch()
        app.typeKey("2", modifierFlags: .command)
        let table = app.outlines["activityTable"]
        XCTAssertTrue(table.waitForExistence(timeout: 2))
        let rows = table.descendants(matching: .outlineRow)
        XCTAssertGreaterThanOrEqual(rows.count, 2)

        let first = rows.element(boundBy: 0)
        let second = rows.element(boundBy: 1)
        table.staticTexts["Morning coffee"].click()
        XCTAssertTrue(first.isSelected)
        table.staticTexts["Lunch at work"].click()
        XCTAssertTrue(second.isSelected)
        XCTAssertFalse(first.isSelected)
    }

    func testRepeatedTransactionSelectionAcrossMacViews() {
        let app = XCUIApplication()
        app.launchEnvironment["ANKA_TEST_RUN"] = UUID().uuidString
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"] // a crash-restore prompt would block launch
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        let notes = ["Morning coffee", "Lunch at work", "Ride home", "Weekly groceries", "Cinema night", "Coffee with friends"]
        for destination in ["Overview", "Activity", "Sample card"] {
            switch destination {
            case "Overview": app.staticTexts["Overview"].firstMatch.click()
            case "Activity": app.typeKey("2", modifierFlags: .command)
            default: app.staticTexts["Sample card"].firstMatch.click()
            }
            XCTAssertTrue(app.outlines["activityTable"].waitForExistence(timeout: 5))
            var clickDurations: [TimeInterval] = []
            for note in notes + notes.reversed() {
                let rowText = app.outlines["activityTable"].staticTexts[note]
                XCTAssertTrue(clickDurations.isEmpty ? rowText.waitForExistence(timeout: 3) : rowText.exists,
                              "Missing \(note) in \(destination)")
                let start = Date()
                rowText.click()
                clickDurations.append(Date().timeIntervalSince(start))
                let inspectorMatches = app.staticTexts.matching(identifier: note).count
                XCTAssertGreaterThanOrEqual(inspectorMatches, 2,
                                            "Inspector did not show \(note) in \(destination)")
            }
            let report = XCTAttachment(string: "\(destination): \(clickDurations.count) clicks; median \(clickDurations.sorted()[clickDurations.count / 2])s; max \(clickDurations.max() ?? 0)s")
            report.name = "Transaction stress timing - \(destination)"
            report.lifetime = .keepAlways
            add(report)
        }
    }

    func testInspectorFollowsSelectionDeleteUndoAndStaysHidden() {
        let app = XCUIApplication()
        app.launchEnvironment["ANKA_TEST_RUN"] = UUID().uuidString
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"] // a crash-restore prompt would block launch
        app.launch()
        app.typeKey("2", modifierFlags: .command)
        let table = app.outlines["activityTable"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))
        let coffee = { app.staticTexts.matching(identifier: "Morning coffee") }

        table.staticTexts["Morning coffee"].click()
        XCTAssertGreaterThanOrEqual(coffee().count, 2, "inspector shows selection")

        // Delete key deletes without a prompt; Edit ▸ Undo restores.
        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        XCTAssertTrue(table.staticTexts["Morning coffee"].waitForNonExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Nothing Selected"].exists)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(table.staticTexts["Morning coffee"].waitForExistence(timeout: 3))

        // Navigating away clears the selection.
        table.staticTexts["Lunch at work"].click()
        app.typeKey("1", modifierFlags: .command)
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(table.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Nothing Selected"].waitForExistence(timeout: 2))

        // A hidden inspector stays hidden when a row is selected.
        app.buttons["toggleInspector"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Nothing Selected"].waitForNonExistence(timeout: 2))
        table.staticTexts["Ride home"].click()
        XCTAssertEqual(app.staticTexts.matching(identifier: "Ride home").count, 1, "only the table row, no inspector")
        app.buttons["toggleInspector"].firstMatch.click()
        XCTAssertTrue(app.staticTexts.matching(identifier: "Ride home").element(boundBy: 1).waitForExistence(timeout: 3), "inspector slides in showing the selection")
    }

    func testInspectorToggleKeepsLayoutInsideNarrowWindow() {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["ANKA_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["ANKA_TEST_WINDOW_WIDTH"] = "1000" // narrowest allowed
        app.launch()
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        app.staticTexts["Sample card"].firstMatch.click() // card page: its fixed-width card used to break the split view
        sleep(1) // let the width hook apply
        let toggle = app.buttons["toggleInspector"].firstMatch
        for _ in 0..<2 {
            toggle.click(); sleep(1)
            let bounds = window.frame
            for element in [toggle, app.buttons["newExpense"].firstMatch] {
                XCTAssertTrue(element.exists && element.isHittable, "\(element) hidden at width \(bounds.width)")
                if element.exists { XCTAssertLessThanOrEqual(element.frame.maxX, bounds.maxX + 1, "toolbar spills past window \(bounds)") }
            }
            let empty = app.staticTexts["Nothing Selected"]
            if empty.exists { XCTAssertLessThanOrEqual(empty.frame.maxX, bounds.maxX + 1, "inspector spills past window \(bounds); text \(empty.frame)") }
            let sidebarItem = app.staticTexts["Overview"].firstMatch
            XCTAssertTrue(sidebarItem.exists && sidebarItem.frame.minX >= bounds.minX, "sidebar pushed out \(sidebarItem.frame) vs \(bounds)")
        }
    }

    func testSettingsUseSidebarPanes() {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-MacSettingsPane", "general"]
        app.launchEnvironment["ANKA_TEST_RUN"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        let main = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); main.name = "Main"; main.lifetime = .keepAlways; add(main)
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows["com_apple_SwiftUI_Settings_window"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        for pane in ["General", "Appearance", "Shortcuts", "Security", "AI Chat", "Data"] {
            let row = settings.outlines.staticTexts[pane]
            XCTAssertTrue(row.exists, "\(pane) missing from the sidebar")
            row.click()
            let titled = expectation(for: NSPredicate(format: "title == %@", pane), evaluatedWith: settings)
            wait(for: [titled], timeout: 2)
            let shot = XCTAttachment(screenshot: settings.screenshot())
            shot.name = pane; shot.lifetime = .keepAlways; add(shot)
        }
    }

    func testChatProposesAndSavesWithFakeChat() {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["ANKA_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["ANKA_FAKE_CHAT"] = "1"
        app.launch()
        app.typeKey("7", modifierFlags: .command)
        let input = app.textFields["chatInput"].exists ? app.textFields["chatInput"] : app.textViews["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 3))
        input.click()
        input.typeText("Kopi 28rb\r")
        let save = app.buttons["proposalSave"]
        XCTAssertTrue(save.waitForExistence(timeout: 5), "The proposal shows a confirm card")
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); shot.name = "Chat"; shot.lifetime = .keepAlways; add(shot)
        save.click()
        XCTAssertTrue(app.staticTexts["Saved"].waitForExistence(timeout: 3))
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["Kopi"].waitForExistence(timeout: 3), "Saved expense lands in Activity")
    }

    func testMultiSelectShowsSummaryAndDeletesWithOneUndo() {
        let app = XCUIApplication()
        app.launchEnvironment["ANKA_TEST_RUN"] = UUID().uuidString
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        app.typeKey("2", modifierFlags: .command)
        let table = app.outlines["activityTable"]
        XCTAssertTrue(table.waitForExistence(timeout: 5))

        table.staticTexts["Ride home"].click()
        XCUIElement.perform(withKeyModifiers: .command) { table.staticTexts["Morning coffee"].click() }
        XCTAssertTrue(app.staticTexts["2 Expenses"].waitForExistence(timeout: 3), "inspector summarises the selection")
        let shot = XCTAttachment(screenshot: app.windows.firstMatch.screenshot()); shot.name = "MultiSelect"; shot.lifetime = .keepAlways; add(shot)

        app.typeKey(XCUIKeyboardKey.delete.rawValue, modifierFlags: [])
        XCTAssertTrue(table.staticTexts["Ride home"].waitForNonExistence(timeout: 3))
        XCTAssertFalse(table.staticTexts["Morning coffee"].exists)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(table.staticTexts["Ride home"].waitForExistence(timeout: 3), "one undo restores both")
        XCTAssertTrue(table.staticTexts["Morning coffee"].exists)
    }
}
