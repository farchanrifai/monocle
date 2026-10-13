import AppKit
import SwiftUI

/// Chat as a sidebar destination: the shared transcript in a readable column, input pinned to the bottom.
/// `compact` is the Quick Chat panel: same session and transcript, a slimmer header with "Open in Monocle".
struct MacChatView: View {
    @Bindable var state: MacAppState
    var compact = false
    var close: (() -> Void)? = nil
    @AppStorage("chatEnabled") private var chatEnabled = false
    @AppStorage("chatBackend") private var backend = "claude"
    @State private var savedKey = Self.keyAvailable
    private var hasKey: Bool { savedKey || backend == "apple" }
    @State private var draft = ""
    @State private var mentionSelection = 0
    @FocusState private var inputFocused: Bool
    @State private var fieldFrame: CGRect = .zero
    @State private var flightX: CGFloat = 0
    @State private var flightY: CGFloat = 0
    @State private var composerHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                        .padding(.horizontal, gutter).padding(.vertical, compact ? 8 : 16)
                        // The composer floats over the transcript; this keeps the last bubble resting above it.
                        // (Real padding: contentMargins is ignored when the content is shorter than the view, which hid a first bubble behind the composer.)
                        .padding(.bottom, composerHeight)
                        .frame(maxWidth: .infinity)
                }
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .overlay(alignment: .bottom) {
                    inputBar
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerHeight = $0 }
                    .overlay(alignment: .top) {
                        ChatMentionList(model: model, session: session, draft: $draft, selection: $mentionSelection)
                            .frame(maxWidth: 720).padding(.horizontal, gutter).frame(maxWidth: .infinity)
                            .alignmentGuide(.top) { $0[.bottom] + 4 }
                    }
                }
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
        .environment(\.chatFlightID, session.flightID)
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
        .navigationTitle("Chat")
        .onExitCommand { close?() } // Esc hides the Quick Chat panel
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

    /// The message that is flying out of the field, styled like its bubble.
    private var flightLabel: Text? {
        guard let id = session.flightID, case .user(let text)? = session.rows.last(where: { $0.id == id })?.kind else { return nil }
        return ChatMentionList.styled(text, names: ChatMentionList.names(model), color: .white, bold: true, padded: true)
    }

    private var gutter: CGFloat { compact ? 16 : 24 }

    private var clearButton: some View {
        Button("Clear Chat", systemImage: "trash") { session.clear(); session.scope = ChatScopeMenuItems.homeScope(model) }
            .disabled(session.rows.isEmpty || session.isTyping)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if !compact { Text("Chat").font(.largeTitle.bold()) }
            Menu { ChatScopeMenuItems(model: model, session: session) } label: { Text(ChatScopeMenuItems.label(scope)) }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Scope: \(ChatScopeMenuItems.label(scope))")
                .accessibilityIdentifier("chatScopeMenu")
            Spacer()
            if compact {
                Button("Open in Monocle", systemImage: "macwindow") { state.openChatInApp() }
                    .help("Continue this conversation in the main window")
                    .accessibilityIdentifier("quickChatOpenApp")
            }
            if compact {
                clearButton.labelStyle(.iconOnly).help("Clear Chat")
            } else {
                clearButton
            }
        }
        .padding(.horizontal, gutter).padding(.top, compact ? 4 : 24).padding(.bottom, 8)
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Return sends; Option-Return adds a line.
            MentionTextField(prompt: "Add an expense or ask… (@ card, # category)", text: $draft, names: ChatMentionList.names(model))
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($inputFocused)
                // Return picks the highlighted @ or # suggestion while one is showing.
                .onSubmit { if !ChatMentionList.pickSelected(mentionSelection, model: model, session: session, draft: &draft) { send(draft) } }
                // Tab confirms the highlighted suggestion too; with no list showing it keeps moving focus.
                .onKeyPress(.tab) { ChatMentionList.pickSelected(mentionSelection, model: model, session: session, draft: &draft) ? .handled : .ignored }
                .onKeyPress(.downArrow) { ChatMentionList.move(1, selection: &mentionSelection, model: model, session: session, draft: draft) ? .handled : .ignored }
                .onKeyPress(.upArrow) { ChatMentionList.move(-1, selection: &mentionSelection, model: model, session: session, draft: draft) ? .handled : .ignored }
                .padding(.horizontal, 14).padding(.vertical, 10)
                // Where a sent bubble starts: its shape grows out of this field (ChatFlight).
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("chat")) } action: { fieldFrame = $0 }
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
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
        .padding(.horizontal, gutter).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) {
            ProgressiveBlur(edge: .bottom, solid: 36, fade: 40, tint: Color(nsColor: .windowBackgroundColor))
        }
    }

    private func send(_ input: String) {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !session.isTyping, hasKey else { return }
        let session = session, model = model
        let scope = ChatScopeMenuItems.applyMention(in: input, session: session, model: model)
        let row = session.appendUserRow(input.trimmingCharacters(in: .whitespacesAndNewlines), animated: !reduceMotion) { draft = "" }
        Task {
            let outputs = await session.send(input, model: model, scope: scope, appended: row)
            if case .text(let reply)? = outputs.first(where: { if case .text = $0 { true } else { false } }) {
                AccessibilityNotification.Announcement(reply).post()
            }
        }
    }
}

/// Esc closes the panel even when nothing in it has focus (e.g. the "AI Chat Is Off" state).
final class QuickChatPanel: NSPanel {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

/// The global Quick Chat window: a floating, non-activating panel like Quick Record, showing the same
/// ChatSession as the Chat page, so a conversation started here continues in the main window.
@MainActor
final class QuickChatPanelController {
    private unowned let state: MacAppState
    private var panel: NSPanel?
    private static let autosaveName = "QuickChatPanel"

    init(state: MacAppState) { self.state = state }

    /// The shortcut toggles: pressed again while the panel is in front, it hides.
    func show() {
        if let panel, panel.isVisible, panel.isKeyWindow { close(); return }
        let panel = panel ?? makePanel()
        if let scheme = state.model.preferredColorScheme {
            panel.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        } else {
            panel.appearance = nil
        }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            QuickRecordPanelController.centerOnScreen(panel)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        // Style bits go in at creation: changing styleMask later re-shows the title bar buttons and drops the
        // non-activating behaviour, which activated Monocle and fronted the main window on first open.
        let value = QuickRecordPanelController.makePanel(QuickChatPanel.self, extraStyle: [.resizable, .closable])
        value.minSize = NSSize(width: 420, height: 420)
        let controller = NSHostingController(rootView:
            MacChatView(state: state, compact: true, close: { [weak self] in self?.close() })
                .preferredColorScheme(state.model.preferredColorScheme)
                .overlay(alignment: .top) { // "monocle" centred in the transparent title bar, as on Quick Record
                    GeometryReader { proxy in
                        Text("monocle").font(.headline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).frame(height: proxy.safeAreaInsets.top)
                            .offset(y: -proxy.safeAreaInsets.top)
                    }.accessibilityHidden(true)
                }
        )
        controller.sizingOptions = [] // the panel's own (remembered) size wins; the chat fills it
        value.contentViewController = controller
        value.setContentSize(NSSize(width: 560, height: 640))
        if !value.setFrameUsingName(Self.autosaveName) { QuickRecordPanelController.centerOnScreen(value) }
        value.setFrameAutosaveName(Self.autosaveName)
        panel = value
        return value
    }
}
