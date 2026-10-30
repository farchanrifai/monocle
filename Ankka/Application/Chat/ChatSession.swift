import Foundation
import Observation
import SwiftUI

enum ProposalState: Equatable, Codable { case pending, saved, discarded, opened, undone }

/// The assistant's proposed edit (`updated`) or delete (`updated == nil`) of a saved expense.
struct ExpenseChange: Codable, Equatable {
    var original: Expense
    var updated: Expense?
}

/// A chart under a chat answer, built by ToolExecutor from AnalyticsReport: every number is app-computed.
struct ChatChart: Codable, Equatable {
    enum Style: String, Codable { case donut, bars, trend, comparison, budget, stats, pace, cumulative, ranking }
    struct Item: Codable, Equatable {
        var label: String
        /// Minor units. Comparison and cumulative: the later period. Budget: spent. Pace: spent so far.
        var value: Int64
        /// Comparison and cumulative: the earlier period. Budget: the limit. Pace: the budget line.
        var reference: Int64? = nil
        /// Ranking: the line under the label (day · category).
        var detail: String? = nil
        /// Pace and cumulative: a day still to come, where only the reference line draws.
        var isFuture: Bool? = nil
    }
    /// One tile of an overview: an app-formatted value and its label.
    struct Stat: Codable, Equatable { var label: String; var value: String }
    var style: Style
    var title: String
    var items: [Item]
    /// Comparison and cumulative: [earlier, later] period names.
    var series: [String] = []
    /// Stats only.
    var stats: [Stat]? = nil
    /// Trend: the daily average, drawn as a line across the bars.
    var average: Int64? = nil
    /// A one-line takeaway under the title, like "12% under budget pace".
    var caption: String? = nil

    /// Charts saved before ChatChart existed were category donuts.
    init(categories points: [CategorySpendPoint], title: String) {
        self.init(style: .donut, title: title, items: points.map { Item(label: $0.categoryName, value: $0.amount) })
    }

    init(style: Style, title: String, items: [Item], series: [String] = [], stats: [Stat]? = nil, average: Int64? = nil, caption: String? = nil) {
        self.style = style; self.title = title; self.items = items; self.series = series
        self.stats = stats; self.average = average; self.caption = caption
    }
}

struct ChatRow: Identifiable, Equatable, Codable {
    enum Kind: Equatable, Codable {
        case user(String)
        case assistant(String)
        case proposal(Expense, ProposalState)
        case change(ExpenseChange, ProposalState)
        case bill(Bill, ProposalState)
        /// Pre-ChatChart saved chats only; new charts use `.chart`.
        case summary([CategorySpendPoint])
        case chart(ChatChart)
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
/// describes. Saved to chat.json next to the ledger: what the user sees and what Claude remembers, together (the on-device
/// model's memory lives only in its session).
@MainActor @Observable
final class ChatSession {
    var rows: [ChatRow] = [] { didSet { save() } }
    var isTyping = false
    /// The user row currently morphing out of the composer (views only; never saved).
    var flightID: UUID?
    /// Identity of the thinking bubble; the reply's first text row reuses it so the bubble grows in place.
    var typingID = UUID()
    /// The reply as it streams in; shown in the thinking bubble until the finished rows replace it. Never saved.
    var streamingText: String?
    /// Reveals `streamingText` at a steady pace (see `StreamPacer`).
    let pacer = StreamPacer()
    /// Chat-local scope: starts from the Home filter, never writes back to it (CHAT_SPEC §2).
    var scope: AnalyticsFilterScope? { didSet { save() } }
    @ObservationIgnored var agent: (any ChatBackend)?
    /// Apple Intelligence answering a turn Claude couldn't (offline, busy, monthly cap).
    @ObservationIgnored private var fallback: AppleChatAgent?
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
        // Claude's history made under other instructions or tools can't be continued (bound thinking blocks); the rows stay.
        if json["fingerprint"] as? String == ClaudeChatAgent.fingerprint { restoredMessages = json["messages"] as? [[String: Any]] ?? [] }
        loading = false
    }

    func clear() {
        agent?.reset()
        fallback?.reset()
        restoredMessages = []
        scope = nil
        rows = []
    }

    /// Called after every change to rows; the agent has already appended its messages by then.
    func save() {
        guard !loading, let fileURL else { return }
        do {
            let ui = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Snapshot(rows: rows, scope: scope)))
            let json: [String: Any] = ["version": 1, "fingerprint": ClaudeChatAgent.fingerprint, "ui": ui,
                                       "messages": (agent as? ClaudeChatAgent)?.messages ?? restoredMessages]
            try JSONSerialization.data(withJSONObject: json).write(to: fileURL, options: .atomic)
        } catch {
            // ponytail: history is a convenience copy; a failed write never interrupts the chat.
        }
    }
}

extension ChatSession {
    /// Why chat can't run, or nil when it can: Claude for Pro (once allowed, or still to ask), else Apple Intelligence.
    /// DEBUG UI runs can swap in a scripted backend.
    static func unavailableReason(isPro: Bool) -> String? {
        #if DEBUG
        if usesFakeChat { return nil }
        #endif
        if ClaudeConsent.uses(isPro: isPro) || ClaudeConsent.needsAsking(isPro: isPro) { return nil }
        guard let reason = AppleChatAgent.unavailableReason else { return nil }
        #if os(iOS)
        if !isPro { return reason + " Ankka Pro adds chat by Claude on any iPhone." }
        return reason + " Or turn on Chat with Claude in Settings."
        #else
        return reason
        #endif
    }

    /// Sends Claude the newest Pro transaction for the server to check. DEBUG: the owner's free-team builds can't buy Pro,
    /// so one launch with `-ankkaOwnerKey <key>` stores the server's owner key instead.
    static func claudeCredentials(_ model: AppModel) async -> [String: String]? {
        #if DEBUG
        // ponytail: plain defaults, not the Keychain; debug builds on the owner's phone only.
        if let key = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["ankkaOwnerKey"] as? String {
            UserDefaults.standard.set(key, forKey: "ankkaOwnerKey")
        }
        if let key = UserDefaults.standard.string(forKey: "ankkaOwnerKey"), !key.isEmpty { return ["x-ankka-owner": key] }
        #endif
        return await model.pro?.receipt().map { ["x-ankka-receipt": $0] }
    }

    private func makeAgent(claude: Bool, model: AppModel) -> any ChatBackend {
        guard claude else { return AppleChatAgent(model: model) }
        let credentials = { [weak model] () async throws -> [String: String] in
            guard let model, let credentials = await Self.claudeCredentials(model) else {
                throw ClaudeClient.ClientError.notPro("Claude chat is part of Ankka Pro.")
            }
            return credentials
        }
        let agent = ClaudeChatAgent(model: model, messages: restoredMessages) { body in
            try await ClaudeClient(credentials: try await credentials()).send(body)
        } stream: { body, onText in
            try await ClaudeClient(credentials: try await credentials()).stream(body, onText: onText)
        }
        agent.onText = { [weak self] delta in
            guard let self else { return }
            streamingText = delta.map { (streamingText ?? "") + $0 }
            if let streamingText { pacer.set(streamingText) } else { pacer.reset() }
        }
        return agent
    }

    /// Sends one user message and appends the reply rows. Returns the reply so the caller can announce it.
    @discardableResult
    func send(_ input: String, model: AppModel, scope: AnalyticsFilterScope, appended: ChatRow? = nil) async -> [ChatAgent.Output] {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTyping else { return [] }
        // A view that already appended the row (inside an animation) passes it as `appended`.
        if appended == nil { rows.append(ChatRow(kind: .user(text))) }
        typingID = UUID()
        isTyping = true
        let claude = ClaudeConsent.uses(isPro: model.isPro)
        // Switching backend starts the other model fresh; Claude's history is kept for when it comes back.
        if claude != (agent is ClaudeChatAgent) {
            if let old = agent as? ClaudeChatAgent { restoredMessages = old.messages }
            agent = nil
        }
        let agent: any ChatBackend
        #if DEBUG
        agent = self.agent ?? (Self.usesFakeChat ? FakeChatAgent(model: model) : makeAgent(claude: claude, model: model))
        #else
        agent = self.agent ?? makeAgent(claude: claude, model: model)
        #endif
        streamingText = nil
        pacer.reset()
        self.agent = agent
        var outputs = Self.limitQuestions(await agent.send(text, scope: scope, now: .now), isPro: model.isPro)
        // Claude couldn't be reached and nothing was proposed yet: answer on this iPhone instead, when it can.
        if let failure = (agent as? ClaudeChatAgent)?.failure, outputs.count == 1, AppleChatAgent.unavailableReason == nil {
            streamingText = nil
            pacer.reset()
            let fallback = fallback ?? AppleChatAgent(model: model)
            self.fallback = fallback
            let why = if case .offline = failure { "You're offline" } else { failure.localizedDescription }
            outputs = [.notice("\(why). Answered by Apple Intelligence on this iPhone.")] + (await fallback.send(text, scope: scope, now: .now))
        }
        // A reply that opens with text grows out of the thinking bubble: both changes land in one animation. One that opens with a
        // card lets the bubble go, so no text slides down across the card.
        let reply = outputs.enumerated().map { index, output -> ChatRow in
            switch output {
            case .text(let text): ChatRow(id: index == 0 ? typingID : UUID(), kind: .assistant(text))
            case .proposal(let expense): ChatRow(kind: .proposal(expense, .pending))
            case .change(let change): ChatRow(kind: .change(change, .pending))
            case .bill(let bill): ChatRow(kind: .bill(bill, .pending))
            case .chart(let chart): ChatRow(kind: .chart(chart))
            case .notice(let text): ChatRow(kind: .notice(text))
            case .error(let text): ChatRow(kind: .error(text))
            }
        }
        await pacer.drain() // let the last words finish fading in before the finished bubble replaces the stream
        withAnimation(Self.replyAnimation) {
            isTyping = false
            streamingText = nil
            pacer.reset()
            rows += reply
        }
        return outputs
    }

    /// Free answers a few questions a day; adding, editing or deleting through chat never counts.
    /// ponytail: past the limit the on-device answer is computed, then replaced by the notice.
    static func limitQuestions(_ outputs: [ChatAgent.Output], isPro: Bool, today: String = Day.string(.now),
                               defaults: UserDefaults = .standard) -> [ChatAgent.Output] {
        let changes = outputs.contains { switch $0 { case .proposal, .change, .bill: true; default: false } }
        let answered = outputs.contains { if case .error = $0 { false } else { true } }
        guard !isPro, !changes, answered else { return outputs }
        let stored = defaults.string(forKey: "chatQuestions")?.split(separator: ":").map(String.init) ?? []
        let count = stored.first == today ? Int(stored.last ?? "") ?? 0 : 0
        guard count < Plan.freeQuestionsPerDay else {
            return [.notice("Free answers \(Plan.freeQuestionsPerDay) questions a day. Adding expenses here is unlimited; Pro answers everything.")]
        }
        defaults.set("\(today):\(count + 1)", forKey: "chatQuestions")
        return outputs
    }

    /// Save, discard or open a proposal card; only Save writes, and the assistant hears what the user chose.
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
        case .pending, .undone:
            break
        }
        rows[index].kind = .proposal(expense, state)
    }
}

extension ChatSession {
    /// Apply (`.saved`), keep (`.discarded`) or undo (`.undone`) an edit/delete card. Nothing is written until the user confirms.
    func resolveChange(_ id: UUID, _ change: ExpenseChange, as state: ProposalState, model: AppModel) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let original = change.original
        let label = "\(Money.format(original.amount)) \(original.note.isEmpty ? "" : "\"\(original.note)\" ")on \(original.day)"
        let verb = change.updated == nil ? "delete" : "edit"
        do {
            switch state {
            case .saved:
                // The card was built from a snapshot; refuse if the expense changed since, rather than overwrite it.
                guard let cardID = original.cardID, model.expenses(for: cardID).contains(where: { $0 == original }) else {
                    throw ToolExecutor.ToolError(message: "That expense changed or was deleted since. Ask again to see it as it is now.")
                }
                if let updated = change.updated { try model.save(updated) } else { try delete(original, model: model) }
                agent?.note("The user confirmed the \(verb) of the expense \(label).")
            case .undone:
                if change.updated != nil { try model.save(original) }
                else { model.restore(original, occurrences: model.undoExpense?.id == original.id ? model.undoOccurrences : []) }
                agent?.note("The user undid the \(verb) of the expense \(label); it is back as it was.")
            case .discarded:
                agent?.note("The user declined the \(verb) of the expense \(label); nothing changed.")
            case .pending, .opened:
                break
            }
        } catch {
            rows.append(ChatRow(kind: .error((error as? ToolExecutor.ToolError)?.message ?? error.localizedDescription)))
            return
        }
        rows[index].kind = .change(change, state)
    }

    /// Save or discard a proposed bill; only Save writes.
    func resolveBill(_ id: UUID, _ bill: Bill, as state: ProposalState, model: AppModel) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let label = "\"\(bill.name)\" \(Money.format(bill.amount)) \(bill.recurrence.title.lowercased())"
        switch state {
        case .saved:
            do { try model.saveBill(bill, in: bill.cardID) } catch {
                rows.append(ChatRow(kind: .error(error.localizedDescription)))
                return
            }
            agent?.note("The user saved the proposed bill \(label).")
        case .discarded:
            agent?.note("The user discarded the proposed bill \(label).")
        case .pending, .opened, .undone:
            break
        }
        rows[index].kind = .bill(bill, state)
    }

    /// AppModel.delete reports failure through `model.error`; surface it here instead.
    private func delete(_ expense: Expense, model: AppModel) throws {
        model.delete(expense)
        guard model.undoExpense?.id == expense.id else {
            throw ToolExecutor.ToolError(message: model.error ?? "Couldn't delete the expense.")
        }
    }
}

#if DEBUG
extension ChatSession {
    /// UI-test hook: a scripted backend that proposes "Kopi 28rb". No model, no network.
    nonisolated static var usesFakeChat: Bool { ProcessInfo.processInfo.environment["ANKKA_FAKE_CHAT"] != nil }
}

/// Proposes Kopi 28rb through the real ToolExecutor, so the proposal card and Save path are the app's own.
@MainActor
final class FakeChatAgent: ChatBackend {
    private let model: AppModel
    init(model: AppModel) { self.model = model }
    func note(_ text: String) {}
    func reset() {}
    func send(_ text: String, scope: AnalyticsFilterScope, now: Date) async -> [ChatAgent.Output] {
        let input = Data(#"{"amount": 28000, "category": "Food & Drink", "note": "Kopi"}"#.utf8)
        let outcome = ToolExecutor(model: model, scope: scope, now: now).run("propose_expense", input: input)
        return [.text("Adding it.")] + (outcome.proposal.map { [.proposal($0)] } ?? [.error(outcome.json)])
    }
}
#endif
