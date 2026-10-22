import XCTest
@testable import Anka

/// Chat session, mentions and shared tool helpers: no model, no network.
@MainActor
final class ChatAgentTests: XCTestCase {
    private var model: AppModel!
    private var tempDir: URL!

    override func setUp() async throws {
        let repo = try ExpenseRepository(inMemory: true)
        _ = try repo.createCard(named: "Daily")
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        model = AppModel(expenses: try ExpenseService(store: repo), state: FileLocalStateStore(directory: tempDir))
        try model.reload()
    }

    override func tearDown() async throws { try? FileManager.default.removeItem(at: tempDir) }

    func testChatSessionRestoresTheTranscriptFromDisk() throws {
        let file = tempDir.appendingPathComponent("chat.json")
        let session = ChatSession(fileURL: file)
        session.scope = .allCards
        session.rows = [ChatRow(kind: .user("spent today?")), ChatRow(kind: .assistant("Rp28.000 so far."))]

        let restored = ChatSession(fileURL: file)
        XCTAssertEqual(restored.rows, session.rows)
        XCTAssertEqual(restored.scope, .allCards)

        restored.clear()
        let cleared = ChatSession(fileURL: file)
        XCTAssertTrue(cleared.rows.isEmpty)
        XCTAssertNil(cleared.scope)
    }

    func testChatSavedWithClaudeHistoryStillOpens() throws {
        let file = tempDir.appendingPathComponent("chat.json")
        let ui = try JSONSerialization.jsonObject(with: JSONEncoder().encode(["rows": [ChatRow(kind: .user("hi"))]]))
        let json: [String: Any] = ["version": 1, "fingerprint": "old", "ui": ui, "messages": [["role": "user", "content": "hi"]]]
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        XCTAssertEqual(ChatSession(fileURL: file).rows.count, 1, "the transcript survives; the Claude side is dropped")
    }

    func testFakeChatProposesThroughTheRealExecutor() async throws {
        let outputs = await FakeChatAgent(model: model).send("kopi 28rb", scope: .allCards, now: .now)
        guard case .proposal(let expense)? = outputs.last else { return XCTFail("expected a proposal, got \(outputs)") }
        XCTAssertEqual(expense.amount, 2_800_000)
        XCTAssertEqual(expense.note, "Kopi")
    }

    func testChatSaveWritesAndEditOpensUnsavedDraftInEntrySheet() async throws {
        let cardID = try XCTUnwrap(model.cards.first?.id)
        let category = try XCTUnwrap(try model.activeCategories(in: cardID).first)
        let expense = Expense(amount: 2_800_000, day: "2026-09-14", note: "Kopi",
                              splits: [.init(categoryID: category.id, amount: 2_800_000)], source: "chat", cardID: cardID)

        model.showChat = true
        model.openInEntry(expense)
        XCTAssertFalse(model.showChat, "Chat closes so the entry sheet can present")
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertTrue(model.showEntry)
        XCTAssertFalse(model.draft.editing, "A proposal is new, not an edit of a saved expense")
        XCTAssertEqual(try model.draft.expense().amount, 2_800_000)
        XCTAssertEqual(model.draft.civilDay, "2026-09-14")
        XCTAssertEqual(model.draft.source, "chat")
        XCTAssertFalse(model.expenses(for: cardID).contains { $0.id == expense.id }, "Opening the editor never saves")

        try model.saveFromChat(expense)
        XCTAssertTrue(model.expenses(for: cardID).contains { $0.id == expense.id && $0.source == "chat" })
    }

    func testUnreadableHistoryStartsEmpty() throws {
        let file = tempDir.appendingPathComponent("chat.json")
        try Data("not json".utf8).write(to: file)
        XCTAssertTrue(ChatSession(fileURL: file).rows.isEmpty)
    }

    func testMentionQueryOnlyForATrailingAtWord() {
        XCTAssertEqual(ChatMentionList.query(in: "@"), "")
        XCTAssertEqual(ChatMentionList.query(in: "how much on @Tok"), "Tok")
        XCTAssertEqual(ChatMentionList.query(in: "@Tokyo Tr"), "Tokyo Tr", "Card names can have spaces")
        XCTAssertNil(ChatMentionList.query(in: "mail me@home"), "An @ inside a word is not a mention")
        XCTAssertNil(ChatMentionList.query(in: "kopi 28rb"))
    }

    func testHashMentionsACategoryAndTheLaterTriggerWins() {
        XCTAssertEqual(ChatMentionList.mention(in: "#")?.trigger, "#")
        let word = ChatMentionList.mention(in: "how much on #Food & Dr")
        XCTAssertEqual(word?.trigger, "#"); XCTAssertEqual(word?.query, "Food & Dr")
        XCTAssertEqual(ChatMentionList.mention(in: "@Daily #Tra")?.query, "Tra", "the word being typed decides")
        XCTAssertEqual(ChatMentionList.mention(in: "#Food @Da")?.trigger, "@")
        XCTAssertNil(ChatMentionList.mention(in: "issue#12"), "A # inside a word is not a mention")
    }

    func testMentionsMarkKnownNamesOnly() {
        let names: [Character: [String]] = ["@": ["Everyday", "Tokyo Trip"], "#": ["Food & Drink", "Food"]]
        func marked(_ text: String) -> [String] {
            ChatMentionList.mentionRanges(text, names: names).map { String(text[$0]) }
        }
        XCTAssertEqual(marked("last month on #Food & Drink  @Everyday"), ["#Food & Drink", "@Everyday"])
        XCTAssertEqual(marked("#food is cheap, @tokyo trip too"), ["#food", "@tokyo trip"], "case doesn't matter")
        XCTAssertEqual(marked("@tokyo is nice"), [], "a partial name doesn't match")
        XCTAssertEqual(marked("mail me@Everyday and #Foodie"), [], "inside a word, or a longer word, is not a mention")
    }

    func testTypedAtMentionSetsTheScopeOnSend() throws {
        let session = ChatSession()
        XCTAssertEqual(ChatScopeMenuItems.applyMention(in: "and @all cards?", session: session, model: model), .allCards)
        XCTAssertEqual(session.scope, .allCards, "the header follows")
        let stack = try XCTUnwrap(model.stacks.first { $0.name == "Daily" })
        XCTAssertEqual(ChatScopeMenuItems.applyMention(in: "how much on @daily", session: session, model: model), .stack(id: stack.id, name: "Daily"))
        XCTAssertEqual(ChatScopeMenuItems.applyMention(in: "no mention here", session: session, model: model), .stack(id: stack.id, name: "Daily"), "no mention keeps the scope")
    }

    func testDraftColoursTheMentionBeingTyped() {
        let names: [Character: [String]] = ["@": ["Everyday"], "#": ["Food & Drink"]]
        let text = "on #Foo"
        XCTAssertEqual(ChatMentionList.mentionRanges(text, names: names, typing: true).map { String(text[$0]) }, ["#Foo"])
        XCTAssertTrue(ChatMentionList.mentionRanges(text, names: names).isEmpty)
    }

    func testTypingColoursOnlyTheNamePartOfTheTail() {
        let names: [Character: [String]] = ["@": ["Work", "Tokyo Trip"], "#": ["Food & Drink"]]
        func coloured(_ text: String) -> [String] {
            ChatMentionList.mentionRanges(text, names: names, typing: true).map { String(text[$0]) }
        }
        XCTAssertEqual(coloured("what's in @Work last month?"), ["@Work"])
        XCTAssertEqual(coloured("on @Tokyo Tr"), ["@Tokyo Tr"], "an unfinished multi-word name stays coloured")
        XCTAssertEqual(coloured("on @zzz"), ["@"], "no name starts that way: only the trigger")
        XCTAssertEqual(coloured("on #"), ["#"])
    }

    func testRangeLabelNamesTheDates() {
        XCTAssertTrue(ToolExecutor.rangeLabel("2026-10-01", "2026-10-31").hasPrefix("1–"))
        XCTAssertTrue(ToolExecutor.rangeLabel("2026-10-01", "2026-10-31").contains("2026"))
        XCTAssertTrue(ToolExecutor.rangeLabel("2026-09-01", "2026-10-12").contains(" – "), "a span across months names both ends")
    }

    func testBothMentionsCanShareAMessage() {
        XCTAssertEqual(ChatMentionList.mention(in: "#Food & Drink @Eve")?.trigger, "@")
        XCTAssertEqual(ChatMentionList.mention(in: "#Food & Drink @Everyday #Tra")?.query, "Tra")
    }

    func testFollowUpPeriodIsReadFromToolCalls() {
        func period(_ json: String) -> String? { ChatAgent.period(in: Data(json.utf8)) }
        XCTAssertEqual(period(#"{"period": "last_month", "group_by": "category"}"#), "last_month")
        XCTAssertEqual(period(#"{"period_a": "this_month", "period_b": "last_month"}"#), "last_month")
        XCTAssertNil(period(#"{"start": "2026-09-01", "end": "2026-09-30"}"#))
        XCTAssertNil(period(#"{"period": "someday"}"#), "unknown periods are ignored")
    }
}
