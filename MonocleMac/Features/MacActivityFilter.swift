import SwiftUI

/// Structured filters beside the toolbar search: the search finds text, these narrow by category, card and date.
struct ActivityFilter: Equatable {
    var categories: Set<String> = []
    var cards: Set<String> = []
    /// Inclusive `yyyy-MM-dd` bounds.
    var from: String?
    var to: String?

    var isActive: Bool { !categories.isEmpty || !cards.isEmpty || from != nil || to != nil }

    func matches(_ row: MacExpenseRow) -> Bool {
        (categories.isEmpty || categories.contains(row.category))
            && (cards.isEmpty || cards.contains(row.card))
            && (from.map { row.day >= $0 } ?? true)
            && (to.map { row.day <= $0 } ?? true)
    }
}

/// What the visible table can be filtered by. The page publishes it; the toolbar button shows only while it exists.
struct ActivityFilterOptions: Equatable {
    var categories: [String]
    var cards: [String]

    init(rows: [MacExpenseRow]) {
        categories = Array(Set(rows.map(\.category))).sorted()
        cards = Array(Set(rows.map(\.card).filter { !$0.isEmpty })).sorted()
    }
}

/// Toolbar button with a popover of collapsible sections. Ticking values keeps the popover open.
struct ActivityFilterButton: View {
    let state: MacAppState
    @State private var showing = false
    @State private var expanded: Set<String> = ["Category"]

    private var filter: ActivityFilter { state.activityFilter }

    var body: some View {
        Button { showing.toggle() } label: {
            Label("Filter", systemImage: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .help("Filter")
        .accessibilityIdentifier("filterButton")
        .popover(isPresented: $showing, arrowEdge: .bottom) { content }
    }

    @ViewBuilder private var content: some View {
        let options = state.filterOptions ?? ActivityFilterOptions(rows: [])
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Filters").font(.headline)
                Spacer()
                Button("Clear") { state.activityFilter = ActivityFilter() }.buttonStyle(.borderless).disabled(!filter.isActive)
            }.padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    section("Category", count: filter.categories.count) {
                        checklist(options.categories, selection: Binding(get: { state.activityFilter.categories }, set: { state.activityFilter.categories = $0 }))
                    }
                    section("Date", count: (filter.from == nil ? 0 : 1) + (filter.to == nil ? 0 : 1)) { dates }
                    if options.cards.count > 1 {
                        section("Card", count: filter.cards.count) {
                            checklist(options.cards, selection: Binding(get: { state.activityFilter.cards }, set: { state.activityFilter.cards = $0 }))
                        }
                    }
                }.padding(14)
            }.frame(maxHeight: 420)
        }.frame(width: 290)
    }

    private func section<Content: View>(_ title: String, count: Int, @ViewBuilder content: () -> Content) -> some View {
        let body = content()
        return DisclosureGroup(isExpanded: Binding(get: { expanded.contains(title) }, set: { if $0 { expanded.insert(title) } else { expanded.remove(title) } })) {
            body.padding(.top, 6).padding(.bottom, 8)
        } label: {
            HStack {
                Text(title).font(.callout.weight(.semibold))
                if count > 0 { Text("\(count)").font(.caption.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1).background(Color.accentColor, in: Capsule()).foregroundStyle(.white) }
            }
        }
    }

    private func checklist(_ options: [String], selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(options, id: \.self) { name in
                Toggle(name, isOn: Binding(get: { selection.wrappedValue.contains(name) },
                                           set: { if $0 { selection.wrappedValue.insert(name) } else { selection.wrappedValue.remove(name) } }))
                    .toggleStyle(.checkbox)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dates: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                preset("This month") { let d = Date.now; return (Calendar.current.dateInterval(of: .month, for: d)?.start ?? d, d) }
                preset("30 days") { (Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now, .now) }
                preset("This year") { (Calendar.current.dateInterval(of: .year, for: .now)?.start ?? .now, .now) }
            }
            dateRow("From", bound: Binding(get: { state.activityFilter.from }, set: { state.activityFilter.from = $0 }))
            dateRow("Until", bound: Binding(get: { state.activityFilter.to }, set: { state.activityFilter.to = $0 }))
        }
    }

    private func preset(_ title: String, range: @escaping () -> (Date, Date)) -> some View {
        Button(title) { let r = range(); state.activityFilter.from = Day.string(r.0); state.activityFilter.to = Day.string(r.1) }
            .buttonStyle(.bordered).controlSize(.small)
    }

    private func dateRow(_ title: String, bound: Binding<String?>) -> some View {
        HStack {
            Toggle(title, isOn: Binding(get: { bound.wrappedValue != nil }, set: { bound.wrappedValue = $0 ? Day.string(.now) : nil })).toggleStyle(.checkbox)
            Spacer()
            if bound.wrappedValue != nil {
                DatePicker(title, selection: Binding(get: { bound.wrappedValue.flatMap { Day.date($0) } ?? .now }, set: { bound.wrappedValue = Day.string($0) }),
                           displayedComponents: .date).labelsHidden().datePickerStyle(.field)
            }
        }
    }
}
