import SwiftUI

struct ScrollInfo: Equatable {
    var scrollOffset: CGFloat = 0
    var containerSize: CGSize = .zero
    var safeArea: EdgeInsets = .init()
    var minY: CGFloat = 0
}

/// Main home screen presenting an Apple Wallet-style stacked card deck with durable multi-book persistence.
struct BookHomeView: View {
    @Bindable var model: AppModel
    var showsBottomBar: Bool = false
    @State private var selectedID: UUID?
    @State private var allActivities = false
    @State private var managing = false
    @State private var showingBudgets = false
    @State private var showingCreateBook = false
    @State private var newBookName = ""
    @State private var createBookError: String?
    @State private var pull: CGFloat = 0
    @State private var info = ScrollInfo()
    @ScaledMetric(relativeTo: .headline) private var stripHeight = 44
    @ScaledMetric(relativeTo: .title) private var cardHeight = 224
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var headingFocused: Bool

    private var visible: [BookProfile] { model.visibleBooks }
    private var current: BookProfile? { model.books.first { $0.id == selectedID } }

    private var direction: BookVisualDirection { model.visualDirection }
    private var paper: Color {
        switch direction {
        case .light:
            return MC.paper
        case .ledger:
            return Color(red: 0.96, green: 0.94, blue: 0.88)
        case .instrument, .signal:
            return .black
        }
    }
    private var ink: Color {
        switch direction {
        case .light, .ledger:
            return MC.ink
        case .instrument, .signal:
            return .white
        }
    }
    private var amountFont: Font {
        switch direction {
        case .light, .signal:
            return .title.bold()
        case .ledger:
            return .system(.title, design: .serif, weight: .semibold)
        case .instrument:
            return .system(.title, design: .monospaced, weight: .bold)
        }
    }

    private static let cardPalette: [Color] = [
        Color(red: 0.99, green: 0.40, blue: 0.22), // Tangerine
        Color(red: 0.68, green: 0.79, blue: 0.99), // Soft Sky Blue
        Color(red: 0.84, green: 0.94, blue: 0.38), // Acid Lime
        Color(red: 0.93, green: 0.68, blue: 0.88), // Lavender
        Color(red: 0.98, green: 0.80, blue: 0.28), // Goldenrod
        Color(red: 0.40, green: 0.85, blue: 0.75), // Seafoam
        Color(red: 0.85, green: 0.45, blue: 0.55), // Rose
        Color(red: 0.55, green: 0.60, blue: 0.90)  // Periwinkle
    ]

    private func cardColor(for book: BookProfile) -> Color {
        Self.cardPalette[abs(book.colorIndex) % Self.cardPalette.count]
    }

    private var selectedBookBinding: Binding<BookProfile?> {
        Binding(
            get: { current },
            set: { newBook in
                focus(newBook?.id)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 24) {
                    stack
                    if visible.isEmpty {
                        ContentUnavailableView {
                            Label("Your stack is empty", systemImage: "rectangle.stack")
                        } description: {
                            Text("All books are still accessible in the options menu.")
                        } actions: {
                            Button("Manage visible books") { managing = true }
                        }
                    }
                    activitySection(bookID: nil)
                        .offset(y: (reduceMotion || selectedID != nil) ? 0 : (pull * (CGFloat(max(0, visible.count - 1)) * 0.22 - 0.90)))
                        .opacity(selectedID == nil ? 1 : 0)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.always)
            .scrollDisabled(selectedID != nil)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, value in
                info.scrollOffset = value
                pull = reduceMotion ? 0 : max(0, -value)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .global).minY
            } action: { newValue in
                info.minY = newValue - info.safeArea.top
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                proxy.size
            } action: { newValue in
                info.containerSize = newValue
            }
            .onGeometryChange(for: EdgeInsets.self) { proxy in
                proxy.safeAreaInsets
            } action: { newValue in
                info.safeArea = newValue
            }
        }
        .background(paper).foregroundStyle(ink)
        .preferredColorScheme((direction == .light || direction == .ledger) ? .light : .dark)
        .safeAreaInset(edge: .bottom) {
            if showsBottomBar {
                Button {
                    let targetID = selectedID ?? visible.first?.id ?? model.activeBookID
                    model.openEntry(for: targetID)
                } label: {
                    Label("Add Expense", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(18)
                        .background(ink, in: Capsule())
                        .foregroundStyle(paper)
                }
                .buttonStyle(PressFeedbackStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
                .accessibilityIdentifier("addExpenseButton")
            }
        }
        .sheet(item: selectedBookBinding) { book in
            let spacing: CGFloat = 16
            let minSheetHeight: CGFloat = max(180, info.containerSize.height + info.safeArea.bottom - cardHeight - spacing)
            BookDetailSheet(
                model: model,
                book: book,
                paper: paper,
                ink: ink,
                onDismiss: { focus(nil) }
            )
            .presentationDetents([.height(minSheetHeight), .large])
            .presentationBackgroundInteraction(.enabled(upThrough: .large))
            .interactiveDismissDisabled()
            .presentationDragIndicator(.visible)
            .presentationBackground(paper)
        }
        .sheet(isPresented: $managing) {
            manageStackSheet
        }
        .sheet(isPresented: $showingBudgets) {
            NavigationStack {
                BudgetsView(model: model)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingBudgets = false }
                        }
                    }
            }
        }
        .alert("Create new book", isPresented: $showingCreateBook) {
            TextField("Book name", text: $newBookName)
            Button("Create") {
                let name = newBookName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                do {
                    let created = try model.createBook(named: name)
                    focus(created.id)
                    newBookName = ""
                } catch {
                    createBookError = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) { newBookName = "" }
        } message: {
            Text("Enter a name for the new personal expense book.")
        }
        .alert("Could not create book", isPresented: Binding(get: { createBookError != nil }, set: { if !$0 { createBookError = nil } })) {
            Button("OK") { createBookError = nil }
        } message: {
            Text(createBookError ?? "")
        }
        .onAppear {
            if let active = model.selectedBookID {
                selectedID = active
            }
        }
        .onChange(of: model.selectedBookID) { _, newID in
            if selectedID != newID {
                focus(newID)
            }
        }
    }

    private var header: some View {
        HStack {
            if current != nil {
                Button { focus(nil) } label: {
                    Image(systemName: "xmark")
                        .font(.headline.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .foregroundStyle(ink)
                }
                .accessibilityLabel("All book cards")
                .accessibilityIdentifier("closeBookDetail")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("monocle").font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-1.2)
                        .foregroundStyle(ink)
                    Text(".").font(.system(size: 30, weight: .bold)).foregroundStyle(MC.red)
                }
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityElement(children: .combine)
            }
            Spacer()
            Button { model.showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(ink)
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("homeSettings")
            optionsMenu
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var stack: some View {
        VStack(spacing: -(cardHeight - stripHeight)) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, book in
                cardItem(book, index: index)
            }
        }
    }

    private func cardItem(_ book: BookProfile, index: Int) -> some View {
        let isSelected = selectedID != nil
        let isCurrent = selectedID == book.id
        let selectedIdx = selectedIndex

        return Button {
            focus(isCurrent ? nil : book.id)
        } label: {
            cardView(book, index: index)
                .frame(height: cardHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(book.name), \(model.expenses(for: book.id).count) transactions")
        .accessibilityIdentifier("stack-book-\(book.id)")
        .visualEffect { [info, isSelected, selectedIdx, isCurrent, pull, reduceMotion] content, proxy in
            let rect = proxy.frame(in: .scrollView)
            let bounds = info.containerSize
            let pushOffset = selectedIdx < index ? (bounds.height - rect.minY) : -rect.minY
            let scale: CGFloat = (reduceMotion || selectedIdx < index) ? 1.0 : 0.95
            let fan: CGFloat = (reduceMotion || isSelected) ? 0 : (CGFloat(index) * (pull * 0.22) - (pull * 0.90))

            return content
                .scaleEffect(isSelected ? (isCurrent ? 1.0 : scale) : 1.0, anchor: .top)
                .offset(y: isSelected ? pushOffset : fan)
        }
    }

    private var selectedIndex: Int {
        visible.firstIndex { $0.id == selectedID } ?? visible.count
    }

    private func cardView(_ book: BookProfile, index: Int) -> some View {
        let bookExpenses = model.expenses(for: book.id)
        let total = model.spent(for: book.id)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(book.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(String(format: "%02d", index + 1))
                    .font(.caption.monospaced())
            }
            .frame(minHeight: max(16, stripHeight - 24), alignment: .top)

            Spacer(minLength: 0)

            Text(Money.format(total))
                .font(amountFont)
                .monospacedDigit()
                .minimumScaleFactor(0.65)
            Text("\(bookExpenses.count) TRANSACTIONS")
                .font(.caption.monospaced())
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.black)
        .background(cardColor(for: book), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: -2)
        .accessibilityElement(children: .combine)
    }

    private func activitySection(bookID: UUID?) -> some View {
        let activities = model.activities(selectedBookID: bookID, allBooks: allActivities)
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(bookID != nil ? (model.books.first { $0.id == bookID }?.name ?? "Book Activities") : "Recent Activities")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)
                Spacer()
            }

            if bookID == nil {
                Picker("Activity scope", selection: $allActivities) {
                    Text("Visible books").tag(false)
                    Text("All books").tag(true)
                }
                .pickerStyle(.segmented)
            }

            if activities.isEmpty {
                ContentUnavailableView("Nothing recorded yet", systemImage: "text.book.closed",
                                       description: Text("Tap Add Expense below to record your first transaction."))
                    .padding(.vertical, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(activities) { row in
                        activityRow(row, showBookLabel: bookID == nil)
                        Rectangle()
                            .fill(ink.opacity(direction == .light ? 0.08 : 0.15))
                            .frame(height: 0.5)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    private func activityRow(_ expense: Expense, showBookLabel: Bool) -> some View {
        Button {
            model.edit(expense)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(expense.day)
                    .font(.caption.monospaced())
                    .foregroundStyle(ink.opacity(0.6))
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(model.title(expense))
                            .foregroundStyle(ink)
                        Spacer()
                        Text(Money.format(expense.amount))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                    }
                    VStack(alignment: .leading) {
                        Text(model.title(expense))
                            .foregroundStyle(ink)
                        Text(Money.format(expense.amount))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                    }
                }
                .font(.body.weight(.medium))

                if showBookLabel, let bID = expense.bookID, let b = model.books.first(where: { $0.id == bID }) {
                    Text(b.name)
                        .font(.caption)
                        .foregroundStyle(ink.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("expense-\(expense.note)")
        .contextMenu {
            Button("Edit", systemImage: "pencil") {
                model.edit(expense)
            }
            Button("Repeat", systemImage: "repeat") {
                model.repeatExpense(expense)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                model.delete(expense)
            }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Visual direction", selection: $model.visualDirection) {
                ForEach(BookVisualDirection.allCases) { dir in
                    Text(dir.rawValue).tag(dir)
                }
            }

            Button {
                showingCreateBook = true
            } label: {
                Label("Create new book", systemImage: "plus.rectangle.on.rectangle")
            }

            Button {
                managing = true
            } label: {
                Label("Manage stack", systemImage: "slider.horizontal.3")
            }

            Button {
                showingBudgets = true
            } label: {
                Label("Budgets", systemImage: "chart.bar.xaxis")
            }

            if selectedID != nil {
                Button("Return to stack") { focus(nil) }
            }

            Section("All books") {
                ForEach(model.books) { book in
                    Button(book.name) {
                        focus(book.id)
                    }
                }
            }

            Section {
                Button {
                    model.showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .frame(width: 44, height: 44)
                .foregroundStyle(ink)
        }
        .accessibilityLabel("Book options")
        .accessibilityIdentifier("bookOptionsMenu")
    }

    private func focus(_ id: UUID?) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.86)) {
            selectedID = id
            model.selectedBookID = id
            if let id {
                model.selectBook(id)
            }
        }
        headingFocused = true
    }

    private var manageStackSheet: some View {
        NavigationStack {
            List {
                Section("Visible cards · drag to reorder") {
                    ForEach(model.orderedBooks) { book in
                        Toggle(book.name, isOn: Binding(
                            get: { !model.hiddenBookIDs.contains(book.id) },
                            set: { isVisible in
                                model.setBookHidden(id: book.id, isHidden: !isVisible)
                            }
                        ))
                    }
                    .onMove { from, to in
                        model.reorderBooks(fromOffsets: from, toOffset: to)
                    }
                }

                Section {
                    Button("Show every book") {
                        model.hiddenBookIDs = []
                        model.persistWorkspacePreferences()
                    }
                    Button("Create new book") {
                        managing = false
                        showingCreateBook = true
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Manage stack")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { managing = false }
                }
            }
        }
    }
}

struct BookDetailSheet: View {
    @Bindable var model: AppModel
    let book: BookProfile
    var paper: Color = MC.paper
    var ink: Color = MC.ink
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.name)
                                .font(.title2.bold())
                                .foregroundStyle(ink)
                                .accessibilityAddTraits(.isHeader)
                            Text("\(model.expenses(for: book.id).count) transactions · \(Money.format(model.spent(for: book.id)))")
                                .font(.subheadline)
                                .foregroundStyle(ink.opacity(0.6))
                        }
                        Spacer()
                        Button {
                            model.openEntry(for: book.id)
                        } label: {
                            Label("Add Expense", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(ink, in: Capsule())
                                .foregroundStyle(paper)
                        }
                        .buttonStyle(PressFeedbackStyle())
                        .accessibilityIdentifier("addExpenseButton")
                    }
                    .padding(.top, 8)

                    Divider()
                        .overlay(ink.opacity(paper == MC.paper ? 0.08 : 0.15))

                    let activities = model.activities(selectedBookID: book.id, allBooks: false)
                    if activities.isEmpty {
                        ContentUnavailableView("Nothing recorded yet", systemImage: "text.book.closed",
                                               description: Text("Tap Add Expense below to record your first transaction."))
                            .padding(.vertical, 24)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(activities) { expense in
                                activityRow(expense)
                                Rectangle()
                                    .fill(ink.opacity(paper == MC.paper ? 0.08 : 0.15))
                                    .frame(height: 0.5)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollBounceBehavior(.always)
            .background(paper)
            .navigationTitle(book.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        onDismiss()
                    }
                    .foregroundStyle(ink)
                }
            }
            .sheet(isPresented: $model.showEntry, onDismiss: {
                if !model.draftNeedsConfirmation { model.discardDraft() }
            }) {
                EntryView(model: model)
            }
        }
    }

    private func activityRow(_ expense: Expense) -> some View {
        Button {
            model.edit(expense)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(expense.day)
                    .font(.caption.monospaced())
                    .foregroundStyle(ink.opacity(0.6))
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(model.title(expense))
                            .foregroundStyle(ink)
                        Spacer()
                        Text(Money.format(expense.amount))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                    }
                    VStack(alignment: .leading) {
                        Text(model.title(expense))
                            .foregroundStyle(ink)
                        Text(Money.format(expense.amount))
                            .monospacedDigit()
                            .foregroundStyle(ink)
                    }
                }
                .font(.body.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("expense-\(expense.note)")
        .contextMenu {
            Button("Edit", systemImage: "pencil") {
                model.edit(expense)
            }
            Button("Repeat", systemImage: "repeat") {
                model.repeatExpense(expense)
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                model.delete(expense)
            }
        }
    }
}

