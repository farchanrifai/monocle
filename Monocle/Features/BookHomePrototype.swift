import SwiftUI

/// Isolated design exploration. Sample writes never reach ExpenseService or the user's store.
struct BookHomePrototype: View {
    enum Direction: String, CaseIterable, Identifiable {
        case light = "Light", instrument = "Instrument", ledger = "Ledger", signal = "Signal"
        var id: Self { self }
    }
    @State var direction: Direction = .light
    @State private var books = PrototypeBookSamples.books
    @State private var activities = PrototypeBookSamples.activities
    @State private var hidden: Set<Int> = []
    @State private var selected: Int?
    @State private var allBooks = false
    @State private var managing = false
    @State private var adding = false
    @State private var pull: CGFloat = 0
    @State private var info = ScrollInfo()
    @ScaledMetric(relativeTo: .headline) private var stripHeight = 44
    @ScaledMetric(relativeTo: .title) private var cardHeight = 224
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var headingFocused: Bool

    private var visible: [PrototypeBook] { books.filter { !hidden.contains($0.id) } }
    private var current: PrototypeBook? { books.first { $0.id == selected } }
    private var paper: Color {
        switch direction {
        case .light: return MC.paper
        case .ledger: return Color(red: 0.96, green: 0.94, blue: 0.88)
        case .instrument, .signal: return .black
        }
    }
    private var ink: Color {
        switch direction {
        case .light, .ledger: return MC.ink
        case .instrument, .signal: return .white
        }
    }
    private func color(_ id: Int) -> Color {
        [Color(red: 0.99, green: 0.40, blue: 0.22), Color(red: 0.68, green: 0.79, blue: 0.99),
         Color(red: 0.84, green: 0.94, blue: 0.38), Color(red: 0.93, green: 0.68, blue: 0.88)][abs(id) % 4]
    }

    private var selectedBookBinding: Binding<PrototypeBook?> {
        Binding(
            get: { current },
            set: { newBook in
                focus(newBook?.id)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if current != nil {
                    Button { focus(nil) } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }.accessibilityLabel("All book cards")
                } else {
                    Text("Monocle").font(.largeTitle.bold())
                }
                Spacer()
                options
            }.padding(.horizontal, 20).padding(.bottom, 8)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 24) {
                    stack
                    if visible.isEmpty {
                        ContentUnavailableView {
                            Label("Your stack is empty", systemImage: "rectangle.stack")
                        } description: { Text("All books are still in the options menu.") }
                        actions: { Button("Choose visible books") { managing = true } }
                    }
                    activityList(bookID: nil)
                        .offset(y: (reduceMotion || selected != nil) ? 0 : (pull * (CGFloat(max(0, visible.count - 1)) * 0.22 - 0.90)))
                        .opacity(selected == nil ? 1 : 0)
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
            }
            .scrollBounceBehavior(.always)
            .scrollDisabled(selected != nil)
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
        .safeAreaInset(edge: .bottom) {
            if selected == nil {
                Button { adding = true } label: {
                    Label("Add Expense", systemImage: "plus").font(.headline)
                        .frame(maxWidth: .infinity).padding(18).background(ink, in: Capsule()).foregroundStyle(paper)
                }.buttonStyle(PressFeedbackStyle()).padding(.horizontal, 20).padding(.bottom, 8)
            }
        }
        .sheet(item: selectedBookBinding) { book in
            let spacing: CGFloat = 16
            let minSheetHeight: CGFloat = max(180, info.containerSize.height - cardHeight - spacing)
            PrototypeBookDetailSheet(
                book: book,
                activities: $activities,
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
        .sheet(isPresented: $managing) { management }
        .sheet(isPresented: $adding) {
            PrototypeExpenseEntry(books: books, initialBookID: selected ?? visible.first?.id ?? books[0].id) {
                activities.insert($0, at: 0)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme((direction == .light || direction == .ledger) ? .light : .dark)
    }

    private var stack: some View {
        VStack(spacing: -(cardHeight - stripHeight)) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, book in
                cardItem(book, index: index)
            }
        }
    }

    private func cardItem(_ book: PrototypeBook, index: Int) -> some View {
        let isSelected = selected != nil
        let isCurrent = selected == book.id
        let selectedIdx = selectedIndex

        return Button {
            focus(isCurrent ? nil : book.id)
        } label: {
            card(book)
                .frame(height: cardHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(book.name), \(count(book.id)) transactions")
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

    private var selectedIndex: Int { visible.firstIndex { $0.id == selected } ?? visible.count }

    private func activityList(bookID: Int?) -> some View {
        let values = PrototypeBookSamples.activities(activities, selectedBookID: bookID,
                            visibleBookIDs: Set(visible.map(\.id)), allBooks: allBooks)
        return VStack(alignment: .leading, spacing: 12) {
            Text(books.first { $0.id == bookID }?.name ?? "All Activities")
                .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                .accessibilityFocused($headingFocused)
            if bookID == nil {
                Picker("Activity scope", selection: $allBooks) {
                    Text("Visible books").tag(false)
                    Text("All books").tag(true)
                }.pickerStyle(.segmented)
            }
            if values.isEmpty {
                ContentUnavailableView("Nothing recorded yet", systemImage: "text.book.closed",
                                       description: Text("Add a sample expense to explore this book."))
            }
            LazyVStack(spacing: 0) {
                ForEach(values) { row in
                    Button { if bookID == nil { focus(row.bookID) } } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.day).font(.caption.monospaced())
                            ViewThatFits(in: .horizontal) {
                                HStack { Text(row.title); Spacer(); Text(Money.format(row.amount)).monospacedDigit() }
                                VStack(alignment: .leading) { Text(row.title); Text(Money.format(row.amount)).monospacedDigit() }
                            }.font(.body.weight(.medium))
                            Text(books.first { $0.id == row.bookID }?.name ?? "Book").font(.caption)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 16)
                    }.buttonStyle(.plain)
                    Rectangle().fill(ink.opacity(0.2)).frame(height: 1).accessibilityHidden(true)
                }
            }
        }
    }

    private var options: some View {
        Menu {
            Picker("Visual direction", selection: $direction) {
                ForEach(Direction.allCases) { Text($0.rawValue).tag($0) }
            }
            Button("Leave design prototype") { dismiss() }
            Button("Manage stack", systemImage: "slider.horizontal.3") { managing = true }
            Button("Return to stack") { focus(nil) }
            Section("All books") {
                ForEach(books) { book in Button(book.name) { focus(book.id) } }
            }
        } label: { Image(systemName: "ellipsis.circle").font(.title2).frame(width: 44, height: 44) }
            .accessibilityLabel("Book options")
    }

    private func count(_ id: Int) -> Int { activities.filter { $0.bookID == id }.count }
    private func card(_ book: PrototypeBook) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(book.name).font(.headline).lineLimit(1)
                Spacer(minLength: 8)
                Text(String(format: "%02d", book.id)).font(.caption.monospaced())
            }.frame(minHeight: stripHeight - 24, alignment: .top)
            Spacer(minLength: 0)
            Text(Money.format(activities.filter { $0.bookID == book.id }.reduce(0) { $0 + $1.amount }))
                .font(direction == .ledger ? .system(.title, design: .serif, weight: .semibold) : .title.bold())
                .monospacedDigit().minimumScaleFactor(0.65)
            Text("\(count(book.id)) TRANSACTIONS · SAMPLE").font(.caption.monospaced())
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.black)
        .background(color(book.id), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 8, y: -2)
        .accessibilityElement(children: .combine)
    }

    private func focus(_ id: Int?) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.48, dampingFraction: 0.86)) {
            selected = id
        }
        headingFocused = true
    }

    private var management: some View {
        NavigationStack {
            List {
                Section("Visible cards · drag to reorder") {
                    ForEach(books) { book in
                        Toggle(book.name, isOn: Binding(get: { !hidden.contains(book.id) }, set: {
                            if $0 { hidden.remove(book.id) } else { hidden.insert(book.id) }
                        }))
                        .contextMenu {
                            Button("Move to top") {
                                books.removeAll { $0.id == book.id }; books.insert(book, at: 0)
                            }
                        }
                        .accessibilityAction(named: "Move to top") {
                            books.removeAll { $0.id == book.id }; books.insert(book, at: 0)
                        }
                    }.onMove { books.move(fromOffsets: $0, toOffset: $1) }
                }
                Section("Try a state") {
                    Button("One visible book") { hidden = Set(books.dropFirst().map(\.id)) }
                    Button("Show every book") { hidden = [] }
                    Button("Hide every book") { hidden = Set(books.map(\.id)) }
                }
            }.environment(\.editMode, .constant(.active))
                .navigationTitle("Manage stack")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { managing = false } } }
        }
    }
}

private struct PrototypeBookDetailSheet: View {
    let book: PrototypeBook
    @Binding var activities: [PrototypeActivity]
    let paper: Color
    let ink: Color
    var onDismiss: () -> Void
    @State private var addingExpense = false

    private var bookActivities: [PrototypeActivity] {
        activities.filter { $0.bookID == book.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Latest Transactions")
                        .font(.headline)
                        .foregroundStyle(ink)
                        .padding(.top, 8)

                    if bookActivities.isEmpty {
                        ContentUnavailableView("Nothing recorded yet", systemImage: "text.book.closed",
                                               description: Text("Add a sample expense to explore this book."))
                            .padding(.vertical, 24)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(bookActivities) { row in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(row.day).font(.caption.monospaced())
                                    ViewThatFits(in: .horizontal) {
                                        HStack {
                                            Text(row.title)
                                            Spacer()
                                            Text(Money.format(row.amount)).monospacedDigit()
                                        }
                                        VStack(alignment: .leading) {
                                            Text(row.title)
                                            Text(Money.format(row.amount)).monospacedDigit()
                                        }
                                    }.font(.body.weight(.medium))
                                    Text(book.name).font(.caption)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 16)

                                Rectangle().fill(ink.opacity(0.2)).frame(height: 1).accessibilityHidden(true)
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
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        addingExpense = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .accessibilityLabel("Add Expense")
                }
            }
            .sheet(isPresented: $addingExpense) {
                PrototypeExpenseEntry(books: [book], initialBookID: book.id) { newActivity in
                    activities.insert(newActivity, at: 0)
                }
            }
        }
    }
}


private struct PrototypeExpenseEntry: View {
    let books: [PrototypeBook]
    let initialBookID: Int
    let record: (PrototypeActivity) -> Void
    @State private var bookID = 0
    @State private var amount = ""
    @State private var note = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Book", selection: $bookID) { ForEach(books) { Text($0.name).tag($0.id) } }
                    TextField("Amount (IDR)", text: $amount).keyboardType(.numberPad)
                    TextField("Note", text: $note)
                } footer: { Text("Sample only. This does not write to your saved book.") }
                if let error { Text(error).foregroundStyle(.red) }
                Button("Record sample expense") {
                    do {
                        let value = try Money.parse(amount)
                        guard books.contains(where: { $0.id == bookID }) else { throw EntryError.corruptStore }
                        record(.init(id: UUID(), bookID: bookID, title: note.isEmpty ? "Expense" : note,
                                     amount: value, day: Day.string(.now)))
                        dismiss()
                    } catch { self.error = error.localizedDescription }
                }
            }.navigationTitle("Add Expense")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .onAppear { bookID = initialBookID }
        }
    }
}

#Preview("Light") { NavigationStack { BookHomePrototype(direction: .light) } }
#Preview("Instrument") { NavigationStack { BookHomePrototype(direction: .instrument) } }
#Preview("Ledger") { NavigationStack { BookHomePrototype(direction: .ledger) } }
#Preview("Signal") { NavigationStack { BookHomePrototype(direction: .signal) } }
#Preview("Large text") { NavigationStack { BookHomePrototype() }.environment(\.dynamicTypeSize, .accessibility3) }
