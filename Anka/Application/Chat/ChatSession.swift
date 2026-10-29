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
/// describes. Saved to chat.json next to the ledger (what the user sees; the on-device model's memory lives only in its session).
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
        loading = false
    }

    func clear() {
        agent?.reset()
        scope = nil
        rows = []
    }

    /// Called after every change to rows.
    func save() {
        guard !loading, let fileURL else { return }
        do {
            let ui = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Snapshot(rows: rows, scope: scope)))
            let json: [String: Any] = ["version": 1, "ui": ui]
            try JSONSerialization.data(withJSONObject: json).write(to: fileURL, options: .atomic)
        } catch {
            // ponytail: history is a convenience copy; a failed write never interrupts the chat.
        }
    }
}

extension ChatSession {
    /// Why chat can't run on this device, or nil when it can. DEBUG UI runs can swap in a scripted backend.
    static var unavailableReason: String? {
        #if DEBUG
        if usesFakeChat { return nil }
        #endif
        return AppleChatAgent.unavailableReason
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
        let agent: any ChatBackend
        #if DEBUG
        agent = self.agent ?? (Self.usesFakeChat ? FakeChatAgent(model: model) : AppleChatAgent(model: model))
        #else
        agent = self.agent ?? AppleChatAgent(model: model)
        #endif
        streamingText = nil
        pacer.reset()
        self.agent = agent
        let outputs = Self.limitQuestions(await agent.send(text, scope: scope, now: .now), isPro: model.isPro)
        // The reply grows out of the thinking bubble: both changes land in one animation, the first text bubble scales up from its tail.
        let firstText = outputs.firstIndex { if case .text = $0 { true } else { false } }
        let reply = outputs.enumerated().map { index, output -> ChatRow in
            switch output {
            case .text(let text): ChatRow(id: index == firstText ? typingID : UUID(), kind: .assistant(text))
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
    nonisolated static var usesFakeChat: Bool { ProcessInfo.processInfo.environment["ANKA_FAKE_CHAT"] != nil }
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
