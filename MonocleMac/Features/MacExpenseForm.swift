import AppKit
import SwiftUI

/// The one expense form: a sheet in the app (New, Edit, Repeat) and a floating panel for the global Quick Record hotkey.
/// Keyboard first: focus starts at the top, Tab reaches every control (even with macOS Keyboard Navigation off),
/// only ⌘↩ saves so a stray Return never records anything, Esc closes.
struct MacExpenseForm: View {
    @Bindable var model: AppModel
    let title: String
    var topPadding: CGFloat = 24
    let close: (Bool) -> Void
    @FocusState private var focus: MacEntryField?
    @State private var message: String?
    @State private var saved = false
    @State private var showDiscardConfirmation = false

    private var showsQuick: Bool { model.isEntryFieldShown(.quick) && !model.draft.editing }
    private var firstFocus: MacEntryField { showsQuick ? .text : .amount }
    private var isForeign: Bool { model.draft.isForeign(reporting: model.reportingCurrency) }
    private let shortcutHelp = "Tab next · Space or ↑↓ opens a list · ⌘↩ save · ⌘⇧S split · Esc close"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                    .help(shortcutHelp)
                    .accessibilityLabel("Keyboard shortcuts").accessibilityHint(shortcutHelp)
            }

            if showsQuick {
                HStack(spacing: 8) {
                    Image(systemName: "text.cursor").foregroundStyle(.secondary)
                    TextField("Type “coffee 28k” and press Return", text: $model.draft.text)
                        .textFieldStyle(.plain)
                        .focused($focus, equals: .text)
                        .onSubmit { parseText() }
                        .accessibilityLabel("Expense description and amount")
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(.quaternary.opacity(0.5), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(model.draft.currency ?? model.reportingCurrency).font(.title3.weight(.medium)).foregroundStyle(.secondary)
                    TextField("0", text: $model.draft.amount)
                        .textFieldStyle(.plain)
                        .font(.system(size: 34, weight: .semibold, design: .rounded)).monospacedDigit()
                        .focused($focus, equals: .amount)
                        .accessibilityLabel("Amount")
                        .accessibilityIdentifier("expenseAmount")
                    if model.isEntryFieldShown(.currency) || isForeign {
                        PopUpPicker(title: "Currency", options: currencyChoices.map { .init(id: $0, name: $0, symbol: nil) },
                                    selection: Binding(get: { model.draft.currency ?? model.reportingCurrency }, set: { code in
                                        guard let code else { return }
                                        model.draft.currency = code == model.reportingCurrency ? nil : code
                                        model.draft.rate = ""; model.draft.rateSource = nil
                                    }))
                            .frame(width: 92) // a real popup so Tab reaches it; a SwiftUI Picker is skipped without Keyboard Navigation
                    }
                }
                if isForeign { // a hidden currency field still shows when the expense already has one
                    HStack(spacing: 6) {
                        Text("1 \(model.draft.currency ?? "") =").foregroundStyle(.secondary)
                        TextField("Rate", text: Binding(get: { model.draft.rate }, set: { model.draft.rate = $0; model.draft.rateSource = .manual }))
                            .textFieldStyle(.roundedBorder).frame(width: 100)
                        Text(model.reportingCurrency).foregroundStyle(.secondary)
                        if let expense = try? model.draft.expense(reporting: model.reportingCurrency) {
                            Text("≈ \(Money.format(expense.amount, code: model.reportingCurrency))").foregroundStyle(.secondary)
                        } else if let rateError = model.rateError {
                            Text(rateError).font(.caption).foregroundStyle(.red).lineLimit(2)
                        }
                    }.font(.callout)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 1) {
                ForEach(model.entryRowOrder, id: \.self) { detailRow($0) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if model.draft.isSplit {
                MacSplitEditor(model: model, focus: $focus)
            }

            if let message { Text(message).font(.caption).foregroundStyle(saved ? .green : .red).accessibilityLabel(message) }

            HStack {
                if model.isEntryFieldShown(.split) || model.draft.isSplit {
                    Button(model.draft.isSplit ? "Stop Splitting" : "Split…") { toggleSplit() }
                        .keyboardShortcut("s", modifiers: [.command, .shift])
                        .help("⌘⇧S")
                }
                Spacer()
                Button("Cancel", role: .cancel) { requestClose() }
                    .keyboardShortcut(.cancelAction)
                Button(model.draft.editing ? "Save Changes" : "Add") { save() }
                    .buttonStyle(.glassProminent).tint(.red)
                    .keyboardShortcut(.return, modifiers: .command)
                    .accessibilityIdentifier("recordExpense")
                    .disabled(saved)
            }
        }
        .padding(24).padding(.top, topPadding - 24)
        .frame(width: 540)
        .defaultFocus($focus, firstFocus)
        .task(id: "\(model.draft.currency ?? "")|\(model.draft.civilDay)") { await model.refreshDraftRate() }
        .onAppear {
            model.prefillDraftDefaults()
            DispatchQueue.main.async { focus = firstFocus } // the top field, every time
        }
        .confirmationDialog("Keep this draft?", isPresented: $showDiscardConfirmation) {
            Button("Keep Draft and Close") { model.persistDraft(); close(false) }
            Button("Discard Draft", role: .destructive) { if model.discardDraft() { close(false) } }
            Button("Continue Editing", role: .cancel) {}
        } message: { Text("Your entered details can be kept for the next time you add an expense.") }
    }

    private var currencyChoices: [String] {
        var seen = Set<String>()
        let cards = model.cards.flatMap { [$0.currency, $0.spendingCurrency].compactMap { $0 } }
        return ([model.reportingCurrency] + cards + Money.commonCurrencies).filter { seen.insert($0).inserted }
    }

    @ViewBuilder private func detailRow(_ kind: EntryFormRow) -> some View {
        switch kind {
        case .category:
            if !model.draft.isSplit {
                row("Category") {
                    PopUpPicker(title: "Category", placeholder: "Choose…",
                                options: model.activeCategories.map { .init(id: $0.id, name: $0.name, symbol: $0.symbol) },
                                selection: $model.draft.categoryID)
                }
            }
        case .card:
            row("Card") {
                PopUpPicker(title: "Card", options: model.cards.map { .init(id: $0.id, name: $0.name, symbol: "creditcard.fill") },
                            selection: Binding(get: { model.draft.cardID ?? model.activeCardID }, set: { id in
                                guard let id else { return }
                                _ = model.selectCard(id); model.draft.cardID = id
                                if !model.draft.editing {
                                    model.draft.paidWithID = nil
                                    if model.draft.amount.isEmpty { model.draft.currency = nil }
                                    model.prefillDraftDefaults()
                                }
                            }))
            }
        case .paidWith:
            if (model.isEntryFieldShown(.paidWith) && !model.paymentMethods.isEmpty) || model.paymentMethod(model.draft.paidWithID) != nil {
                row("Paid with") {
                    PopUpPicker(title: "Paid with", placeholder: "Not set",
                                options: model.paymentMethods.map { .init(id: $0.id, name: $0.name, symbol: $0.kind.symbol) },
                                selection: $model.draft.paidWithID)
                }
            }
        case .note:
            if model.isEntryFieldShown(.note) || !model.draft.note.isEmpty {
                row("Note") {
                    TextField("Optional", text: $model.draft.note)
                        .textFieldStyle(.plain).multilineTextAlignment(.trailing)
                        .focused($focus, equals: .note)
                        .accessibilityIdentifier("expenseNote")
                }
            }
        case .date:
            if model.isEntryFieldShown(.date) || model.draft.civilDay != Day.string(.now) {
                row("Date") { MacDateField(date: $model.draft.date, focus: $focus) }
            }
        }
    }

    /// One line of the grouped fields: label left, control right.
    private func row(_ label: String, @ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            content().frame(maxWidth: 280, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5))
    }

    @discardableResult private func parseText() -> Bool {
        do {
            let parsed = try ExpenseParser.parse(model.draft.text, categories: model.activeCategories, rules: model.settings.categoryRules)
            model.draft.amount = Money.digits(parsed.amount)
            model.draft.note = parsed.note
            model.draft.categoryID = parsed.categoryID ?? model.draft.categoryID
            model.draft.source = "text"
            message = parsed.categoryID == nil ? "Amount found. Choose a category." : nil
            focus = .amount
            return true
        } catch { message = error.localizedDescription; return false }
    }

    private func toggleSplit() {
        if model.draft.isSplit { model.stopSplitting(); return }
        model.beginSplitting()
        model.addSplitPart()
        if let last = model.draft.splitParts.last { focus = .splitAmount(last.id) }
    }

    private func save() {
        guard !saved else { return }
        if model.draft.amount.isEmpty, !model.draft.text.isEmpty, !parseText() { return }
        if !model.draft.isSplit, model.draft.categoryID == nil { message = "Choose a category."; return }
        guard model.saveDraft() else { message = model.error; model.error = nil; return }
        saved = true
        message = "Expense added"
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            close(true)
        }
    }

    private func requestClose() {
        if model.draftNeedsConfirmation { showDiscardConfirmation = true }
        else { close(false) }
    }
}

/// Today / Yesterday shortcuts plus the date itself. The date is one Tab stop: ← → move a day, T is today,
/// Space or Return opens the calendar.
private struct MacDateField: View {
    @Binding var date: Date
    var focus: FocusState<MacEntryField?>.Binding
    @State private var showCalendar = false
    private var calendar: Calendar { .current }
    private var yesterday: Date { calendar.date(byAdding: .day, value: -1, to: .now) ?? .now }

    var body: some View {
        HStack(spacing: 6) {
            chip("Today", on: calendar.isDateInToday(date)) { date = .now }
            chip("Yesterday", on: calendar.isDateInYesterday(date)) { date = yesterday }
            Button { showCalendar.toggle() } label: {
                Label(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()), systemImage: "calendar")
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
            .buttonStyle(.plain)
            .focusable().focused(focus, equals: .date)
            .onKeyPress(keys: [.leftArrow, .rightArrow, .space, .return, KeyEquivalent("t")]) { press in
                switch press.key {
                case .leftArrow: step(-1)
                case .rightArrow: step(1)
                case KeyEquivalent("t"): date = .now
                default: showCalendar = true
                }
                return .handled
            }
            .accessibilityLabel("Date").accessibilityHint("Left and right arrows change the day, Space opens the calendar")
            .popover(isPresented: $showCalendar, arrowEdge: .bottom) {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.graphical).labelsHidden().padding(12)
                    .focusEffectDisabled() // the popover focuses the calendar and drew a blue ring around it
            }
        }
    }

    private func chip(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain).font(.callout)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(on ? AnyShapeStyle(Color.accentColor.opacity(0.25)) : AnyShapeStyle(.quaternary), in: Capsule())
            .focusable(false) // the date field is the Tab stop
    }

    private func step(_ days: Int) { date = calendar.date(byAdding: .day, value: days, to: date) ?? date }
}

enum MacEntryField: Hashable {
    case text, amount, note, date, splitAmount(UUID)
}

private struct MacSplitEditor: View {
    @Bindable var model: AppModel
    var focus: FocusState<MacEntryField?>.Binding

    var body: some View {
        GroupBox("Split") {
            VStack(spacing: 8) {
                ForEach($model.draft.splitParts) { $split in
                    HStack {
                        PopUpPicker(title: "Category", options: model.activeCategories.map { .init(id: $0.id, name: $0.name, symbol: $0.symbol) },
                                    selection: Binding(get: { split.categoryID }, set: { if let id = $0 { split.categoryID = id } }))
                        TextField("Amount", text: $split.amount)
                            .textFieldStyle(.roundedBorder).frame(width: 140)
                            .focused(focus, equals: .splitAmount(split.id))
                        Button { remove(split.id) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).accessibilityLabel("Remove split")
                    }
                }
                HStack {
                    Button("Add Line") { add() }.keyboardShortcut("a", modifiers: [.command, .shift])
                    Spacer()
                    // ⌘⌫ removes the line whose amount has focus.
                    Button("Remove Line") { if let id = focusedLine { remove(id) } }
                        .keyboardShortcut(.delete, modifiers: .command)
                        .disabled(focusedLine == nil)
                }
            }.padding(4)
        }
    }

    private var focusedLine: UUID? {
        if case .splitAmount(let id) = focus.wrappedValue { id } else { nil }
    }

    private func add() {
        model.addSplitPart()
        if let last = model.draft.splitParts.last { focus.wrappedValue = .splitAmount(last.id) }
    }

    private func remove(_ id: UUID) {
        guard let index = model.draft.splitParts.firstIndex(where: { $0.id == id }) else { return }
        model.draft.splitParts.remove(at: index)
        if model.draft.splitParts.count < 2 { model.stopSplitting(); focus.wrappedValue = .amount; return }
        focus.wrappedValue = .splitAmount(model.draft.splitParts[max(0, index - 1)].id)
    }
}

struct PopUpOption<ID: Hashable> { let id: ID; let name: String; let symbol: String? }

/// The native popup menu (opens on the full list), kept in the Tab loop. A plain Picker/NSPopUpButton only joins it
/// when macOS Keyboard Navigation is on, which is off by default. Space, ↑ or ↓ opens the menu; typing jumps within it.
struct PopUpPicker<ID: Hashable>: NSViewRepresentable {
    let title: String
    var placeholder: String? // first item, meaning "nothing chosen"
    let options: [PopUpOption<ID>]
    @Binding var selection: ID?

    init(title: String, placeholder: String? = nil, options: [PopUpOption<ID>], selection: Binding<ID?>) {
        self.title = title; self.placeholder = placeholder; self.options = options; _selection = selection
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TabbablePopUpButton {
        let button = TabbablePopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.changed(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal) // fill the row like the text fields
        button.setAccessibilityLabel(title)
        return button
    }

    func updateNSView(_ button: TabbablePopUpButton, context: Context) {
        context.coordinator.parent = self
        let menu = NSMenu()
        if let placeholder { menu.addItem(item(placeholder, symbol: nil, tag: -1)) }
        for (index, option) in options.enumerated() { menu.addItem(item(option.name, symbol: option.symbol, tag: index)) }
        button.menu = menu // addItem(withTitle:) would drop duplicate names
        button.selectItem(withTag: options.firstIndex { $0.id == selection } ?? -1)
    }

    private func item(_ title: String, symbol: String?, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.tag = tag
        item.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        return item
    }

    final class Coordinator: NSObject {
        var parent: PopUpPicker
        init(_ parent: PopUpPicker) { self.parent = parent }
        @objc func changed(_ sender: NSPopUpButton) {
            let tag = sender.selectedTag()
            parent.selection = parent.options.indices.contains(tag) ? parent.options[tag].id : nil
        }
    }
}

final class TabbablePopUpButton: NSPopUpButton {
    override var canBecomeKeyView: Bool { isEnabled }
    override var acceptsFirstResponder: Bool { isEnabled }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49, 125, 126: performClick(nil) // Space, ↓, ↑: show the whole list
        default: super.keyDown(with: event)
        }
    }
}

/// The global Quick Record window: floats over whatever app is in front, full-screen ones included, without
/// activating Monocle (like Spotlight), so the main window never comes forward and focus returns on close.
@MainActor
final class QuickRecordPanelController {
    private unowned let state: MacAppState
    private var panel: NSPanel?
    private var needsCentering = false // no saved position yet

    init(state: MacAppState) { self.state = state }

    func show(title: String) {
        let panel = panel ?? makePanel()
        if panel.isVisible { panel.orderFrontRegardless(); panel.makeKey(); return }
        if let scheme = state.model.preferredColorScheme {
            panel.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        } else {
            panel.appearance = nil
        }
        panel.contentViewController = Self.makeContent(model: state.model, title: title) { [weak self] _ in self?.panel?.orderOut(nil) }
        // Remembered position (frame autosave) unless it's gone off every screen; else the middle of the screen.
        panel.layoutIfNeeded() // take the form's height before placing
        if needsCentering || !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            Self.centerOnScreen(panel); needsCentering = false
        }
        panel.orderFrontRegardless() // Monocle stays inactive, so the ordinary makeKeyAndOrderFront wouldn't order it in
        panel.makeKey()
    }

    private func makePanel() -> NSPanel {
        let value = Self.makePanel()
        needsCentering = !value.setFrameUsingName(Self.autosaveName)
        value.setFrameAutosaveName(Self.autosaveName) // saves every move the user makes
        panel = value
        return value
    }

    static func makePanel(_ type: NSPanel.Type = NSPanel.self, extraStyle: NSWindow.StyleMask = []) -> NSPanel {
        // Titled for key focus, rounded corners and shadow; non-activating so the app in front keeps being the active
        // app; the title bar is transparent with no traffic lights and the system title hidden (drawn centred instead).
        let value = type.init(contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
                            styleMask: NSWindow.StyleMask([.titled, .fullSizeContentView, .nonactivatingPanel]).union(extraStyle), backing: .buffered, defer: false)
        value.title = "monocle" // for accessibility and window lists
        value.titleVisibility = .hidden
        value.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] where !(extraStyle.contains(.closable) && button == .closeButton) { value.standardWindowButton(button)?.isHidden = true }
        value.isMovableByWindowBackground = true
        value.becomesKeyOnlyIfNeeded = false
        value.hidesOnDeactivate = false // Monocle is never the active app while this shows
        value.level = .floating
        value.isReleasedWhenClosed = false
        value.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        return value
    }

    private static let autosaveName = "QuickRecordPanel"

    /// Exact middle of the screen with the pointer (NSWindow.center() sits higher, by design).
    static func centerOnScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else { return }
        let area = screen.visibleFrame, size = window.frame.size
        window.setFrameOrigin(CGPoint(x: area.midX - size.width / 2, y: area.midY - size.height / 2))
    }

    static func makeContent(model: AppModel, title: String, close: @escaping (Bool) -> Void) -> NSViewController {
        let controller = NSHostingController(rootView:
            MacExpenseForm(model: model, title: title, topPadding: 4, close: close) // the title bar above already gives room
                .preferredColorScheme(model.preferredColorScheme)
                .overlay(alignment: .top) { // "monocle" centred in the (transparent) title bar above the form
                    GeometryReader { proxy in
                        Text("monocle").font(.headline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).frame(height: proxy.safeAreaInsets.top)
                            .offset(y: -proxy.safeAreaInsets.top)
                    }.accessibilityHidden(true)
                }
        )
        // ponytail: default sizing (min/max from the form) still grows the panel for splits. `.preferredContentSize`
        // looped window resize -> SwiftUI safe-area invalidation -> resize, and AppKit aborted (crash on open).
        return controller
    }
}
