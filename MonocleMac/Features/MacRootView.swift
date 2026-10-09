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
    @FocusState private var searchFocused: Bool

    init(state: MacAppState) {
        self.state = state
        model = state.model
    }

    var body: some View {
        ZStack {
            NavigationSplitView {
                sidebar
                    .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
            } content: {
                content
                    .navigationSplitViewColumnWidth(min: 540, ideal: 720)
            } detail: {
                if state.inspectorVisible { MacInspector(state: state) }
                else { ContentUnavailableView("Inspector Hidden", systemImage: "sidebar.right") }
            }
            .navigationSplitViewStyle(.balanced)
            .toolbar { toolbar }
            .disabled(model.appLock.blocksContent)
            .blur(radius: model.appLock.blocksContent ? 10 : 0)

            if state.commandBarVisible { CommandBarOverlay(state: state) }
            if model.appLock.blocksContent { MacLockView(model: model) }
        }
        .frame(minWidth: 900, minHeight: 620)
        .background(MacTheme.paper)
        .sheet(isPresented: $state.regularEntryVisible) {
            MacExpenseForm(model: model, quickRecord: false) { _ in state.regularEntryVisible = false }
        }
        .sheet(item: $state.transferSheet) { MacDataTransferView(state: state, mode: $0) }
        .alert("Monocle", isPresented: Binding(get: { model.error != nil || state.shortcutError != nil }, set: { if !$0 { model.error = nil; state.shortcutError = nil } })) {
            Button("OK") { model.error = nil; state.shortcutError = nil }
        } message: { Text(model.error ?? state.shortcutError ?? "") }
        .onChange(of: state.searchFocusToken) { _, _ in searchFocused = true }
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

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            TextField("Search", text: $state.searchText)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .frame(width: 220)
                .accessibilityIdentifier("searchField")
            Button { state.perform(.commandBar) } label: { Label("Commands", systemImage: "command") }
                .help("Command Bar (\(state.shortcut(for: .commandBar)?.displayName ?? ""))")
            Button { state.perform(.newExpense) } label: { Label("Expense", systemImage: "plus") }
                .buttonStyle(.borderedProminent).tint(MacTheme.accent)
                .accessibilityIdentifier("newExpense")
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
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(.title2, design: .monospaced, weight: .semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(MacTheme.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct MacOverviewView: View {
    @Bindable var state: MacAppState
    private var model: AppModel { state.model }
    var body: some View {
        Page(title: "Overview") {
            ScrollView(.horizontal) {
                HStack(spacing: 14) {
                    ForEach(model.books) { book in
                        MacCardView(model: model, book: book)
                            .onTapGesture { state.selectCard(book.id) }
                    }
                }
            }.scrollIndicators(.hidden)
            HStack {
                SummaryTile(title: "Cycle spending", value: Money.format(model.spent), detail: model.cycle.label)
                SummaryTile(title: "Remaining", value: Money.format(model.remaining), detail: "of \(Money.format(model.activeBudget.overallLimit))")
                SummaryTile(title: "Upcoming bills", value: "\(model.billOccurrences.filter { $0.status == .pending }.count)", detail: "Awaiting action")
            }
            GroupBox("Recent Activity") {
                MacCompactExpenseList(state: state, expenses: filtered(model.allExpenses()).prefix(8).map { $0 })
            }
        }
    }
    private func filtered(_ expenses: [Expense]) -> [Expense] {
        expenses.sorted { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
    }
}

private struct MacCardView: View {
    let model: AppModel
    let book: BookProfile
    private var customization: BookCardCustomization { model.customization(for: book.id) }
    var body: some View {
        VStack(alignment: .leading) {
            HStack { Image(systemName: "circle.grid.cross.fill"); Spacer(); Text("MONOCLE").font(.caption2.bold()) }
            Spacer()
            Text(book.name).font(.title3.bold())
            Text(Money.format(model.expenses(for: book.id).reduce(0) { $0 + $1.amount })).font(.system(.headline, design: .monospaced))
        }.foregroundStyle(CardPalette.resolvedTextColor(for: customization)).padding(16).frame(width: 250, height: 150)
            .background { background.clipShape(RoundedRectangle(cornerRadius: 16)) }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 16))
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

private struct MacCompactExpenseList: View {
    @Bindable var state: MacAppState
    let expenses: [Expense]
    var body: some View {
        VStack(spacing: 0) {
            ForEach(expenses) { expense in
                Button {
                    state.inspectorSelection = .expense(expense.id); state.inspectorVisible = true
                } label: {
                    HStack {
                        Text(Day.title(expense.day)).frame(width: 90, alignment: .leading)
                        Text(state.model.title(expense)).lineLimit(1)
                        Spacer()
                        Text(Money.format(expense.amount)).font(.system(.body, design: .monospaced)).foregroundStyle(.primary)
                    }.padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain)
                if expense.id != expenses.last?.id { Divider() }
            }
        }.padding(.horizontal, 8)
    }
}

struct MacActivityView: View {
    @Bindable var state: MacAppState
    let bookID: UUID?
    @State private var sortOrder: [KeyPathComparator<MacExpenseRow>] = []

    private var rows: [MacExpenseRow] {
        let source = bookID.map(state.model.expenses(for:)) ?? state.model.allExpenses()
        let books = Dictionary(state.model.books.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let rows = source.map { expense in
            MacExpenseRow(expense: expense, title: state.model.title(expense),
                          category: state.model.category(expense.allocations.first?.categoryID)?.name ?? "Split",
                          book: expense.bookID.flatMap { books[$0] } ?? "",
                          amount: Money.format(expense.amount))
        }
        let query = state.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty ? rows : rows.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.category.localizedCaseInsensitiveContains(query)
        }
        return sortOrder.isEmpty
            ? filtered.sorted { $0.day == $1.day ? $0.expense.createdAt > $1.expense.createdAt : $0.day > $1.day }
            : filtered.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(bookID.flatMap { id in state.model.books.first(where: { $0.id == id })?.name } ?? "Activity").font(.largeTitle.bold())
            MacActivityTable(rows: rows, state: state, sortOrder: $sortOrder, edit: edit)
                .accessibilityIdentifier("activityTable")
        }.padding(24).navigationTitle("Activity")
    }
    private func edit(_ expense: Expense) {
        state.model.edit(expense); state.model.showEntry = false; state.regularEntryVisible = true
    }
}

private struct MacExpenseRow: Identifiable {
    let expense: Expense
    let title: String
    let category: String
    let book: String
    let amount: String
    var id: Expense.ID { expense.id }
    var day: String { expense.day }
    var amountMinor: Int64 { expense.amount }
}

private struct MacActivityTable: View {
    let rows: [MacExpenseRow]
    let state: MacAppState
    @Binding var sortOrder: [KeyPathComparator<MacExpenseRow>]
    let edit: (Expense) -> Void
    @State private var selection: Expense.ID?

    var body: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
                TableColumn("Date", value: \.day) { Text($0.day).font(.system(.body, design: .monospaced)) }.width(min: 96, ideal: 110)
                TableColumn("Note", value: \.title) { Text($0.title) }
                TableColumn("Category", value: \.category) { Text($0.category) }
                TableColumn("Card", value: \.book) { Text($0.book) }
                TableColumn("Amount", value: \.amountMinor) { Text($0.amount).font(.system(.body, design: .monospaced)) }.width(min: 110, ideal: 130)
            }
            .onChange(of: selection) { _, id in if let id { state.inspectorSelection = .expense(id); state.inspectorVisible = true } }
            .onKeyPress(.return) { if let row = rows.first(where: { $0.id == selection }) { edit(row.expense) }; return .handled }
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
    @State private var deleteCandidate: Expense?
    private var model: AppModel { state.model }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inspector").font(.title2.bold())
            switch state.inspectorSelection {
            case .expense(let id): expenseInspector(model.expense(id: id))
            case .bill(let id): billInspector(model.bills.first { $0.id == id })
            case .card(let id): cardInspector(model.books.first { $0.id == id })
            case nil: ContentUnavailableView("Nothing Selected", systemImage: "cursorarrow.click", description: Text("Select a transaction, bill, or card."))
            }
            if model.undoExpense != nil { Button("Undo Delete") { model.undoDelete() } }
            Spacer()
        }.padding(20).navigationTitle("Inspector")
        .alert("Delete this expense?", isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })) {
            Button("Delete", role: .destructive) { if let expense = deleteCandidate { model.delete(expense); state.inspectorSelection = nil }; deleteCandidate = nil }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: { Text("You can undo immediately from the inspector.") }
    }

    @ViewBuilder private func expenseInspector(_ expense: Expense?) -> some View {
        if let expense {
            Text(model.title(expense)).font(.headline)
            Text(Money.format(expense.amount)).font(.system(.title, design: .monospaced, weight: .semibold))
            LabeledContent("Date", value: expense.day)
            LabeledContent("Category", value: model.category(expense.allocations.first?.categoryID)?.name ?? "Split")
            LabeledContent("Card", value: model.books.first(where: { $0.id == expense.bookID })?.name ?? "")
            Divider()
            Button("Edit") { model.edit(expense); model.showEntry = false; state.regularEntryVisible = true }
            Button("Repeat") { model.repeatExpense(expense); model.showEntry = false; state.regularEntryVisible = true }
            Button("Delete", role: .destructive) { deleteCandidate = expense }
        }
    }

    @ViewBuilder private func billInspector(_ bill: BillRule?) -> some View {
        if let bill {
            Text(bill.name).font(.headline)
            Text(Money.format(bill.amount)).font(.system(.title2, design: .monospaced))
            LabeledContent("Schedule", value: bill.recurrence.title)
            LabeledContent("Recording", value: bill.recordingMode.title)
        }
    }

    @ViewBuilder private func cardInspector(_ book: BookProfile?) -> some View {
        if let book {
            Text(book.name).font(.headline)
            LabeledContent("Transactions", value: "\(model.expenses(for: book.id).count)")
            LabeledContent("Total", value: Money.format(model.expenses(for: book.id).reduce(0) { $0 + $1.amount }))
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
