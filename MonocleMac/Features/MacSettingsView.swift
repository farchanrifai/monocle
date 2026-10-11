import AppKit
import SwiftUI

private enum SettingsPane: String, CaseIterable, Identifiable {
    case general, paidWith, currency, appearance, shortcuts, security, chat, data
    var id: Self { self }
    var title: String {
        switch self {
        case .general: "General"; case .paidWith: "Paid with"; case .currency: "Currency"; case .appearance: "Appearance"; case .shortcuts: "Shortcuts"
        case .security: "Security"; case .chat: "AI Chat"; case .data: "Data"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"; case .paidWith: "creditcard.and.123"; case .currency: "dollarsign.arrow.circlepath"; case .appearance: "circle.lefthalf.filled"; case .shortcuts: "keyboard"
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
            detail
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
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
                Section {
                    Picker("Entry mode", selection: Binding(get: { model.preferredEntryMode }, set: { model.preferredEntryMode = $0 })) {
                        Text("Manual").tag(EntryMode.keypad); Text("Text").tag(EntryMode.text)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    SettingsNote("Quick Add (\(state.shortcut(for: .quickRecord)?.displayName ?? "no shortcut")) and Quick Chat (\(state.shortcut(for: .quickChat)?.displayName ?? "no shortcut")) open from anywhere while Monocle is running.")
                }
                Section {
                    ForEach(EntryFormField.allCases, id: \.self) { field in
                        Toggle(field.title, isOn: Binding(get: { model.isEntryFieldShown(field) }, set: { model.setEntryField(field, shown: $0) }))
                    }
                } header: { Text("Add Expense form") } footer: {
                    SettingsNote("Amount, card and category are always shown. A hidden field still appears when an expense already has a value for it. A hidden date means today.")
                }
            }
        case .paidWith:
            PaidWithSettingsPane(model: model)
        case .currency:
            CurrencySettingsPane(model: model)
        case .appearance:
            Form {
                Section {
                    Picker("Appearance", selection: Binding(get: { model.autoAppearance ? "automatic" : model.manualAppearance == .light ? "light" : "dark" }, set: { value in
                        if value == "automatic" { model.autoAppearance = true }
                        else { model.manualAppearance = value == "light" ? .light : .dark }
                    })) { Text("Automatic").tag("automatic"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                        .pickerStyle(.segmented)
                } footer: { SettingsNote("Automatic follows your Mac's appearance.") }
            }
        case .shortcuts:
            ShortcutSettings(state: state)
        case .security:
            Form {
                Section {
                    Picker("Lock Monocle", selection: Binding(get: { model.settings.appLockTimeout }, set: { value in
                        Task { if case .failure(let error) = await model.setAppLockTimeout(value) { lockError = error.localizedDescription } }
                    })) {
                        Text("Never").tag(AppLockTimeout?.none)
                        ForEach(AppLockTimeout.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        SettingsNote("Unlock with Touch ID or your Mac login password.")
                        if let lockError { SettingsNote(lockError).foregroundStyle(.red) }
                    }
                }
            }
        case .chat:
            ChatSettingsPane()
        case .data:
            Form {
                Section("CSV") {
                    LabeledContent("Spreadsheet") {
                        HStack { Button("Import…") { state.perform(.importCSV) }; Button("Export…") { state.perform(.exportCSV) } }
                    }
                }
                Section {
                    LabeledContent("Full backup") {
                        HStack { Button("Export…") { state.perform(.exportBackup) }; Button("Restore…") { state.perform(.restoreBackup) } }
                    }
                } header: { Text("Backup") } footer: { SettingsNote("Backups use the same format as Monocle for iPhone.") }
            }
        }
    }
}

/// Paid with labels and the active card's default. Labels never carry a balance.
private struct PaidWithSettingsPane: View {
    @Bindable var model: AppModel
    @State private var newName = ""
    @State private var error: String?
    private var card: Card? { model.cards.first { $0.id == model.activeCardID } }

    var body: some View {
        Form {
            Section {
                ForEach(model.paymentMethods) { method in
                    HStack {
                        TextField("Name", text: Binding(get: { method.name }, set: { name in
                            var value = method; value.name = name
                            do { try model.savePaymentMethod(value); error = nil } catch { self.error = error.localizedDescription }
                        })).labelsHidden()
                        Picker("Kind", selection: Binding(get: { method.kind }, set: { kind in
                            var value = method; value.kind = kind
                            do { try model.savePaymentMethod(value) } catch { self.error = error.localizedDescription }
                        })) { ForEach(PaymentMethod.Kind.allCases, id: \.self) { Text($0.title).tag($0) } }
                            .labelsHidden().fixedSize()
                        Button("Delete", role: .destructive) {
                            do { try model.deletePaymentMethod(id: method.id); error = nil } catch { self.error = error.localizedDescription }
                        }
                    }
                }
                HStack {
                    TextField("New label", text: $newName, prompt: Text("New label, like BCA debit")).labelsHidden()
                    Button("Add") {
                        do { try model.savePaymentMethod(PaymentMethod(name: newName)); newName = ""; error = nil }
                        catch { self.error = error.localizedDescription }
                    }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: { Text("Labels") } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    SettingsNote("Paid with records how you paid. Monocle never tracks balances.")
                    if let error { SettingsNote(error).foregroundStyle(.red) }
                }
            }
            if let card {
                Section("Default") {
                    Picker(card.name, selection: Binding(get: { card.defaultPaidWithID }, set: { id in
                        do { try model.setDefaultPaidWith(id, for: card.id) } catch { self.error = error.localizedDescription }
                    })) {
                        Text("None").tag(UUID?.none)
                        ForEach(model.paymentMethods) { method in Text(method.name).tag(UUID?.some(method.id)) }
                    }
                }
            }
        }
    }
}

/// Reporting currency for the workspace; budget and spending currency for the active card.
private struct CurrencySettingsPane: View {
    @Bindable var model: AppModel
    @State private var pending: String?
    @State private var working = false
    @State private var error: String?
    private var card: Card? { model.cards.first { $0.id == model.activeCardID } }
    private var choices: [String] {
        var seen = Set<String>()
        return ([model.reportingCurrency] + Money.commonCurrencies).filter { seen.insert($0).inserted }
    }

    var body: some View {
        Form {
            Section {
                Picker("Reporting currency", selection: Binding(get: { model.reportingCurrency }, set: { pending = $0 })) {
                    ForEach(choices, id: \.self) { Text($0).tag($0) }
                }.disabled(working)
            } footer: {
                SettingsNote("Stacks, analytics and widgets add up in this currency. Changing it converts every expense at the rate of its own day; a safety backup is made first.")
            }
            if let card {
                Section {
                    Picker("Budget", selection: Binding(get: { model.currency(of: card) }, set: { code in
                        run { try await model.setCardCurrencies(budget: code, spending: card.spendingCurrency, for: card.id) }
                    })) { ForEach(choices, id: \.self) { Text($0).tag($0) } }.disabled(working)
                    Picker("Spending", selection: Binding(get: { card.spendingCurrency ?? model.currency(of: card) }, set: { code in
                        run { try await model.setCardCurrencies(budget: card.currency, spending: code, for: card.id) }
                    })) { ForEach(choices, id: \.self) { Text($0).tag($0) } }.disabled(working)
                } header: { Text(card.name) } footer: {
                    SettingsNote("The budget currency is what the card's budget and totals use. New expenses start in the spending currency, and the card shows an ≈ amount in it.")
                }
            }
            if working || error != nil {
                Section {
                    if working { ProgressView().controlSize(.small) }
                    if let error { SettingsNote(error).foregroundStyle(.red) }
                }
            }
        }
        .alert("Change reporting currency to \(pending ?? "")?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Convert") { let code = pending; pending = nil; if let code { run { try await model.changeReportingCurrency(to: code) } } }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { Text("Every expense is converted at the rate of its own day. Budgets, bills and stack caps convert at today's rate. A safety backup is made first.") }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        working = true; error = nil
        Task { do { try await operation() } catch { self.error = error.localizedDescription }; working = false }
    }
}

/// Secondary explanation under a control, wrapped to the control column.
private struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.callout).foregroundStyle(.secondary) // footers inherit this colour in grouped forms
            .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
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
            Section {
                Toggle("Enable AI chat", isOn: $chatEnabled).accessibilityIdentifier("chatEnabledToggle")
                Picker("Model", selection: $backend) {
                    Text("Claude").tag("claude")
                    Text("Apple Intelligence").tag("apple")
                }
            } footer: {
                SettingsNote(backend == "apple"
                             ? (AppleChatAgent.unavailableReason ?? "Chat runs on this Mac with Apple Intelligence; nothing leaves the device. Expenses are only saved when you click Save.")
                             : "Your messages, plus the spending data needed to answer them (amounts, dates, notes, category and card names), are sent to Anthropic's Claude. Nothing is sent until you use chat, and expenses are only saved when you click Save.")
            }
            if backend == "claude" {
                Section {
                    if hasKey {
                        LabeledContent("Claude API") {
                            HStack {
                                Label("Saved in Keychain", systemImage: "checkmark.seal.fill").foregroundStyle(.secondary)
                                Button("Remove") { APIKeyStore.delete(); hasKey = false }
                            }
                        }
                    } else {
                        HStack {
                            SecureField("API key", text: $keyDraft, prompt: Text("sk-ant-…")).labelsHidden()
                                .accessibilityIdentifier("chatAPIKeyField")
                                .onSubmit(save)
                            Button("Save", action: save)
                                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                } header: { Text("API key") } footer: { SettingsNote("Stored in the Keychain on this Mac only. Create one at platform.claude.com.") }
            }
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
                    ForEach(group) { id in
                        LabeledContent(title(for: id)) {
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
            Section {
                Button("Restore Defaults") { state.resetShortcuts(); error = nil; recording = nil }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let error { SettingsNote(error).foregroundStyle(.red) }
                    SettingsNote("Click a shortcut, then press a key with modifiers. Quit, Hide, Close, Undo, Cut, Copy, Paste, and Select All keep their standard macOS shortcuts.")
                }
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
