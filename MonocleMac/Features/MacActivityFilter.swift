import SwiftUI

/// Structured filters that sit beside the toolbar search: the search finds text, these narrow by category, card and date.
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

/// Chips under the page title: Category, Card and Date, plus "12 of 340" and Clear.
struct ActivityFilterBar: View {
    @Binding var filter: ActivityFilter
    let rows: [MacExpenseRow]
    let shown: Int
    @State private var showingDates = false

    private var categories: [String] { Array(Set(rows.map(\.category))).sorted() }
    private var cards: [String] { Array(Set(rows.map(\.card).filter { !$0.isEmpty })).sorted() }

    var body: some View {
        HStack(spacing: 8) {
            menu("Category", options: categories, selection: $filter.categories)
            if cards.count > 1 { menu("Card", options: cards, selection: $filter.cards) }
            dateChip
            Spacer()
            if filter.isActive {
                Text("\(shown) of \(rows.count)").font(.callout).foregroundStyle(.secondary).monospacedDigit()
                Button("Clear") { filter = ActivityFilter() }.buttonStyle(.borderless)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activityFilterBar")
    }

    private func menu(_ title: String, options: [String], selection: Binding<Set<String>>) -> some View {
        Menu {
            ForEach(options, id: \.self) { name in
                Toggle(name, isOn: Binding(get: { selection.wrappedValue.contains(name) },
                                           set: { if $0 { selection.wrappedValue.insert(name) } else { selection.wrappedValue.remove(name) } }))
            }
            if !selection.wrappedValue.isEmpty { Divider(); Button("Any \(title.lowercased())") { selection.wrappedValue = [] } }
        } label: {
            chip(selection.wrappedValue.isEmpty ? title : "\(title) · \(summary(selection.wrappedValue))", active: !selection.wrappedValue.isEmpty)
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    private func summary(_ set: Set<String>) -> String { set.count == 1 ? set.first! : "\(set.count)" }

    private var dateChip: some View {
        let title: String = switch (filter.from, filter.to) {
        case (nil, nil): "Date"
        case (let from?, nil): "From \(Day.title(from))"
        case (nil, let to?): "Until \(Day.title(to))"
        case (let from?, let to?): "\(Day.title(from)) – \(Day.title(to))"
        }
        return Button { showingDates.toggle() } label: { chip(title, active: filter.from != nil || filter.to != nil) }
            .buttonStyle(.plain)
            .popover(isPresented: $showingDates, arrowEdge: .bottom) { datePopover }
    }

    private var datePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                preset("This month") { let d = Date.now; return (Calendar.current.dateInterval(of: .month, for: d)?.start ?? d, d) }
                preset("Last 30 days") { (Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now, .now) }
                preset("This year") { (Calendar.current.dateInterval(of: .year, for: .now)?.start ?? .now, .now) }
            }
            Divider()
            dateRow("From", bound: $filter.from)
            dateRow("Until", bound: $filter.to)
            HStack { Spacer(); Button("Any date") { filter.from = nil; filter.to = nil; showingDates = false }.disabled(filter.from == nil && filter.to == nil) }
        }.padding(14).frame(width: 330)
    }

    private func preset(_ title: String, range: @escaping () -> (Date, Date)) -> some View {
        Button(title) { let r = range(); filter.from = Day.string(r.0); filter.to = Day.string(r.1) }.buttonStyle(.bordered).controlSize(.small)
    }

    private func dateRow(_ title: String, bound: Binding<String?>) -> some View {
        HStack {
            Toggle(title, isOn: Binding(get: { bound.wrappedValue != nil }, set: { bound.wrappedValue = $0 ? Day.string(.now) : nil }))
            Spacer()
            if bound.wrappedValue != nil {
                DatePicker(title, selection: Binding(get: { bound.wrappedValue.flatMap { Day.date($0) } ?? .now }, set: { bound.wrappedValue = Day.string($0) }),
                           displayedComponents: .date).labelsHidden().datePickerStyle(.field)
            }
        }
    }

    private func chip(_ title: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Text(title).lineLimit(1)
            Image(systemName: "chevron.down").font(.caption2.weight(.bold))
        }
        .font(.callout.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 6)
        .background(active ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
        .foregroundStyle(active ? Color.white : Color.primary)
    }
}
