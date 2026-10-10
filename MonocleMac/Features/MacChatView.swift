import AppKit
import SwiftUI

/// Chat as a sidebar destination: the shared transcript in a readable column, input pinned to the bottom.
struct MacChatView: View {
    @Bindable var state: MacAppState
    @AppStorage("chatEnabled") private var chatEnabled = false
    @AppStorage("chatBackend") private var backend = "claude"
    @State private var savedKey = Self.keyAvailable
    private var hasKey: Bool { savedKey || backend == "apple" }
    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    private var model: AppModel { state.model }
    private var session: ChatSession { state.model.chat }
    private var scope: AnalyticsFilterScope { session.scope ?? ChatScopeMenuItems.homeScope(model) }
    private var canSend: Bool { !session.isTyping && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            if chatEnabled && hasKey {
                ScrollView {
                    ChatTranscript(model: model, session: session, send: send)
                        .frame(maxWidth: 720)
                        .padding(.horizontal, 24).padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .safeAreaInset(edge: .bottom, spacing: 0) { inputBar }
            } else {
                ContentUnavailableView {
                    Label(chatEnabled ? "Add Your API Key" : "AI Chat Is Off", systemImage: "bubble.left.and.text.bubble.right")
                } description: {
                    Text(chatEnabled ? "Save your Anthropic API key, or switch Model to Apple Intelligence, in Settings ▸ AI Chat." : "Turn on chat in Settings ▸ AI Chat.")
                } actions: {
                    Button("Open Settings…") { state.perform(.settings) }
                        .buttonStyle(.borderedProminent).tint(MC.red)
                        .accessibilityIdentifier("chatSetup")
                }
                .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle("Chat")
        .onAppear {
            if session.scope == nil { session.scope = ChatScopeMenuItems.homeScope(model) }
            inputFocused = true
        }
        // Back from the Settings window: pick up a newly saved or removed key.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            savedKey = Self.keyAvailable
        }
    }

    private static var keyAvailable: Bool {
        #if DEBUG
        if ChatSession.usesFakeClaude { return true }
        #endif
        return APIKeyStore.read() != nil
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Chat").font(.largeTitle.bold())
            Menu { ChatScopeMenuItems(model: model, session: session) } label: { Text(ChatScopeMenuItems.label(scope)) }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Scope: \(ChatScopeMenuItems.label(scope))")
                .accessibilityIdentifier("chatScopeMenu")
            Spacer()
            Button("Clear Chat", systemImage: "trash") { session.clear(); session.scope = ChatScopeMenuItems.homeScope(model) }
                .disabled(session.rows.isEmpty || session.isTyping)
        }
        .padding(.horizontal, 24).padding(.top, 24).padding(.bottom, 8)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Return sends; Option-Return adds a line.
            TextField("Add an expense or ask…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit { send(draft) }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
                .accessibilityIdentifier("chatInput")
            Button { send(draft) } label: {
                Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(canSend ? MC.red : Color.secondary.opacity(0.4), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .accessibilityLabel("Send")
            .accessibilityIdentifier("chatSend")
        }
        .frame(maxWidth: 720)
        .padding(.horizontal, 24).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func send(_ input: String) {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !session.isTyping, hasKey else { return }
        draft = ""
        let session = session, model = model, scope = scope
        Task {
            let outputs = await session.send(input, model: model, scope: scope)
            if case .text(let reply)? = outputs.first(where: { if case .text = $0 { true } else { false } }) {
                AccessibilityNotification.Announcement(reply).post()
            }
        }
    }
}
