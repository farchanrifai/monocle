import SwiftUI

struct BudgetsView: View {
    @Bindable var model: AppModel
    @State private var editing: BudgetEditTarget?
    @State private var showingAnalytics = false
    /// nil follows the active card.
    @State private var picked: BudgetSubject?

    private var subject: BudgetSubject { picked ?? .card(model.activeCardID) }
    private var editable: Bool { if case .card = subject { true } else { false } }
    private var isStack: Bool { if case .stack = subject { true } else { false } }

    private var subjectName: String {
        switch subject {
        case .card(let id): model.cards.first { $0.id == id }?.name ?? "Card"
        case .stack(let id): model.stacks.first { $0.id == id }?.name ?? "Stack"
        }
    }

    var body: some View {
        let status = model.budgetStatus(subject)
        let cycles = model.budgetCycles(subject)
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Eyebrow(text: status.map { $0.isTransition ? "Transition · \($0.cycle.label)" : $0.cycle.label } ?? "No budget")
                Text("Room for what\nmatters.").font(.largeTitle.weight(.medium)).tracking(-1)
                subjectMenu
                if let status {
                    headline(status)
                } else {
                    Text(editable ? "This card has no budget yet." : "No monthly budget to show here yet.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                if let status, !status.lines.isEmpty {
                    HStack {
                        Text(isStack ? "By card" : "Where it went").font(.title3.weight(.semibold))
                        Spacer()
                        Eyebrow(text: "This cycle")
                    }
                    BudgetLineRows(lines: status.lines, currency: status.currency, onEdit: isStack ? { editing = BudgetEditTarget(id: $0) } : nil)
                }

                if cycles.count > 1, let status {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Cycle by cycle").font(.title3.weight(.semibold))
                        BudgetCyclesChart(results: cycles, currency: status.currency)
                        Text(isStack ? "Past stack cycles add up the cards' budgets that applied then. A cap is today's cap." : "Grey is the limit, dark is what you spent. Red went over.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if case .card(let id) = subject, let input = model.budgetCardInput(id) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Budget history").font(.title3.weight(.semibold))
                        ForEach(input.budgets.reversed()) { budget in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("From \(Day.title(budget.effectiveDay))")
                                    Text(budget.totalUntilDay.map { "Total until \(Day.title($0))" } ?? "Cycle starts on day \(budget.startDay)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let transitionEndDay = budget.transitionEndDay {
                                        Text("Transition ends \(Day.title(transitionEndDay))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(Money.format(budget.overallLimit, code: input.currency)).font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                    Text("Budget changes are stored as effective-dated versions. Amount changes can start this or the next cycle; a start-day change begins at the next existing boundary and keeps the transition period visible.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("A stack budget is its cap, or the sum of its cards' monthly budgets. Goals (Total until) are left out. Edit a card's budget with the pencil on its row; change the cap under Stacks.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(24)
        }.background(MC.paper)
            .navigationTitle("Budgets").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Analytics", systemImage: "chart.line.uptrend.xyaxis") { showingAnalytics = true }
                        .accessibilityIdentifier("budgetsAnalyticsButton")
                }
                if case .card(let id) = subject { ToolbarItem(placement: .topBarTrailing) { Button("Edit", systemImage: "slider.horizontal.3") { editing = BudgetEditTarget(id: id) } } }
            }
            .sheet(item: $editing) { BudgetEditor(model: model, cardID: $0.id).scrollEdgeEffectStyle(.soft, for: .all) }
            .navigationDestination(isPresented: $showingAnalytics) {
                AnalyticsView(model: model).hidesBottomNavigation(model)
            }
    }

    private var subjectMenu: some View {
        Menu {
            Section("Cards") {
                ForEach(model.unhiddenCards) { card in
                    Button { picked = .card(card.id) } label: {
                        if subject == .card(card.id) { Label(card.name, systemImage: "checkmark") } else { Text(card.name) }
                    }
                }
            }
            if !model.stacks.isEmpty, model.isPro { // stack budgets are Pro
                Section("Stacks") {
                    ForEach(model.stacks) { stack in
                        Button { picked = .stack(stack.id) } label: {
                            if subject == .stack(stack.id) { Label(stack.name, systemImage: "checkmark") } else { Label(stack.name, systemImage: stack.icon) }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isStack ? "square.stack.3d.up.fill" : "creditcard.fill").font(.caption)
                Text(subjectName).font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(MC.surface, in: Capsule())
        }
        .accessibilityIdentifier("budgetSubjectMenu")
    }

    private func headline(_ status: BudgetStatus) -> some View {
        let lastDay = status.cycle.calendar.date(byAdding: .day, value: -1, to: status.cycle.end) ?? status.cycle.end
        return VStack(alignment: .leading, spacing: 14) {
            Eyebrow(text: status.remaining < 0 ? "Over budget" : (status.isGoal ? "Left until \(Day.title(Day.string(lastDay)))" : "Left this cycle"))
            Text((status.approximate ? "≈ " : "") + Money.format(abs(status.remaining), code: status.currency))
                .font(.system(size: 37, weight: .medium)).tracking(-1.5).minimumScaleFactor(0.6).lineLimit(1)
            ProgressView(value: min(1, status.fraction)).tint(MC.red)
            HStack {
                Text("\(Money.format(status.spent, code: status.currency)) spent")
                Spacer()
                Text("of \(Money.format(status.limit, code: status.currency))")
            }.font(.caption).foregroundStyle(.secondary)
            if let pace = status.pace {
                Text(pace.label + (status.projected.map { " · on pace for \(Money.format($0, code: status.currency))" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(22).background(MC.surface, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct BudgetEditor: View {
    let model: AppModel
    let cardID: UUID
    private var budget: BudgetVersion { model.budgetPeriod(for: cardID).budget }
    private var cycle: Cycle { model.budgetPeriod(for: cardID).cycle }
    private var categories: [ExpenseCategory] { model.activeCategories(for: cardID) }
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var startDay = 1
    @State private var applyToNextCycle = false
    @State private var categoryAmounts: [UUID: String] = [:]
    @State private var originalBudget: BudgetVersion?
    @State private var error: String?
    @State private var isTotal = false
    @State private var totalUntil = Date.now

    private func resolveInput(_ input: String, preserving previous: Int64?) throws -> Int64 {
        if let previous, input == Money.format(previous, currency: false) { return previous }
        return try Money.parse(input)
    }
    private var changingStartDay: Bool { startDay != budget.startDay }
    /// A goal starts at this cycle's start, so it takes the place of a monthly budget that starts there.
    private var replacesMonthly: Bool { budget.totalUntilDay == nil && budget.effectiveDay == Day.string(cycle.start) }
    private var transitionCycle: Cycle {
        .init(start: cycle.end, end: BudgetHistory.transitionEnd(after: cycle.end, startDay: startDay))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Budget", selection: $isTotal) {
                        Text("Monthly").tag(false)
                        Text("Total until").tag(true)
                    }.pickerStyle(.segmented)
                    if isTotal {
                        DatePicker("Last day", selection: $totalUntil, in: cycle.start..., displayedComponents: .date)
                    }
                } footer: {
                    Text(isTotal ? "One amount for the whole period, from \(Day.title(Day.string(cycle.start))) through the last day. Use it for a trip or a goal."
                                    + (replacesMonthly ? " It replaces this cycle's monthly budget, category limits included; the monthly total comes back when the goal ends, the category limits do not." : "")
                                 : "The budget repeats every cycle.")
                }
                Section("Overall budget · \(model.currency(ofCard: cardID))") {
                    TextField(Money.format(450_000_000, currency: false), text: $amount.groupedAmount(code: model.currency(ofCard: cardID))).keyboardType(.numberPad)
                }
                if !isTotal { Section {
                    Picker("Day of month", selection: $startDay) {
                        ForEach(1...31, id: \.self) { Text("Day \($0)").tag($0) }
                    }
                    if changingStartDay {
                        LabeledContent("Starts", value: "Next boundary · \(Day.title(Day.string(cycle.end)))")
                        LabeledContent("Transition period", value: transitionCycle.label)
                    } else {
                        Picker("Apply change", selection: $applyToNextCycle) {
                            Text("This cycle").tag(false)
                            Text("Next cycle").tag(true)
                        }
                    }
                } header: { Text("Cycle starts")
                } footer: {
                    Text(changingStartDay
                         ? "The new amount applies during this transition period. Future cycles begin on day \(startDay)."
                         : "Historical cycles keep their saved budget. Only this version and later periods use the new amount.")
                } }
                Section {
                    ForEach(categories) { category in
                        TextField(category.name + " · no limit", text: Binding(
                            get: { categoryAmounts[category.id] ?? "" },
                            set: { categoryAmounts[category.id] = $0 }
                        ).groupedAmount(code: model.currency(ofCard: cardID))).keyboardType(.numberPad)
                    }
                } header: { Text("Category limits · optional")
                } footer: {
                    Text("Category limits are independent from the overall budget. Leave a category blank for no limit.")
                }
                if let error { Section { Text(error).foregroundStyle(MC.red) } }
            }.navigationTitle("Budget settings").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                let limits = try categories.compactMap { category -> CategoryBudget? in
                                    let value = categoryAmounts[category.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                    guard !value.isEmpty else { return nil }
                                    return CategoryBudget(categoryID: category.id, limit: try resolveInput(value, preserving: originalBudget?.limit(for: category.id)))
                                }
                                try model.saveBudget(overallLimit: try resolveInput(amount, preserving: originalBudget?.overallLimit),
                                                     startDay: isTotal ? budget.startDay : startDay,
                                                     categoryLimits: limits,
                                                     applyToNextCycle: !isTotal && !changingStartDay && applyToNextCycle,
                                                     totalUntil: isTotal ? totalUntil : nil, cardID: cardID)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }
                .onAppear {
                    originalBudget = budget
                    amount = Money.format(budget.overallLimit, currency: false)
                    startDay = budget.startDay
                    isTotal = budget.totalUntilDay != nil
                    totalUntil = budget.totalUntilDay.flatMap { Day.date($0) }
                        ?? Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
                    categoryAmounts = Dictionary(uniqueKeysWithValues: categories.map { category in
                        (category.id, budget.limit(for: category.id).map { Money.format($0, currency: false) } ?? "")
                    })
                }
        }
    }
}
