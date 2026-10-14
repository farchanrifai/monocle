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
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @State private var composerHeight: CGFloat = 0
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
            .scrollPosition($scrollPosition)
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
                    ChatInputBar(text: $draft, focused: $inputFocused, isBusy: isTyping, names: ChatMentionList.names(model), onSend: { send(draft) })
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
        .onAppear {
            if session.scope == nil { session.scope = ChatScopeMenuItems.homeScope(model) }
            takePrefill()
        }
        .onChange(of: model.chatPrefill) { _, _ in takePrefill() }
        .sheet(isPresented: $showingSetup, onDismiss: { savedKey = APIKeyStore.read() != nil }) {
            NavigationStack {
                ChatSettingsView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSetup = false } } }
            }
        }
    }

    /// A `monocle://chat?q=` question lands in the composer; the owner taps Send.
    private func takePrefill() {
        guard let text = model.chatPrefill else { return }
        draft = text
        model.chatPrefill = nil
    }

    private func send(_ input: String) {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isTyping, hasKey else { return }
        sentCount += 1
        let session = session, model = model
        let scope = ChatScopeMenuItems.applyMention(in: input, session: session, model: model)
        let row = session.appendUserRow(input.trimmingCharacters(in: .whitespacesAndNewlines), animated: !reduceMotion) { draft = "" }
        // Sending from higher up the conversation brings you back to the bottom, where the new message and its reply appear.
        withAnimation(reduceMotion ? nil : .smooth) { scrollPosition.scrollTo(edge: .bottom) }
        Task { // once more after layout, so the new bubble's height is counted
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(reduceMotion ? nil : .smooth) { scrollPosition.scrollTo(edge: .bottom) }
        }
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
