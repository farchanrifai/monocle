import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// The conversation itself, shared by the iPhone sheet and the Mac pane: bubbles, cards, charts and the empty state.
struct ChatTranscript: View {
    let model: AppModel
    let session: ChatSession
    var send: (String) -> Void

    private static let suggestions = ["Kopi 28rb", "How much did I spend this month?", "Am I over budget?"]
    private var rows: [ChatRow] { session.rows }

    var body: some View {
        LazyVStack(spacing: 4) {
            if rows.isEmpty && !session.isTyping { emptyState }
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                rowView(row, hasTail: isLastInRun(index))
                    .padding(.top, startsRun(index) ? 10 : 0)
            }
            if session.isTyping { TypingBubble().padding(.top, 10) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(MC.red)
            Text("Add an expense or ask about your spending, in English or Bahasa Indonesia.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            VStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button(suggestion) { send(suggestion) }
                        .buttonStyle(.bordered)
                        .tint(MC.red)
                }
            }
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func rowView(_ row: ChatRow, hasTail: Bool) -> some View {
        switch row.kind {
        case .user(let text), .assistant(let text):
            ChatBubble(isUser: row.isUser, hasTail: hasTail) { Text(Self.markdown(text)) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(row.isUser ? "You: " : "Monocle: ") + Text(Self.markdown(text)))
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") { Self.copy(text) }
                }
        case .proposal(let expense, let state):
            ExpenseProposalCard(
                expense: expense,
                category: expense.bookID.flatMap { try? model.activeCategories(in: $0) }?.first { $0.id == expense.allocations.first?.categoryID },
                splitLabel: expense.allocations.count > 1 ? categoryName(expense) : nil,
                cardName: model.books.first { $0.id == expense.bookID }?.name ?? "",
                state: state,
                onSave: { session.resolveProposal(row.id, expense, as: .saved, model: model) },
                onDiscard: { session.resolveProposal(row.id, expense, as: .discarded, model: model) },
                onEdit: { session.resolveProposal(row.id, expense, as: .opened, model: model) })
        case .change(let change, let state):
            ExpenseChangeCard(
                change: change,
                categoryName: categoryName,
                cardName: model.books.first { $0.id == change.original.bookID }?.name ?? "",
                state: state,
                onApply: { session.resolveChange(row.id, change, as: .saved, model: model) },
                onKeep: { session.resolveChange(row.id, change, as: .discarded, model: model) },
                onUndo: { session.resolveChange(row.id, change, as: .undone, model: model) })
        case .bill(let bill, let state):
            BillProposalCard(
                bill: bill,
                categoryName: (try? model.expenseService?.categories(for: bill.bookID))??.first { $0.id == bill.categoryID }?.name ?? "",
                cardName: model.books.first { $0.id == bill.bookID }?.name ?? "",
                state: state,
                onSave: { session.resolveBill(row.id, bill, as: .saved, model: model) },
                onDiscard: { session.resolveBill(row.id, bill, as: .discarded, model: model) })
        case .summary(let points):
            ChatChartView(chart: ChatChart(categories: points, title: "Spending by category"))
        case .chart(let chart):
            ChatChartView(chart: chart)
        case .notice(let message):
            Text(message).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 6)
        case .error(let message):
            Text(message).font(.footnote).foregroundStyle(MC.red).frame(maxWidth: .infinity)
        }
    }

    private func categoryName(_ expense: Expense) -> String {
        let categories = expense.bookID.flatMap { id in try? model.expenseService?.categories(for: id) } ?? []
        let name = { (a: Allocation) in categories.first { $0.id == a.categoryID }?.name ?? "Unknown" }
        if expense.allocations.count == 1 { return name(expense.allocations[0]) }
        return expense.allocations.map { "\(name($0)) \(Money.format($0.amount))" }.joined(separator: " · ")
    }

    // Tails sit on the last bubble of a same-sender run, as in Messages.
    private func isLastInRun(_ index: Int) -> Bool {
        guard rows[index].isBubble else { return false }
        let next = rows.indices.contains(index + 1) ? rows[index + 1] : nil
        return next == nil || next?.isUser != rows[index].isUser || next?.isBubble == false
    }

    private func startsRun(_ index: Int) -> Bool {
        index > 0 && rows[index - 1].isUser != rows[index].isUser
    }

    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    private static func copy(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

/// Stacks, cards and All Cards; picking one tells Claude (and the transcript) what it now answers about.
struct ChatScopeMenuItems: View {
    let model: AppModel
    let session: ChatSession

    /// Chat starts from the Home filter and never writes back to it (CHAT_SPEC §2).
    static func homeScope(_ model: AppModel) -> AnalyticsFilterScope {
        if model.filterScope == .activeStack, let stack = model.currentStack { .stack(id: stack.id, name: stack.name) } else { .allCards }
    }

    static func label(_ scope: AnalyticsFilterScope) -> String { scope.isAllCards ? "All cards" : "\(scope.subtitle): \(scope.title)" }

    private var scope: AnalyticsFilterScope { session.scope ?? Self.homeScope(model) }

    /// Shared by this menu and the @ picker.
    static func select(_ target: AnalyticsFilterScope, session: ChatSession, model: AppModel) {
        guard target != (session.scope ?? homeScope(model)) else { return }
        session.scope = target
        session.rows.append(ChatRow(kind: .notice("Now answering about \(label(target))")))
    }

    var body: some View {
        if !model.stacks.isEmpty {
            Section("Stacks") {
                ForEach(model.stacks) { stack in
                    scopeButton(.stack(id: stack.id, name: stack.name), label: stack.name, icon: stack.icon)
                }
            }
        }
        Section("Cards") {
            ForEach(model.unhiddenBooks) { card in
                scopeButton(.card(id: card.id, name: card.name), label: card.name, icon: "creditcard")
            }
        }
        Section { scopeButton(.allCards, label: "All Cards", icon: "rectangle.stack") }
    }

    private func scopeButton(_ target: AnalyticsFilterScope, label: String, icon: String) -> some View {
        Button { Self.select(target, session: session, model: model) } label: {
            if target == scope { Label(label, systemImage: "checkmark") } else { Label(label, systemImage: icon) }
        }
    }
}

/// Typing "@" in the chat input lists stacks and cards; picking one sets the chat scope, like the scope menu.
struct ChatMentionList: View {
    let model: AppModel
    let session: ChatSession
    @Binding var draft: String

    struct Target { let scope: AnalyticsFilterScope; let name: String; let icon: String }

    /// "…@Da" → "Da"; nil unless the draft ends in an @ word (at the start or after a space).
    static func query(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@"), at == text.startIndex || text[text.index(before: at)].isWhitespace else { return nil }
        let query = text[text.index(after: at)...]
        return query.contains(where: \.isNewline) ? nil : String(query)
    }

    static func targets(_ model: AppModel, matching query: String) -> [Target] {
        let all = model.stacks.map { Target(scope: .stack(id: $0.id, name: $0.name), name: $0.name, icon: $0.icon) }
            + model.unhiddenBooks.map { Target(scope: .card(id: $0.id, name: $0.name), name: $0.name, icon: "creditcard") }
            + [Target(scope: .allCards, name: "All Cards", icon: "rectangle.stack")]
        return query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    /// Picks the first match (Return on the Mac). False when no @ word is being typed.
    @discardableResult
    static func pickFirst(model: AppModel, session: ChatSession, draft: inout String) -> Bool {
        guard let query = query(in: draft), let first = targets(model, matching: query).first else { return false }
        pick(first, session: session, model: model, draft: &draft)
        return true
    }

    static func pick(_ target: Target, session: ChatSession, model: AppModel, draft: inout String) {
        if let at = draft.lastIndex(of: "@") { draft = String(draft[..<at]) + "@\(target.name) " }
        ChatScopeMenuItems.select(target.scope, session: session, model: model)
    }

    var body: some View {
        if let query = Self.query(in: draft) {
            let targets = Self.targets(model, matching: query)
            if !targets.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(targets.prefix(6).enumerated()), id: \.offset) { index, target in
                        Button { Self.pick(target, session: session, model: model, draft: &draft) } label: {
                            Label(target.name, systemImage: target.icon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(index == 0 ? Color.secondary.opacity(0.12) : .clear, in: .rect(cornerRadius: 10))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Answer about \(target.name)")
                    }
                }
                .padding(6)
                .frame(maxWidth: 320, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("chatMentionList")
            }
        }
    }
}
