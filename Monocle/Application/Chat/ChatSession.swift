import Foundation
import Observation

enum ProposalState: Equatable, Codable { case pending, saved, discarded, opened }

struct ChatRow: Identifiable, Equatable, Codable {
    enum Kind: Equatable, Codable {
        case user(String)
        case assistant(String)
        case proposal(Expense, ProposalState)
        case summary([CategorySpendPoint])
        case notice(String)
        case error(String)
    }
    var id = UUID()
    var kind: Kind

    var isUser: Bool { if case .user = kind { true } else { false } }
    var isBubble: Bool {
        switch kind { case .user, .assistant: true; default: false }
    }
}

/// The conversation, owned by AppModel so it outlives the chat screen and is wiped with the data it
/// describes. Saved to chat.json next to the ledger: what the user sees and what Claude remembers, together.
@MainActor @Observable
final class ChatSession {
    var rows: [ChatRow] = [] { didSet { save() } }
    var isTyping = false
    /// Chat-local scope: starts from the Home filter, never writes back to it (CHAT_SPEC §2).
    var scope: AnalyticsFilterScope? { didSet { save() } }
    @ObservationIgnored var agent: ChatAgent?
    /// Claude's side of a restored conversation, handed to the agent when it is first created.
    @ObservationIgnored private(set) var restoredMessages: [[String: Any]] = []
    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var loading = false

    private struct Snapshot: Codable { var rows: [ChatRow]; var scope: AnalyticsFilterScope? }

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ui = json["ui"], let uiData = try? JSONSerialization.data(withJSONObject: ui),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: uiData) else { return }
        // ponytail: an unreadable file starts an empty chat and is overwritten on the next change; chat is not ledger data.
        loading = true
        rows = snapshot.rows
        scope = snapshot.scope
        restoredMessages = json["messages"] as? [[String: Any]] ?? []
        loading = false
    }

    func clear() {
        agent?.reset()
        restoredMessages = []
        scope = nil
        rows = []
    }

    /// Called after every change to rows; the agent has already appended its messages by then.
    func save() {
        guard !loading, let fileURL else { return }
        do {
            let ui = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Snapshot(rows: rows, scope: scope)))
            let json: [String: Any] = ["version": 1, "ui": ui, "messages": agent?.messages ?? restoredMessages]
            try JSONSerialization.data(withJSONObject: json).write(to: fileURL, options: .atomic)
        } catch {
            // ponytail: history is a convenience copy; a failed write never interrupts the chat.
        }
    }
}

extension ChatSession {
    /// Sends one user message and appends Claude's reply rows. Returns the reply so the caller can announce it.
    @discardableResult
    func send(_ input: String, model: AppModel, scope: AnalyticsFilterScope) async -> [ChatAgent.Output] {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTyping else { return [] }
        rows.append(ChatRow(kind: .user(text)))
        isTyping = true
        // The key is read per request, so changing it in Settings keeps the conversation.
        let agent = agent ?? ChatAgent(model: model, messages: restoredMessages) { body in
            #if DEBUG
            if Self.usesFakeClaude { return try Self.fakeClaude(body) }
            #endif
            guard let key = APIKeyStore.read() else { throw ClaudeClient.ClientError.unauthorized }
            return try await ClaudeClient(apiKey: key).send(body)
        }
        self.agent = agent
        let outputs = await agent.send(text, scope: scope)
        isTyping = false
        rows += outputs.map { output in
            switch output {
            case .text(let text): ChatRow(kind: .assistant(text))
            case .proposal(let expense): ChatRow(kind: .proposal(expense, .pending))
            case .chart(let points): ChatRow(kind: .summary(points))
            case .notice(let text): ChatRow(kind: .notice(text))
            case .error(let text): ChatRow(kind: .error(text))
            }
        }
        return outputs
    }

    /// Save, discard or open a proposal card; only Save writes, and Claude hears what the user chose.
    func resolveProposal(_ id: UUID, _ expense: Expense, as state: ProposalState, model: AppModel) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let summary = "\(Money.format(expense.amount)) \(expense.note.isEmpty ? "" : "\"\(expense.note)\" ")on \(expense.day)"
        switch state {
        case .saved:
            do { try model.saveFromChat(expense) } catch {
                rows.append(ChatRow(kind: .error(error.localizedDescription)))
                return
            }
            agent?.note("The user saved the proposed expense \(summary).")
        case .opened:
            agent?.note("The user opened the proposed expense \(summary) in the editor; it may have been changed or saved there.")
            model.openInEntry(expense)
        case .discarded:
            agent?.note("The user discarded the proposed expense \(summary).")
        case .pending:
            break
        }
        rows[index].kind = .proposal(expense, state)
    }
}

#if DEBUG
extension ChatSession {
    /// UI-test hook: a scripted Claude that proposes "Kopi 28rb", then confirms. No network, no key.
    nonisolated static var usesFakeClaude: Bool { ProcessInfo.processInfo.environment["MONOCLE_FAKE_CLAUDE"] != nil }

    nonisolated static func fakeClaude(_ body: Data) throws -> Data {
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let last = (json?["messages"] as? [[String: Any]])?.last?["content"] as? [[String: Any]]
        let content: [[String: Any]]
        let stop: String
        if last?.first?["type"] as? String == "tool_result" {
            content = [["type": "text", "text": "Click **Save** to record it."]]; stop = "end_turn"
        } else {
            content = [["type": "text", "text": "Adding it."],
                       ["type": "tool_use", "id": "fake1", "name": "propose_expense",
                        "input": ["amount": 28000, "category": "Food & Drink", "note": "Kopi"]]]
            stop = "tool_use"
        }
        return try JSONSerialization.data(withJSONObject: ["role": "assistant", "content": content, "stop_reason": stop])
    }
}
#endif
