import XCTest
@testable import Anka

@MainActor
final class BackendSessionTests: XCTestCase {
    func testQueuedUpdateAndEndKeepTheirOriginalActivityDuringReplacement() async {
        let client = FakeSessionActivities()
        let manager = SpendingSessionManager(activityClient: client)
        manager.startSession(name: "A", cardName: "Card")
        manager.recordExpense(amount: 100, note: nil, categorySymbol: nil)
        manager.startSession(name: "B", cardName: "Card")
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.handles.count, 2)
        XCTAssertEqual(client.handles[0].updates.map(\.currentSpent), [100])
        XCTAssertEqual(client.handles[0].ended.count, 1)
        XCTAssertTrue(client.handles[1].updates.isEmpty)
        XCTAssertTrue(client.handles[1].ended.isEmpty)
        XCTAssertTrue(manager.isSessionActive)
        XCTAssertEqual(manager.sessionName, "B")
        manager.recordExpense(amount: 200, note: nil, categorySymbol: nil)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(client.handles[1].updates.map(\.currentSpent), [200])
    }

    func testDeniedActivityRetainsAppSessionAndExposesFailure() {
        let client = FakeSessionActivities()
        client.isEnabled = false
        let manager = SpendingSessionManager(activityClient: client)
        manager.startSession(name: "A", cardName: "Card")
        XCTAssertTrue(manager.isSessionActive)
        XCTAssertNotNil(manager.activityError)
        XCTAssertTrue(client.handles.isEmpty)
    }
}

@MainActor
private final class FakeSessionActivities: SessionActivityClient {
    var isEnabled = true
    var handles: [FakeSessionActivity] = []
    var existing: [any SessionActivityHandle] { [] }
    func request(attributes: SpendingActivityAttributes, state: SpendingActivityAttributes.ContentState) throws -> any SessionActivityHandle {
        let handle = FakeSessionActivity(attributes: attributes, state: state)
        handles.append(handle)
        return handle
    }
}

@MainActor
private final class FakeSessionActivity: SessionActivityHandle {
    var attributes: SpendingActivityAttributes
    var state: SpendingActivityAttributes.ContentState
    var updates: [SpendingActivityAttributes.ContentState] = []
    var ended: [SpendingActivityAttributes.ContentState] = []
    init(attributes: SpendingActivityAttributes, state: SpendingActivityAttributes.ContentState) { self.attributes = attributes; self.state = state }
    func update(_ state: SpendingActivityAttributes.ContentState) async { updates.append(state); self.state = state }
    func end(_ state: SpendingActivityAttributes.ContentState) async { ended.append(state); await Task.yield() }
}
