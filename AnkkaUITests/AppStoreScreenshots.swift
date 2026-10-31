import XCTest

/// Raw App Store screenshots on the marketing demo data. Skipped unless the runner sets ANKKA_SCREENSHOTS
/// (`TEST_RUNNER_ANKKA_SCREENSHOTS=1 xcodebuild test ... -only-testing:AnkkaUITests/AppStoreScreenshots`);
/// the shots are kept as attachments in the result bundle.
@MainActor
final class AppStoreScreenshots: XCTestCase {
    override func setUp() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ANKKA_SCREENSHOTS"] != nil, "Screenshots only on request")
    }

    private func launch(screen: String? = nil, fakeChat: Bool = false, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        if let screen { app.launchEnvironment["ANKKA_SCREEN"] = screen }
        if fakeChat { app.launchEnvironment["ANKKA_FAKE_CHAT"] = "1" }
        app.launchArguments = ["-AppleLocale", "en_US", "-AppleLanguages", "(en)", "-DemoData", "-ankkaPro", "YES"] + extra
        app.launch()
        return app
    }

    private func shoot(_ name: String, _ app: XCUIApplication, settle: TimeInterval = 1.5) {
        Thread.sleep(forTimeInterval: settle)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func test1Home() {
        let app = launch()
        XCTAssertTrue(app.buttons["addExpense"].waitForExistence(timeout: 15))
        shoot("01-home", app, settle: 2.5)
    }

    func test2Card() {
        let app = launch()
        XCTAssertTrue(app.buttons["addExpense"].waitForExistence(timeout: 15))
        app.open(URL(string: "ankka://card?id=61000000-0000-0000-0000-000000000001")!)
        shoot("02-card", app, settle: 2.5)
    }

    func test3Tokyo() {
        let app = launch()
        XCTAssertTrue(app.buttons["addExpense"].waitForExistence(timeout: 15))
        app.open(URL(string: "ankka://card?id=61000000-0000-0000-0000-000000000004")!)
        shoot("03-tokyo", app, settle: 2.5)
    }

    /// On a fresh Indonesian setup (rupiah) so "kopi 28rb" reads as Rp 28.000.
    func test4ChatAdd() {
        let app = XCUIApplication()
        app.launchEnvironment["ANKKA_TEST_RUN"] = UUID().uuidString
        app.launchEnvironment["ANKKA_SCREEN"] = "chat"
        app.launchEnvironment["ANKKA_FAKE_CHAT"] = "1"
        app.launchArguments = ["-AppleLocale", "id_ID", "-AppleLanguages", "(en)", "-ankkaPro", "YES"]
        app.launch()
        let input = app.textViews["chatInput"].exists ? app.textViews["chatInput"] : app.textFields["chatInput"]
        XCTAssertTrue(input.waitForExistence(timeout: 15))
        input.tap()
        input.typeText("kopi 28rb")
        app.buttons["chatSend"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 10))
        // Tapping the transcript puts the keyboard away so the proposal card has the room.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        shoot("04-chat-add", app, settle: 2)
    }

    func test5ChatAsk() {
        let app = launch(screen: "chat-demo")
        shoot("05-chat-ask", app, settle: 3)
    }

    func test6Budgets() {
        let app = launch(screen: "budgets")
        shoot("06-budgets", app, settle: 3)
    }

    func test7Analytics() {
        let app = launch(screen: "analytics")
        shoot("07-analytics", app, settle: 3)
    }

    func test8Entry() {
        let app = launch(screen: "entry")
        XCTAssertTrue(app.buttons["key-2"].waitForExistence(timeout: 15))
        for key in ["key-1", "key-2"] where app.buttons[key].exists { app.buttons[key].tap() }
        shoot("08-entry", app, settle: 1.5)
    }

    func test9Intro() {
        let app = launch(extra: ["-ankkaIntro", "YES"])
        shoot("09-intro", app, settle: 4)
    }
}
