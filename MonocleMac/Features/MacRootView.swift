import AppKit
import Charts
import SwiftUI

private enum MacTheme {
    static let accent = Color(red: 0.85, green: 0.16, blue: 0.12)
    static let paper = Color(nsColor: .windowBackgroundColor)
    static let panel = Color(nsColor: .controlBackgroundColor)
}

struct MacRootView: View {
    @Bindable var state: MacAppState
    @Bindable private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchExpanded = false

    init(state: MacAppState) {
        self.state = state
        model = state.model
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            } detail: {
                // ponytail: hand-rolled inspector column. The system `.inspector` inserted its full width before
                // squeezing the content, so the sidebar slid off and the window overflowed on every toggle (and
                // looped/crashed in narrow windows). Fixed 300pt, not resizable; add a drag handle if needed.
                HStack(spacing: 0) {
                    content
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    if state.inspectorVisible {
                        Divider()
                        MacInspector(state: state)
                            .frame(width: 300)
                            .transition(.move(edge: .trailing))
                    }
                }
                .clipped()
                .animation(.smooth(duration: 0.25), value: state.inspectorVisible)
            }
            .toolbar { toolbar }
            .disabled(model.appLock.blocksContent)
            .blur(radius: model.appLock.blocksContent ? 10 : 0)

            if state.commandBarVisible { CommandBarOverlay(state: state) }
            if model.appLock.blocksContent { MacLockView(model: model) }
        }
        .frame(minWidth: 1000, minHeight: 620) // sidebar + full-width table columns + 300pt inspector
        #if DEBUG
        .onAppear { // UI-test hook: start at a given width (tests can't drag-resize; the saved width would leak between tests)
            let env = ProcessInfo.processInfo.environment
            if let width = env["MONOCLE_TEST_WINDOW_WIDTH"].flatMap(Double.init) ?? (env["MONOCLE_TEST_RUN"] != nil ? 1180 : nil) {
                DispatchQueue.main.async {
                    guard let window = NSApp.windows.first(where: \.isVisible) else { return }
                    var frame = window.frame; frame.size.width = width; window.setFrame(frame, display: true)
                }
            }
        }
        #endif
        .background(MacTheme.paper)
        .sheet(isPresented: $state.regularEntryVisible) {
            MacExpenseForm(model: model, quickRecord: false) { _ in state.regularEntryVisible = false }
        }
        .sheet(item: $state.transferSheet) { MacDataTransferView(state: state, mode: $0) }
        .alert("Monocle", isPresented: Binding(get: { model.error != nil || state.shortcutError != nil }, set: { if !$0 { model.error = nil; state.shortcutError = nil } })) {
            Button("OK") { model.error = nil; state.shortcutError = nil }
        } message: { Text(model.error ?? state.shortcutError ?? "") }
        .onChange(of: state.searchFocusToken) { _, _ in searchExpanded = true } // an open field refocuses on the token itself
        .onChange(of: model.showEntry) { _, shouldShow in
            if shouldShow { model.showEntry = false; state.regularEntryVisible = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background { model.appLock.suspend() }
            else if phase == .active { model.appLock.resume() }
        }
    }

    private var sidebar: some View {
        List(selection: $state.destination) {
            Section {
                Label("Overview", systemImage: "rectangle.grid.2x2").tag(MacDestination.overview)
                Label("Activity", systemImage: "list.bullet.rectangle").tag(MacDestination.activity)
            }
            Section("Cards") {
                Label("All Cards", systemImage: "creditcard").tag(MacDestination.cards)
                ForEach(model.books) { book in
                    Label(book.name, systemImage: "creditcard.fill").tag(MacDestination.card(book.id))
                }
            }
            Section("Planning") {
                Label("Budgets", systemImage: "gauge.with.dots.needle.67percent").tag(MacDestination.budgets)
                Label("Bills", systemImage: "calendar.badge.clock").tag(MacDestination.bills)
            }
            Section {
                Label("Analytics", systemImage: "chart.bar.xaxis").tag(MacDestination.analytics)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("monocle")
    }

    @ViewBuilder private var content: some View {
        switch state.destination {
        case .overview: MacOverviewView(state: state)
        case .activity: MacActivityView(state: state, bookID: nil)
        case .cards: MacCardsView(state: state)
        case .card(let id): MacCardDetailView(state: state, bookID: id)
        case .budgets: MacBudgetsView(state: state)
        case .bills: MacBillsView(state: state)
        case .analytics: MacAnalyticsView(state: state)
        }
    }

    /// Magnifier when idle; expands on click or ⌘F. Esc clears and collapses; clicking away collapses an empty field.
    @ViewBuilder private var searchField: some View {
        if searchExpanded || !state.searchText.isEmpty {
            ToolbarSearchField(text: $state.searchText, focusToken: state.searchFocusToken) { searchExpanded = false }
                .frame(width: 220)
        } else {
            Button { searchExpanded = true } label: { Label("Search", systemImage: "magnifyingglass") }
                .help("Search (\(state.shortcut(for: .focusSearch)?.displayName ?? ""))")
                .accessibilityIdentifier("searchButton")
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            searchField
            Button { state.perform(.commandBar) } label: { Label("Commands", systemImage: "command") }
                .help("Command Bar (\(state.shortcut(for: .commandBar)?.displayName ?? ""))")
            Button { state.perform(.newExpense) } label: { Label("Expense", systemImage: "plus") }
                .buttonStyle(.borderedProminent).tint(MacTheme.accent)
                .accessibilityIdentifier("newExpense")
        }
        ToolbarItem {
            Button { state.perform(.toggleInspector) } label: { Label("Inspector", systemImage: "sidebar.right") }
                .help("Toggle Inspector (\(state.shortcut(for: .toggleInspector)?.displayName ?? ""))")
                .accessibilityIdentifier("toggleInspector")
        }
    }
}

private struct CommandBarOverlay: View {
    @Bindable var state: MacAppState
    @State private var query = ""
    @State private var selected = 0

    private var results: [MacCommand] {
        query.isEmpty ? state.commands : state.commands.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.22).ignoresSafeArea().onTapGesture { state.commandBarVisible = false }
            Button("") { state.commandBarVisible = false }
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0).opacity(0)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    CommandTextField(text: $query) {
                        guard !results.isEmpty else { return }
                        selected = min(results.count - 1, selected + 1)
                    } onUp: {
                        selected = max(0, selected - 1)
                    } onReturn: {
                        if results.indices.contains(selected) { state.perform(results[selected]) }
                    } onEscape: {
                        state.commandBarVisible = false
                    }
                }
                .font(.title3)
                .frame(height: 30)
                .padding(16)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                                Button { state.perform(command) } label: {
                                    HStack {
                                        Image(systemName: command.symbol).frame(width: 24)
                                        Text(command.title)
                                        Spacer()
                                        if let id = command.commandID, let shortcut = state.shortcut(for: id) {
                                            Text(shortcut.displayName).foregroundStyle(.secondary)
                                        }
                                    }.padding(.horizontal, 14).padding(.vertical, 9).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .background(index == selected ? MacTheme.accent.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
                                .id(command.id)
                            }
                        }.padding(8)
                    }.frame(height: min(390, CGFloat(max(results.count, 1)) * 43 + 16))
                    .onChange(of: selected) { _, value in
                        if results.indices.contains(value) { proxy.scrollTo(results[value].id) }
                    }
                }
            }
            .frame(width: 570)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator))
            .shadow(radius: 24, y: 12)
            .padding(.top, 110)
        }
        .onChange(of: query) { _, _ in selected = 0 }
        .onExitCommand { state.commandBarVisible = false }
    }
}

private struct CommandTextField: NSViewRepresentable {
    @Binding var text: String
    let onDown: () -> Void
    let onUp: () -> Void
    let onReturn: () -> Void
    let onEscape: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> FirstResponderTextField {
        let field = FirstResponderTextField()
        field.placeholderString = "Type a command"
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize(for: .large))
        field.onTextChange = context.coordinator.updateText
        field.setAccessibilityIdentifier("commandBar")
        context.coordinator.install(for: field)
        return field
    }

    func updateNSView(_ field: FirstResponderTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onDown = onDown
        context.coordinator.onUp = onUp
        context.coordinator.onReturn = onReturn
        context.coordinator.onEscape = onEscape
        if field.stringValue != text { field.stringValue = text }
    }

    static func dismantleNSView(_ field: FirstResponderTextField, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor final class Coordinator: NSObject {
        var text: Binding<String>
        var onDown = {}
        var onUp = {}
        var onReturn = {}
        var onEscape = {}
        private var monitor: Any?
        init(text: Binding<String>) { self.text = text }

        func updateText(_ value: String) { text.wrappedValue = value }

        func install(for field: NSTextField) {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let keyCode = event.keyCode
                let handled = MainActor.assumeIsolated { self?.handle(keyCode) == true }
                return handled ? nil : event
            }
        }

        func uninstall() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func handle(_ keyCode: UInt16) -> Bool {
            switch keyCode {
            case 125: onDown()
            case 126: onUp()
            case 36, 76: onReturn()
            case 53: onEscape()
            default: return false
            }
            return true
        }

    }
}

/// AppKit search field: SwiftUI focus doesn't reliably reach toolbar items, and NSSearchField brings the native
/// magnifier, clear button, and Esc handling.
private struct ToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    let focusToken: UUID
    let onEnd: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = "Search"
        field.focusRingType = .none
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("searchField")
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) } // opened to be typed into
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        }
    }

    @MainActor final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: ToolbarSearchField
        var focusToken: UUID
        init(_ parent: ToolbarSearchField) { self.parent = parent; focusToken = parent.focusToken }

        func controlTextDidChange(_ note: Notification) {
            parent.text = (note.object as? NSSearchField)?.stringValue ?? ""
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            parent.text = ""
            control.window?.makeFirstResponder(nil)
            parent.onEnd()
            return true
        }

        func controlTextDidEndEditing(_ note: Notification) {
            if parent.text.isEmpty { parent.onEnd() }
        }
    }
}

private final class FirstResponderTextField: NSTextField {
    var onTextChange: ((String) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(self)
        }
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification)
        onTextChange?((currentEditor() as? NSTextView)?.string ?? stringValue)
    }
}

struct Page<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(title).font(.largeTitle.bold())
                content
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }.navigationTitle(title)
    }
}

struct SummaryTile: View {
    let title: String
    let value: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.system(.title2, design: .monospaced, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct MacOverviewView: View {
    @Bindable var state: MacAppState
    private var model: AppModel { state.model }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Overview").font(.largeTitle.bold())
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(model.books) { book in
                        MacCardView(model: model, book: book)
                            .onTapGesture { state.selectCard(book.id) }
                    }
                }.padding(.vertical, 12) // room for the shadow and hover lift
            }.scrollIndicators(.hidden).scrollClipDisabled() // clipping cut the shadow into a hard edge
            HStack {
                SummaryTile(title: "Cycle spending", value: Money.format(model.spent), detail: model.cycle.label)
                SummaryTile(title: "Remaining", value: Money.format(model.remaining), detail: "of \(Money.format(model.activeBudget.overallLimit))")
                SummaryTile(title: "Upcoming bills", value: "\(model.billOccurrences.filter { $0.status == .pending }.count)", detail: "Awaiting action")
            }
            Text("Recent Activity").font(.title2.bold())
            MacExpenseTable(state: state, bookID: nil, limit: 50) // same table as Activity; fills the rest of the window
        }.padding(24).navigationTitle("Overview")
    }
}

private struct MacCardView: View {
    let model: AppModel
    let book: BookProfile
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt: CGSize = .zero // pointer position, -1...1 from the centre
    @State private var hovering = false
    private static let size = CGSize(width: 250, height: 150)
    private var customization: BookCardCustomization { model.customization(for: book.id) }

    var body: some View {
        VStack(alignment: .leading) {
            HStack { Image(systemName: "circle.grid.cross.fill"); Spacer(); Text("MONOCLE").font(.caption2.bold()) }
            Spacer()
            Text(book.name).font(.title3.bold())
            Text(Money.format(model.expenses(for: book.id).reduce(0) { $0 + $1.amount })).font(.system(.headline, design: .monospaced))
        }
            .offset(x: tilt.width * 4, y: tilt.height * 4) // text floats above the face for depth
            .foregroundStyle(CardPalette.resolvedTextColor(for: customization)).padding(16).frame(width: Self.size.width, height: Self.size.height)
            .background {
                background
                    .overlay {
                        RadialGradient(colors: [.white.opacity(0.28), .clear],
                                       center: UnitPoint(x: (tilt.width + 1) / 2, y: (tilt.height + 1) / 2), startRadius: 0, endRadius: 200)
                            .opacity(hovering ? 1 : 0)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .rotation3DEffect(.degrees(-tilt.height * 8), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(tilt.width * 10), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .scaleEffect(hovering ? 1.03 : 1)
            .shadow(color: .black.opacity(hovering ? 0.2 : 0.12), radius: hovering ? 14 : 8, x: -tilt.width * 6, y: 4 - tilt.height * 4)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onContinuousHover { phase in
                guard !reduceMotion else { return }
                switch phase {
                case .active(let point):
                    hovering = true
                    tilt = CGSize(width: max(-1, min(1, point.x / Self.size.width * 2 - 1)),
                                  height: max(-1, min(1, point.y / Self.size.height * 2 - 1)))
                case .ended:
                    hovering = false; tilt = .zero
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: tilt)
            .animation(.easeOut(duration: 0.2), value: hovering)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var background: some View {
        switch customization.style {
        case .palette(let index): Rectangle().fill(CardPalette.color(for: index).gradient)
        case .customColor(let hex): Rectangle().fill(CardPalette.color(fromHex: hex).gradient)
        case .stock(let design):
            LinearGradient(colors: stockColors(design), startPoint: .topLeading, endPoint: .bottomTrailing)
        case .customPhoto(let filename):
            if let image = CardArtworkStore.shared.loadArtwork(filename: filename) {
                Image(nsImage: image).resizable().scaledToFill().overlay(Color.black.opacity(0.16))
            } else { Rectangle().fill(CardPalette.color(for: book.colorIndex).gradient) }
        }
    }
    private func stockColors(_ design: StockCardDesign) -> [Color] {
        switch design {
        case .sunsetHeat: [.red, .orange, .purple]
        case .auroraBorealis: [.indigo, .mint, .blue]
        case .midnightCosmo: [.black, .indigo, .purple]
        case .acidCyber: [.green, .yellow, .cyan]
        case .titaniumMetal: [.gray, .white, .gray]
        case .appleAura: [.pink, .cyan, .yellow]
        case .topographic: [.black, .green]
        case .neoGrid: [.black, .blue, .pink]
        case .warmParchment: [.brown.opacity(0.7), .orange.opacity(0.4), .white]
        }
    }
}


struct MacActivityView: View {
    @Bindable var state: MacAppState
    let bookID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(bookID.flatMap { id in state.model.books.first(where: { $0.id == id })?.name } ?? "Activity").font(.largeTitle.bold())
            MacExpenseTable(state: state, bookID: bookID)
        }.padding(24).navigationTitle("Activity")
    }
}

/// The one transaction table (Overview, Activity, card pages). `limit` keeps only the newest rows.
struct MacExpenseTable: View {
    let state: MacAppState
    let bookID: UUID?
    var limit: Int?
    @State private var sortOrder: [KeyPathComparator<MacExpenseRow>] = []
    @State private var allRows: [MacExpenseRow] = []
    @State private var rows: [MacExpenseRow] = []

    var body: some View {
        MacActivityTable(rows: rows, state: state, sortOrder: $sortOrder)
            .accessibilityIdentifier("activityTable")
            // Rows rebuild only when data or the card changes, not on every window refresh (selection, inspector, typing).
            .onChange(of: RowsSource(revision: state.model.dataRevision, bookID: bookID, bookCount: state.model.books.count), initial: true) { buildRows() }
            .onChange(of: state.searchText) { refresh() }
            .onChange(of: sortOrder) { refresh() }
    }

    private struct RowsSource: Equatable { let revision: UInt64; let bookID: UUID?; let bookCount: Int }

    private func buildRows() {
        let model = state.model
        var source = bookID.map(model.expenses(for:)) ?? model.allExpenses()
        if let limit {
            source = Array(source.sorted { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }.prefix(limit))
        }
        let books = Dictionary(model.books.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        allRows = MacExpenseRow.make(source, bookNames: books, categoryName: { model.category($0)?.name })
        refresh()
    }

    private func refresh() { rows = MacExpenseRow.filter(allRows, query: state.searchText, sortOrder: sortOrder) }
}

struct MacExpenseRow: Identifiable {
    let expense: Expense
    let title: String
    let category: String
    let book: String
    var id: Expense.ID { expense.id }
    var day: String { expense.day }
    var amountMinor: Int64 { expense.amount }

    static func make(_ expenses: [Expense], bookNames: [UUID: String], categoryName: (UUID) -> String?) -> [MacExpenseRow] {
        var names: [UUID: String] = [:]
        func name(_ id: UUID?) -> String? {
            guard let id else { return nil }
            if let cached = names[id] { return cached }
            let value = categoryName(id); names[id] = value; return value
        }
        return expenses.map { expense in
            let category = name(expense.allocations.first?.categoryID)
            return MacExpenseRow(expense: expense, title: expense.note.isEmpty ? category ?? "Expense" : expense.note,
                                 category: category ?? "Split", book: expense.bookID.flatMap { bookNames[$0] } ?? "")
        }
    }

    static func filter(_ rows: [MacExpenseRow], query: String, sortOrder: [KeyPathComparator<MacExpenseRow>]) -> [MacExpenseRow] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? rows : rows.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.category.localizedCaseInsensitiveContains(query)
        }
        return sortOrder.isEmpty
            ? filtered.sorted { $0.day == $1.day ? $0.expense.createdAt > $1.expense.createdAt : $0.day > $1.day }
            : filtered.sorted(using: sortOrder)
    }
}

private struct MacActivityTable: View {
    let rows: [MacExpenseRow]
    let state: MacAppState
    @Binding var sortOrder: [KeyPathComparator<MacExpenseRow>]
    @Environment(\.undoManager) private var undoManager

    /// The inspector selection is the only selection, so the table and inspector can't disagree.
    private var selection: Binding<Expense.ID?> {
        Binding(get: { if case .expense(let id) = state.inspectorSelection { id } else { nil } },
                set: { state.inspect($0.map { .expense($0) }) })
    }

    var body: some View {
        Table(rows, selection: selection, sortOrder: $sortOrder) {
                // Small minimums so sidebar + all columns + inspector fit the 1000pt minimum window.
                TableColumn("Date", value: \.day) { Text($0.day).font(.system(.body, design: .monospaced)) }.width(min: 90, ideal: 110)
                TableColumn("Note", value: \.title) { Text($0.title) }.width(min: 60, ideal: 180)
                TableColumn("Category", value: \.category) { Text($0.category) }.width(min: 50, ideal: 120)
                TableColumn("Card", value: \.book) { Text($0.book) }.width(min: 50, ideal: 120)
                TableColumn("Amount", value: \.amountMinor) { Text(Money.format($0.amountMinor)).font(.system(.body, design: .monospaced)) }.width(min: 90, ideal: 130)
            }
            .contextMenu(forSelectionType: Expense.ID.self) { ids in
                if let expense = expense(ids.first) { ExpenseMenuItems(state: state, expense: expense) }
            } primaryAction: { ids in
                if let expense = expense(ids.first) { state.edit(expense) }
            }
            .onDeleteCommand { if let expense = expense(selection.wrappedValue) { state.delete(expense, undoManager: undoManager) } }
    }

    private func expense(_ id: Expense.ID?) -> Expense? {
        guard let id else { return nil }
        return rows.first { $0.id == id }?.expense
    }
}

struct ExpenseMenuItems: View {
    let state: MacAppState
    let expense: Expense
    @Environment(\.undoManager) private var undoManager
    var body: some View {
        Button("Edit…") { state.edit(expense) }
        Button("Repeat…") { state.repeatExpense(expense) }
        Divider()
        Button("Delete", role: .destructive) { state.delete(expense, undoManager: undoManager) }
    }
}

struct MacCardsView: View {
    @Bindable var state: MacAppState
    var body: some View {
        Page(title: "Cards") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 18)], spacing: 18) {
                ForEach(state.model.books) { book in MacCardView(model: state.model, book: book).onTapGesture { state.selectCard(book.id) } }
            }
        }
    }
}

struct MacCardDetailView: View {
    @Bindable var state: MacAppState
    let bookID: UUID
    var body: some View {
        VStack(spacing: 0) {
            if let book = state.model.books.first(where: { $0.id == bookID }) {
                HStack { MacCardView(model: state.model, book: book); Spacer() }.padding(24)
                Divider()
            }
            MacActivityView(state: state, bookID: bookID)
        }.onAppear { _ = state.model.selectBook(bookID) }
    }
}

struct MacInspector: View {
    @Bindable var state: MacAppState
    private var model: AppModel { state.model }

    var body: some View {
        let _ = model.dataRevision // refresh after edits to cards that aren't active
        Group {
            switch state.inspectorSelection {
            case .expense(let id): if let expense = model.expense(id: id) { ExpenseInspector(state: state, expense: expense) } else { empty }
            case .bill(let id): if let bill = model.bills.first(where: { $0.id == id }) { BillInspector(model: model, bill: bill) { state.editingBill = bill } } else { empty }
            case .card(let id): if let book = model.books.first(where: { $0.id == id }) { CardInspector(state: state, book: book) } else { empty }
            case nil: empty
            }
        }
        // Same opaque paper as the content so the panel reads as part of the window, not a sheet over the wallpaper.
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacTheme.paper)
    }

    private var empty: some View {
        ContentUnavailableView("Nothing Selected", systemImage: "cursorarrow.click", description: Text("Select a transaction, bill, or card."))
    }
}

/// Icon, title, subtitle, and amount at the top of every inspector.
private struct InspectorHeader: View {
    let symbol: String
    let title: String
    let subtitle: String
    var amount: Int64?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.title2).foregroundStyle(MacTheme.accent)
                    .frame(width: 40, height: 40).background(MacTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).lineLimit(2)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            if let amount {
                Text(Money.format(amount)).font(.system(.title, design: .monospaced, weight: .semibold)).textSelection(.enabled)
            }
        }.padding(.vertical, 4)
    }
}

/// Actions pinned under the inspector form; the destructive one sits apart on the trailing edge.
private struct InspectorActions<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    var body: some View {
        HStack { leading; Spacer(); trailing }
            .padding(12).frame(maxWidth: .infinity).background(MacTheme.paper)
            .overlay(alignment: .top) { Divider() }
    }
}

private struct ExpenseInspector: View {
    let state: MacAppState
    let expense: Expense
    @Environment(\.undoManager) private var undoManager
    private var model: AppModel { state.model }

    var body: some View {
        let isSplit = expense.allocations.count > 1
        let category = model.category(expense.allocations.first?.categoryID)
        Form {
            Section {
                InspectorHeader(symbol: isSplit ? "square.split.2x1" : category?.symbol ?? "questionmark.circle",
                                title: model.title(expense),
                                subtitle: isSplit ? "Split across \(expense.allocations.count) categories" : category?.name ?? "No category",
                                amount: expense.amount)
            }
            Section("Details") {
                LabeledContent("Date", value: Day.title(expense.day))
                LabeledContent("Card", value: model.books.first(where: { $0.id == expense.bookID })?.name ?? "—")
                LabeledContent("Recorded", value: expense.createdAt.formatted(date: .abbreviated, time: .shortened))
                if expense.source != "manual" { LabeledContent("Source", value: expense.source.capitalized) }
            }
            // The header shows two lines of the note; long notes get their full text here.
            if expense.note.count > 60 || expense.note.contains("\n") {
                Section("Note") { Text(expense.note).textSelection(.enabled) }
            }
            if isSplit {
                Section("Split") {
                    ForEach(Array(expense.allocations.enumerated()), id: \.offset) { _, allocation in
                        let part = model.category(allocation.categoryID)
                        LabeledContent {
                            Text(Money.format(allocation.amount)).font(.system(.body, design: .monospaced))
                        } label: {
                            Label(part?.name ?? "No category", systemImage: part?.symbol ?? "questionmark.circle")
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InspectorActions {
                Button("Edit…") { state.edit(expense) }
                Button("Repeat…") { state.repeatExpense(expense) }
            } trailing: {
                Button("Delete", role: .destructive) { state.delete(expense, undoManager: undoManager) }
                    .help("Delete (Edit ▸ Undo restores it)")
            }
        }
    }
}

private struct BillInspector: View {
    let model: AppModel
    let bill: BillRule
    let edit: () -> Void

    var body: some View {
        let category = model.category(bill.categoryID)
        let pending = model.billOccurrences.filter { $0.billRuleID == bill.id && $0.status == .pending }.min { $0.dueDay < $1.dueDay }
        Form {
            Section {
                InspectorHeader(symbol: category?.symbol ?? "calendar.badge.clock", title: bill.name,
                                subtitle: bill.isActive ? category?.name ?? "Bill" : "Paused", amount: bill.amount)
            }
            if let pending {
                Section("Needs Attention") {
                    LabeledContent("Due", value: Day.title(pending.dueDay))
                    HStack {
                        Button("Skip") { act { try model.skipBillOccurrence(pending.id) } }
                        Spacer()
                        Button("Record") { act { _ = try model.confirmBillOccurrence(pending.id) } }.buttonStyle(.borderedProminent)
                    }
                }
            }
            Section("Schedule") {
                LabeledContent("Repeats", value: bill.recurrence.title)
                LabeledContent("Recording", value: bill.recordingMode.title)
                LabeledContent("Reminder", value: !bill.hasReminder ? "Off" : bill.reminderLeadDays == 0 ? "On the day" : "\(bill.reminderLeadDays) days before")
                LabeledContent("Card", value: model.books.first(where: { $0.id == bill.bookID })?.name ?? "—")
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InspectorActions { Button("Edit Bill…", action: edit) } trailing: { EmptyView() }
        }
    }

    private func act(_ work: () throws -> Void) {
        do { try work() } catch { model.error = error.localizedDescription }
    }
}

private struct CardInspector: View {
    let state: MacAppState
    let book: BookProfile
    private var model: AppModel { state.model }

    var body: some View {
        let expenses = model.expenses(for: book.id)
        Form {
            Section {
                MacCardView(model: model, book: book).frame(maxWidth: .infinity)
            }
            Section("Spending") {
                LabeledContent("Transactions", value: "\(expenses.count)")
                LabeledContent("Total", value: Money.format(expenses.reduce(0) { $0 + $1.amount }))
                if let last = expenses.map(\.day).max() { LabeledContent("Last expense", value: Day.title(last)) }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InspectorActions {
                Button("New Expense on This Card") { _ = model.selectBook(book.id); state.perform(.newExpense) }
            } trailing: { EmptyView() }
        }
    }
}

private struct MacLockView: View {
    @Bindable var model: AppModel
    @State private var error: String?
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill").font(.system(size: 38)).foregroundStyle(MacTheme.accent)
            Text("Monocle is locked").font(.title2.bold())
            Text("Use Touch ID or your Mac login password.").foregroundStyle(.secondary)
            Button("Unlock") { Task { if case .failure(let value) = await model.appLock.unlock() { error = value.localizedDescription } } }
                .buttonStyle(.borderedProminent).tint(MacTheme.accent)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(36).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)).shadow(radius: 20)
    }
}
