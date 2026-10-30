import SwiftUI

/// Full-screen chat (CHAT_SPEC §1). Apple Intelligence proposes and answers through the shared tools; only the Save button writes.
struct ChatView: View {
    @Bindable var model: AppModel
    @Bindable var session: ChatSession
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var sentCount = 0
    @FocusState private var inputFocused: Bool
    /// Read when the screen opens: Apple Intelligence can be turned on, or finish downloading, while the app runs.
    @State private var unavailable = ChatSession.unavailableReason
    @State private var mentionSelection = 0
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isTyping: Bool { session.isTyping }
    private var scope: AnalyticsFilterScope { session.scope ?? ChatScopeMenuItems.homeScope(model) }
    private var scopeLabel: String { ChatScopeMenuItems.label(scope) }

    var body: some View {
        NavigationStack {
            ScrollView {
                ChatTranscript(model: model, session: session, send: send, fill: { draft = $0; inputFocused = true })
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
            }
            .background(Color.chatCanvas) // one canvas behind the list, under both safe areas
            .scrollPosition($scrollPosition)
            .defaultScrollAnchor(.bottom)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.always)
            // Tapping the transcript dismisses the keyboard; buttons inside rows still win the tap.
            .onTapGesture { inputFocused = false }
            // Over the transcript, not the bar: the bar only takes taps inside its own frame. The bar's inset puts it just above the composer.
            .overlay(alignment: .bottom) {
                if unavailable == nil {
                    ChatMentionList(model: model, session: session, draft: $draft, selection: $mentionSelection)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                }
            }
            // The composer is a bar, so the transcript rests above it and blurs under it with the native soft edge.
            .safeAreaBar(edge: .bottom) {
                Group {
                  if unavailable == nil {
                    ChatInputBar(text: $draft, focused: $inputFocused, isBusy: isTyping, names: ChatMentionList.names(model), onSend: { send(draft) })
                  } else {
                    Text(unavailable ?? "")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("chatUnavailable")
                  }
                }
            }
            .environment(\.chatFlightID, session.flightID)
            .sensoryFeedback(.impact(weight: .light), trigger: sentCount)
            .navigationTitle("anka")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("anka").font(.headline)
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
        .scrollEdgeEffectStyle(.soft, for: .all)
        .onAppear {
            if session.scope == nil { session.scope = ChatScopeMenuItems.homeScope(model) }
            unavailable = ChatSession.unavailableReason
            takePrefill()
        }
        .onChange(of: model.chatPrefill) { _, _ in takePrefill() }
    }

    /// A `anka://chat?q=` question lands in the composer; the owner taps Send.
    private func takePrefill() {
        guard let text = model.chatPrefill else { return }
        draft = text
        model.chatPrefill = nil
    }

    private func send(_ input: String) {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isTyping, unavailable == nil else { return }
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
