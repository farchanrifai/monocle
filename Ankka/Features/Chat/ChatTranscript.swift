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

    /// Where a tapped suggestion goes. The phone fills the composer so the owner can edit before sending; nil sends it (Mac pane).
    var fill: ((String) -> Void)? = nil

    /// An expense, a split (the agent's colon form), both in the reporting currency's usual shorthand, and the overview insight.
    private static var suggestions: [(symbol: String, text: String)] {
        [("plus.circle", "Add " + (Money.reportingCurrency == "IDR" ? "Kopi 28rb" : "Coffee 5")),
         ("square.split.2x1", Money.reportingCurrency == "IDR" ? "Add pasar 50rb: 30rb makan, 20rb belanja" : "Add groceries 50: 30 food, 20 household"),
         ("gauge.with.needle", "How am I doing this month?")]
    }
    private var rows: [ChatRow] { session.rows }

    var body: some View {
        LazyVStack(spacing: 4) {
            if rows.isEmpty && !session.isTyping { emptyState }
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                let row = index < rows.count ? rows[index] : nil // nil: the thinking bubble
                Group {
                    // One call site for the thinking bubble and the reply's first text, so the same view grows in place.
                    if let text = bubbleText(row) {
                        let streaming = row == nil && text != nil
                        // The clock only runs while text streams in; at rest it renders once.
                        TimelineView(.animation(paused: !streaming)) { context in
                            let shown = streaming ? session.pacer.advance(to: context.date) : nil
                            ChatBubble(isUser: false, hasTail: isLastInRun(index), rowID: id) {
                                if let text {
                                    Text(Self.markdown(streaming ? session.pacer.visible : text))
                                        .textRenderer(StreamFadeRenderer(shown: shown))
                                        .modifier(SmoothHeight())
                                        .transition(.opacity)
                                } else { TypingDots().transition(.opacity) }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel(text.map { Text("Ankka: ") + Text(Self.markdown($0)) } ?? Text("Ankka is typing"))
                        .contextMenu {
                            if let text { Button("Copy", systemImage: "doc.on.doc") { Self.copy(text) } }
                        }
                    } else if let row {
                        rowView(row, hasTail: isLastInRun(index))
                    }
                }
                .padding(.top, startsRun(index) ? 10 : 0)
                // The user's bubble grows on its own (ChatBubble); reply cards and texts fade in while the list moves up.
                .transition(row == nil ? .scale(scale: 0.6, anchor: .bottomLeading).combined(with: .opacity) : row!.isUser ? .identity : .opacity)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.82), value: session.isTyping)
        .animation(ChatSession.replyAnimation, value: session.streamingText == nil) // the thinking bubble opens up when the first words arrive
    }

    private var ids: [UUID] { rows.map(\.id) + (session.isTyping ? [session.typingID] : []) }

    /// `.some(nil)` for the thinking bubble, `.some(text)` for an assistant text, nil for every other row.
    private func bubbleText(_ row: ChatRow?) -> String?? {
        guard let row else { return .some(session.streamingText.flatMap { $0.isEmpty ? nil : $0 }) }
        if case .assistant(let text) = row.kind { return .some(text) }
        return nil
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(MC.red)
                .frame(width: 68, height: 68)
                .background(Color.chatSurface, in: Circle())
                .accessibilityHidden(true)
            Text("Add an expense or ask")
                .font(.title3.weight(.semibold))
                .padding(.top, 16)
            Text("In English or Bahasa Indonesia. Type @ for a Card, # for a Category.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            VStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.text) { suggestion in
                    Button { (fill ?? send)(suggestion.text) } label: {
                        Label(suggestion.text, systemImage: suggestion.symbol)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .labelStyle(SuggestionLabelStyle())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .background(Color.chatSurface, in: .rect(cornerRadius: 14, style: .continuous))
                            .contentShape(.rect(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 24)
        }
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .frame(maxWidth: 420)
    }

    @ViewBuilder
    private func rowView(_ row: ChatRow, hasTail: Bool) -> some View {
        switch row.kind {
        case .user(let text), .assistant(let text):
            ChatBubble(isUser: row.isUser, hasTail: hasTail, rowID: row.id) {
                if row.isUser { mentionStyled(text).textRenderer(MentionChipRenderer(chip: .black.opacity(0.28))) } else { Text(Self.markdown(text)) }
            }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(row.isUser ? "You: " : "Ankka: ") + Text(Self.markdown(text)))
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
        guard index < rows.count else { return true } // the thinking bubble
        guard rows[index].isBubble else { return false }
        let next = rows.indices.contains(index + 1) ? rows[index + 1] : nil
        return next == nil || next?.isUser != rows[index].isUser || next?.isBubble == false
    }

    private func startsRun(_ index: Int) -> Bool {
        index > 0 && rows[index - 1].isUser != (index < rows.count ? rows[index].isUser : false)
    }

    /// A sent message with its @card and #category mentions as chips, so they read apart from the rest of the text.
    private func mentionStyled(_ text: String) -> Text {
        ChatMentionList.styled(text, names: ChatMentionList.names(model), color: .white, bold: true, padded: true)
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

/// Stacks, cards and All Cards; picking one tells the assistant (and the transcript) what it now answers about.
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

    /// A hand-typed "@Name" that was never picked from the list still sets the scope on send, so the header never disagrees with the answer.
    /// The last "@" mention wins; returns the scope the message is sent with.
    static func applyMention(in text: String, session: ChatSession, model: AppModel) -> AnalyticsFilterScope {
        let names = ChatMentionList.names(model)
        if let range = ChatMentionList.mentionRanges(text, names: names).last(where: { text[$0].first == "@" }) {
            let name = String(text[range].dropFirst())
            let target: AnalyticsFilterScope? =
                if let stack = model.stacks.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { .stack(id: stack.id, name: stack.name) }
                else if let card = model.cards.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) { .card(id: card.id, name: card.name) }
                else if name.caseInsensitiveCompare("All Cards") == .orderedSame { .allCards }
                else { nil }
            if let target { select(target, session: session, model: model) }
        }
        return session.scope ?? homeScope(model)
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

/// Icon in a fixed-width leading slot so the suggestion texts line up.
private struct SuggestionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon.foregroundStyle(MC.red).frame(width: 22)
            configuration.title
        }
    }
}

/// Typing "@" in the chat input lists stacks and cards; picking one sets the chat scope, like the scope menu.
/// Floats above the input (attach with `.overlay(alignment: .top)`), so the transcript never moves.
/// Marks the text of a mention so `MentionChipRenderer` can find it.
struct MentionChip: TextAttribute {}

/// Draws a rounded, padded chip behind every `MentionChip` run, then the text on top.
/// The chip reaches a little past the glyphs; it never changes the text's own layout.
struct MentionChipRenderer: TextRenderer {
    var chip: Color
    /// How far the chip reaches past the text. The composer keeps this small: there the neighbours are one plain space away.
    var outset: CGFloat = 1
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line where run[MentionChip.self] != nil {
                let rect = run.typographicBounds.rect.insetBy(dx: -outset, dy: -1)
                context.fill(Path(roundedRect: rect, cornerRadius: 7, style: .continuous), with: .color(chip))
            }
        }
        for line in layout { context.draw(line) }
    }
}

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
                ChatMentionList.styled(text, names: names, color: .white, bold: false, typing: true)
                    .textRenderer(MentionChipRenderer(chip: MC.red.opacity(0.75), outset: 2))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transaction { $0.animation = nil } // the typed text mirrors the field exactly, never mid-transition
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

    /// The "@Name" / "#Name" stretches of a draft (a known name after a space or at the start, longest match first).
    /// `typing` adds the unfinished mention at the end: the trigger plus as much of the text after it as still begins
    /// some name, so "@Work last month?" gives only "@Work" and an unfinished "@Tokyo Tr" gives all of it.
    static func mentionRanges(_ text: String, names: [Character: [String]], typing: Bool = false) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            defer { index = text.index(after: index) }
            guard let candidates = names[text[index]], index == text.startIndex || text[text.index(before: index)].isWhitespace else { continue }
            let rest = text[text.index(after: index)...]
            let ends: (String.Index) -> Bool = { $0 == text.endIndex || !(text[$0].isLetter || text[$0].isNumber) }
            guard let name = candidates.sorted(by: { $0.count > $1.count }).first(where: {
                rest.range(of: $0, options: [.caseInsensitive, .anchored]).map { ends($0.upperBound) } ?? false
            }), let match = rest.range(of: name, options: [.caseInsensitive, .anchored]) else { continue }
            ranges.append(index..<match.upperBound)
        }
        if typing, let open = mention(in: text), let start = text.lastIndex(of: open.trigger) {
            let tail = text[text.index(after: start)...].lowercased()
            let pool = (names[open.trigger] ?? []).map { $0.lowercased() }
            var length = tail.count
            while length > 0, !pool.contains(where: { $0.hasPrefix(String(tail.prefix(length))) }) { length -= 1 }
            ranges.append(start..<(text.index(start, offsetBy: 1 + length, limitedBy: text.endIndex) ?? text.endIndex))
        }
        // Overlapping or touching stretches become one chip.
        return ranges.sorted { $0.lowerBound < $1.lowerBound }.reduce(into: []) { merged, range in
            if let last = merged.last, range.lowerBound <= last.upperBound { merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound) }
            else { merged.append(range) }
        }
    }

    /// The text with each mention in `color` and tagged for `MentionChipRenderer`, which draws the rounded chip behind it.
    /// The composer passes `bold: false` and `padded: false`: it draws this over its own invisible text, so every glyph must keep its width.
    /// `padded` puts a thin space inside each end of the chip, which is real room around the name without moving the words beside it.
    static func styled(_ text: String, names: [Character: [String]], color: Color, bold: Bool, padded: Bool = false, typing: Bool = false) -> Text {
        var result = Text(verbatim: ""), cursor = text.startIndex
        for range in mentionRanges(text, names: names, typing: typing) {
            let plain = Text(verbatim: String(text[cursor..<range.lowerBound]))
            let chip = Text(verbatim: padded ? "\u{2009}\(text[range])\u{2009}" : String(text[range])).foregroundStyle(color).fontWeight(bold ? .bold : nil).customAttribute(MentionChip())
            result = Text("\(result)\(plain)\(chip)")
            cursor = range.upperBound
        }
        return Text("\(result)\(Text(verbatim: String(text[cursor...])))")
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
