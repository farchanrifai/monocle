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

    private var isTyping: Bool { session.isTyping }
    private var scope: AnalyticsFilterScope { session.scope ?? ChatScopeMenuItems.homeScope(model) }
    private var scopeLabel: String { ChatScopeMenuItems.label(scope) }

    var body: some View {
        NavigationStack {
            ScrollView {
                ChatTranscript(model: model, session: session, send: send)
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

    private func send(_ input: String) {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isTyping, hasKey else { return }
        draft = ""
        sentCount += 1
        let session = session, model = model, scope = scope
        Task {
            let outputs = await session.send(input, model: model, scope: scope)
            // VoiceOver users hear the reply arrive without hunting for it.
            if case .text(let reply)? = outputs.first(where: { if case .text = $0 { true } else { false } }) {
                AccessibilityNotification.Announcement(reply).post()
            } else if case .error(let message)? = outputs.last {
                AccessibilityNotification.Announcement(message).post()
            }
        }
    }
}
