import Charts
import SwiftUI

struct MacBudgetsView: View {
    @Bindable var state: MacAppState
    @State private var editing = false
    private var model: AppModel { state.model }
    private var categories: [ExpenseCategory] { model.activeCategories(for: model.activeCardID) }
    private var usedPercent: Int {
        let ratio = Double(model.spent) / Double(max(Int64(1), model.activeBudget.overallLimit))
        return Int((ratio * 100).rounded())
    }
    var body: some View {
        return Page(title: "Budgets") {
            HStack {
                SummaryTile(title: "Limit", value: Money.format(model.activeBudget.overallLimit, code: model.activeCardCurrency), detail: model.cycle.label)
                SummaryTile(title: "Spent", value: Money.format(model.spent, code: model.activeCardCurrency), detail: "\(usedPercent)% used")
                SummaryTile(title: "Remaining", value: Money.format(model.remaining, code: model.activeCardCurrency),
                            detail: model.activeBudget.totalUntilDay.map { "Total until \(Day.title($0))" } ?? "Cycle day \(model.activeBudget.startDay)")
            }
            HStack { Text("Category budgets").font(.title2.bold()); Spacer(); Button("Edit Budget") { editing = true }.buttonStyle(.glass) }
            Table(categories) {
                TableColumn("Category") { category in Label(category.name, systemImage: category.symbol) }
                TableColumn("Spent") { category in Text(Money.format(model.spent(in: category), code: model.activeCardCurrency)).font(.system(.body, design: .monospaced)) }
                TableColumn("Limit") { category in
                    Text(model.activeBudget.limit(for: category.id).map { Money.format($0, code: model.activeCardCurrency) } ?? "—").font(.system(.body, design: .monospaced))
                }
                TableColumn("Progress") { category in
                    let limit = model.activeBudget.limit(for: category.id) ?? model.activeBudget.overallLimit
                    ProgressView(value: min(1, Double(model.spent(in: category)) / Double(max(1, limit))))
                }
            }.frame(minHeight: 280)
        }
        .sheet(isPresented: $editing) { BudgetEditor(model: model) { editing = false } }
    }
}

private struct BudgetEditor: View {
    @Bindable var model: AppModel
    let close: () -> Void
    @State private var amount: String
    @State private var startDay: Int
    @State private var categoryAmounts: [UUID: String]
    @State private var nextCycle = false
    @State private var error: String?
    @State private var isTotal: Bool
    @State private var totalUntil: Date

    init(model: AppModel, close: @escaping () -> Void) {
        self.model = model; self.close = close
        _amount = State(initialValue: Money.digits(model.activeBudget.overallLimit))
        _startDay = State(initialValue: model.activeBudget.startDay)
        _categoryAmounts = State(initialValue: Dictionary(uniqueKeysWithValues: model.activeBudget.categoryLimits.map { ($0.categoryID, Money.digits($0.limit)) }))
        _isTotal = State(initialValue: model.activeBudget.totalUntilDay != nil)
        _totalUntil = State(initialValue: model.activeBudget.totalUntilDay.flatMap { Day.date($0) }
            ?? Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Budget").font(.title2.bold())
            Form {
                Picker("Budget", selection: $isTotal) {
                    Text("Monthly").tag(false)
                    Text("Total until").tag(true)
                }.pickerStyle(.segmented)
                TextField("Overall limit (\(model.activeCardCurrency))", text: $amount)
                if isTotal {
                    DatePicker("Last day", selection: $totalUntil, in: model.cycle.start..., displayedComponents: .date)
                    Text("One amount from \(Day.title(Day.string(model.cycle.start))) through the last day. Use it for a trip or a goal.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Stepper("Cycle begins on day \(startDay)", value: $startDay, in: 1...31)
                    Toggle("Apply to next cycle", isOn: $nextCycle)
                }
                Section("Categories") {
                    ForEach(model.activeCategories) { category in
                        TextField(category.name, text: Binding(get: { categoryAmounts[category.id] ?? "" }, set: { categoryAmounts[category.id] = $0 }))
                    }
                }
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel", role: .cancel, action: close); Button("Save") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command) }
        }.padding(24).frame(width: 500, height: 570)
    }
    private func save() {
        do {
            let total = try Money.parse(amount)
            let categories = try categoryAmounts.compactMap { id, value -> CategoryBudget? in
                guard !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return CategoryBudget(categoryID: id, limit: try Money.parse(value))
            }
            try model.saveBudget(overallLimit: total, startDay: isTotal ? model.activeBudget.startDay : startDay, categoryLimits: categories,
                                 applyToNextCycle: !isTotal && nextCycle, totalUntil: isTotal ? totalUntil : nil)
            close()
        } catch { self.error = error.localizedDescription }
    }
}

struct MacBillsView: View {
    @Bindable var state: MacAppState
    @State private var adding = false
    private var model: AppModel { state.model }
    private var pending: [BillOccurrence] { model.billOccurrences.filter { $0.status == .pending }.sorted { $0.dueDay < $1.dueDay } }
    var body: some View {
        Page(title: "Bills") {
            HStack {
                SummaryTile(title: "Active bills", value: "\(model.bills.filter(\.isActive).count)", detail: "Recurring rules")
                SummaryTile(title: "Pending", value: "\(pending.count)", detail: "Need confirmation")
                SummaryTile(title: "Monthly total", value: Money.format(model.bills.filter(\.isActive).reduce(0) { $0 + $1.amount }), detail: "Scheduled amount")
            }
            HStack { Text("Schedule").font(.title2.bold()); Spacer(); Button("New Bill") { adding = true }.buttonStyle(.glassProminent) }
            Table(model.bills, selection: Binding<BillRule.ID?>(get: {
                if case .bill(let id) = state.inspectorSelection { id } else { nil }
            }, set: { state.inspect($0.map { .bill($0) }) })) {
                TableColumn("Name") { Text($0.name) }
                TableColumn("Amount") { Text(Money.format($0.amount)).font(.system(.body, design: .monospaced)) }
                TableColumn("Schedule") { Text($0.recurrence.title) }
                TableColumn("Mode") { Text($0.recordingMode == .automatic ? "Automatic" : "Confirm") }
                TableColumn("Active") { Image(systemName: $0.isActive ? "checkmark.circle.fill" : "pause.circle") }
            }
            .contextMenu(forSelectionType: BillRule.ID.self) { ids in
                if let bill = model.bills.first(where: { ids.contains($0.id) }) { Button("Edit Bill…") { state.editingBill = bill } }
            } primaryAction: { ids in
                state.editingBill = model.bills.first { ids.contains($0.id) }
            }
            .frame(minHeight: 240)
            if !pending.isEmpty {
                Text("Needs attention").font(.title2.bold())
                ForEach(pending) { occurrence in
                    if let rule = model.bills.first(where: { $0.id == occurrence.billRuleID }) {
                        HStack {
                            VStack(alignment: .leading) { Text(rule.name).font(.headline); Text("Due \(occurrence.dueDay)").foregroundStyle(.secondary) }
                            Spacer(); Text(Money.format(rule.amount)).font(.system(.body, design: .monospaced))
                            Button("Skip") { do { try model.skipBillOccurrence(occurrence.id) } catch { model.error = error.localizedDescription } }.buttonStyle(.glass)
                            Button("Add") { do { _ = try model.confirmBillOccurrence(occurrence.id) } catch { model.error = error.localizedDescription } }.buttonStyle(.glassProminent)
                        }.padding(12).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .sheet(isPresented: $adding) { BillEditor(model: model, bill: nil) { adding = false } }
        .sheet(item: $state.editingBill) { bill in BillEditor(model: model, bill: bill) { state.editingBill = nil } }
        .onAppear { model.reconcileBills() }
    }
}

private struct BillEditor: View {
    @Bindable var model: AppModel
    let original: BillRule?
    let close: () -> Void
    @State private var name: String
    @State private var amount: String
    @State private var categoryID: UUID?
    @State private var recurrence: BillRecurrence
    @State private var mode: BillRecordingMode
    @State private var reminder: Bool
    @State private var leadDays: Int
    @State private var active: Bool
    @State private var error: String?

    init(model: AppModel, bill: BillRule?, close: @escaping () -> Void) {
        self.model = model; original = bill; self.close = close
        _name = State(initialValue: bill?.name ?? "")
        _amount = State(initialValue: bill.map { Money.digits($0.amount) } ?? "")
        _categoryID = State(initialValue: bill?.categoryID ?? model.activeCategories.first?.id)
        _recurrence = State(initialValue: bill?.recurrence ?? .monthly(day: 1))
        _mode = State(initialValue: bill?.recordingMode ?? .pending)
        _reminder = State(initialValue: bill?.hasReminder ?? true)
        _leadDays = State(initialValue: bill?.reminderLeadDays ?? 0)
        _active = State(initialValue: bill?.isActive ?? true)
    }
    private var monthlyDay: Binding<Int> { Binding(get: { if case .monthly(let day) = recurrence { day } else { 1 } }, set: { recurrence = .monthly(day: $0) }) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(original == nil ? "New Bill" : "Edit Bill").font(.title2.bold())
            Form {
                TextField("Name", text: $name)
                TextField("Amount", text: $amount)
                Picker("Category", selection: $categoryID) { ForEach(model.activeCategories) { Label($0.name, systemImage: $0.symbol).tag(Optional($0.id)) } }
                Picker("Repeat", selection: Binding(get: { recurrence.title.hasPrefix("Monthly") ? 0 : recurrence.title.hasPrefix("Weekly") ? 1 : 2 }, set: { value in
                    recurrence = value == 0 ? .monthly(day: 1) : value == 1 ? .weekly(weekday: 2) : .yearly(month: 1, day: 1)
                })) { Text("Monthly").tag(0); Text("Weekly").tag(1); Text("Yearly").tag(2) }
                recurrenceControls
                Picker("When due", selection: $mode) { ForEach(BillRecordingMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                Toggle("Reminder", isOn: $reminder)
                if reminder { Stepper("Remind \(leadDays) days before", value: $leadDays, in: 0...30) }
                Toggle("Active", isOn: $active)
            }.formStyle(.grouped)
            if let error { Text(error).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel", role: .cancel, action: close); Button("Save") { save() }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command) }
        }.padding(24).frame(width: 480, height: 550)
    }
    @ViewBuilder private var recurrenceControls: some View {
        switch recurrence {
        case .monthly: Stepper("Day \(monthlyDay.wrappedValue)", value: monthlyDay, in: 1...31)
        case .weekly(let weekday): Picker("Weekday", selection: Binding(get: { weekday }, set: { recurrence = .weekly(weekday: $0) })) { ForEach(1...7, id: \.self) { Text(Calendar.current.weekdaySymbols[$0 - 1]).tag($0) } }
        case .yearly(let month, let day):
            Picker("Month", selection: Binding(get: { month }, set: { recurrence = .yearly(month: $0, day: day) })) { ForEach(1...12, id: \.self) { Text(Calendar.current.monthSymbols[$0 - 1]).tag($0) } }
            Stepper("Day \(day)", value: Binding(get: { day }, set: { recurrence = .yearly(month: month, day: $0) }), in: 1...31)
        }
    }
    private func save() {
        do {
            guard let categoryID else { throw BillError.missingCategory }
            let value = BillRule(id: original?.id ?? UUID(), cardID: original?.cardID ?? model.activeCardID, name: name, amount: try Money.parse(amount), categoryID: categoryID, recurrence: recurrence, recordingMode: mode, hasReminder: reminder, reminderLeadDays: leadDays, createdAt: original?.createdAt ?? .now, isActive: active)
            try value.validate(categories: model.activeCategories)
            try model.saveBill(value, in: value.cardID)
            close()
        } catch { self.error = error.localizedDescription }
    }
}

struct MacAnalyticsView: View {
    @Bindable var state: MacAppState
    @State private var horizon: AnalyticsTimeHorizon? = .thisCycle // nil = custom
    @State private var customStart = Calendar.current.date(byAdding: .day, value: -29, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var editingDate: Bool? // true = start, false = end
    @State private var scopeCycle: BudgetCycle? // nil = calendar month, as on iOS for multi-card scopes
    @State private var hoverDay: String?
    @State private var hoverCumulative: String?
    @State private var hoverWeekday: String?
    private var model: AppModel { state.model }
    private static let idr = Decimal.FormatStyle.Currency(code: "IDR").precision(.fractionLength(0))

    /// "This month" is dropped when the budget cycle is the calendar month (identical data).
    private var horizons: [AnalyticsTimeHorizon] {
        let cycle = AnalyticsEngine.dateRange(for: .thisCycle, currentCycle: scopeCycle)
        let month = AnalyticsEngine.dateRange(for: .thisMonth)
        return AnalyticsTimeHorizon.allCases.filter { $0 != .thisMonth || cycle.startDay != month.startDay || cycle.endDay != month.endDay }
    }
    private var range: (startDate: Date, endDate: Date, startDay: String, endDay: String) {
        horizon.map { AnalyticsEngine.dateRange(for: $0, currentCycle: scopeCycle) }
            ?? (customStart, customEnd, Day.string(customStart), Day.string(customEnd))
    }
    private func cardExpenses(from start: String, to end: String) -> [(card: String, expense: Expense)] {
        model.cards(in: state.analyticsScope).flatMap { card in // hidden cards stay out unless picked directly
            model.expenses(for: card.id).filter { $0.day >= start && $0.day <= end }.map { (card.name, $0) }
        }
    }
    private func grouped(_ pairs: [(String, Int64)]) -> [(String, Int64)] {
        Dictionary(pairs, uniquingKeysWith: +).map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    var body: some View {
        let range = range
        let rows = cardExpenses(from: range.startDay, to: range.endDay)
        let expenses = rows.map(\.expense)
        let total = expenses.reduce(0) { $0 + $1.amount }
        let daily = grouped(expenses.map { ($0.day, $0.amount) }).sorted { $0.0 < $1.0 }
        var running: Int64 = 0
        let cumulative = daily.map { running += $0.1; return ($0.0, running) }
        let categories = grouped(expenses.flatMap(\.allocations).map { (model.category($0.categoryID)?.name ?? "Other", $0.amount) })
        let cards = grouped(rows.map { ($0.card, $0.expense.amount) })
        let paidWith = AnalyticsEngine.paidWithTotals(expenses, methods: model.paymentMethods).map { ($0.name, $0.amount) }
        let weekdays = weekdayTotals(expenses)
        let dayCounts = Dictionary(grouping: expenses, by: \.day).mapValues(\.count)
        let dayAmounts = Dictionary(uniqueKeysWithValues: daily)
        // Previous period of equal length, for the comparison tile.
        let length = max(1, (Calendar.current.dateComponents([.day], from: range.startDate, to: range.endDate).day ?? 0) + 1)
        let prevEnd = Calendar.current.date(byAdding: .day, value: -1, to: range.startDate) ?? range.startDate
        let prevStart = Calendar.current.date(byAdding: .day, value: -(length - 1), to: prevEnd) ?? prevEnd
        let previous = cardExpenses(from: Day.string(prevStart), to: Day.string(prevEnd)).reduce(0) { $0 + $1.expense.amount }
        let change = previous == 0 ? nil : Int((Double(total - previous) / Double(previous) * 100).rounded())
        let biggestDay = daily.max { $0.1 < $1.1 }

        return Page(title: "Analytics") {
            periodBar(range)
                .task(id: state.analyticsScope) {
                    // Only a single card has one budget cycle; stacks and all cards use the calendar month.
                    guard case .card(let id, _) = state.analyticsScope, let budgets = try? model.expenseService?.budgets(for: id) else { scopeCycle = nil; return }
                    scopeCycle = BudgetHistory.period(containing: .now, budgets: budgets)?.cycle
                }
            HStack(spacing: 12) {
                SummaryTile(title: "Total", value: Money.format(total), detail: "\(expenses.count) expenses")
                SummaryTile(title: "Average", value: Money.format(total / Int64(max(1, daily.count))), detail: "per active day")
                SummaryTile(title: "vs previous", value: change.map { "\($0 > 0 ? "+" : "")\($0)%" } ?? "—", detail: "previous \(length) days: \(Money.format(previous))")
                SummaryTile(title: "Biggest day", value: Money.format(biggestDay?.1 ?? 0), detail: biggestDay.map { Day.title($0.0) } ?? "No spending")
            }
            cardRow {
                ChartCard("Spending over time", info: "How much you spent each day. Tall bars show your busiest spending days.") {
                    Chart {
                        ForEach(daily, id: \.0) { point in
                            BarMark(x: .value("Day", Day.date(point.0) ?? .now, unit: .day), y: .value("Amount", point.1 / 100))
                                .foregroundStyle(.red.gradient).opacity(hoverDay == nil || hoverDay == point.0 ? 1 : 0.35)
                        }
                        if let day = hoverDay, let amount = dayAmounts[day] {
                            RuleMark(x: .value("Day", Day.date(day) ?? .now, unit: .day)).foregroundStyle(.clear)
                                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                    ChartTooltip(title: Day.title(day), amount: amount, detail: transactions(dayCounts[day] ?? 0))
                                }
                        }
                    }
                    .chartOverlay { proxy in HoverOverlay(proxy: proxy) { x in hoverDay = x.flatMap { proxy.value(atX: $0, as: Date.self) }.map { Day.string($0) }.flatMap { dayAmounts[$0] == nil ? nil : $0 } } }
                    .chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                    .chartYAxis { AxisMarks(format: Self.idr) }
                }
                ChartCard("By category", info: "Where your money went, biggest category first. The percentage is its share of the total.") { BarList(items: Array(categories.prefix(8)), total: total) }
            }
            cardRow {
                ChartCard("Cumulative", info: "Your total adding up day by day. A steeper line means you spent faster.") {
                    Chart {
                        ForEach(cumulative, id: \.0) { point in
                            AreaMark(x: .value("Day", Day.date(point.0) ?? .now, unit: .day), y: .value("Total", point.1 / 100)).foregroundStyle(.red.opacity(0.15).gradient)
                            LineMark(x: .value("Day", Day.date(point.0) ?? .now, unit: .day), y: .value("Total", point.1 / 100)).foregroundStyle(.red)
                        }
                        if let day = hoverCumulative, let point = cumulative.first(where: { $0.0 == day }) {
                            RuleMark(x: .value("Day", Day.date(day) ?? .now, unit: .day)).foregroundStyle(.secondary.opacity(0.5))
                            PointMark(x: .value("Day", Day.date(day) ?? .now, unit: .day), y: .value("Total", point.1 / 100)).foregroundStyle(.red)
                                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                    ChartTooltip(title: "Total by \(Day.title(day))", amount: point.1, detail: "\(Money.format(dayAmounts[day] ?? 0)) that day")
                                }
                        }
                    }
                    .chartOverlay { proxy in HoverOverlay(proxy: proxy) { x in
                        // Snap to the latest active day at or before the cursor.
                        let day = x.flatMap { proxy.value(atX: $0, as: Date.self) }.map { Day.string($0) }
                        hoverCumulative = day.flatMap { d in cumulative.last(where: { $0.0 <= d })?.0 }
                    } }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 6)) { AxisGridLine(); AxisValueLabel(format: .dateTime.day().month(.abbreviated)) } }
                    .chartYAxis { AxisMarks(format: Self.idr) }
                }
                ChartCard("By weekday", info: "Spending grouped by day of the week. Shows which days you tend to spend most.") {
                    Chart {
                        ForEach(weekdays, id: \.name) { point in
                            BarMark(x: .value("Weekday", point.name), y: .value("Amount", point.amount / 100))
                                .foregroundStyle(.red.gradient).cornerRadius(4).opacity(hoverWeekday == nil || hoverWeekday == point.name ? 1 : 0.35)
                        }
                        if let name = hoverWeekday, let point = weekdays.first(where: { $0.name == name }) {
                            RuleMark(x: .value("Weekday", name)).foregroundStyle(.clear)
                                .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                    ChartTooltip(title: point.full, amount: point.amount, detail: transactions(point.count))
                                }
                        }
                    }
                    .chartOverlay { proxy in HoverOverlay(proxy: proxy) { x in hoverWeekday = x.flatMap { proxy.value(atX: $0, as: String.self) } } }
                    .chartYAxis { AxisMarks(format: Self.idr) }
                }
            }
            if !paidWith.isEmpty {
                cardRow {
                    ChartCard("By Paid with", info: "How you paid for the expenses in view. Expenses without a label show as Not set.") { BarList(items: paidWith, total: total) }
                }
            }
            cardRow {
                if !state.analyticsScope.isCard {
                    ChartCard("By card", info: "How the total splits across the cards in view. Hidden cards are not counted.") { BarList(items: cards, total: total) }
                }
                ChartCard("Largest expenses", info: "Your six biggest single expenses in this period.") {
                    VStack(spacing: 10) {
                        ForEach(expenses.sorted { $0.amount > $1.amount }.prefix(6)) { expense in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(expense.note.isEmpty ? (model.category(expense.allocations.first?.categoryID)?.name ?? "Expense") : expense.note).lineLimit(1)
                                    Text(Day.title(expense.day)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.format(expense.amount)).monospacedDigit()
                            }.font(.callout)
                        }
                    }.frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    private func weekdayTotals(_ expenses: [Expense]) -> [(name: String, full: String, amount: Int64, count: Int)] {
        let calendar = Calendar.current
        var totals = [Int64](repeating: 0, count: 7), counts = [Int](repeating: 0, count: 7)
        for expense in expenses {
            guard let date = Day.date(expense.day) else { continue }
            let index = calendar.component(.weekday, from: date) - 1
            totals[index] += expense.amount; counts[index] += 1
        }
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }
        return order.map { (calendar.shortWeekdaySymbols[$0], calendar.weekdaySymbols[$0], totals[$0], counts[$0]) }
    }

    private func transactions(_ count: Int) -> String { count == 1 ? "1 expense" : "\(count) expenses" }

    /// Two equal-height cards: each fills the row, row height = tallest card.
    private func cardRow(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 18) { content() }.fixedSize(horizontal: false, vertical: true)
    }

    private func periodBar(_ range: (startDate: Date, endDate: Date, startDay: String, endDay: String)) -> some View {
        HStack(spacing: 8) {
            scopeMenu
            Divider().frame(height: 18).padding(.horizontal, 4)
            ForEach(horizons) { option in Pill(option.rawValue, selected: horizon == option) { horizon = option } }
            Pill("Custom", selected: horizon == nil) { useCustom(range) }
            Divider().frame(height: 18).padding(.horizontal, 4)
            datePill(range.startDate, start: true, range: range)
            Text("–").foregroundStyle(.secondary)
            datePill(range.endDate, start: false, range: range)
        }
    }

    private var scopeMenu: some View {
        let scope = state.analyticsScope
        let pick = { (new: AnalyticsFilterScope) in withAnimation(.snappy) { state.analyticsScope = new } }
        return Menu {
            Button { pick(.allCards) } label: { Label("All cards", systemImage: "rectangle.stack") }
            if !model.stacks.isEmpty {
                Section("Stacks") {
                    ForEach(model.stacks) { stack in Button { pick(.stack(id: stack.id, name: stack.name)) } label: { Label(stack.name, systemImage: stack.icon) } }
                }
            }
            Section("Cards") {
                ForEach(model.unhiddenCards) { card in Button { pick(.card(id: card.id, name: card.name)) } label: { Label(card.name, systemImage: "creditcard") } }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: scope.icon)
                Text(scope.title)
                Image(systemName: "chevron.down").font(.caption2.weight(.bold))
            }
            .font(.callout.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 7)
            .background(Color.secondary.opacity(0.12), in: Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    }

    private func useCustom(_ range: (startDate: Date, endDate: Date, startDay: String, endDay: String)) {
        if horizon != nil { customStart = range.startDate; customEnd = range.endDate } // keep the visible range
        horizon = nil
    }

    private func datePill(_ date: Date, start: Bool, range: (startDate: Date, endDate: Date, startDay: String, endDay: String)) -> some View {
        Pill(date.formatted(date: .abbreviated, time: .omitted), selected: horizon == nil && editingDate == start) {
            useCustom(range); editingDate = start
        }
        .popover(isPresented: Binding(get: { editingDate == start }, set: { if !$0 { editingDate = nil } }), arrowEdge: .bottom) {
            MonthCalendar(selection: start ? $customStart : $customEnd, rangeStart: customStart, rangeEnd: customEnd,
                          bounds: start ? Date.distantPast...customEnd : customStart...Date.distantFuture)
        }
    }
}

private struct Pill: View {
    let title: String, selected: Bool, action: () -> Void
    init(_ title: String, selected: Bool, action: @escaping () -> Void) { self.title = title; self.selected = selected; self.action = action }
    var body: some View {
        Button { withAnimation(.snappy) { action() } } label: {
            Text(title).font(.callout.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 7)
                .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(selected ? Color.white : Color.primary)
        }.buttonStyle(.plain)
    }
}

private struct ChartCard<Content: View>: View {
    let title: String, info: String
    @ViewBuilder let content: Content
    @State private var showInfo = false
    init(_ title: String, info: String, @ViewBuilder content: () -> Content) { self.title = title; self.info = info; self.content = content() }
    var body: some View {
        GroupBox { content.frame(minHeight: 240, maxHeight: .infinity).padding(8) } label: {
            HStack(spacing: 4) {
                Text(title)
                Button { showInfo.toggle() } label: { Image(systemName: "info.circle").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("About \(title)")
                    .popover(isPresented: $showInfo, arrowEdge: .bottom) {
                        Text(info).font(.callout).fixedSize(horizontal: false, vertical: true).frame(width: 240, alignment: .leading).padding(14)
                    }
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Labelled horizontal bars; plain rows because Charts overlapped category labels on macOS.
private struct BarList: View {
    let items: [(String, Int64)], total: Int64
    var body: some View {
        let peak = max(1, items.map(\.1).max() ?? 1)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(items, id: \.0) { name, amount in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(name); Spacer()
                        Text("\(Int((Double(amount) / Double(max(1, total)) * 100).rounded()))%").foregroundStyle(.tertiary)
                        Text(Money.format(amount)).foregroundStyle(.secondary).monospacedDigit()
                    }.font(.callout)
                    GeometryReader { Capsule().fill(.red.gradient).frame(width: max(6, $0.size.width * CGFloat(amount) / CGFloat(peak))) }.frame(height: 8)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Month grid in SwiftUI; the AppKit graphical DatePicker drew a dated focus ring.
private struct MonthCalendar: View {
    @Binding var selection: Date
    let rangeStart: Date, rangeEnd: Date, bounds: ClosedRange<Date>
    @State private var month: Date = .now
    @Environment(\.dismiss) private var dismiss
    private let calendar = Calendar.current

    var body: some View {
        let first = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        let days: [Date?] = Array(repeating: nil, count: lead) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first) }
        let symbols = (0..<7).map { calendar.veryShortWeekdaySymbols[(calendar.firstWeekday - 1 + $0) % 7] }
        VStack(spacing: 10) {
            HStack {
                Text(first.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                Button { shift(1) } label: { Image(systemName: "chevron.right") }
            }.buttonStyle(.borderless)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(32), spacing: 2), count: 7), spacing: 2) {
                ForEach(symbols.indices, id: \.self) { Text(symbols[$0]).font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                ForEach(days.indices, id: \.self) { index in
                    if let day = days[index] { cell(day) } else { Color.clear.frame(height: 32) }
                }
            }
        }
        .padding(14).frame(width: 260)
        .onAppear { month = selection }
    }

    private func cell(_ day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: selection)
        let inRange = day >= calendar.startOfDay(for: rangeStart) && day <= rangeEnd
        let enabled = bounds.contains(day) || calendar.isDate(day, inSameDayAs: bounds.lowerBound)
        return Button { selection = day; dismiss() } label: {
            Text("\(calendar.component(.day, from: day))").font(.callout.weight(selected ? .semibold : .regular)).monospacedDigit()
                .frame(width: 32, height: 32)
                .background {
                    if selected { Circle().fill(Color.accentColor) } else if inRange { Circle().fill(Color.accentColor.opacity(0.15)) }
                }
                .foregroundStyle(selected ? Color.white : calendar.isDateInToday(day) ? Color.accentColor : Color.primary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.3)
    }

    private func shift(_ value: Int) { withAnimation(.snappy) { month = calendar.date(byAdding: .month, value: value, to: month) ?? month } }
}

/// Reports the hovered x position inside the plot area, or nil when the pointer leaves.
private struct HoverOverlay: View {
    let proxy: ChartProxy
    let onHover: (CGFloat?) -> Void
    var body: some View {
        GeometryReader { geometry in
            Rectangle().fill(.clear).contentShape(Rectangle()).onContinuousHover { phase in
                if case .active(let point) = phase, let plot = proxy.plotFrame { onHover(point.x - geometry[plot].minX) } else { onHover(nil) }
            }
        }
    }
}

private struct ChartTooltip: View {
    let title: String, amount: Int64, detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(Money.format(amount)).font(.callout.weight(.semibold)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    }
}
