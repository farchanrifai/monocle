import SwiftUI

/// Full-screen chat (CHAT_SPEC §1). Claude proposes and answers through ChatAgent; only the Save button writes.
struct ChatView: View {
    @Bindable var model: AppModel
    @Bindable var session: ChatSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var sentCount = 0
    @FocusState private var inputFocused: Bool
    @AppStorage("chatEnabled") private var chatEnabled = false
    @AppStorage("chatBackend") private var backend = "claude"
    @State private var savedKey = APIKeyStore.read() != nil
    private var hasKey: Bool { savedKey || backend == "apple" }
    @State private var showingSetup = false
    @State private var mentionSelection = 0
    @State private var composerHeight: CGFloat = 0
    @State private var fieldFrame: CGRect = .zero
    @State private var flightX: CGFloat = 0
    @State private var flightY: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isTyping: Bool { session.isTyping }
    private var scope: AnalyticsFilterScope { session.scope ?? ChatScopeMenuItems.homeScope(model) }
    private var scopeLabel: String { ChatScopeMenuItems.label(scope) }

    var body: some View {
        NavigationStack {
            ScrollView {
                ChatTranscript(model: model, session: session, send: send)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    // The composer floats over the transcript; this keeps the last bubble resting above it.
                    .padding(.bottom, composerHeight)
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
            .overlay(alignment: .bottom) {
                Group {
                  if chatEnabled && hasKey {
                    ChatInputBar(text: $draft, focused: $inputFocused, isBusy: isTyping, names: ChatMentionList.names(model), onSend: { send(draft) }, onFieldFrame: { fieldFrame = $0 })
                        .overlay(alignment: .top) {
                            ChatMentionList(model: model, session: session, draft: $draft, selection: $mentionSelection)
                                .padding(.horizontal, 12)
                                .alignmentGuide(.top) { $0[.bottom] + 4 }
                        }
                  } else {
                    Button(chatEnabled ? "Add your API key" : "Turn on AI chat") { showingSetup = true }
                        .buttonStyle(.borderedProminent)
                        .tint(MC.red)
                        .padding(12)
                        .accessibilityIdentifier("chatSetup")
                  }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
            }
            .environment(\.chatFlightID, session.flightID)
            .environment(\.chatReplyID, session.replyID)
            .coordinateSpace(name: "chat")
            .chatFlightLayer(from: fieldFrame, x: flightX, y: flightY, active: session.flightID != nil && ChatSession.sendStyle == .imessage, label: flightLabel)
            .onChange(of: session.flightID) { _, id in
                flightX = 0; flightY = 0
                guard id != nil, ChatSession.sendStyle == .imessage else { return }
                withAnimation(ChatSession.sweepAnimation) { flightX = 1 }
                let landed = id
                withAnimation(ChatSession.liftAnimation, completionCriteria: .logicallyComplete) { flightY = 1 } completion: {
                    if session.flightID == landed { session.flightID = nil }
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
                        Menu { ChatScopeMenuItems(model: model, session: session) } label: {
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
                        Button("Clear chat", systemImage: "trash", role: .destructive) { session.clear(); session.scope = ChatScopeMenuItems.homeScope(model) }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Chat options")
                }
            }
        }
        .tint(MC.red)
        .onAppear { if session.scope == nil { session.scope = ChatScopeMenuItems.homeScope(model) } }
        .sheet(isPresented: $showingSetup, onDismiss: { savedKey = APIKeyStore.read() != nil }) {
            NavigationStack {
                ChatSettingsView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSetup = false } } }
            }
        }
    }

    /// The message that is flying out of the field, styled like its bubble.
    private var flightLabel: Text? {
        guard let id = session.flightID, case .user(let text)? = session.rows.last(where: { $0.id == id })?.kind else { return nil }
        return ChatMentionList.styled(text, names: ChatMentionList.names(model), color: .white, bold: true, padded: true)
    }

    private func send(_ input: String) {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isTyping, hasKey else { return }
        sentCount += 1
        let session = session, model = model, scope = scope
        let row = session.appendUserRow(input.trimmingCharacters(in: .whitespacesAndNewlines), animated: !reduceMotion) { draft = "" }
        Task {
            let outputs = await session.send(input, model: model, scope: scope, appended: row)
            // VoiceOver users hear the reply arrive without hunting for it.
            if case .text(let reply)? = outputs.first(where: { if case .text = $0 { true } else { false } }) {
                AccessibilityNotification.Announcement(reply).post()
            } else if case .error(let message)? = outputs.last {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }
}
