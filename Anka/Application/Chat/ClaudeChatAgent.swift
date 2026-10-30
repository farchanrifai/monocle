import CryptoKit
import Foundation

/// Claude through Anka's chat server, for Pro users who allowed it (CHAT_SPEC §6). The tool loop: send the conversation,
/// run every requested tool on-device, return all results in one user message, repeat until Claude answers.
/// History is append-only (preserved thinking).
@MainActor
final class ClaudeChatAgent: ChatBackend {
    static let maxSteps = 6
    /// ponytail: start a fresh API conversation past this many messages instead of trimming (trimming edits history).
    static let maxMessages = 80

    private(set) var messages: [[String: Any]] = []
    private var notes: [String] = []
    /// The period of the last answer, so a follow-up that names none ("what categories?") keeps it.
    private var lastPeriod: String?
    private let model: AppModel
    private let transport: (Data) async throws -> Data
    /// Streams a request: calls back with each text delta and returns the assembled response. nil sends the whole request at once.
    typealias Stream = (Data, @escaping @MainActor @Sendable (String) -> Void) async throws -> Data
    private let stream: Stream?
    /// Live text of the step being answered; `nil` marks the start of a new step (the previous step's text is final).
    var onText: (@MainActor (String?) -> Void)?
    /// Why the last turn couldn't reach Claude (offline, busy, cap, no Pro), so ChatSession can answer on-device instead.
    private(set) var failure: ClaudeClient.ClientError?

    init(model: AppModel, messages: [[String: Any]] = [], transport: @escaping (Data) async throws -> Data, stream: Stream? = nil) {
        self.model = model
        self.messages = messages
        self.transport = transport
        self.stream = stream
    }

    /// Something the user did in the UI (saved or discarded a proposal) that Claude should know next turn.
    func note(_ text: String) { notes.append(text) }

    func reset() { messages = []; notes = []; lastPeriod = nil }

    func send(_ text: String, scope: AnalyticsFilterScope, now: Date = .now) async -> [ChatAgent.Output] {
        failure = nil
        return await turn(text, scope: scope, now: now, restarted: false)
    }

    /// Changes whenever the instructions or tools do; a saved conversation made under another one can't be continued
    /// (its thinking blocks are bound to the old tools), so ChatSession drops it on load.
    static let fingerprint: String = {
        let tools = (try? JSONSerialization.data(withJSONObject: ChatAgent.tools, options: [.sortedKeys])) ?? Data()
        return SHA256.hash(data: Data(ChatAgent.systemPrompt.utf8) + tools).map { String(format: "%02x", $0) }.joined()
    }()

    private func turn(_ text: String, scope: AnalyticsFilterScope, now: Date, restarted: Bool) async -> [ChatAgent.Output] {
        var outputs: [ChatAgent.Output] = []
        if messages.count > Self.maxMessages {
            reset()
            outputs.append(.notice("Started a fresh conversation to keep chat fast."))
        }
        let checkpoint = messages.count
        let executor = ToolExecutor(model: model, scope: scope, now: now)
        var content: [[String: Any]] = [["type": "text", "text": ChatAgent.context(executor, now: now, lastPeriod: lastPeriod)]]
        content += notes.map { ["type": "text", "text": "App note: \($0)"] }
        content.append(["type": "text", "text": text])
        messages.append(["role": "user", "content": content])

        for _ in 0..<Self.maxSteps {
            let reply: [String: Any]
            do {
                let data: Data
                if let stream, let onText {
                    onText(nil)
                    var body = requestBody()
                    body["stream"] = true
                    data = try await stream(try JSONSerialization.data(withJSONObject: body)) { delta in onText(delta) }
                } else {
                    data = try await transport(try JSONSerialization.data(withJSONObject: requestBody()))
                }
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      json["content"] is [[String: Any]] else { throw ClaudeClient.ClientError.invalidResponse }
                reply = json
            } catch {
                // History made under older tools or instructions no longer verifies; start over once instead of failing every message.
                if !restarted, error.localizedDescription.contains("`thinking` block") {
                    reset()
                    return [.notice("Started a fresh conversation: the assistant was updated.")] + (await turn(text, scope: scope, now: now, restarted: true))
                }
                failure = error as? ClaudeClient.ClientError
                return rollback(to: checkpoint, outputs, error: error.localizedDescription)
            }
            let blocks = reply["content"] as? [[String: Any]] ?? []
            messages.append(["role": "assistant", "content": blocks])
            for block in blocks where block["type"] as? String == "text" {
                if let text = block["text"] as? String, !text.isEmpty { outputs.append(.text(text)) }
            }
            switch reply["stop_reason"] as? String {
            case "tool_use":
                let results = blocks.filter { $0["type"] as? String == "tool_use" }.map { block -> [String: Any] in
                    let input = (try? JSONSerialization.data(withJSONObject: block["input"] ?? [String: Any]())) ?? Data()
                    let outcome = executor.run(block["name"] as? String ?? "", input: input)
                    if !outcome.isError, let period = ChatAgent.period(in: input) { lastPeriod = period }
                    if let proposal = outcome.proposal { outputs.append(.proposal(proposal)) }
                    if let change = outcome.change { outputs.append(.change(change)) }
                    if let bill = outcome.bill { outputs.append(.bill(bill)) }
                    if let chart = outcome.chart { outputs.append(.chart(chart)) }
                    return ["type": "tool_result", "tool_use_id": block["id"] as? String ?? "",
                            "content": outcome.json, "is_error": outcome.isError]
                }
                messages.append(["role": "user", "content": results])
            case "refusal":
                return rollback(to: checkpoint, outputs, error: "I can't help with that one.")
            case "max_tokens":
                return rollback(to: checkpoint, outputs, error: "That answer ran too long. Try a narrower question.")
            default:
                notes = []
                return outputs
            }
        }
        return rollback(to: checkpoint, outputs, error: "That took too many steps. Try a simpler question.")
    }

    /// Drop this turn so the next request starts from a valid, unedited prefix (no dangling tool_use).
    private func rollback(to checkpoint: Int, _ outputs: [ChatAgent.Output], error: String) -> [ChatAgent.Output] {
        messages.removeSubrange(checkpoint...)
        return outputs.filter { if case .text = $0 { false } else { true } } + [.error(error)]
    }

    private func requestBody() -> [String: Any] {
        ["model": ClaudeClient.model,
         "max_tokens": 16_000,
         "output_config": ["effort": "low"],
         // Cache the static prefix (tools + system) explicitly, and let automatic caching follow the
         // append-only conversation so each turn re-reads earlier turns at ~0.1x input price.
         "system": [["type": "text", "text": ChatAgent.systemPrompt, "cache_control": ["type": "ephemeral"]]],
         "cache_control": ["type": "ephemeral"],
         "tools": ChatAgent.tools,
         "messages": messages]
    }
}

/// The one-time choice to send chat to Claude (App Review 5.1.2(i)): nil until asked, then true or false, changeable in
/// Settings. iPhone only; the Mac stays on-device.
enum ClaudeConsent {
    static let key = "chatClaude"

    static var choice: Bool? {
        get { UserDefaults.standard.object(forKey: key) as? Bool }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func uses(isPro: Bool) -> Bool {
        #if os(iOS)
        isPro && choice == true
        #else
        false
        #endif
    }

    /// Pro and never asked: ChatView asks before the first message goes out.
    static func needsAsking(isPro: Bool) -> Bool {
        #if DEBUG
        if ChatSession.usesFakeChat { return false } // UI runs script the backend; nothing goes to Claude
        #endif
        #if os(iOS)
        return isPro && choice == nil
        #else
        return false
        #endif
    }
}
