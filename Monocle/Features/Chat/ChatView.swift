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

/// The conversation outlives the full-screen cover: RootView owns it for as long as the app runs.
// ponytail: in-memory only; persist to chat.json (CHAT_SPEC §7) when history across launches matters.
@MainActor @Observable
final class ChatSession {
    var rows: [ChatRow] = []
    var isTyping = false
    /// Chat-local scope: starts from the Home filter, never writes back to it (CHAT_SPEC §2).
    var scope: AnalyticsFilterScope?
    @ObservationIgnored var agent: ChatAgent?

    func clear() { rows = []; agent?.reset() }
}

/// Full-screen chat (CHAT_SPEC §1). Claude proposes and answers through ChatAgent; only the Save button writes.
struct ChatView: View {
    @Bindable var model: AppModel
    @Bindable var session: ChatSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var sentCount = 0
    @FocusState private var inputFocused: Bool
    @AppStorage("chatEnabled") private var chatEnabled = false
    @State private var hasKey = APIKeyStore.read() != nil
    @State private var showingSetup = false

    private static let suggestions = ["Kopi 28rb", "How much did I spend this month?", "Am I over budget?"]

    private var rows: [ChatRow] { session.rows }
    private var isTyping: Bool { session.isTyping }
    private var scope: AnalyticsFilterScope { session.scope ?? homeScope }

    private var scopeLabel: String { scope.isAllCards ? "All cards" : "\(scope.subtitle): \(scope.title)" }

    private var homeScope: AnalyticsFilterScope {
        if model.filterScope == .activeStack, let stack = model.currentStack { .stack(id: stack.id, name: stack.name) } else { .allCards }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 4) {
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
                if chatEnabled && hasKey {
                    ChatInputBar(text: $draft, focused: $inputFocused, isBusy: isTyping, onSend: { send(draft) })
                } else {
                    Button(chatEnabled ? "Add your API key" : "Turn on AI chat") { showingSetup = true }
                        .buttonStyle(.borderedProminent)
                        .tint(MC.red)
                        .padding(12)
                        .accessibilityIdentifier("chatSetup")
                }
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
                        Button("Clear chat", systemImage: "trash", role: .destructive) { session.clear(); session.scope = homeScope }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Chat options")
                }
            }
        }
        .tint(MC.red)
        .onAppear { if session.scope == nil { session.scope = homeScope } }
        .sheet(isPresented: $showingSetup, onDismiss: { hasKey = APIKeyStore.read() != nil }) {
            NavigationStack {
                ChatSettingsView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSetup = false } } }
            }
        }
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
            session.scope = target
            session.rows.append(ChatRow(kind: .notice("Now answering about \(scopeLabel)")))
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
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text(row.isUser ? "You: " : "Monocle: ") + Text(Self.markdown(text)))
                .contextMenu {
                    Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
                }
        case .proposal(let expense, let state):
            ExpenseProposalCard(
                expense: expense,
                category: expense.bookID.flatMap { try? model.activeCategories(in: $0) }?.first { $0.id == expense.allocations.first?.categoryID },
                cardName: model.books.first { $0.id == expense.bookID }?.name ?? "",
                state: state,
                onSave: { setProposal(row.id, expense, .saved) },
                onDiscard: { setProposal(row.id, expense, .discarded) },
                onEdit: { setProposal(row.id, expense, .opened) })
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

    private func setProposal(_ id: UUID, _ expense: Expense, _ state: ProposalState) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let summary = "\(Money.format(expense.amount)) \(expense.note.isEmpty ? "" : "\"\(expense.note)\" ")on \(expense.day)"
        switch state {
        case .saved:
            do { try model.saveFromChat(expense) } catch {
                session.rows.append(ChatRow(kind: .error(error.localizedDescription)))
                return
            }
            session.agent?.note("The user saved the proposed expense \(summary).")
        case .opened:
            session.agent?.note("The user opened the proposed expense \(summary) in the editor; it may have been changed or saved there.")
            model.openInEntry(expense)
        case .discarded:
            session.agent?.note("The user discarded the proposed expense \(summary).")
        case .pending:
            break
        }
        session.rows[index].kind = .proposal(expense, state)
    }

    private func send(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTyping, hasKey else { return }
        draft = ""
        sentCount += 1
        session.rows.append(ChatRow(kind: .user(text)))
        session.isTyping = true
        // The key is read per request, so changing it in Settings keeps the conversation.
        let agent = session.agent ?? ChatAgent(model: model) { body in
            guard let key = APIKeyStore.read() else { throw ClaudeClient.ClientError.unauthorized }
            return try await ClaudeClient(apiKey: key).send(body)
        }
        session.agent = agent
        let session = session, scope = scope
        Task {
            let outputs = await agent.send(text, scope: scope)
            session.isTyping = false
            // VoiceOver users hear the reply arrive without hunting for it.
            if case .text(let reply)? = outputs.first(where: { if case .text = $0 { true } else { false } }) {
                AccessibilityNotification.Announcement(reply).post()
            } else if case .error(let message)? = outputs.last {
                AccessibilityNotification.Announcement(message).post()
            }
            session.rows += outputs.map { output in
                switch output {
                case .text(let text): ChatRow(kind: .assistant(text))
                case .proposal(let expense): ChatRow(kind: .proposal(expense, .pending))
                case .chart(let points): ChatRow(kind: .summary(points))
                case .notice(let text): ChatRow(kind: .notice(text))
                case .error(let text): ChatRow(kind: .error(text))
                }
            }
        }
    }
}
