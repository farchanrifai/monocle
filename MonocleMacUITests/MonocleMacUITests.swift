import XCTest

@MainActor final class MonocleMacUITests: XCTestCase {
    func testLaunchesMainWindow() {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"] // a crash-restore prompt would block launch
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["newExpense"].exists)
        XCTAssertTrue(app.textFields["searchField"].exists)
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
        app.typeText("Quick Record")
        app.typeKey(XCUIKeyboardKey.return.rawValue, modifierFlags: [])
        let quickRecord = app.dialogs["Quick Record"]
        XCTAssertTrue(quickRecord.waitForExistence(timeout: 2))
        XCTAssertTrue(quickRecord.textFields["expenseAmount"].exists)
        XCTAssertEqual(quickRecord.segmentedControls.count, 0)
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
    }

    func testActivitySelectionUpdatesInspectorAcrossRows() {
        let app = XCUIApplication()
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
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
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"] // a crash-restore prompt would block launch
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))

        let notes = ["Morning coffee", "Lunch at work", "Ride home", "Weekly groceries", "Cinema night", "Coffee with friends"]
        for destination in ["Overview", "Activity", "Sample book"] {
            switch destination {
            case "Overview": app.staticTexts["Overview"].firstMatch.click()
            case "Activity": app.typeKey("2", modifierFlags: .command)
            default: app.staticTexts["Sample book"].firstMatch.click()
            }
            if destination != "Overview" {
                XCTAssertTrue(app.outlines["activityTable"].waitForExistence(timeout: 5))
            }
            var clickDurations: [TimeInterval] = []
            for note in notes + notes.reversed() {
                let rowText = destination == "Overview"
                    ? app.buttons.matching(NSPredicate(format: "label CONTAINS %@", note)).firstMatch
                    : app.outlines["activityTable"].staticTexts[note]
                XCTAssertTrue(clickDurations.isEmpty ? rowText.waitForExistence(timeout: 3) : rowText.exists,
                              "Missing \(note) in \(destination)")
                let start = Date()
                rowText.click()
                clickDurations.append(Date().timeIntervalSince(start))
                let inspectorMatches = app.staticTexts.matching(identifier: note).count
                XCTAssertGreaterThanOrEqual(inspectorMatches, destination == "Overview" ? 1 : 2,
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
        app.launchEnvironment["MONOCLE_TEST_RUN"] = UUID().uuidString
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
        XCTAssertGreaterThanOrEqual(app.staticTexts.matching(identifier: "Ride home").count, 2)
    }
}
