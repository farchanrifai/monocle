import XCTest
@testable import Anka

/// Claude agent loop against a scripted transport: no network, no server.
@MainActor
final class ClaudeChatTests: XCTestCase {
    private var model: AppModel!
    private var tempDir: URL!
    private var sent: [[String: Any]] = []

    override func setUp() async throws {
        let repo = try ExpenseRepository(inMemory: true)
        _ = try repo.createCard(named: "Daily")
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
        XCTAssertEqual((body["tools"] as? [[String: Any]])?.count, ChatAgent.tools.count)
        XCTAssertNotNil(body["cache_control"], "Automatic caching follows the growing conversation")
        let system = try XCTUnwrap(body["system"] as? [[String: Any]])
        XCTAssertNotNil(system.last?["cache_control"], "Static tools + system prefix has its own cache point")
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
        let agent = ClaudeChatAgent(model: model) { _ in
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
        let capped = agent(replies: Array(repeating: looping, count: ClaudeChatAgent.maxSteps))
        let outputs = await capped.send("loop", scope: .allCards)
        XCTAssertEqual(sent.count, ClaudeChatAgent.maxSteps)
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

    func testChatSessionRestoresBothSidesOfTheConversationFromDisk() async throws {
        let file = tempDir.appendingPathComponent("chat.json")
        let session = ChatSession(fileURL: file)
        let agent = agent(replies: [reply([text("Rp28.000 so far.")], stop: "end_turn")])
        session.agent = agent
        session.scope = .allCards
        let outputs = await agent.send("spent today?", scope: .allCards)
        session.rows = [ChatRow(kind: .user("spent today?"))] + outputs.map { _ in ChatRow(kind: .assistant("Rp28.000 so far.")) }

        let restored = ChatSession(fileURL: file)
        XCTAssertEqual(restored.rows, session.rows)
        XCTAssertEqual(restored.scope, .allCards)
        XCTAssertEqual(restored.restoredMessages.count, 2, "Claude's history is restored with the transcript")

        // A restored agent continues the same append-only conversation.
        let next = ClaudeChatAgent(model: model, messages: restored.restoredMessages) { [unowned self] body in
            sent.append(try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:])
            return try JSONSerialization.data(withJSONObject: Self.reply([Self.text("ok")], stop: "end_turn"))
        }
        _ = await next.send("and yesterday?", scope: .allCards)
        XCTAssertEqual((sent.last?["messages"] as? [[String: Any]])?.count, 3)

        restored.clear()
        let cleared = ChatSession(fileURL: file)
        XCTAssertTrue(cleared.rows.isEmpty)
        XCTAssertTrue(cleared.restoredMessages.isEmpty)
        XCTAssertNil(cleared.scope)
    }

    // MARK: - Helpers

    private func agent(replies: [[String: Any]]) -> ClaudeChatAgent {
        var queue = replies
        return ClaudeChatAgent(model: model) { [unowned self] body in
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

    // MARK: - Streaming

    /// The events of one streamed message: thinking, a text block split in pieces, then a tool call whose input arrives as partial JSON.
    private static let toolTurnEvents: [[String: Any]] = [
        ["type": "message_start", "message": ["id": "msg_1", "role": "assistant", "content": [], "usage": ["input_tokens": 10]]],
        ["type": "content_block_start", "index": 0, "content_block": ["type": "thinking", "thinking": "", "signature": ""]],
        ["type": "content_block_delta", "index": 0, "delta": ["type": "thinking_delta", "thinking": "Hm."]],
        ["type": "content_block_delta", "index": 0, "delta": ["type": "signature_delta", "signature": "sig123"]],
        ["type": "content_block_stop", "index": 0],
        ["type": "content_block_start", "index": 1, "content_block": ["type": "text", "text": ""]],
        ["type": "content_block_delta", "index": 1, "delta": ["type": "text_delta", "text": "Let me "]],
        ["type": "content_block_delta", "index": 1, "delta": ["type": "text_delta", "text": "check."]],
        ["type": "content_block_stop", "index": 1],
        ["type": "content_block_start", "index": 2, "content_block": ["type": "tool_use", "id": "t1", "name": "list_cards", "input": [String: Any]()]],
        ["type": "content_block_delta", "index": 2, "delta": ["type": "input_json_delta", "partial_json": ""]],
        ["type": "content_block_stop", "index": 2],
        ["type": "message_delta", "delta": ["stop_reason": "tool_use"], "usage": ["output_tokens": 20]],
        ["type": "message_stop"],
    ]

    func testStreamAssemblerRebuildsTheNonStreamingMessage() throws {
        var assembler = StreamAssembler()
        var deltas: [String] = []
        for event in Self.toolTurnEvents { if let delta = assembler.add(event) { deltas.append(delta) } }
        XCTAssertEqual(deltas, ["Let me ", "check."])
        let message = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(assembler.message)) as? [String: Any])
        XCTAssertEqual(message["stop_reason"] as? String, "tool_use")
        let blocks = try XCTUnwrap(message["content"] as? [[String: Any]])
        XCTAssertEqual(blocks.map { $0["type"] as? String }, ["thinking", "text", "tool_use"])
        XCTAssertEqual(blocks[0]["thinking"] as? String, "Hm.")
        XCTAssertEqual(blocks[0]["signature"] as? String, "sig123", "thinking must round-trip with its signature")
        XCTAssertEqual(blocks[1]["text"] as? String, "Let me check.")
        XCTAssertEqual(blocks[2]["name"] as? String, "list_cards")
        XCTAssertNotNil(blocks[2]["input"] as? [String: Any], "an empty partial input is an empty object, not missing")
    }

    func testStreamAssemblerParsesPartialToolInput() throws {
        var assembler = StreamAssembler()
        for event: [String: Any] in [
            ["type": "message_start", "message": ["role": "assistant"]],
            ["type": "content_block_start", "index": 0, "content_block": ["type": "tool_use", "id": "t", "name": "get_summary", "input": [String: Any]()]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "input_json_delta", "partial_json": "{\"period\": \"last_"]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "input_json_delta", "partial_json": "month\"}"]],
            ["type": "content_block_stop", "index": 0],
            ["type": "message_stop"],
        ] { _ = assembler.add(event) }
        let message = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(assembler.message)) as? [String: Any])
        let input = try XCTUnwrap(((message["content"] as? [[String: Any]])?.first)?["input"] as? [String: Any])
        XCTAssertEqual(input["period"] as? String, "last_month")
    }

    func testAgentStreamsTextAndStillRunsTools() async throws {
        // Step 1 streams a preface and asks for a tool; step 2 streams the answer.
        var turns: [[[String: Any]]] = [
            Self.toolTurnEvents,
            [["type": "message_start", "message": ["role": "assistant"]],
             ["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]],
             ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": "You have "]],
             ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": "one card."]],
             ["type": "content_block_stop", "index": 0],
             ["type": "message_delta", "delta": ["stop_reason": "end_turn"]],
             ["type": "message_stop"]],
        ]
        let agent = ClaudeChatAgent(model: model, transport: { _ in XCTFail("should stream"); return Data() }, stream: { body, onText in
            var assembler = StreamAssembler()
            for event in turns.removeFirst() { if let delta = assembler.add(event) { await onText(delta) } }
            return try XCTUnwrap(assembler.message)
        })
        var live: [String?] = []
        agent.onText = { live.append($0) }
        let outputs = await agent.send("cards?", scope: .allCards)
        XCTAssertEqual(live, [nil, "Let me ", "check.", nil, "You have ", "one card."], "nil marks each new step")
        XCTAssertEqual(outputs, [.text("Let me check."), .text("You have one card.")])
        XCTAssertEqual(agent.messages.count, 4, "user, assistant (tool_use), tool_result, assistant")
    }

    func testStrictToolsStayUnderTheAPIOptionalParameterLimit() {
        func optionals(_ schema: [String: Any]) -> Int {
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            let required = Set(schema["required"] as? [String] ?? [])
            return properties.reduce(0) { sum, entry in
                let items = entry.value["items"] as? [String: Any]
                return sum + (required.contains(entry.key) ? 0 : 1) + (entry.value["type"] as? String == "object" ? optionals(entry.value) : 0)
                    + (items.map(optionals) ?? 0)
            }
        }
        let total = ChatAgent.tools.filter { $0["strict"] as? Bool == true }
            .reduce(0) { $0 + optionals($1["input_schema"] as? [String: Any] ?? [:]) }
        XCTAssertLessThanOrEqual(total, 24, "Anthropic rejects strict tool schemas with more than 24 optional parameters")
    }

    func testFailureIsReportedForTheOnDeviceFallback() async throws {
        let agent = ClaudeChatAgent(model: model) { _ in throw ClaudeClient.ClientError.limit("Monthly limit.") }
        let outputs = await agent.send("hi", scope: .allCards)
        XCTAssertEqual(outputs, [.error("Monthly limit.")])
        guard case .limit = agent.failure else { return XCTFail("ChatSession needs the failure to answer on-device") }
        let ok = self.agent(replies: [reply([text("ok")], stop: "end_turn")])
        _ = await ok.send("hi", scope: .allCards)
        XCTAssertNil(ok.failure)
    }

    func testClaudeOnlyForProWhoAllowedIt() {
        let saved = ClaudeConsent.choice
        defer { ClaudeConsent.choice = saved }
        ClaudeConsent.choice = nil
        XCTAssertTrue(ClaudeConsent.needsAsking(isPro: true))
        XCTAssertFalse(ClaudeConsent.needsAsking(isPro: false), "Free never sees the question")
        XCTAssertNil(ChatSession.unavailableReason(isPro: true), "Pro can chat: the question comes first")
        ClaudeConsent.choice = true
        XCTAssertTrue(ClaudeConsent.uses(isPro: true))
        XCTAssertFalse(ClaudeConsent.uses(isPro: false), "A lapsed subscription falls back to on-device")
        ClaudeConsent.choice = false
        XCTAssertFalse(ClaudeConsent.uses(isPro: true))
        if AppleChatAgent.unavailableReason != nil {
            XCTAssertTrue(ChatSession.unavailableReason(isPro: true)?.hasSuffix("Or turn on Chat with Claude in Settings.") == true)
            XCTAssertTrue(ChatSession.unavailableReason(isPro: false)?.hasSuffix("Anka Pro adds chat by Claude on any iPhone.") == true)
        }
    }
}
