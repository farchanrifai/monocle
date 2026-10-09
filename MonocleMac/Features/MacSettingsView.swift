import AppKit
import SwiftUI

struct MacSettingsView: View {
    @Bindable var state: MacAppState
    @Bindable private var model: AppModel
    @State private var lockError: String?

    init(state: MacAppState) { self.state = state; model = state.model }

    var body: some View {
        TabView {
            Form {
                Picker("Preferred entry mode", selection: Binding(get: { model.preferredEntryMode }, set: { model.preferredEntryMode = $0 })) {
                    Text("Manual").tag(EntryMode.keypad); Text("Text").tag(EntryMode.text)
                }
                Text("The global shortcut opens Quick Record while Monocle is running.").foregroundStyle(.secondary)
            }.formStyle(.grouped).tabItem { Label("General", systemImage: "gear") }

            Form {
                Picker("Appearance", selection: Binding(get: { model.autoAppearance ? "automatic" : model.manualAppearance == .light ? "light" : "dark" }, set: { value in
                    if value == "automatic" { model.autoAppearance = true }
                    else { model.manualAppearance = value == "light" ? .light : .dark }
                })) { Text("Automatic").tag("automatic"); Text("Light").tag("light"); Text("Dark").tag("dark") }
            }.formStyle(.grouped).tabItem { Label("Appearance", systemImage: "circle.lefthalf.filled") }

            ShortcutSettings(state: state).tabItem { Label("Shortcuts", systemImage: "keyboard") }

            Form {
                Picker("App lock", selection: Binding(get: { model.settings.appLockTimeout }, set: { value in
                    Task { if case .failure(let error) = await model.setAppLockTimeout(value) { lockError = error.localizedDescription } }
                })) {
                    Text("Off").tag(AppLockTimeout?.none)
                    ForEach(AppLockTimeout.allCases) { Text($0.title).tag(Optional($0)) }
                }
                Text("Uses Touch ID or your Mac login password.").foregroundStyle(.secondary)
                if let lockError { Text(lockError).foregroundStyle(.red) }
            }.formStyle(.grouped).tabItem { Label("Security", systemImage: "lock") }

            ChatSettingsView().tabItem { Label("AI Chat", systemImage: "bubble.left.and.text.bubble.right") }

            Form {
                Button("Import CSV…") { state.perform(.importCSV) }
                Button("Export CSV…") { state.perform(.exportCSV) }
                Button("Export Backup…") { state.perform(.exportBackup) }
                Button("Restore Backup…") { state.perform(.restoreBackup) }
                Text("Backups use the same format as Monocle for iPhone.").foregroundStyle(.secondary)
            }.formStyle(.grouped).tabItem { Label("Data", systemImage: "externaldrive") }
        }.padding(18).frame(width: 680, height: 560)
    }
}

private struct ShortcutSettings: View {
    @Bindable var state: MacAppState
    @State private var recording: MacCommandID?
    @State private var error: String?

    private let customizable: [MacCommandID] = MacCommandID.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Shortcuts").font(.title2.bold()); Spacer(); Button("Reset Defaults") { state.resetShortcuts(); error = nil } }
            Text("Select a shortcut, then press one key with modifiers. Conflicts are rejected immediately.").foregroundStyle(.secondary)
            List(customizable) { id in
                HStack {
                    Text(title(for: id)); Spacer()
                    if recording == id {
                        KeyChordRecorder { chord in assign(chord, to: id) }.frame(width: 130, height: 26)
                    } else {
                        Button(state.shortcut(for: id)?.displayName ?? "None") { recording = id; error = nil }
                            .frame(minWidth: 110)
                    }
                }.padding(.vertical, 3)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Text("Quit, Hide, Close, Undo, Cut, Copy, Paste, and Select All keep their standard macOS shortcuts.").font(.caption).foregroundStyle(.secondary)
        }.padding(8)
    }

    private func title(for id: MacCommandID) -> String {
        state.commands.first(where: { $0.commandID == id })?.title ?? id.rawValue
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
