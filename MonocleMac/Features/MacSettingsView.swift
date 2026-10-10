import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, shortcuts, security, chat, data
    var id: Self { self }
    var title: String {
        switch self {
        case .general: "General"; case .appearance: "Appearance"; case .shortcuts: "Shortcuts"
        case .security: "Security"; case .chat: "AI Chat"; case .data: "Data"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"; case .appearance: "circle.lefthalf.filled"; case .shortcuts: "keyboard"
        case .security: "lock"; case .chat: "bubble.left.and.text.bubble.right"; case .data: "externaldrive"
        }
    }
}

/// Sidebar settings in the System Settings / Dia layout: translucent sidebar, and panes as centred column forms
/// (right-aligned "Label:" column, controls on the left edge of the second column).
struct MacSettingsView: View {
    @Bindable var state: MacAppState
    @Bindable private var model: AppModel
    @State private var lockError: String?
    @AppStorage("MacSettingsPane") private var savedPane: SettingsPane = .general
    @State private var selection: SettingsPane?
    private var pane: SettingsPane { selection ?? savedPane }

    init(state: MacAppState) { self.state = state; model = state.model }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: $selection) { pane in
                Label(pane.title, systemImage: pane.symbol).tag(pane)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            ScrollView {
                detail
                    .formStyle(.columns)
                    .padding(.horizontal, 40).padding(.top, 28).padding(.bottom, 40)
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle(pane.title)
            .id(pane) // the detail column otherwise keeps showing the first pane
        }
        .frame(width: 780, height: 560)
        .onAppear { if selection == nil { selection = savedPane } }
        .onChange(of: selection) { _, value in if let value { savedPane = value } }
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .general:
            Form {
                Picker("Entry mode:", selection: Binding(get: { model.preferredEntryMode }, set: { model.preferredEntryMode = $0 })) {
                    Text("Manual").tag(EntryMode.keypad); Text("Text").tag(EntryMode.text)
                }
                .pickerStyle(.radioGroup)
                SettingsNote("Quick Add (\(state.shortcut(for: .quickRecord)?.displayName ?? "no shortcut")) and Quick Chat (\(state.shortcut(for: .quickChat)?.displayName ?? "no shortcut")) open from anywhere while Monocle is running.")
            }
        case .appearance:
            Form {
                Picker("Appearance:", selection: Binding(get: { model.autoAppearance ? "automatic" : model.manualAppearance == .light ? "light" : "dark" }, set: { value in
                    if value == "automatic" { model.autoAppearance = true }
                    else { model.manualAppearance = value == "light" ? .light : .dark }
                })) { Text("Automatic").tag("automatic"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                    .pickerStyle(.radioGroup)
            }
        case .shortcuts:
            ShortcutSettings(state: state)
        case .security:
            Form {
                Picker("Lock Monocle:", selection: Binding(get: { model.settings.appLockTimeout }, set: { value in
                    Task { if case .failure(let error) = await model.setAppLockTimeout(value) { lockError = error.localizedDescription } }
                })) {
                    Text("Never").tag(AppLockTimeout?.none)
                    ForEach(AppLockTimeout.allCases) { Text($0.title).tag(Optional($0)) }
                }
                .fixedSize()
                SettingsNote("Unlock with Touch ID or your Mac login password.")
                if let lockError { SettingsNote(lockError).foregroundStyle(.red) }
            }
        case .chat:
            ChatSettingsPane()
        case .data:
            Form {
                LabeledContent("CSV:") {
                    HStack { Button("Import…") { state.perform(.importCSV) }; Button("Export…") { state.perform(.exportCSV) } }
                }
                LabeledContent("Backup:") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Button("Export…") { state.perform(.exportBackup) }; Button("Restore…") { state.perform(.restoreBackup) } }
                        SettingsNote("Backups use the same format as Monocle for iPhone.")
                    }
                }
            }
        }
    }
}

/// Secondary explanation under a control, wrapped to the control column.
private struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
            .frame(maxWidth: 360, alignment: .leading).fixedSize(horizontal: false, vertical: true)
    }
}

/// Opt-in, disclosure and personal API key (CHAT_SPEC §0 rule 6, §9); the iPhone has its own sheet.
private struct ChatSettingsPane: View {
    @AppStorage("chatEnabled") private var chatEnabled = false
    @AppStorage("chatBackend") private var backend = "claude"
    @State private var keyDraft = ""
    @State private var hasKey = APIKeyStore.read() != nil

    var body: some View {
        Form {
            LabeledContent("AI Chat:") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Enable AI chat", isOn: $chatEnabled).accessibilityIdentifier("chatEnabledToggle")
                    Picker("Model", selection: $backend) {
                        Text("Claude").tag("claude")
                        Text("Apple Intelligence").tag("apple")
                    }
                    .fixedSize()
                    SettingsNote(backend == "apple"
                                 ? (AppleChatAgent.unavailableReason ?? "Chat runs on this Mac with Apple Intelligence; nothing leaves the device. Expenses are only saved when you click Save.")
                                 : "Your messages, plus the spending data needed to answer them (amounts, dates, notes, category and card names), are sent to Anthropic's Claude. Nothing is sent until you use chat, and expenses are only saved when you click Save.")
                }
            }
            if backend == "claude" { LabeledContent("API key:") {
                VStack(alignment: .leading, spacing: 8) {
                    if hasKey {
                        HStack {
                            Label("Saved in Keychain", systemImage: "checkmark.seal.fill").foregroundStyle(.secondary)
                            Button("Remove") { APIKeyStore.delete(); hasKey = false }
                        }
                    } else {
                        HStack {
                            SecureField("API key", text: $keyDraft, prompt: Text("sk-ant-…")).labelsHidden().frame(width: 240)
                                .accessibilityIdentifier("chatAPIKeyField")
                                .onSubmit(save)
                            Button("Save", action: save)
                                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    SettingsNote("Stored in the Keychain on this Mac only. Create one at platform.claude.com.")
                }
            } }
        }
    }

    private func save() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        hasKey = APIKeyStore.save(key)
        keyDraft = ""
    }
}

private struct ShortcutSettings: View {
    @Bindable var state: MacAppState
    @State private var recording: MacCommandID?
    @State private var error: String?

    var body: some View {
        Form {
            ForEach(Self.groups, id: \.self) { group in
                Section {
                    if group != Self.groups.first { Color.clear.frame(height: 14) } // column forms ignore Section spacing
                    ForEach(group) { id in
                        LabeledContent("\(title(for: id)):") {
                            if recording == id {
                                KeyChordRecorder { chord in assign(chord, to: id) }.frame(width: 110, height: 22)
                            } else {
                                Button { recording = id; error = nil } label: {
                                    Text(state.shortcut(for: id)?.displayName ?? "None").frame(width: 90)
                                }
                            }
                        }
                    }
                }
            }
            LabeledContent("") {
                VStack(alignment: .leading, spacing: 8) {
                    if let error { SettingsNote(error).foregroundStyle(.red) }
                    SettingsNote("Click a shortcut, then press a key with modifiers. Quit, Hide, Close, Undo, Cut, Copy, Paste, and Select All keep their standard macOS shortcuts.")
                    Button("Restore Defaults") { state.resetShortcuts(); error = nil; recording = nil }
                }
                .padding(.top, 12)
            }
        }
    }

    // Spacing between groups instead of one long wall of rows.
    private static let groups: [[MacCommandID]] = [
        [.commandBar, .newExpense, .quickRecord, .quickChat, .focusSearch, .toggleSidebar, .toggleInspector],
        [.overview, .activity, .budgets, .bills, .analytics, .cards, .chat],
        [.importCSV, .exportCSV, .exportBackup, .restoreBackup, .settings, .lock]
    ]

    private func title(for id: MacCommandID) -> String {
        id == .commandBar ? "Command Bar" : state.commands.first(where: { $0.commandID == id })?.title ?? id.rawValue
    }
    private func assign(_ chord: KeyChord, to id: MacCommandID) {
        do { try state.setShortcut(chord, for: id); recording = nil; error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private struct KeyChordRecorder: NSViewRepresentable {
    let captured: (KeyChord) -> Void
    func makeNSView(context: Context) -> RecorderView { let view = RecorderView(); view.captured = captured; DispatchQueue.main.async { view.window?.makeFirstResponder(view) }; return view }
    func updateNSView(_ view: RecorderView, context: Context) { view.captured = captured; DispatchQueue.main.async { view.window?.makeFirstResponder(view) } }

    @MainActor final class RecorderView: NSView {
        var captured: ((KeyChord) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.controlBackgroundColor.setFill(); bounds.fill()
            let value = "Press shortcut…" as NSString
            value.draw(at: NSPoint(x: 8, y: 5), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor])
            NSColor.keyboardFocusIndicatorColor.setStroke(); NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).stroke()
        }
        override func keyDown(with event: NSEvent) {
            let named: [UInt16: String] = [36: "return", 53: "escape", 49: "space", 123: "left", 124: "right", 125: "down", 126: "up"]
            let key = named[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased()
            guard let key, !key.isEmpty else { NSSound.beep(); return }
            var modifiers: KeyModifiers = []
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags.contains(.command) { modifiers.insert(.command) }
            if flags.contains(.option) { modifiers.insert(.option) }
            if flags.contains(.control) { modifiers.insert(.control) }
            if flags.contains(.shift) { modifiers.insert(.shift) }
            captured?(KeyChord(key, modifiers: modifiers))
        }
    }
}
