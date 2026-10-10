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
        XCTAssertEqual((body["tools"] as? [[String: Any]])?.count, 10)
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

    func testChatSaveWritesAndEditOpensUnsavedDraftInEntrySheet() async throws {
        let bookID = try XCTUnwrap(model.books.first?.id)
        let category = try XCTUnwrap(try model.activeCategories(in: bookID).first)
        let expense = Expense(amount: 2_800_000, day: "2026-09-14", note: "Kopi",
                              allocations: [.init(categoryID: category.id, amount: 2_800_000)], source: "chat", bookID: bookID)

        model.showChat = true
        model.openInEntry(expense)
        XCTAssertFalse(model.showChat, "Chat closes so the entry sheet can present")
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertTrue(model.showEntry)
        XCTAssertFalse(model.draft.editing, "A proposal is new, not an edit of a saved expense")
        XCTAssertEqual(try model.draft.expense().amount, 2_800_000)
        XCTAssertEqual(model.draft.civilDay, "2026-09-14")
        XCTAssertEqual(model.draft.source, "chat")
        XCTAssertFalse(model.expenses(for: bookID).contains { $0.id == expense.id }, "Opening the editor never saves")

        try model.saveFromChat(expense)
        XCTAssertTrue(model.expenses(for: bookID).contains { $0.id == expense.id && $0.source == "chat" })
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
        let next = ChatAgent(model: model, messages: restored.restoredMessages) { [unowned self] body in
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

    func testUnreadableHistoryStartsEmpty() throws {
        let file = tempDir.appendingPathComponent("chat.json")
        try Data("not json".utf8).write(to: file)
        XCTAssertTrue(ChatSession(fileURL: file).rows.isEmpty)
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

}
