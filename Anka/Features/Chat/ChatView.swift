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
    @State private var unavailable = ChatSession.unavailableReason(isPro: false)
    /// The message waiting while the one-time Claude question is up.
    @State private var askingClaude: String?
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
            // Tapping the transcript dismisses the keyboard; buttons inside rows still win the tap. The composer lives in the
            // safe-area bar, where clearing the focus state alone leaves the keyboard up, so the first responder resigns too.
            .onTapGesture {
                inputFocused = false
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
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
                    VStack(spacing: 10) {
                        Text(unavailable ?? "")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("chatUnavailable")
                        if !model.isPro {
                            Button("See Pro") { model.paywall = "Chat with Claude works on any iPhone, in any language." }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
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
            unavailable = ChatSession.unavailableReason(isPro: model.isPro)
            takePrefill()
        }
        .onChange(of: model.chatPrefill) { _, _ in takePrefill() }
        .sheet(isPresented: Binding(get: { askingClaude != nil }, set: { if !$0, let input = askingClaude { draft = input; askingClaude = nil } })) {
            ClaudeConsentSheet(onDevice: AppleChatAgent.unavailableReason == nil) { allowed in
                let input = askingClaude ?? ""
                askingClaude = nil
                guard let allowed else { draft = input; return }
                ClaudeConsent.choice = allowed
                unavailable = ChatSession.unavailableReason(isPro: model.isPro)
                if unavailable == nil { send(input) } else { draft = input }
            }
        }
    }

    /// A `anka://chat?q=` question lands in the composer; the owner taps Send.
    private func takePrefill() {
        guard let text = model.chatPrefill else { return }
        draft = text
        model.chatPrefill = nil
    }

    private func send(_ input: String) {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isTyping, unavailable == nil else { return }
        if ClaudeConsent.needsAsking(isPro: model.isPro) {
            askingClaude = input
            draft = ""
            return
        }
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

/// Asked once, before the first message goes to Claude (App Review 5.1.2(i)). Settings ▸ Chat with Claude changes it later.
struct ClaudeConsentSheet: View {
    /// Apple Intelligence can answer instead.
    let onDevice: Bool
    /// true: use Claude. false: keep chat on this iPhone. nil: not now (ask again next time).
    let choose: (Bool?) -> Void

    static let disclosure = "Anka Pro answers with Claude by Anthropic, on any iPhone and in any language. To answer, your message and the spending details it needs (amounts, dates, notes, category and card names) are sent to Anthropic through Anka's server. They're used only to answer you: Anka's server keeps nothing, and Anthropic doesn't use them to train its models."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill")
                .font(.system(size: 40))
                .foregroundStyle(MC.red)
            Text("Chat with Claude").font(.title2.bold())
            Text(Self.disclosure)
            Text(onDevice ? "Or keep chat on this iPhone with Apple Intelligence. You can change this in Settings." : "You can change this in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button { choose(true) } label: { Text("Use Claude").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("claudeAllow")
            Button { choose(onDevice ? false : nil) } label: { Text(onDevice ? "Keep on iPhone" : "Not now").frame(maxWidth: .infinity) }
                .controlSize(.large)
                .accessibilityIdentifier("claudeDecline")
        }
        .padding(24)
        .tint(MC.red)
        .presentationDetents([.large])
    }
}
