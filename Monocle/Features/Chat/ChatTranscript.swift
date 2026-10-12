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
            ChatBubble(isUser: row.isUser, hasTail: hasTail) { Text(row.isUser ? mentionStyled(text) : Self.markdown(text)) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(row.isUser ? "You: " : "Monocle: ") + Text(Self.markdown(text)))
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") { Self.copy(text) }
                }
        case .proposal(let expense, let state):
            ExpenseProposalCard(
                expense: expense,
                category: expense.cardID.flatMap { try? model.activeCategories(in: $0) }?.first { $0.id == expense.splits.first?.categoryID },
                splitLabel: expense.splits.count > 1 ? categoryName(expense) : nil,
                cardName: model.cards.first { $0.id == expense.cardID }?.name ?? "",
                state: state,
                onSave: { session.resolveProposal(row.id, expense, as: .saved, model: model) },
                onDiscard: { session.resolveProposal(row.id, expense, as: .discarded, model: model) },
                onEdit: { session.resolveProposal(row.id, expense, as: .opened, model: model) })
        case .change(let change, let state):
            ExpenseChangeCard(
                change: change,
                categoryName: categoryName,
                cardName: model.cards.first { $0.id == change.original.cardID }?.name ?? "",
                state: state,
                onApply: { session.resolveChange(row.id, change, as: .saved, model: model) },
                onKeep: { session.resolveChange(row.id, change, as: .discarded, model: model) },
                onUndo: { session.resolveChange(row.id, change, as: .undone, model: model) })
        case .bill(let bill, let state):
            BillProposalCard(
                bill: bill,
                categoryName: (try? model.expenseService?.categories(for: bill.cardID))??.first { $0.id == bill.categoryID }?.name ?? "",
                cardName: model.cards.first { $0.id == bill.cardID }?.name ?? "",
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
        let categories = expense.cardID.flatMap { id in try? model.expenseService?.categories(for: id) } ?? []
        let name = { (a: Split) in categories.first { $0.id == a.categoryID }?.name ?? "Unknown" }
        if expense.splits.count == 1 { return name(expense.splits[0]) }
        return expense.splits.map { "\(name($0)) \(Money.format($0.amount))" }.joined(separator: " · ")
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

    /// A sent message with its @card and #category mentions in their own colour, so they read apart from the rest of the text.
    private func mentionStyled(_ text: String) -> AttributedString {
        ChatMentionList.highlight(text, names: ChatMentionList.names(model), color: Color(red: 1, green: 0.9, blue: 0.55), bold: true)
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
            ForEach(model.unhiddenCards) { card in
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
/// Floats above the input (attach with `.overlay(alignment: .top)`), so the transcript never moves.
/// The composer's text field with @ and # mentions in colour. SwiftUI's TextField can't colour part of its text, so the
/// field's own text is clear and a Text with the same font and width is drawn over it; the caret and selection stay native.
struct MentionTextField: View {
    let prompt: String
    @Binding var text: String
    let names: [Character: [String]]
    var identifier = "chatInput"

    var body: some View {
        TextField(prompt, text: $text, axis: .vertical)
            .foregroundStyle(.clear)
            .accessibilityIdentifier(identifier)
            .overlay(alignment: .topLeading) {
                Text(ChatMentionList.highlight(text, names: names, color: MC.red, bold: false, typing: true))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

struct ChatMentionList: View {
    let model: AppModel
    let session: ChatSession
    @Binding var draft: String
    /// Highlighted row; arrow keys move it on the Mac, Return picks it.
    @Binding var selection: Int

    /// `scope` is set for an @ row (a card, stack or All Cards); a # row is a category and only inserts its name.
    struct Target { let scope: AnalyticsFilterScope?; let name: String; let icon: String; var trigger: Character = "@" }

    /// "…@Da" → ("@", "Da"), "…#Foo" → ("#", "Foo"); nil unless the draft ends in such a word (at the start or after a space).
    static func mention(in text: String) -> (trigger: Character, query: String)? {
        let starts = ["@", "#"].compactMap { mark -> (index: String.Index, mark: Character)? in
            guard let at = text.lastIndex(of: Character(mark)), at == text.startIndex || text[text.index(before: at)].isWhitespace else { return nil }
            return (at, Character(mark))
        }
        guard let start = starts.max(by: { $0.index < $1.index }) else { return nil }
        let query = text[text.index(after: start.index)...]
        return query.contains(where: \.isNewline) ? nil : (start.mark, String(query))
    }

    static func query(in text: String) -> String? { mention(in: text)?.query }

    /// What "@" and "#" can name: cards, stacks and All Cards; every category once.
    static func names(_ model: AppModel) -> [Character: [String]] {
        var seen = Set<String>()
        let categories = model.cards.flatMap { model.activeCategories(for: $0.id) }.map(\.name).filter { seen.insert($0.lowercased()).inserted }
        return ["@": model.stacks.map(\.name) + model.cards.map(\.name) + ["All Cards"], "#": categories]
    }

    /// Colours each "@Name" / "#Name" (a known name after a space or at the start, longest match first).
    /// `typing` also colours the unfinished mention at the end of a draft. The composer passes `bold: false`:
    /// it draws this text over its own invisible text, so the glyphs must keep the same widths.
    static func highlight(_ text: String, names: [Character: [String]], color: Color, bold: Bool, typing: Bool = false) -> AttributedString {
        var result = AttributedString(text)
        func paint(_ range: Range<String.Index>) {
            guard let target = Range(range, in: result) else { return }
            result[target].foregroundColor = color
            if bold { result[target].font = .body.bold() }
        }
        var index = text.startIndex
        while index < text.endIndex {
            defer { index = text.index(after: index) }
            guard let candidates = names[text[index]], index == text.startIndex || text[text.index(before: index)].isWhitespace else { continue }
            let rest = text[text.index(after: index)...]
            let ends: (String.Index) -> Bool = { $0 == text.endIndex || !(text[$0].isLetter || text[$0].isNumber) }
            guard let name = candidates.sorted(by: { $0.count > $1.count }).first(where: {
                rest.range(of: $0, options: [.caseInsensitive, .anchored]).map { ends($0.upperBound) } ?? false
            }), let match = rest.range(of: name, options: [.caseInsensitive, .anchored]) else { continue }
            paint(index..<match.upperBound)
        }
        if typing, let open = mention(in: text), let start = text.lastIndex(of: open.trigger) { paint(start..<text.endIndex) }
        return result
    }

    static func targets(_ model: AppModel, scope: AnalyticsFilterScope, mention: (trigger: Character, query: String)) -> [Target] {
        let all: [Target]
        if mention.trigger == "#" {
            // The categories of the cards the chat is answering about, once each by name.
            var seen = Set<String>()
            all = model.cards(in: scope).flatMap { model.activeCategories(for: $0.id) }
                .filter { seen.insert($0.name.lowercased()).inserted }
                .map { Target(scope: nil, name: $0.name, icon: $0.symbol, trigger: "#") }
        } else {
            all = model.stacks.map { Target(scope: .stack(id: $0.id, name: $0.name), name: $0.name, icon: $0.icon) }
                + model.unhiddenCards.map { Target(scope: .card(id: $0.id, name: $0.name), name: $0.name, icon: "creditcard") }
                + [Target(scope: .allCards, name: "All Cards", icon: "rectangle.stack")]
        }
        return Array((mention.query.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(mention.query) }).prefix(6))
    }

    /// Rows currently shown for the draft (empty when no @ or # word is being typed).
    static func visible(_ model: AppModel, session: ChatSession, draft: String) -> [Target] {
        mention(in: draft).map { targets(model, scope: session.scope ?? ChatScopeMenuItems.homeScope(model), mention: $0) } ?? []
    }

    /// Picks the highlighted row (Return on the Mac). False when the list isn't showing.
    @discardableResult
    static func pickSelected(_ selection: Int, model: AppModel, session: ChatSession, draft: inout String) -> Bool {
        let rows = visible(model, session: session, draft: draft)
        guard !rows.isEmpty else { return false }
        pick(rows[min(max(selection, 0), rows.count - 1)], session: session, model: model, draft: &draft)
        return true
    }

    /// Moves the highlight; false (key not handled) when the list isn't showing.
    static func move(_ step: Int, selection: inout Int, model: AppModel, session: ChatSession, draft: String) -> Bool {
        let count = visible(model, session: session, draft: draft).count
        guard count > 0 else { return false }
        selection = min(max(selection + step, 0), count - 1)
        return true
    }

    static func pick(_ target: Target, session: ChatSession, model: AppModel, draft: inout String) {
        if let at = draft.lastIndex(of: target.trigger) { draft = String(draft[..<at]) + "\(target.trigger)\(target.name) " }
        if let scope = target.scope { ChatScopeMenuItems.select(scope, session: session, model: model) }
    }

    var body: some View {
        let targets = Self.visible(model, session: session, draft: draft)
        if !targets.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(targets.enumerated()), id: \.offset) { index, target in
                        Button { Self.pick(target, session: session, model: model, draft: &draft) } label: {
                            Label(target.name, systemImage: target.icon)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(index == min(selection, targets.count - 1) ? Color.secondary.opacity(0.14) : .clear, in: .rect(cornerRadius: 10))
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(target.scope == nil ? "Ask about the \(target.name) category" : "Answer about \(target.name)")
                    }
                }
                .padding(6)
                .frame(maxWidth: 320, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("chatMentionList")
                .onChange(of: Self.query(in: draft)) { selection = 0 }
        }
    }
}
