import SwiftUI

struct ChatRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case user(String)
        case assistant(String)
        case proposal(Expense, ProposalState)
        case summary([CategorySpendPoint])
        case notice(String)
        case error(String)
    }
    let id = UUID()
    var kind: Kind

    var isUser: Bool { if case .user = kind { true } else { false } }
    var isBubble: Bool {
        switch kind { case .user, .assistant: true; default: false }
    }
}

/// Full-screen chat. Step 1 of CHAT_SPEC §11: UI preview with mock content, no AI and no writes.
struct ChatView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [ChatRow] = []
    @State private var draft = ""
    @State private var isTyping = false
    @State private var sentCount = 0
    /// Chat-local scope: starts from the Home filter, never writes back to it (CHAT_SPEC §2).
    @State private var scope: AnalyticsFilterScope = .allCards
    @FocusState private var inputFocused: Bool

    private static let suggestions = ["Kopi 28rb", "How much did I spend this month?", "Am I over budget?"]

    private var scopeLabel: String { scope.isAllCards ? "All cards" : "\(scope.subtitle): \(scope.title)" }

    private var homeScope: AnalyticsFilterScope {
        if model.filterScope == .activeStack, let stack = model.currentStack { .stack(id: stack.id, name: stack.name) } else { .allCards }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 4) {
                    Text("Preview: AI isn't connected yet. Nothing here is saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 8)
                    if rows.isEmpty && !isTyping { emptyState }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, hasTail: isLastInRun(index))
                            .padding(.top, startsRun(index) ? 10 : 0)
                    }
                    if isTyping { TypingBubble().padding(.top, 10) }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.always)
            // Tapping the transcript dismisses the keyboard; buttons inside rows still win the tap.
            .onTapGesture { inputFocused = false }
            .scrollEdgeEffectHidden(true, for: .all)
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    ProgressiveBlur(solid: max(proxy.safeAreaInsets.top - 30, 0), fade: 52, tint: Color(uiColor: .systemBackground))
                        .ignoresSafeArea(edges: .top)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ChatInputBar(text: $draft, focused: $inputFocused, isBusy: isTyping, onSend: { send(draft) })
            }
            .sensoryFeedback(.impact(weight: .light), trigger: sentCount)
            .navigationTitle("monocle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("monocle").font(.headline)
                        Menu { scopeMenu } label: {
                            HStack(spacing: 3) {
                                Text(scopeLabel)
                                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("Scope: \(scopeLabel)")
                        .accessibilityIdentifier("chatScopeMenu")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("chatClose")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Clear chat", systemImage: "trash", role: .destructive) { rows = [] }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Chat options")
                }
            }
        }
        .tint(MC.red)
        .onAppear(perform: seedPreview)
    }

    @ViewBuilder
    private var scopeMenu: some View {
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
        Button {
            guard target != scope else { return }
            scope = target
            rows.append(ChatRow(kind: .notice("Now answering about \(scopeLabel)")))
        } label: {
            if target == scope { Label(label, systemImage: "checkmark") } else { Label(label, systemImage: icon) }
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
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                }
        case .proposal(let expense, let state):
            ExpenseProposalCard(
                expense: expense,
                category: model.categories.first { $0.id == expense.allocations.first?.categoryID },
                cardName: model.books.first { $0.id == expense.bookID }?.name ?? "",
                state: state,
                onSave: { setProposal(row.id, expense, .saved) },
                onDiscard: { setProposal(row.id, expense, .discarded) })
        case .summary(let points):
            ChatSummaryChart(points: points)
        case .notice(let message):
            Text(message).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 6)
        case .error(let message):
            Text(message).font(.footnote).foregroundStyle(MC.red).frame(maxWidth: .infinity)
        }
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

    // ponytail: preview "Save" only flips the card state; real saves go through AppModel.save in step 4.
    private func setProposal(_ id: UUID, _ expense: Expense, _ state: ProposalState) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].kind = .proposal(expense, state)
    }

    private func send(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTyping else { return }
        draft = ""
        sentCount += 1
        rows.append(ChatRow(kind: .user(text)))
        isTyping = true
        Task {
            try? await Task.sleep(for: .seconds(1))
            isTyping = false
            rows.append(ChatRow(kind: .assistant("AI isn't connected yet. This is a preview of the chat screen.")))
        }
    }

    private func seedPreview() {
        guard rows.isEmpty else { return }
        scope = homeScope
        var seeded = [ChatRow(kind: .user("kopi 28rb"))]
        if let category = model.categories.first {
            let amount: Int64 = 2_800_000
            let expense = Expense(amount: amount, day: Day.string(.now), note: "Kopi",
                                  allocations: [Allocation(categoryID: category.id, amount: amount)],
                                  source: "chat", bookID: model.activeBookID)
            seeded.append(ChatRow(kind: .assistant("Got it. Check the details and tap **Save**.")))
            seeded.append(ChatRow(kind: .proposal(expense, .pending)))
        }
        seeded.append(ChatRow(kind: .user("How much did I spend this month?")))
        let report = AnalyticsReport.build(data: model.reportingData(for: scope), horizon: .thisMonth)
        if let error = report.errorMessage {
            seeded.append(ChatRow(kind: .error(error)))
        } else {
            let total = (try? Money.checkedSum(report.categoryPoints.map(\.amount))) ?? 0
            seeded.append(ChatRow(kind: .assistant("This month so far: **\(Money.format(total))**. Here it is by category.")))
            seeded.append(ChatRow(kind: .summary(report.categoryPoints)))
        }
        rows = seeded
    }
}
