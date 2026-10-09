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

/// Sidebar settings, matching the main window's sidebar rather than a toolbar of tabs.
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
            .navigationSplitViewColumnWidth(190)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .formStyle(.grouped)
                .navigationTitle(pane.title)
                .id(pane) // the detail column otherwise keeps showing the first pane
        }
        .frame(width: 760, height: 540)
        .onAppear { if selection == nil { selection = savedPane } }
        .onChange(of: selection) { _, value in if let value { savedPane = value } }
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .general:
            Form {
                Section {
                    Picker("Preferred entry mode", selection: Binding(get: { model.preferredEntryMode }, set: { model.preferredEntryMode = $0 })) {
                        Text("Manual").tag(EntryMode.keypad); Text("Text").tag(EntryMode.text)
                    }
                } footer: {
                    Text("The global shortcut opens Quick Record while Monocle is running.")
                }
            }
        case .appearance:
            Form {
                Picker("Appearance", selection: Binding(get: { model.autoAppearance ? "automatic" : model.manualAppearance == .light ? "light" : "dark" }, set: { value in
                    if value == "automatic" { model.autoAppearance = true }
                    else { model.manualAppearance = value == "light" ? .light : .dark }
                })) { Text("Automatic").tag("automatic"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                    .pickerStyle(.segmented)
            }
        case .shortcuts:
            ShortcutSettings(state: state)
        case .security:
            Form {
                Section {
                    Picker("App lock", selection: Binding(get: { model.settings.appLockTimeout }, set: { value in
                        Task { if case .failure(let error) = await model.setAppLockTimeout(value) { lockError = error.localizedDescription } }
                    })) {
                        Text("Off").tag(AppLockTimeout?.none)
                        ForEach(AppLockTimeout.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                } footer: {
                    Text("Uses Touch ID or your Mac login password.")
                    if let lockError { Text(lockError).foregroundStyle(.red) }
                }
            }
        case .chat:
            ChatSettingsView()
        case .data:
            Form {
                Section {
                    LabeledContent("CSV") {
                        Button("Import…") { state.perform(.importCSV) }
                        Button("Export…") { state.perform(.exportCSV) }
                    }
                    LabeledContent("Backup") {
                        Button("Export…") { state.perform(.exportBackup) }
                        Button("Restore…") { state.perform(.restoreBackup) }
                    }
                } footer: {
                    Text("Backups use the same format as Monocle for iPhone.")
                }
            }
        }
    }
}

private struct ShortcutSettings: View {
    @Bindable var state: MacAppState
    @State private var recording: MacCommandID?
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                ForEach(MacCommandID.allCases) { id in
                    LabeledContent(title(for: id)) {
                        if recording == id {
                            KeyChordRecorder { chord in assign(chord, to: id) }.frame(width: 130, height: 24)
                        } else {
                            Button(state.shortcut(for: id)?.displayName ?? "None") { recording = id; error = nil }
                                .frame(minWidth: 110)
                        }
                    }
                }
            } header: {
                Text("Click a shortcut, then press a key with modifiers.")
            } footer: {
                if let error { Text(error).foregroundStyle(.red) }
                Text("Quit, Hide, Close, Undo, Cut, Copy, Paste, and Select All keep their standard macOS shortcuts.")
            }
            Section {
                Button("Restore Defaults") { state.resetShortcuts(); error = nil; recording = nil }
            }
        }
    }

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
