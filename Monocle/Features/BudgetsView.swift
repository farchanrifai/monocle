import SwiftUI

struct BudgetsView: View {
    @Bindable var model: AppModel
    @State private var editing = false

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Eyebrow(text: model.currentBudgetPeriod.isTransition ? "Transition · \(model.cycle.label)" : model.cycle.label)
                    Text("Room for what\nmatters.").font(.largeTitle.weight(.medium)).tracking(-1)
                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow(text: model.remaining >= 0 ? "Left this cycle" : "Over budget")
                        Text(Money.format(abs(model.remaining))).font(.system(size: 37, weight: .medium, design: .monospaced)).tracking(-1.5).minimumScaleFactor(0.6).lineLimit(1)
                        ProgressView(value: min(1, Double(model.spent) / Double(max(1, model.activeBudget.overallLimit)))).tint(MC.red)
                        HStack {
                            Text("\(Money.format(model.spent)) spent")
                            Spacer()
                            Text("of \(Money.format(model.activeBudget.overallLimit))")
                        }.font(.caption).foregroundStyle(.secondary)
                    }.padding(22).background(MC.surface, in: RoundedRectangle(cornerRadius: 22))

                    Button {
                        model.showAnalytics = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .font(.title3)
                                .foregroundStyle(MC.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Spending Trends & Charts")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Burn-up curves, velocity, and daily rhythm")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .background(MC.surface, in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(PressFeedbackStyle())
                    .accessibilityIdentifier("openAnalyticsFromBudgets")

                    HStack {
                        Text("Where it went").font(.title3.weight(.semibold))
                        Spacer()
                        Eyebrow(text: "This cycle")
                    }
                    VStack(spacing: 22) {
                        ForEach(model.categories) { category in
                            let spent = model.spent(in: category)
                            let limit = model.activeBudget.limit(for: category.id)
                            HStack(spacing: 14) {
                                CategoryMark(symbol: category.symbol)
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(category.name).font(.subheadline)
                                        Spacer()
                                        Text(limit.map { "\(Money.format(spent)) / \(Money.format($0))" } ?? Money.format(spent))
                                            .font(.subheadline.monospacedDigit())
                                    }
                                    if let limit {
                                        ProgressView(value: min(1, Double(spent) / Double(max(1, limit)))).tint(MC.red)
                                    } else {
                                        ProgressView(value: model.spent == 0 ? 0 : Double(spent) / Double(model.spent)).tint(.primary)
                                    }
                                }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Budget history").font(.title3.weight(.semibold))
                        ForEach(model.budgetHistory.reversed()) { budget in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("From \(Day.title(budget.effectiveDay))")
                                    Text("Cycle starts on day \(budget.startDay)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let transitionEndDay = budget.transitionEndDay {
                                        Text("Transition ends \(Day.title(transitionEndDay))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(Money.format(budget.overallLimit)).font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                    Text("Budget changes are stored as effective-dated versions. Amount changes can start this or the next cycle; a start-day change begins at the next existing boundary and keeps the transition period visible.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(24)
        }.background(MC.paper)
            .navigationTitle("Budgets").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Edit", systemImage: "slider.horizontal.3") { editing = true } } }
            .sheet(isPresented: $editing) { BudgetEditor(model: model) }
            .sheet(isPresented: $model.showAnalytics) { AnalyticsView(model: model) }
    }
}

struct BudgetEditor: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var startDay = 1
    @State private var applyToNextCycle = false
    @State private var categoryAmounts: [UUID: String] = [:]
    @State private var originalBudget: BudgetVersion?
    @State private var error: String?

    private func resolveInput(_ input: String, preserving previous: Int64?) throws -> Int64 {
        if let previous, input == Money.exactDigits(previous) { return previous }
        return try Money.parse(input)
    }
    private var changingStartDay: Bool { startDay != model.activeBudget.startDay }
    private var transitionCycle: BudgetCycle {
        .init(start: model.cycle.end, end: BudgetHistory.transitionEnd(after: model.cycle.end, startDay: startDay))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Overall budget · IDR") {
                    TextField("4500000", text: $amount).keyboardType(.numberPad)
                }
                Section {
                    Picker("Day of month", selection: $startDay) {
                        ForEach(1...31, id: \.self) { Text("Day \($0)").tag($0) }
                    }
                    if changingStartDay {
                        LabeledContent("Starts", value: "Next boundary · \(Day.title(Day.string(model.cycle.end)))")
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
                }
                Section {
                    ForEach(model.categories) { category in
                        TextField(category.name + " · no limit", text: Binding(
                            get: { categoryAmounts[category.id] ?? "" },
                            set: { categoryAmounts[category.id] = $0 }
                        )).keyboardType(.numberPad)
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
                                let limits = try model.categories.compactMap { category -> CategoryBudget? in
                                    let value = categoryAmounts[category.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                                    guard !value.isEmpty else { return nil }
                                    return CategoryBudget(categoryID: category.id, limit: try resolveInput(value, preserving: originalBudget?.limit(for: category.id)))
                                }
                                try model.saveBudget(overallLimit: try resolveInput(amount, preserving: originalBudget?.overallLimit), startDay: startDay,
                                                     categoryLimits: limits,
                                                     applyToNextCycle: !changingStartDay && applyToNextCycle)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                }
                .onAppear {
                    originalBudget = model.activeBudget
                    amount = Money.exactDigits(model.activeBudget.overallLimit)
                    startDay = model.activeBudget.startDay
                    categoryAmounts = Dictionary(uniqueKeysWithValues: model.categories.map { category in
                        (category.id, model.activeBudget.limit(for: category.id).map { Money.exactDigits($0) } ?? "")
                    })
                }
        }
    }
}
