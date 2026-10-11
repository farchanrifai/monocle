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
        matches(.init(category: row.category, card: row.card, day: row.day), ignoring: [])
    }

    enum Facet { case category, card }

    func matches(_ key: ActivityFilterOptions.Key, ignoring facet: Set<Facet>) -> Bool {
        (facet.contains(.category) || categories.isEmpty || categories.contains(key.category))
            && (facet.contains(.card) || cards.isEmpty || cards.contains(key.card))
            && (from.map { key.day >= $0 } ?? true)
            && (to.map { key.day <= $0 } ?? true)
    }
}

/// What the visible table can be filtered by. The page publishes it; the toolbar button shows only while it exists.
struct ActivityFilterOptions: Equatable {
    struct Key: Equatable { let category: String, card: String, day: String }
    var keys: [Key]
    var categories: [String]
    var cards: [String]

    init(rows: [MacExpenseRow]) {
        keys = rows.map { Key(category: $0.category, card: $0.card, day: $0.day) }
        categories = Array(Set(rows.map(\.category))).sorted()
        cards = Array(Set(rows.map(\.card).filter { !$0.isEmpty })).sorted()
    }

    /// How many rows each value would show with the other filters applied (a value's own facet is ignored, so it can be added).
    func counts(for facet: ActivityFilter.Facet, under filter: ActivityFilter) -> [String: Int] {
        var result: [String: Int] = [:]
        for key in keys where filter.matches(key, ignoring: [facet]) {
            result[facet == .category ? key.category : key.card, default: 0] += 1
        }
        return result
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
                Button("Clear") { state.activityFilter = ActivityFilter() }
                    .buttonStyle(.borderless).fontWeight(filter.isActive ? .semibold : .regular)
                    .foregroundStyle(filter.isActive ? Color.accentColor : Color.secondary)
                    .disabled(!filter.isActive).keyboardShortcut(.delete, modifiers: .command)
            }.padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    section("Category", summary: summary(filter.categories)) {
                        checklist(options.categories, counts: options.counts(for: .category, under: filter),
                                  selection: Binding(get: { state.activityFilter.categories }, set: { state.activityFilter.categories = $0 }))
                    }
                    section("Date", summary: dateSummary) { dates }
                    if options.cards.count > 1 {
                        section("Card", summary: summary(filter.cards)) {
                            checklist(options.cards, counts: options.counts(for: .card, under: filter),
                                      selection: Binding(get: { state.activityFilter.cards }, set: { state.activityFilter.cards = $0 }))
                        }
                    }
                }.padding(.horizontal, 10).padding(.vertical, 8)
            }.frame(maxHeight: 600)
        }
        .frame(width: 280)
        .onAppear {
            // Sections that already hold a selection open; the rest stay folded so the popover is short.
            if !filter.categories.isEmpty { expanded.insert("Category") }
            if filter.from != nil || filter.to != nil { expanded.insert("Date") }
            if !filter.cards.isEmpty { expanded.insert("Card") }
        }
    }

    private func summary(_ set: Set<String>) -> String? {
        let names = set.sorted()
        switch names.count {
        case 0: return nil
        case 1: return names[0]
        default: return "\(names[0]) +\(names.count - 1)"
        }
    }

    private var dateSummary: String? {
        switch (filter.from, filter.to) {
        case (nil, nil): nil
        case (let from?, nil): "From \(Day.title(from))"
        case (nil, let to?): "Until \(Day.title(to))"
        case (let from?, let to?): "\(Day.title(from)) – \(Day.title(to))"
        }
    }

    private func section<Content: View>(_ title: String, summary: String?, @ViewBuilder content: () -> Content) -> some View {
        let body = content()
        let isOpen = Binding(get: { expanded.contains(title) }, set: { if $0 { expanded.insert(title) } else { expanded.remove(title) } })
        return DisclosureGroup(isExpanded: isOpen) {
            body.padding(.top, 2).padding(.bottom, 8)
        } label: {
            HStack(spacing: 8) {
                Text(title).font(.callout.weight(.semibold))
                Spacer(minLength: 4)
                if let summary {
                    Text(summary).font(.caption).foregroundStyle(Color.accentColor).lineLimit(1).truncationMode(.tail)
                }
            }.padding(.vertical, 6)
        }
    }

    private func checklist(_ options: [String], counts: [String: Int], selection: Binding<Set<String>>) -> some View {
        VStack(spacing: 0) {
            ForEach(options, id: \.self) { name in
                FilterRow(title: name, count: counts[name] ?? 0, isOn: Binding(
                    get: { selection.wrappedValue.contains(name) },
                    set: { if $0 { selection.wrappedValue.insert(name) } else { selection.wrappedValue.remove(name) } }))
            }
        }
    }

    // MARK: Date

    private struct Preset {
        let title: String
        let range: () -> (from: String, to: String)
    }

    private var presets: [Preset] {
        let calendar = Calendar.current
        return [
            Preset(title: "This month") { (Day.string(calendar.dateInterval(of: .month, for: .now)?.start ?? .now), Day.string(.now)) },
            Preset(title: "30 days") { (Day.string(calendar.date(byAdding: .day, value: -29, to: .now) ?? .now), Day.string(.now)) },
            Preset(title: "This year") { (Day.string(calendar.dateInterval(of: .year, for: .now)?.start ?? .now), Day.string(.now)) },
        ]
    }

    private var dates: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(presets, id: \.title) { preset in
                    let range = preset.range()
                    let selected = filter.from == range.from && filter.to == range.to
                    Button(preset.title) { state.activityFilter.from = range.from; state.activityFilter.to = range.to }
                        .buttonStyle(.bordered).controlSize(.small)
                        .tint(selected ? Color.accentColor : nil)
                        .fontWeight(selected ? .semibold : .regular)
                }
            }
            dateRow("From", bound: Binding(get: { state.activityFilter.from }, set: { state.activityFilter.from = $0 }))
            dateRow("Until", bound: Binding(get: { state.activityFilter.to }, set: { state.activityFilter.to = $0 }))
        }.padding(.horizontal, 4)
    }

    /// "Any" until a day is picked; the × puts it back.
    private func dateRow(_ title: String, bound: Binding<String?>) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
            if bound.wrappedValue != nil {
                DatePicker(title, selection: Binding(get: { bound.wrappedValue.flatMap { Day.date($0) } ?? .now }, set: { bound.wrappedValue = Day.string($0) }),
                           displayedComponents: .date).labelsHidden().datePickerStyle(.field)
                Button { bound.wrappedValue = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear \(title) date")
            } else {
                Button { bound.wrappedValue = Day.string(.now) } label: {
                    Text("Any").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).accessibilityLabel("Set \(title) date")
            }
            Spacer(minLength: 0)
        }
    }
}

/// One compact, full-width checkbox row with a count, highlighted on hover.
private struct FilterRow: View {
    let title: String
    let count: Int
    @Binding var isOn: Bool
    @State private var hovering = false

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                Text(title).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(count)").font(.callout).monospacedDigit().foregroundStyle(.secondary)
            }
            .opacity(count == 0 && !isOn ? 0.45 : 1)
            .padding(.horizontal, 6).padding(.vertical, 5)
            .background(hovering ? Color.secondary.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count) expenses")
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}
