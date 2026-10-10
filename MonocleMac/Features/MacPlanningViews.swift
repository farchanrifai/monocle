import Charts
import SwiftUI

struct MacBudgetsView: View {
    @Bindable var state: MacAppState
    @State private var editing = false
    private var model: AppModel { state.model }
    private var categories: [ExpenseCategory] { model.activeCategories(for: model.activeBookID) }
    private var usedPercent: Int {
        let ratio = Double(model.spent) / Double(max(Int64(1), model.activeBudget.overallLimit))
        return Int((ratio * 100).rounded())
    }
    var body: some View {
        var spent: [UUID: Int64] = [:]
        for allocation in model.cycleExpenses.lazy.flatMap(\.allocations) { spent[allocation.categoryID, default: 0] += allocation.amount }
        return Page(title: "Budgets") {
            HStack {
                SummaryTile(title: "Limit", value: Money.format(model.activeBudget.overallLimit), detail: model.cycle.label)
                SummaryTile(title: "Spent", value: Money.format(model.spent), detail: "\(usedPercent)% used")
                SummaryTile(title: "Remaining", value: Money.format(model.remaining), detail: "Cycle day \(model.activeBudget.startDay)")
            }
            HStack { Text("Category budgets").font(.title2.bold()); Spacer(); Button("Edit Budget") { editing = true }.buttonStyle(.glass) }
            Table(categories) {
                TableColumn("Category") { category in Label(category.name, systemImage: category.symbol) }
                TableColumn("Spent") { category in Text(Money.format(spent[category.id] ?? 0)).font(.system(.body, design: .monospaced)) }
                TableColumn("Limit") { category in
                    Text(model.activeBudget.limit(for: category.id).map { Money.format($0) } ?? "—").font(.system(.body, design: .monospaced))
                }
                TableColumn("Progress") { category in
                    let limit = model.activeBudget.limit(for: category.id) ?? model.activeBudget.overallLimit
                    ProgressView(value: min(1, Double(spent[category.id] ?? 0) / Double(max(1, limit))))
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

    init(model: AppModel, close: @escaping () -> Void) {
        self.model = model; self.close = close
        _amount = State(initialValue: Money.digits(model.activeBudget.overallLimit))
        _startDay = State(initialValue: model.activeBudget.startDay)
        _categoryAmounts = State(initialValue: Dictionary(uniqueKeysWithValues: model.activeBudget.categoryLimits.map { ($0.categoryID, Money.digits($0.limit)) }))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Budget").font(.title2.bold())
            Form {
                TextField("Overall limit", text: $amount)
                Stepper("Cycle begins on day \(startDay)", value: $startDay, in: 1...31)
                Toggle("Apply to next cycle", isOn: $nextCycle)
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
            try model.saveBudget(overallLimit: total, startDay: startDay, categoryLimits: categories, applyToNextCycle: nextCycle)
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
                            Button("Record") { do { _ = try model.confirmBillOccurrence(occurrence.id) } catch { model.error = error.localizedDescription } }.buttonStyle(.glassProminent)
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
                Picker("Recording", selection: $mode) { ForEach(BillRecordingMode.allCases, id: \.self) { Text($0.title).tag($0) } }
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
            let value = BillRule(id: original?.id ?? UUID(), bookID: original?.bookID ?? model.activeBookID, name: name, amount: try Money.parse(amount), categoryID: categoryID, recurrence: recurrence, recordingMode: mode, hasReminder: reminder, reminderLeadDays: leadDays, createdAt: original?.createdAt ?? .now, isActive: active)
            try value.validate(categories: model.activeCategories)
            try model.saveBill(value, in: value.bookID)
            close()
        } catch { self.error = error.localizedDescription }
    }
}

struct MacAnalyticsView: View {
    @Bindable var state: MacAppState
    @State private var horizon: AnalyticsTimeHorizon = .thisCycle
    private var model: AppModel { state.model }
    private func daily(_ expenses: [Expense]) -> [(String, Int64)] { Dictionary(grouping: expenses, by: \.day).map { ($0.key, $0.value.reduce(0) { $0 + $1.amount }) }.sorted { $0.0 < $1.0 } }
    private func categories(_ expenses: [Expense]) -> [(String, Int64)] {
        var byID: [UUID: Int64] = [:]
        for expense in expenses { for allocation in expense.allocations { byID[allocation.categoryID, default: 0] += allocation.amount } }
        var values: [String: Int64] = [:]
        for (id, amount) in byID { values[model.category(id)?.name ?? "Other", default: 0] += amount }
        return values.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
    var body: some View {
        let range = AnalyticsEngine.dateRange(for: horizon, currentCycle: model.cycle)
        let expenses = model.allExpenses().filter { $0.day >= range.startDay && $0.day <= range.endDay }
        let daily = daily(expenses), categories = categories(expenses)
        return Page(title: "Analytics") {
            Picker("Period", selection: $horizon) { ForEach(AnalyticsTimeHorizon.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            HStack {
                SummaryTile(title: "Total", value: Money.format(expenses.reduce(0) { $0 + $1.amount }), detail: "\(expenses.count) transactions")
                SummaryTile(title: "Average", value: Money.format(expenses.isEmpty ? 0 : expenses.reduce(0) { $0 + $1.amount } / Int64(max(1, daily.count))), detail: "per active day")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 18)], spacing: 18) {
                GroupBox("Spending over time") {
                    Chart(daily, id: \.0) { point in
                        BarMark(x: .value("Day", point.0), y: .value("Amount", point.1 / 100)).foregroundStyle(.red.gradient)
                    }.chartYAxis { AxisMarks(format: Decimal.FormatStyle.Currency(code: "IDR").precision(.fractionLength(0))) }.frame(height: 260).padding(8)
                }
                GroupBox("By category") {
                    Chart(categories.prefix(8), id: \.0) { point in
                        BarMark(x: .value("Amount", point.1 / 100), y: .value("Category", point.0)).foregroundStyle(.red.gradient)
                    }.chartXAxis { AxisMarks(format: Decimal.FormatStyle.Currency(code: "IDR").precision(.fractionLength(0))) }.frame(height: 260).padding(8)
                }
            }
        }
    }
}
