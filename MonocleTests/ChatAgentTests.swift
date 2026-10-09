import XCTest
@testable import Monocle

/// Agent loop against a scripted transport: no network, no API key.
@MainActor
final class ChatAgentTests: XCTestCase {
    private var model: AppModel!
    private var tempDir: URL!
    private var sent: [[String: Any]] = []

    override func setUp() async throws {
        let repo = try ExpenseRepository(inMemory: true)
        _ = try repo.createBook(named: "Daily")
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        model = AppModel(expenses: try ExpenseService(store: repo), state: FileLocalStateStore(directory: tempDir))
        try model.reload()
        sent = []
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: tempDir) }

    func testTextReplyIsReturnedAndRequestIsWellFormed() async throws {
        let agent = agent(replies: [reply([text("Hi!")], stop: "end_turn")])
        let outputs = await agent.send("halo", scope: .allCards)

        XCTAssertEqual(outputs, [.text("Hi!")])
        let body = try XCTUnwrap(sent.first)
        XCTAssertEqual(body["model"] as? String, "claude-haiku-5-5")
        XCTAssertEqual((body["tools"] as? [[String: Any]])?.count, 6)
        let user = try XCTUnwrap((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        XCTAssertTrue((user.first?["text"] as? String ?? "").hasPrefix("<app_context>"))
        XCTAssertEqual(user.last?["text"] as? String, "halo")
        XCTAssertEqual(agent.messages.count, 2)
    }

    func testToolUseRunsOnDeviceAndReturnsResultsInOneMessage() async throws {
        let agent = agent(replies: [
            reply([text("Adding it."),
                   toolUse("t1", "propose_expense", ["amount": 28000, "category": "Food & Drink", "note": "Kopi"]),
                   toolUse("t2", "list_cards", [:])], stop: "tool_use"),
            reply([text("Tap Save to record it.")], stop: "end_turn"),
        ])
        let outputs = await agent.send("kopi 28rb", scope: .allCards)

        guard case .proposal(let expense) = outputs.first(where: { if case .proposal = $0 { true } else { false } }) else {
            return XCTFail("Expected a proposal in \(outputs)")
        }
        XCTAssertEqual(expense.amount, 2_800_000)
        XCTAssertEqual(outputs.last, .text("Tap Save to record it."))

        let second = try XCTUnwrap(sent.last?["messages"] as? [[String: Any]])
        XCTAssertEqual(second.count, 3)
        let results = try XCTUnwrap(second.last?["content"] as? [[String: Any]])
        XCTAssertEqual(results.map { $0["tool_use_id"] as? String }, ["t1", "t2"], "All tool results go back in one user message")
        XCTAssertEqual(results.map { $0["is_error"] as? Bool }, [false, false])
    }

    func testFailureRollsBackSoTheNextTurnStartsClean() async throws {
        var calls = 0
        let agent = ChatAgent(model: model) { _ in
            calls += 1
            if calls == 1 { throw ClaudeClient.ClientError.offline }
            return try JSONSerialization.data(withJSONObject: Self.reply([Self.text("Back.")], stop: "end_turn"))
        }
        let failed = await agent.send("hi", scope: .allCards)
        XCTAssertEqual(failed, [.error(ClaudeClient.ClientError.offline.localizedDescription)])
        XCTAssertEqual(agent.messages.count, 0)

        let retried = await agent.send("hi again", scope: .allCards)
        XCTAssertEqual(retried, [.text("Back.")])
        XCTAssertEqual(agent.messages.count, 2)
    }

    func testStepCapAndRefusalNeverLeaveDanglingToolUse() async throws {
        let looping = reply([toolUse("t", "list_cards", [:])], stop: "tool_use")
        let capped = agent(replies: Array(repeating: looping, count: ChatAgent.maxSteps))
        let outputs = await capped.send("loop", scope: .allCards)
        XCTAssertEqual(sent.count, ChatAgent.maxSteps)
        if case .error = outputs.last {} else { XCTFail("Expected an error after the step cap") }
        XCTAssertEqual(capped.messages.count, 0)

        let refused = agent(replies: [reply([text("partial")], stop: "refusal")])
        let refusal = await refused.send("x", scope: .allCards)
        XCTAssertEqual(refusal, [.error("I can't help with that one.")])
        XCTAssertEqual(refused.messages.count, 0)
    }

    func testAppNotesReachTheNextTurnOnce() async throws {
        let agent = agent(replies: [reply([text("ok")], stop: "end_turn"), reply([text("ok")], stop: "end_turn")])
        agent.note("The user saved the proposed expense.")
        _ = await agent.send("first", scope: .allCards)
        _ = await agent.send("second", scope: .allCards)

        func texts(_ request: [String: Any]) -> [String] {
            let messages = request["messages"] as? [[String: Any]] ?? []
            return (messages.last?["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
        }
        XCTAssertTrue(texts(sent[0]).contains("App note: The user saved the proposed expense."))
        XCTAssertFalse(texts(sent[1]).contains { $0.hasPrefix("App note:") })
    }

    // MARK: - Helpers

    private func agent(replies: [[String: Any]]) -> ChatAgent {
        var queue = replies
        return ChatAgent(model: model) { [unowned self] body in
            sent.append(try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:])
            return try JSONSerialization.data(withJSONObject: queue.removeFirst())
        }
    }

    private func reply(_ content: [[String: Any]], stop: String) -> [String: Any] { Self.reply(content, stop: stop) }
    private static func reply(_ content: [[String: Any]], stop: String) -> [String: Any] { ["content": content, "stop_reason": stop] }
    private func text(_ value: String) -> [String: Any] { Self.text(value) }
    private static func text(_ value: String) -> [String: Any] { ["type": "text", "text": value] }
    private func toolUse(_ id: String, _ name: String, _ input: [String: Any]) -> [String: Any] {
        ["type": "tool_use", "id": id, "name": name, "input": input]
    }
}
