import AppKit
import Carbon
import Observation
import SwiftUI

enum MacDestination: Hashable {
    case overview, activity, cards, card(UUID), budgets, bills, analytics, chat

    var title: String {
        switch self {
        case .overview: "Overview"
        case .activity: "Activity"
        case .cards: "Cards"
        case .card: "Card"
        case .budgets: "Budgets"
        case .bills: "Bills"
        case .analytics: "Analytics"
        case .chat: "Chat"
        }
    }
}

enum MacInspectorSelection: Hashable {
    case expense(UUID), bill(UUID), card(UUID)
}

enum MacCommandID: String, CaseIterable, Identifiable {
    case commandBar, newExpense, quickRecord, focusSearch, toggleSidebar, toggleInspector
    case overview, activity, budgets, bills, analytics, cards, chat
    case importCSV, exportCSV, exportBackup, restoreBackup, settings, lock

    var id: String { rawValue }
}

struct MacCommand: Identifiable {
    let id: String
    let title: String
    let symbol: String
    let commandID: MacCommandID?
    let destination: MacDestination?
}

enum ShortcutValidationError: LocalizedError, Equatable {
    case needsModifier, reserved, conflict(String), unsupported

    var errorDescription: String? {
        switch self {
        case .needsModifier: "Use at least one modifier with a character key."
        case .reserved: "That shortcut is reserved by macOS."
        case .conflict(let title): "Already assigned to \(title)."
        case .unsupported: "Use one letter, number, arrow, Space, Return, or Escape."
        }
    }
}

extension KeyChord {
    static let defaults: [MacCommandID: KeyChord] = [
        .commandBar: .init("k", modifiers: .command),
        .newExpense: .init("n", modifiers: .command),
        .focusSearch: .init("f", modifiers: .command),
        .overview: .init("1", modifiers: .command),
        .activity: .init("2", modifiers: .command),
        .budgets: .init("3", modifiers: .command),
        .bills: .init("4", modifiers: .command),
        .analytics: .init("5", modifiers: .command),
        .cards: .init("6", modifiers: .command),
        .chat: .init("7", modifiers: .command),
        .toggleInspector: .init("i", modifiers: [.option, .command]),
        .quickRecord: .init("m", modifiers: [.control, .option, .command])
    ]

    var displayName: String {
        let prefix = [
            modifiers.contains(.control) ? "⌃" : "",
            modifiers.contains(.option) ? "⌥" : "",
            modifiers.contains(.shift) ? "⇧" : "",
            modifiers.contains(.command) ? "⌘" : ""
        ].joined()
        let keyName: String = switch key {
        case "return": "↩"
        case "escape": "⎋"
        case "space": "Space"
        case "left": "←"
        case "right": "→"
        case "up": "↑"
        case "down": "↓"
        default: key.uppercased()
        }
        return prefix + keyName
    }

    var eventModifiers: SwiftUI.EventModifiers {
        var result: SwiftUI.EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        return result
    }

    var keyboardShortcut: KeyboardShortcut? {
        let equivalent: KeyEquivalent
        if key.count == 1, let character = key.first { equivalent = KeyEquivalent(character) }
        else if key == "return" { equivalent = .return }
        else if key == "escape" { equivalent = .escape }
        else if key == "space" { equivalent = .space }
        else if key == "left" { equivalent = .leftArrow }
        else if key == "right" { equivalent = .rightArrow }
        else if key == "up" { equivalent = .upArrow }
        else if key == "down" { equivalent = .downArrow }
        else { return nil }
        return KeyboardShortcut(equivalent, modifiers: eventModifiers)
    }
}

@MainActor @Observable
final class MacAppState {
    let model: AppModel
    var destination: MacDestination = .overview {
        didSet {
            UserDefaults.standard.set(Self.encode(destination), forKey: "MacDestination")
            if inspectorSelection != nil { inspectorSelection = nil } // a selection from another screen has no row to match
        }
    }
    var inspectorSelection: MacInspectorSelection?
    var inspectorVisible = true { didSet { UserDefaults.standard.set(inspectorVisible, forKey: "MacInspectorVisible") } }
    var editingBill: BillRule?
    var commandBarVisible = false
    var regularEntryVisible = false
    var searchText = ""
    var searchFocusToken = UUID()
    var transferSheet: DataTransferSheet?
    var shortcutError: String?

    @ObservationIgnored private let hotKey = GlobalHotKeyController()
    @ObservationIgnored private lazy var quickPanel = QuickRecordPanelController(state: self)

    /// Observation notifies on every set, even same value, which re-renders the whole window; only write on change.
    /// Selecting never reopens a hidden inspector; `reveal` is for controls whose only job is to inspect.
    func inspect(_ selection: MacInspectorSelection?, reveal: Bool = false) {
        if inspectorSelection != selection { inspectorSelection = selection }
        if reveal, !inspectorVisible { inspectorVisible = true }
    }

    func edit(_ expense: Expense) {
        model.edit(expense); model.showEntry = false; regularEntryVisible = true
    }

    func repeatExpense(_ expense: Expense) {
        model.repeatExpense(expense); model.showEntry = false; regularEntryVisible = true
    }

    /// Deletes without confirmation; Edit ▸ Undo (⌘Z) restores, and Redo deletes again.
    func delete(_ expense: Expense, undoManager: UndoManager?) {
        model.delete(expense)
        guard model.undoExpense?.id == expense.id else { return } // failed; model.error explains
        let occurrences = model.undoOccurrences
        if inspectorSelection == .expense(expense.id) { inspectorSelection = nil }
        undoManager?.registerUndo(withTarget: self) { [weak undoManager] state in
            MainActor.assumeIsolated {
                state.model.restore(expense, occurrences: occurrences)
                undoManager?.registerUndo(withTarget: state) { [weak undoManager] state in
                    MainActor.assumeIsolated { state.delete(expense, undoManager: undoManager) }
                }
                undoManager?.setActionName("Delete Expense")
            }
        }
        undoManager?.setActionName("Delete Expense")
    }

    init(model: AppModel) {
        self.model = model
        destination = Self.decode(UserDefaults.standard.string(forKey: "MacDestination"))
        inspectorVisible = UserDefaults.standard.object(forKey: "MacInspectorVisible") as? Bool ?? true
        #if DEBUG
        if ProcessInfo.processInfo.environment["MONOCLE_TEST_RUN"] != nil { inspectorVisible = true } // UI tests start from a known layout
        #endif
        registerGlobalShortcut()
    }

    var commands: [MacCommand] {
        var result: [MacCommand] = [
            .init(id: MacCommandID.overview.rawValue, title: "Go to Overview", symbol: "rectangle.grid.2x2", commandID: .overview, destination: nil),
            .init(id: MacCommandID.activity.rawValue, title: "Go to Activity", symbol: "list.bullet.rectangle", commandID: .activity, destination: nil),
            .init(id: MacCommandID.cards.rawValue, title: "Go to Cards", symbol: "creditcard", commandID: .cards, destination: nil),
            .init(id: MacCommandID.budgets.rawValue, title: "Go to Budgets", symbol: "gauge.with.dots.needle.67percent", commandID: .budgets, destination: nil),
            .init(id: MacCommandID.bills.rawValue, title: "Go to Bills", symbol: "calendar.badge.clock", commandID: .bills, destination: nil),
            .init(id: MacCommandID.analytics.rawValue, title: "Go to Analytics", symbol: "chart.bar.xaxis", commandID: .analytics, destination: nil),
            .init(id: MacCommandID.chat.rawValue, title: "Go to Chat", symbol: "bubble.left.and.text.bubble.right", commandID: .chat, destination: nil)
        ]
        result += model.books.map { book in
            .init(id: "card.\(book.id)", title: "Open \(book.name)", symbol: "creditcard.fill", commandID: nil, destination: .card(book.id))
        }
        result += [
            .init(id: MacCommandID.newExpense.rawValue, title: "New Expense", symbol: "plus.circle", commandID: .newExpense, destination: nil),
            .init(id: MacCommandID.quickRecord.rawValue, title: "Quick Record", symbol: "bolt.circle", commandID: .quickRecord, destination: nil),
            .init(id: MacCommandID.focusSearch.rawValue, title: "Focus Search", symbol: "magnifyingglass", commandID: .focusSearch, destination: nil),
            .init(id: MacCommandID.toggleSidebar.rawValue, title: "Toggle Sidebar", symbol: "sidebar.left", commandID: .toggleSidebar, destination: nil),
            .init(id: MacCommandID.toggleInspector.rawValue, title: "Toggle Inspector", symbol: "sidebar.right", commandID: .toggleInspector, destination: nil),
            .init(id: MacCommandID.importCSV.rawValue, title: "Import CSV", symbol: "square.and.arrow.down", commandID: .importCSV, destination: nil),
            .init(id: MacCommandID.exportCSV.rawValue, title: "Export CSV", symbol: "tablecells", commandID: .exportCSV, destination: nil),
            .init(id: MacCommandID.exportBackup.rawValue, title: "Export Backup", symbol: "externaldrive", commandID: .exportBackup, destination: nil),
            .init(id: MacCommandID.restoreBackup.rawValue, title: "Restore Backup", symbol: "arrow.counterclockwise", commandID: .restoreBackup, destination: nil),
            .init(id: MacCommandID.settings.rawValue, title: "Settings", symbol: "gearshape", commandID: .settings, destination: nil),
            .init(id: MacCommandID.lock.rawValue, title: "Lock Monocle", symbol: "lock", commandID: .lock, destination: nil)
        ]
        return result
    }

    func shortcut(for id: MacCommandID) -> KeyChord? {
        model.workspacePreferences.macShortcutBindings[id.rawValue] ?? KeyChord.defaults[id]
    }

    func setShortcut(_ chord: KeyChord, for id: MacCommandID) throws {
        try validate(chord, for: id)
        let old = shortcut(for: id)
        model.workspacePreferences.macShortcutBindings[id.rawValue] = chord
        if id == .quickRecord {
            do { try hotKey.register(chord) { [weak self] in self?.showQuickRecord() } }
            catch {
                if let old { try? hotKey.register(old) { [weak self] in self?.showQuickRecord() } }
                model.workspacePreferences.macShortcutBindings[id.rawValue] = old == KeyChord.defaults[id] ? nil : old
                throw error
            }
        }
        model.persistWorkspacePreferences()
    }

    func resetShortcuts() {
        model.workspacePreferences.macShortcutBindings = [:]
        model.persistWorkspacePreferences()
        registerGlobalShortcut()
    }

    func validate(_ chord: KeyChord, for id: MacCommandID) throws {
        let allowedNamed = ["return", "escape", "space", "left", "right", "up", "down"]
        guard (chord.key.count == 1 && chord.key.first?.isASCII == true) || allowedNamed.contains(chord.key) else { throw ShortcutValidationError.unsupported }
        guard !chord.modifiers.isEmpty || allowedNamed.contains(chord.key) else { throw ShortcutValidationError.needsModifier }
        let reserved: Set<KeyChord> = [
            .init("q", modifiers: .command), .init("h", modifiers: .command),
            .init("w", modifiers: .command), .init("x", modifiers: .command),
            .init("c", modifiers: .command), .init("v", modifiers: .command),
            .init("z", modifiers: .command), .init("z", modifiers: [.command, .shift]),
            .init("a", modifiers: .command), .init("m", modifiers: .command),
            .init(",", modifiers: .command), .init("space", modifiers: .command),
            .init("escape", modifiers: [.command, .option]),
            .init("q", modifiers: [.command, .control]),
            .init("h", modifiers: [.command, .option]),
            .init("3", modifiers: [.command, .shift]),
            .init("4", modifiers: [.command, .shift]),
            .init("5", modifiers: [.command, .shift])
        ]
        guard !reserved.contains(chord) else { throw ShortcutValidationError.reserved }
        for other in MacCommandID.allCases where other != id && shortcut(for: other) == chord {
            let title = commands.first(where: { $0.commandID == other })?.title ?? other.rawValue
            throw ShortcutValidationError.conflict(title)
        }
    }

    func perform(_ command: MacCommand) {
        if let destination = command.destination { self.destination = destination; commandBarVisible = false; return }
        if let id = command.commandID { perform(id) }
        commandBarVisible = false
    }

    func perform(_ id: MacCommandID) {
        switch id {
        case .commandBar: commandBarVisible = true
        case .newExpense:
            model.openEntry(); model.showEntry = false; regularEntryVisible = true
        case .quickRecord: showQuickRecord()
        case .focusSearch: searchFocusToken = UUID()
        case .toggleSidebar: NSApp.sendAction(#selector(NSSplitViewController.toggleSidebar(_:)), to: nil, from: nil)
        case .toggleInspector: inspectorVisible.toggle()
        case .overview: destination = .overview
        case .activity: destination = .activity
        case .budgets: destination = .budgets
        case .bills: destination = .bills
        case .analytics: destination = .analytics
        case .cards: destination = .cards
        case .chat: destination = .chat
        case .importCSV: transferSheet = .importCSV
        case .exportCSV: transferSheet = .exportCSV
        case .exportBackup: transferSheet = .exportBackup
        case .restoreBackup: transferSheet = .restoreBackup
        case .settings: NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        case .lock: model.appLock.suspend(now: .distantPast); model.appLock.resume()
        }
    }

    func selectCard(_ id: UUID) {
        _ = model.selectBook(id)
        destination = .card(id)
        inspect(.card(id))
    }

    private func showQuickRecord() {
        model.openEntry(); model.showEntry = false
        quickPanel.show()
    }

    private func registerGlobalShortcut() {
        guard let chord = shortcut(for: .quickRecord) else { return }
        do { try hotKey.register(chord) { [weak self] in self?.showQuickRecord() } }
        catch { shortcutError = error.localizedDescription }
    }

    private static func encode(_ value: MacDestination) -> String {
        switch value {
        case .overview: "overview"; case .activity: "activity"; case .cards: "cards"
        case .card(let id): "card:\(id.uuidString)"; case .budgets: "budgets"; case .bills: "bills"; case .analytics: "analytics"; case .chat: "chat"
        }
    }

    private static func decode(_ value: String?) -> MacDestination {
        guard let value else { return .overview }
        if value.hasPrefix("card:"), let id = UUID(uuidString: String(value.dropFirst(5))) { return .card(id) }
        return switch value { case "activity": .activity; case "cards": .cards; case "budgets": .budgets; case "bills": .bills; case "analytics": .analytics; case "chat": .chat; default: .overview }
    }
}

enum DataTransferSheet: Identifiable {
    case importCSV, exportCSV, exportBackup, restoreBackup
    var id: Self { self }
}

struct MonocleMacCommands: Commands {
    let state: MacAppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            commandButton("New Expense", .newExpense)
            commandButton("Quick Record", .quickRecord)
        }
        CommandMenu("Navigate") {
            commandButton("Overview", .overview)
            commandButton("Activity", .activity)
            commandButton("Budgets", .budgets)
            commandButton("Bills", .bills)
            commandButton("Analytics", .analytics)
            commandButton("Cards", .cards)
            commandButton("Chat", .chat)
            Divider()
            commandButton("Focus Search", .focusSearch)
            commandButton("Toggle Sidebar", .toggleSidebar)
            commandButton("Toggle Inspector", .toggleInspector)
        }
        CommandMenu("Data") {
            commandButton("Import CSV…", .importCSV)
            commandButton("Export CSV…", .exportCSV)
            Divider()
            commandButton("Export Backup…", .exportBackup)
            commandButton("Restore Backup…", .restoreBackup)
            Divider()
            commandButton("Settings…", .settings)
            commandButton("Lock Monocle", .lock)
        }
        CommandGroup(after: .toolbar) { commandButton("Command Bar", .commandBar) }
    }

    @ViewBuilder private func commandButton(_ title: String, _ id: MacCommandID) -> some View {
        let button = Button(title) { state.perform(id) }
        if let shortcut = state.shortcut(for: id)?.keyboardShortcut { button.keyboardShortcut(shortcut) }
        else { button }
    }
}
