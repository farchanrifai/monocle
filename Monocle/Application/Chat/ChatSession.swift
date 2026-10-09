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
