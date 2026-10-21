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
    @AppStorage("MacSidebarStacksExpanded") private var stacksExpanded = true
    @AppStorage("MacSidebarCardsExpanded") private var cardsExpanded = true
    @State private var peekOpen = false // lags the destination one tick so the row exists before the group expands
    @AppStorage("MacSidebarPlanningExpanded") private var planningExpanded = true
    @AppStorage("MacSidebarShowAllStacks") private var showAllStacks = false
    @AppStorage("MacSidebarShowAllCards") private var showAllCards = false

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
                    if state.inspectorVisible && state.destination != .chat { // chat has nothing to inspect
                        MacInspector(state: state)
                            .frame(width: 300)
                            .transition(.move(edge: .trailing))
                    }
                }
                .clipped()
                .animation(.smooth(duration: 0.25), value: state.inspectorVisible)
                .toolbar { toolbar } // on the detail column: on the split view the spacers were ignored
            }
            // Scroll vs table pages gave the bar different backgrounds; the title is hidden at the scene (showsTitle: false).
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
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
        .sheet(item: $state.transferSheet) { MacDataTransferView(state: state, mode: $0) }
        .sheet(isPresented: $state.regularEntryVisible) {
            MacExpenseForm(model: model, title: model.draft.editing ? "Edit Expense" : "New Expense") { _ in state.regularEntryVisible = false }
        }
        .sheet(isPresented: $state.addingCard) { MacCardEditor(model: model, card: nil) { state.addingCard = false } }
        .sheet(item: $state.editingCard) { card in MacCardEditor(model: model, card: card) { state.editingCard = nil } }
        .sheet(item: $state.editingStack) { stack in MacStackEditor(state: state, stack: stack) { state.editingStack = nil } }
        .confirmationDialog("Delete “\(state.deletingCard?.name ?? "")”?", isPresented: Binding(get: { state.deletingCard != nil }, set: { if !$0 { state.deletingCard = nil } }), titleVisibility: .visible) {
            Button("Delete Card", role: .destructive) { if let card = state.deletingCard { state.deleteCard(card) } }
        } message: { Text("All expenses, budgets and bills on this card are deleted too. This can't be undone.") }
        .alert(model.spendingCurrencyQuestion, isPresented: Binding(get: { model.spendingCurrencySuggestion != nil }, set: { if !$0 { model.spendingCurrencySuggestion = nil } })) {
            Button("Use It") { Task { await model.acceptSpendingCurrencySuggestion() } }
            Button("Not Now", role: .cancel) { model.spendingCurrencySuggestion = nil }
        } message: { Text("New expenses on this card will start in that currency, and the card shows an ≈ amount in it.") }
        .alert("Monocle", isPresented: Binding(get: { model.error != nil || state.shortcutError != nil }, set: { if !$0 { model.error = nil; state.shortcutError = nil } })) {
            Button("OK") { model.error = nil; state.shortcutError = nil }
        } message: { Text(model.error ?? state.shortcutError ?? "") }
        .onChange(of: state.searchFocusToken) { _, _ in searchExpanded = true } // an open field refocuses on the token itself
        .onChange(of: model.showEntry) { _, shouldShow in
            // Also from a Quick Chat card's Edit: the sheet lives on the main window, so bring it forward.
            if shouldShow { model.showEntry = false; state.showEntryPanel(); state.bringMainWindowForward() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background { model.appLock.suspend() }
            else if phase == .active { model.appLock.resume() }
        }
    }

    private var sidebar: some View {
        let hidden = model.alwaysHiddenCardIDs
        let cards = model.orderedCards.filter { !hidden.contains($0.id) }
        // A collapsed group still shows the open row alone (not the whole list), and folds back when you leave it.
        var peekStack: Stack? { if !stacksExpanded, case .stack(let id) = state.destination { model.stacks.first { $0.id == id } } else { nil } }
        var peekCard: Card? { if !cardsExpanded, case .card(let id) = state.destination { cards.first { $0.id == id } } else { nil } }
        return List(selection: Binding(get: { state.destination }, set: { value in withAnimation(.smooth(duration: 0.25)) { state.destination = value } })) { // animated so the peeked group folds on a sidebar click
            Section {
                Label("Overview", systemImage: "rectangle.grid.2x2").tag(MacDestination.overview)
                Label("Activity", systemImage: "list.bullet.rectangle").tag(MacDestination.activity)
            }
            Section(isExpanded: Binding(get: { stacksExpanded || (peekOpen && peekStack != nil) }, set: { stacksExpanded = $0 })) {
                ForEach(peekStack.map { [$0] } ?? Self.limited(model.stacks, showAll: showAllStacks) { state.destination == .stack($0.id) }) { stack in
                    Label(stack.name, systemImage: stack.icon).tag(MacDestination.stack(stack.id))
                        .contextMenu {
                            Button("Edit Stack…") { state.editingStack = stack }
                            Button("Delete Stack", role: .destructive) { state.deleteStack(stack) }.disabled(model.stacks.count < 2)
                        }
                }
                if peekStack == nil { moreToggle(count: model.stacks.count, showAll: $showAllStacks) }
                if peekStack == nil, state.showHiddenCards, !hidden.isEmpty {
                    Label("Hidden Cards", systemImage: "eye.slash").tag(MacDestination.hiddenCards)
                }
            } header: {
                Text("Stacks").contextMenu {
                    Button("New Stack…") { state.editingStack = Stack(name: "") }
                    Toggle("Show Hidden Cards", isOn: $state.showHiddenCards)
                }
            }
            Section(isExpanded: Binding(get: { cardsExpanded || (peekOpen && peekCard != nil) }, set: { cardsExpanded = $0 })) {
                if peekCard == nil { Label("All Cards", systemImage: "creditcard").tag(MacDestination.cards) }
                ForEach(peekCard.map { [$0] } ?? Self.limited(cards, showAll: showAllCards) { state.destination == .card($0.id) }) { card in
                    Label(card.name, systemImage: "creditcard.fill").tag(MacDestination.card(card.id))
                        .contextMenu { MacCardMenu(state: state, card: card) }
                }
                if peekCard == nil { moreToggle(count: cards.count, showAll: $showAllCards) }
            } header: {
                Text("Cards").contextMenu { Button("New Card…") { state.addingCard = true } }
            }
            Section("Planning", isExpanded: $planningExpanded) {
                Label("Budgets", systemImage: "gauge.with.dots.needle.67percent").tag(MacDestination.budgets)
                Label("Bills", systemImage: "calendar.badge.clock").tag(MacDestination.bills)
            }
            Section {
                Label("Analytics", systemImage: "chart.bar.xaxis").tag(MacDestination.analytics)
                Label("Chat", systemImage: "bubble.left.and.text.bubble.right").tag(MacDestination.chat)
            }
        }
        .listStyle(.sidebar)
        .animation(.smooth(duration: 0.25), value: state.destination) // animates the group folding back
        .onChange(of: state.destination, initial: true) {
            var instant = Transaction(); instant.disablesAnimations = true
            withTransaction(instant) { peekOpen = false }
            DispatchQueue.main.async { withAnimation(.smooth(duration: 0.25)) { peekOpen = true } }
        }
        .navigationTitle("monocle")
    }

    static let sidebarLimit = 5

    /// The first `sidebarLimit` items, plus any selected item past them so the selection never vanishes.
    static func limited<T: Identifiable>(_ items: [T], showAll: Bool, isSelected: (T) -> Bool) -> [T] {
        guard !showAll, items.count > sidebarLimit else { return items }
        return items.enumerated().filter { $0.offset < sidebarLimit || isSelected($0.element) }.map(\.element)
    }

    @ViewBuilder private func moreToggle(count: Int, showAll: Binding<Bool>) -> some View {
        if count > Self.sidebarLimit {
            Button(showAll.wrappedValue ? "Show Less" : "Show \(count - Self.sidebarLimit) More") { showAll.wrappedValue.toggle() }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.callout)
        }
    }

    @ViewBuilder private var content: some View {
        switch state.destination {
        case .overview: MacOverviewView(state: state)
        case .activity: MacActivityView(state: state, cardID: nil)
        case .cards: MacCardsView(state: state)
        case .card(let id): MacCardDetailView(state: state, cardID: id)
        case .stack(let id):
            if let stack = model.stacks.first(where: { $0.id == id }) { MacStackView(state: state, stack: stack) }
            else { ContentUnavailableView("Stack not found", systemImage: "rectangle.stack") }
        case .hiddenCards: MacStackView(state: state, stack: nil)
        case .budgets: MacBudgetsView(state: state)
        case .bills: MacBillsView(state: state)
        case .analytics: MacAnalyticsView(state: state)
        case .chat: MacChatView(state: state)
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
        ToolbarItemGroup(placement: .navigation) {
            Button { state.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                .disabled(state.backStack.isEmpty)
                .help("Back (\(state.shortcut(for: .goBack)?.displayName ?? ""))")
                .accessibilityIdentifier("navBack")
            Button { state.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                .disabled(state.forwardStack.isEmpty)
                .help("Forward (\(state.shortcut(for: .goForward)?.displayName ?? ""))")
                .accessibilityIdentifier("navForward")
        }
        // No title fills the leading side any more, so a flexible spacer pushes the buttons trailing.
        ToolbarSpacer(.flexible, placement: .primaryAction)
        if state.filterOptions != nil {
            ToolbarItem(placement: .primaryAction) { ActivityFilterButton(state: state) }
        }
        ToolbarItem(placement: .primaryAction) { searchField }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            Button { state.perform(.commandBar) } label: { Label("Commands", systemImage: "command") }
                .help("Command Bar (\(state.shortcut(for: .commandBar)?.displayName ?? ""))")
            Button { state.perform(.toggleInspector) } label: { Label("Inspector", systemImage: "pointer.arrow.click") }
                .disabled(state.destination == .chat)
                .help("Toggle Inspector (\(state.shortcut(for: .toggleInspector)?.displayName ?? ""))")
                .accessibilityIdentifier("toggleInspector")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
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
                    ForEach(model.unhiddenCards) { card in
                        MacCardView(model: model, card: card)
                            .onTapGesture { state.selectCard(card.id) }
                    }
                }.padding(.vertical, 12) // room for the shadow and hover lift
            }.scrollIndicators(.hidden).scrollClipDisabled() // clipping cut the shadow into a hard edge
            HStack {
                SummaryTile(title: "Cycle spending", value: Money.format(model.spent, code: model.activeCardCurrency), detail: model.cycle.label)
                SummaryTile(title: "Remaining", value: Money.format(model.remaining, code: model.activeCardCurrency), detail: "of \(Money.format(model.activeBudget.overallLimit, code: model.activeCardCurrency))")
                SummaryTile(title: "Upcoming bills", value: "\(model.billOccurrences.filter { $0.status == .pending }.count)", detail: "Awaiting action")
            }
            Text("Recent Activity").font(.title2.bold())
            MacExpenseTable(state: state, cardIDs: nil, limit: 50) // same table as Activity; fills the rest of the window
        }.padding(24).navigationTitle("Overview")
    }
}

private struct MacCardView: View {
    let model: AppModel
    let card: Card
    var preview: CardCustomization? // the editor's unsaved style
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var tilt: CGSize = .zero // pointer position, -1...1 from the centre
    @State private var hovering = false
    private static let size = CGSize(width: 250, height: 150)
    private var customization: CardCustomization { preview ?? model.customization(for: card.id) }

    var body: some View {
        VStack(alignment: .leading) {
            HStack { Image(systemName: "circle.grid.cross.fill"); Spacer(); Text("MONOCLE").font(.caption2.bold()) }
            Spacer()
            Text(card.name).font(.title3.bold())
            Text(Money.format(model.spent(for: card.id), code: model.currency(of: card))).font(.system(.headline, design: .monospaced))
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
        case .stock(let design): StockDesignBackgroundView(design: design)
        case .customPhoto(let filename):
            if let image = CardArtworkStore.shared.loadArtwork(filename: filename) {
                Image(nsImage: image).resizable().scaledToFill().overlay(Color.black.opacity(0.16))
            } else { Rectangle().fill(CardPalette.color(for: card.colorIndex).gradient) }
        }
    }
}


struct MacActivityView: View {
    @Bindable var state: MacAppState
    let cardID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cardID.flatMap { id in state.model.cards.first(where: { $0.id == id })?.name } ?? "Activity").font(.largeTitle.bold())
            MacExpenseTable(state: state, cardIDs: cardID.map { [$0] })
        }.padding(24).navigationTitle("Activity")
    }
}

/// The one transaction table (Overview, Activity, card and stack pages). `limit` keeps only the newest rows.
struct MacExpenseTable: View {
    let state: MacAppState
    /// nil = every card except hidden ones (as iOS "All Activities").
    let cardIDs: [UUID]?
    var limit: Int?
    @State private var sortOrder: [KeyPathComparator<MacExpenseRow>] = []
    @State private var allRows: [MacExpenseRow] = []
    @State private var rows: [MacExpenseRow] = []
    @State private var ownerID = UUID()
    private var filter: ActivityFilter { state.activityFilter }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if limit == nil, filter.isActive {
                HStack(spacing: 10) {
                    Text("\(rows.count) of \(allRows.count) · filtered").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                    Button("Clear filters") { state.activityFilter = ActivityFilter() }.buttonStyle(.borderless)
                }
            }
            MacActivityTable(rows: rows, state: state, sortOrder: $sortOrder)
                .accessibilityIdentifier("activityTable")
        }
            // Rows rebuild only when data or the card changes, not on every window refresh (selection, inspector, typing).
            .onChange(of: RowsSource(revision: state.model.dataRevision, cardIDs: cardIDs, cardCount: state.model.cards.count), initial: true) { buildRows() }
            .onChange(of: state.searchText) { refresh() }
            .onChange(of: sortOrder) { refresh() }
            .onChange(of: filter) { refresh() }
            .onChange(of: cardIDs) { state.activityFilter = ActivityFilter() }
            .onAppear { if limit == nil { state.filterOwner = ownerID; publishOptions() } }
            .onDisappear {
                // A newly shown table may already own the filter; only the owner tears it down.
                guard state.filterOwner == ownerID else { return }
                state.filterOwner = nil; state.filterOptions = nil; state.activityFilter = ActivityFilter()
            }
    }

    private struct RowsSource: Equatable { let revision: UInt64; let cardIDs: [UUID]?; let cardCount: Int }

    private func buildRows() {
        let model = state.model
        var source = (cardIDs ?? model.unhiddenCards.map(\.id)).flatMap(model.expenses(for:))
        if let limit {
            source = Array(source.sorted { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }.prefix(limit))
        }
        let cards = Dictionary(model.cards.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let methods = Dictionary(model.paymentMethods.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        allRows = MacExpenseRow.make(source, cardNames: cards, categoryName: { model.category($0)?.name }, paidWithName: { methods[$0] })
        refresh()
        publishOptions()
    }

    private func publishOptions() {
        guard limit == nil, state.filterOwner == ownerID else { return }
        let options = ActivityFilterOptions(rows: allRows)
        if state.filterOptions != options { state.filterOptions = options }
    }

    private func refresh() { rows = MacExpenseRow.filter(allRows, query: state.searchText, filter: filter, sortOrder: sortOrder) }
}

struct MacExpenseRow: Identifiable {
    let expense: Expense
    let title: String
    let category: String
    let card: String
    var paidWith = ""
    var id: Expense.ID { expense.id }
    var day: String { expense.day }
    var amountMinor: Int64 { expense.amount }

    static func make(_ expenses: [Expense], cardNames: [UUID: String], categoryName: (UUID) -> String?, paidWithName: (UUID) -> String? = { _ in nil }) -> [MacExpenseRow] {
        var names: [UUID: String] = [:]
        func name(_ id: UUID?) -> String? {
            guard let id else { return nil }
            if let cached = names[id] { return cached }
            let value = categoryName(id); names[id] = value; return value
        }
        return expenses.map { expense in
            let category = name(expense.splits.first?.categoryID)
            return MacExpenseRow(expense: expense, title: expense.note.isEmpty ? category ?? "Expense" : expense.note,
                                 category: category ?? "Split", card: expense.cardID.flatMap { cardNames[$0] } ?? "",
                                 paidWith: expense.paidWithID.flatMap(paidWithName) ?? "")
        }
    }

    /// Search matches the title, note, category, card, Paid with, and the amount ("45000" or "45,000" finds Rp45,000).
    func matches(_ query: String, amountDigits: String?) -> Bool {
        title.localizedCaseInsensitiveContains(query) || category.localizedCaseInsensitiveContains(query)
            || card.localizedCaseInsensitiveContains(query) || paidWith.localizedCaseInsensitiveContains(query)
            || expense.note.localizedCaseInsensitiveContains(query)
            || amountDigits.map { Money.exactDigits(expense.amount).contains($0) } ?? false
    }

    static func filter(_ rows: [MacExpenseRow], query: String, filter: ActivityFilter = ActivityFilter(), sortOrder: [KeyPathComparator<MacExpenseRow>]) -> [MacExpenseRow] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = query.allSatisfy { $0.isNumber || ",. ".contains($0) } ? query.filter(\.isNumber) : ""
        let scoped = filter.isActive ? rows.filter(filter.matches) : rows
        let filtered = query.isEmpty ? scoped : scoped.filter { $0.matches(query, amountDigits: digits.isEmpty ? nil : digits) }
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
    private var selection: Binding<Set<Expense.ID>> {
        Binding(get: { state.inspectorSelection?.expenseIDs ?? [] },
                set: { state.inspect(MacInspectorSelection(expenseIDs: $0)) })
    }

    var body: some View {
        Table(rows, selection: selection, sortOrder: $sortOrder) {
                // Small minimums so sidebar + all columns + inspector fit the 1000pt minimum window.
                TableColumn("Date", value: \.day) { Text($0.day).font(.system(.body, design: .monospaced)) }.width(min: 90, ideal: 110)
                TableColumn("Note", value: \.title) { Text($0.title) }.width(min: 60, ideal: 180)
                TableColumn("Category", value: \.category) { Text($0.category) }.width(min: 50, ideal: 120)
                TableColumn("Card", value: \.card) { Text($0.card) }.width(min: 50, ideal: 120)
                TableColumn("Amount", value: \.amountMinor) { Text($0.expense.paidText).font(.system(.body, design: .monospaced)) }.width(min: 90, ideal: 130)
            }
            .contextMenu(forSelectionType: Expense.ID.self) { ids in
                let picked = expenses(ids)
                if picked.count == 1 { ExpenseMenuItems(state: state, expense: picked[0]) }
                else if picked.count > 1 { BulkExpenseMenuItems(state: state, expenses: picked) }
            } primaryAction: { ids in
                if ids.count == 1, let expense = expenses(ids).first { state.edit(expense) }
            }
            .onDeleteCommand { state.delete(expenses(selection.wrappedValue), undoManager: undoManager) }
    }

    private func expenses(_ ids: Set<Expense.ID>) -> [Expense] {
        rows.lazy.filter { ids.contains($0.id) }.map(\.expense)
    }
}

struct ExpenseMenuItems: View {
    let state: MacAppState
    let expense: Expense
    @Environment(\.undoManager) private var undoManager
    var body: some View {
        Button("Edit…") { state.edit(expense) }
        Button("Repeat…") { state.repeatExpense(expense) }
        if expense.splits.count == 1 { CategoryMenu(state: state, expenses: [expense]) }
        Divider()
        Button("Delete", role: .destructive) { state.delete(expense, undoManager: undoManager) }
    }
}

struct BulkExpenseMenuItems: View {
    let state: MacAppState
    let expenses: [Expense]
    @Environment(\.undoManager) private var undoManager
    var body: some View {
        CategoryMenu(state: state, expenses: expenses)
        Divider()
        Button("Delete \(expenses.count) Expenses", role: .destructive) { state.delete(expenses, undoManager: undoManager) }
    }
}

/// Categories every selected card shares; split expenses are left as they are.
struct CategoryMenu: View {
    let state: MacAppState
    let expenses: [Expense]
    @Environment(\.undoManager) private var undoManager
    var body: some View {
        let categories = state.sharedCategories(for: expenses)
        Menu("Change Category") {
            ForEach(categories) { category in
                Button { state.recategorize(expenses, to: category.id, undoManager: undoManager) } label: {
                    Label(category.name, systemImage: category.symbol)
                }
            }
        }
        .disabled(categories.isEmpty || expenses.allSatisfy { $0.splits.count > 1 })
    }
}

struct MacCardsView: View {
    @Bindable var state: MacAppState
    private var model: AppModel { state.model }

    var body: some View {
        let hidden = model.alwaysHiddenCardIDs
        let stacked = Set(model.stacks.flatMap(\.cardIDs))
        let unstacked = model.orderedCards.filter { !stacked.contains($0.id) && !hidden.contains($0.id) }
        Page(title: "Cards") {
            HStack {
                Spacer()
                GlassEffectContainer {
                    HStack {
                        Button("New Stack") { state.editingStack = Stack(name: "") }.buttonStyle(.glass)
                        Button("New Card") { state.addingCard = true }.buttonStyle(.glassProminent)
                    }
                }
            }
            ForEach(model.stacks) { stack in
                HStack {
                    Label(stack.name, systemImage: stack.icon).font(.title2.bold())
                    Spacer()
                    Button("Edit Stack…") { state.editingStack = stack }.buttonStyle(.glass)
                }.frame(height: 32)
                MacCardGrid(state: state, cards: model.cards(in: stack))
            }
            if !unstacked.isEmpty {
                if !model.stacks.isEmpty { Text("Not in a Stack").font(.title2.bold()) }
                MacCardGrid(state: state, cards: unstacked)
            }
            if state.showHiddenCards, !hidden.isEmpty {
                Label("Hidden Cards", systemImage: "eye.slash").font(.title2.bold()).frame(height: 32)
                MacCardGrid(state: state, cards: model.hiddenCards)
            }
        }
    }
}

private struct MacCardGrid: View {
    let state: MacAppState
    let cards: [Card]
    var body: some View {
        // Fixed-width columns: flexible ones re-spaced every card on each frame of the inspector animation.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 250), spacing: 18, alignment: .leading)], alignment: .leading, spacing: 18) {
            ForEach(cards) { card in
                MacCardView(model: state.model, card: card)
                    .onTapGesture { state.selectCard(card.id) }
                    .contextMenu { MacCardMenu(state: state, card: card) }
            }
        }
    }
}

/// Right-click actions for a card, shared by the sidebar, the Cards page and stack pages.
struct MacCardMenu: View {
    let state: MacAppState
    let card: Card
    private var model: AppModel { state.model }
    var body: some View {
        let hidden = model.alwaysHiddenCardIDs.contains(card.id)
        Button("Edit Card…") { state.editingCard = card }
        if !hidden, !model.stacks.isEmpty {
            Menu("Stacks") {
                ForEach(model.stacks) { stack in
                    Toggle(stack.name, isOn: Binding(get: { stack.cardIDs.contains(card.id) }, set: { on in
                        var stack = stack
                        if on { stack.cardIDs.append(card.id) } else { stack.cardIDs.removeAll { $0 == card.id } }
                        model.performUIAction { try model.updateStack(stack) }
                    }))
                }
            }
        }
        Button(hidden ? "Unhide Card" : "Hide Card") { state.setCardHidden(card, !hidden) }
        Divider()
        Button("Delete Card…", role: .destructive) { state.deletingCard = card }.disabled(model.cards.count < 2)
    }
}

/// One stack's cards and their combined transactions. `stack == nil` is the built-in Hidden Cards group.
struct MacStackView: View {
    @Bindable var state: MacAppState
    let stack: Stack?
    private var model: AppModel { state.model }

    var body: some View {
        let cards = stack.map(model.cards(in:)) ?? model.hiddenCards
        let expenses = cards.flatMap { model.expenses(for: $0.id) }
        // Stacks use the calendar month, like iOS; a single card's own cycle doesn't apply here.
        let month = Cycle.containing(.now, startDay: 1)
        let cycleTotal = expenses.filter { month.contains($0) }.reduce(0) { $0 + $1.amount }
        let budget = stack.flatMap(model.stackBudgetLimit)
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(stack?.name ?? "Hidden Cards", systemImage: stack?.icon ?? "eye.slash").font(.largeTitle.bold())
                    Spacer()
                    if let stack { Button("Edit Stack…") { state.editingStack = stack }.buttonStyle(.glass) }
                }.frame(height: 44) // SF Symbols differ in height; a fixed row keeps every stack page aligned
                if cards.isEmpty {
                    Text(stack == nil ? "No hidden cards." : "No cards in this stack yet. Use Edit Stack… to add some.").foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 14) {
                            ForEach(cards) { card in
                                MacCardView(model: model, card: card)
                                    .onTapGesture { state.selectCard(card.id) }
                                    .contextMenu { MacCardMenu(state: state, card: card) }
                            }
                        }.padding(.vertical, 12)
                    }.scrollIndicators(.hidden).scrollClipDisabled()
                }
                HStack {
                    SummaryTile(title: "This month", value: Money.format(cycleTotal), detail: month.label)
                    if let budget, let stack {
                        SummaryTile(title: "Stack budget", value: Money.format(budget),
                                    detail: stack.capLimit != nil ? "Cap · \(Money.format(budget - cycleTotal)) left" : "Sum of cards · \(Money.format(budget - cycleTotal)) left")
                    }
                    SummaryTile(title: "Expenses", value: "\(expenses.count)", detail: "\(cards.count) card\(cards.count == 1 ? "" : "s")")
                }
            }.padding(24)
            Divider()
            MacExpenseTable(state: state, cardIDs: cards.map(\.id)).padding(24)
        }.navigationTitle(stack?.name ?? "Hidden Cards")
    }
}

extension AppModel {
    func cards(in stack: Stack) -> [Card] { cards(in: .stack(id: stack.id, name: stack.name)) }
    var hiddenCards: [Card] { orderedCards.filter { alwaysHiddenCardIDs.contains($0.id) } }
}

private struct MacCardEditor: View {
    private enum Kind: String, CaseIterable { case color = "Color", custom = "Custom", template = "Template", photo = "Photo" }
    let model: AppModel
    let original: Card?
    let close: () -> Void
    private let draftID: UUID // names photo files before a new card has its real id
    @State private var name: String
    @State private var custom: CardCustomization
    @State private var kind: Kind
    @State private var customColor: Color
    @State private var importingPhoto = false
    @State private var preparedPhotos: Set<String> = [] // saved while picking; unused ones are removed on close
    @State private var error: String?
    @State private var budgetCurrency: String
    @State private var spendingCurrency: String
    @State private var defaultPaidWithID: UUID?
    @State private var saving = false
    private var currencyChoices: [String] {
        var seen = Set<String>()
        return ([model.reportingCurrency, budgetCurrency, spendingCurrency] + Money.commonCurrencies).filter { seen.insert($0).inserted }
    }

    init(model: AppModel, card: Card?, close: @escaping () -> Void) {
        self.model = model; original = card; self.close = close
        draftID = card?.id ?? UUID()
        let budget = card.map { model.currency(of: $0) } ?? model.reportingCurrency
        _budgetCurrency = State(initialValue: budget)
        _spendingCurrency = State(initialValue: card?.spendingCurrency ?? budget)
        _defaultPaidWithID = State(initialValue: card?.defaultPaidWithID)
        let custom = card.map { model.customization(for: $0.id) } ?? .defaultFor(colorIndex: model.cards.count % CardPalette.standard.count)
        _name = State(initialValue: card?.name ?? "")
        _custom = State(initialValue: custom)
        switch custom.style {
        case .palette: _kind = State(initialValue: .color); _customColor = State(initialValue: CardPalette.color(for: 0))
        case .customColor(let hex): _kind = State(initialValue: .custom); _customColor = State(initialValue: CardPalette.color(fromHex: hex))
        case .stock: _kind = State(initialValue: .template); _customColor = State(initialValue: CardPalette.color(for: 0))
        case .customPhoto: _kind = State(initialValue: .photo); _customColor = State(initialValue: CardPalette.color(for: 0))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(original == nil ? "New Card" : "Edit Card").font(.title2.bold())
            MacCardView(model: model, card: Card(id: draftID, name: name.isEmpty ? "Card name" : name), preview: custom)
                .frame(maxWidth: .infinity)
            Form {
                TextField("Name", text: $name)
                Picker("Style", selection: $kind) { ForEach(Kind.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { _, kind in applyKind(kind) }
                styleControls
                Picker("Text", selection: $custom.textTone) { ForEach(CardTextTone.allCases, id: \.self) { Text($0.title).tag($0) } }
                if original != nil {
                    Section("Currency and payment") {
                        Picker("Budget currency", selection: $budgetCurrency) { ForEach(currencyChoices, id: \.self) { Text($0).tag($0) } }
                        Picker("Spending currency", selection: $spendingCurrency) { ForEach(currencyChoices, id: \.self) { Text($0).tag($0) } }
                        Picker("Default Paid with", selection: $defaultPaidWithID) {
                            Text("None").tag(UUID?.none)
                            ForEach(model.paymentMethods) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    }
                }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { finish(keeping: nil) }
                Button("Save") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || saving)
            }
        }
        .padding(24).frame(width: 560)
        .fileImporter(isPresented: $importingPhoto, allowedContentTypes: [.image]) { result in
            do { try loadPhoto(result.get()) } catch { self.error = error.localizedDescription }
        }
    }

    @ViewBuilder private var styleControls: some View {
        switch kind {
        case .color:
            LabeledContent("Color") {
                HStack(spacing: 6) {
                    ForEach(CardPalette.standard) { swatch in
                        Circle().fill(swatch.color).frame(width: 20, height: 20)
                            .overlay { if custom.style == .palette(index: swatch.id) { Circle().strokeBorder(.primary, lineWidth: 2) } }
                            .onTapGesture { custom.style = .palette(index: swatch.id) }
                            .accessibilityLabel(swatch.name).accessibilityAddTraits(.isButton)
                    }
                }
            }
        case .custom:
            ColorPicker("Color", selection: $customColor, supportsOpacity: false)
                .onChange(of: customColor) { _, color in custom.style = .customColor(hex: CardPalette.hexString(from: color)) }
        case .template:
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(StockCardDesign.allCases) { design in
                    VStack(spacing: 4) {
                        StockDesignBackgroundView(design: design)
                            .frame(height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay { if custom.style == .stock(design) { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 3) } }
                        Text(design.displayName).font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { custom.style = .stock(design) }
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton)
                }
            }
        case .photo:
            LabeledContent("Photo") { Button("Choose Image…") { importingPhoto = true } }
        }
    }

    private func applyKind(_ kind: Kind) {
        switch kind {
        case .color: if case .palette = custom.style {} else { custom.style = .palette(index: original?.colorIndex ?? 0) }
        case .custom: custom.style = .customColor(hex: CardPalette.hexString(from: customColor))
        case .template: if case .stock = custom.style {} else { custom.style = .stock(.sunsetHeat) }
        case .photo: if case .customPhoto = custom.style {} else { importingPhoto = true }
        }
    }

    private func loadPhoto(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let filename = try CardArtworkStore.shared.saveArtwork(Data(contentsOf: url), for: draftID)
        preparedPhotos.insert(filename)
        custom.style = .customPhoto(filename: filename)
        error = nil
    }

    private func save() {
        saving = true
        Task {
            defer { saving = false }
            do { try await apply() } catch { self.error = error.localizedDescription }
        }
    }

    private func apply() async throws {
        do {
            let id: UUID
            if let original {
                id = original.id
                if name != original.name { try model.renameCard(id: id, to: name) }
            } else {
                id = try model.createCard(named: name).id
            }
            if custom != model.customization(for: id) { model.updateCustomization(custom, for: id) }
            if let original {
                if defaultPaidWithID != original.defaultPaidWithID { try model.setDefaultPaidWith(defaultPaidWithID, for: id) }
                if budgetCurrency != model.currency(of: original) || spendingCurrency != (original.spendingCurrency ?? model.currency(of: original)) {
                    try await model.setCardCurrencies(budget: budgetCurrency, spending: spendingCurrency, for: id)
                }
            }
            finish(keeping: custom.style)
        }
    }

    private func finish(keeping style: CardBackgroundStyle?) {
        for filename in preparedPhotos where style != .customPhoto(filename: filename) { CardArtworkStore.shared.deleteArtwork(filename: filename) }
        close()
    }
}

private struct MacStackEditor: View {
    let state: MacAppState
    let original: Stack
    let close: () -> Void
    @State private var stack: Stack
    @State private var error: String?
    private static let icons = ["rectangle.stack", "airplane", "house", "cart", "briefcase", "creditcard", "fork.knife", "sparkles", "car", "cross.case", "sportscourt", "bag"]
    private var isNew: Bool { !model.stacks.contains { $0.id == original.id } }

    private var model: AppModel { state.model }

    init(state: MacAppState, stack: Stack, close: @escaping () -> Void) {
        self.state = state; original = stack; self.close = close
        _stack = State(initialValue: stack)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "New Stack" : "Edit Stack").font(.title2.bold())
            Form {
                TextField("Name", text: $stack.name)
                Picker("Icon", selection: $stack.icon) { ForEach(Self.icons, id: \.self) { Image(systemName: $0).tag($0) } }
                Section("Cards") {
                    ForEach(model.orderedCards.filter { !model.alwaysHiddenCardIDs.contains($0.id) }) { card in
                        // A card belongs to one stack; turning it on here moves it when saved.
                        let elsewhere = model.stacks.first { $0.id != original.id && $0.cardIDs.contains(card.id) }?.name
                        Toggle(isOn: Binding(get: { stack.cardIDs.contains(card.id) }, set: { on in
                            if on { stack.cardIDs.append(card.id) } else { stack.cardIDs.removeAll { $0 == card.id } }
                        })) {
                            Text(card.name)
                            if let elsewhere, !stack.cardIDs.contains(card.id) { Text("In \(elsewhere)") }
                        }
                    }
                }
                Section {
                    Toggle("Monthly cap", isOn: Binding(get: { stack.capLimit != nil }, set: { on in
                        stack.capLimit = on ? (cardSum ?? 1_000_000 * 100) : nil
                    }))
                    if stack.capLimit != nil {
                        TextField("Cap (Rp)", text: Binding(get: { stack.capLimit.map(Money.exactDigits) ?? "" }, set: { text in
                            if let value = try? Money.parse(text) { stack.capLimit = value }
                        }))
                    }
                } header: { Text("Budget") } footer: {
                    Text(stack.capLimit != nil ? "The cap replaces the sum of this stack's card budgets."
                         : cardSum.map { "Sum of card budgets: \(Money.format($0)) a month." } ?? "Sum of the cards' monthly budgets.")
                }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red) }
            HStack {
                if !isNew {
                    Button("Delete Stack", role: .destructive) { state.deleteStack(original); close() }
                        .disabled(model.stacks.count < 2) // the model keeps at least one stack
                }
                Spacer()
                Button("Cancel", role: .cancel, action: close)
                Button("Save") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command)
            }
        }.padding(24).frame(width: 440, height: 600)
    }

    private var cardSum: Int64? { var uncapped = stack; uncapped.capLimit = nil; return model.stackBudgetLimit(uncapped) }

    private func save() {
        do {
            if isNew {
                let created = try model.createStack(name: stack.name, icon: stack.icon, cardIDs: stack.cardIDs)
                if stack.capLimit != nil { var value = created; value.capLimit = stack.capLimit; try model.updateStack(value) }
            }
            else {
                var value = stack
                let trimmed = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
                value.name = trimmed.isEmpty ? original.name : String(trimmed.prefix(40))
                try model.updateStack(value)
            }
            close()
        } catch { self.error = error.localizedDescription }
    }
}

struct MacCardDetailView: View {
    @Bindable var state: MacAppState
    let cardID: UUID
    var body: some View {
        VStack(spacing: 0) {
            if let card = state.model.cards.first(where: { $0.id == cardID }) {
                HStack(alignment: .center, spacing: 24) { MacCardView(model: state.model, card: card); MacCardStats(model: state.model, card: card) }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                Divider()
            }
            MacActivityView(state: state, cardID: cardID)
        }.onAppear { _ = state.model.selectCard(cardID) }
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
            case .expenses(let ids):
                let expenses = ids.compactMap(model.expense(id:))
                if expenses.isEmpty { empty } else { MultiExpenseInspector(state: state, expenses: expenses) }
            case .bill(let id): if let bill = model.bills.first(where: { $0.id == id }) { BillInspector(model: model, bill: bill) { state.editingBill = bill } } else { empty }
            case .card(let id): if let card = model.cards.first(where: { $0.id == id }) { CardInspector(state: state, card: card) } else { empty }
            case nil: empty
            }
        }
        // Same opaque paper as the content so the panel reads as part of the window, not a sheet over the wallpaper.
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacTheme.paper)
    }

    private var empty: some View {
        ContentUnavailableView("Nothing Selected", systemImage: "cursorarrow.click", description: Text("Select an expense, bill, or card."))
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

/// Liquid Glass actions floating under the inspector form; the destructive one sits apart on the trailing edge.
private struct InspectorActions<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    var body: some View {
        GlassEffectContainer {
            HStack { leading; Spacer(); trailing }
        }
        .buttonStyle(.glass).controlSize(.large)
        .padding(12).frame(maxWidth: .infinity)
    }
}

private struct ExpenseInspector: View {
    let state: MacAppState
    let expense: Expense
    @Environment(\.undoManager) private var undoManager
    private var model: AppModel { state.model }

    var body: some View {
        let isSplit = expense.splits.count > 1
        let category = model.category(expense.splits.first?.categoryID)
        Form {
            Section {
                InspectorHeader(symbol: isSplit ? "square.split.2x1" : category?.symbol ?? "questionmark.circle",
                                title: model.title(expense),
                                subtitle: isSplit ? "Split across \(expense.splits.count) categories" : category?.name ?? "No category",
                                amount: expense.amount)
            }
            Section("Details") {
                LabeledContent("Date", value: Day.title(expense.day))
                LabeledContent("Card", value: model.cards.first(where: { $0.id == expense.cardID })?.name ?? "—")
                if expense.originalCurrency != nil {
                    LabeledContent("Paid", value: expense.paidText)
                    LabeledContent("Rate", value: "1 \(expense.originalCurrency ?? "") = \(expense.rate ?? "") \(model.reportingCurrency)\(expense.rateSource == .manual ? " (entered)" : "")")
                }
                if let method = model.paymentMethod(expense.paidWithID) { LabeledContent("Paid with", value: method.name) }
                LabeledContent("Added", value: expense.createdAt.formatted(date: .abbreviated, time: .shortened))
                if expense.source != "manual" { LabeledContent("Source", value: expense.source.capitalized) }
            }
            // The header shows two lines of the note; long notes get their full text here.
            if expense.note.count > 60 || expense.note.contains("\n") {
                Section("Note") { Text(expense.note).textSelection(.enabled) }
            }
            if isSplit {
                Section("Split") {
                    ForEach(Array(expense.splits.enumerated()), id: \.offset) { _, split in
                        let part = model.category(split.categoryID)
                        LabeledContent {
                            Text(Money.format(split.amount)).font(.system(.body, design: .monospaced))
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
                Button("Delete", role: .destructive) { state.delete(expense, undoManager: undoManager) }.foregroundStyle(.red)
                    .help("Delete (Edit ▸ Undo restores it)")
            }
        }
    }
}

private struct MultiExpenseInspector: View {
    let state: MacAppState
    let expenses: [Expense]
    @Environment(\.undoManager) private var undoManager
    private var model: AppModel { state.model }

    var body: some View {
        let days = expenses.map(\.day).sorted()
        let splits = expenses.filter { $0.splits.count > 1 }.count
        let byCategory = Dictionary(grouping: expenses.filter { $0.splits.count == 1 }) { $0.splits[0].categoryID }
            .map { (id: $0.key, category: model.category($0.key), total: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.total > $1.total }
        Form {
            Section {
                InspectorHeader(symbol: "square.stack", title: "\(expenses.count) Expenses",
                                subtitle: days.first == days.last ? Day.title(days[0]) : "\(Day.title(days[0])) – \(Day.title(days[days.count - 1]))",
                                amount: expenses.reduce(0) { $0 + $1.amount })
            }
            Section("By Category") {
                ForEach(byCategory, id: \.id) { entry in
                    LabeledContent {
                        Text(Money.format(entry.total)).font(.system(.body, design: .monospaced))
                    } label: {
                        Label(entry.category?.name ?? "No category", systemImage: entry.category?.symbol ?? "questionmark.circle")
                    }
                }
                if splits > 0 { LabeledContent("Split", value: "\(splits)") }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InspectorActions {
                CategoryMenu(state: state, expenses: expenses).fixedSize()
            } trailing: {
                Button("Delete \(expenses.count)", role: .destructive) { state.delete(expenses, undoManager: undoManager) }.foregroundStyle(.red)
                    .help("Delete all selected (Edit ▸ Undo restores them)")
            }
        }
    }
}

private struct BillInspector: View {
    let model: AppModel
    let bill: Bill
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
                        Button("Skip") { act { try model.skipBillOccurrence(pending.id) } }.buttonStyle(.glass)
                        Spacer()
                        Button("Add") { act { _ = try model.confirmBillOccurrence(pending.id) } }.buttonStyle(.glassProminent)
                    }
                }
            }
            Section("Schedule") {
                LabeledContent("Repeats", value: bill.recurrence.title)
                LabeledContent("When due", value: bill.recordingMode.title)
                LabeledContent("Reminder", value: !bill.hasReminder ? "Off" : bill.reminderLeadDays == 0 ? "On the day" : "\(bill.reminderLeadDays) days before")
                LabeledContent("Card", value: model.cards.first(where: { $0.id == bill.cardID })?.name ?? "—")
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InspectorActions { Button("Edit Bill…", action: edit) } trailing: { EmptyView() }
        }
    }

    private func act(_ work: () throws -> Void) {
        do { try work() } catch { model.report(error) }
    }
}

private struct CardInspector: View {
    let state: MacAppState
    let card: Card
    private var model: AppModel { state.model }

    var body: some View {
        let expenses = model.expenses(for: card.id)
        Form {
            Section {
                MacCardView(model: model, card: card).frame(maxWidth: .infinity)
            }
            Section("Spending") {
                LabeledContent("Expenses", value: "\(expenses.count)")
                LabeledContent("Total", value: Money.format(expenses.reduce(0) { $0 + $1.amount }))
                if let last = expenses.map(\.day).max() { LabeledContent("Last expense", value: Day.title(last)) }
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            InspectorActions {
                Button("New Expense on This Card") { _ = model.selectCard(card.id); state.perform(.newExpense) }
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
