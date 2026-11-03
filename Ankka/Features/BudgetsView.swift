import SwiftUI
import Charts

struct BudgetsView: View {
    @Bindable var model: AppModel
    @State private var editing: BudgetEditTarget?
    /// nil follows the active card.
    @State private var picked: BudgetSubject?
    /// Over-budget nudges put away with Not now, for this visit.
    @State private var dismissedNudges: Set<UUID> = []
    /// A finished cycle picked from the Cycles chart; nil is the running one.
    @State private var viewing: Cycle?

    init(model: AppModel, subject: BudgetSubject? = nil) {
        self.model = model
        _picked = State(initialValue: subject)
    }

    private var subject: BudgetSubject { picked ?? defaultSubject }

    /// The active card when it's visible; otherwise the first visible card with a budget, then any visible card.
    /// A hidden card (the Sample card once put away) never opens the page.
    private var defaultSubject: BudgetSubject {
        let visible = model.unhiddenCards
        if visible.contains(where: { $0.id == model.activeCardID }) { return .card(model.activeCardID) }
        if let budgeted = visible.first(where: { model.budgetStatus(.card($0.id)) != nil }) { return .card(budgeted.id) }
        return .card(visible.first?.id ?? model.activeCardID)
    }
    private var editable: Bool { if case .card = subject { true } else { false } }
    /// A stack or All cards: its rows are cards, not categories.
    private var isStack: Bool { !editable }
    private var scope: AnalyticsFilterScope {
        switch subject {
        case .card(let id): .card(id: id, name: subjectName)
        case .stack(let id): .stack(id: id, name: subjectName)
        case .all: .allCards
        }
    }

    /// The editor opens on `card`, or the page's card, or the active card when it's among the page's cards.
    private func editTarget(card: UUID? = nil) -> BudgetEditTarget {
        let choices: [UUID] = switch subject {
        case .card: model.unhiddenCards.map(\.id)
        case .stack(let id): model.cards(in: .stack(id: id, name: "")).map(\.id)
        case .all: model.unhiddenCards.map(\.id)
        }
        let pageCard: UUID? = if case .card(let id) = subject { id } else { nil }
        let id = card ?? pageCard ?? (choices.contains(model.activeCardID) ? model.activeCardID : choices.first ?? model.activeCardID)
        return BudgetEditTarget(id: id, month: viewing?.start ?? .now, choices: choices.isEmpty ? [id] : choices)
    }

    private var subjectName: String {
        switch subject {
        case .card(let id): model.cards.first { $0.id == id }?.name ?? "Card"
        case .stack(let id): model.stacks.first { $0.id == id }?.name ?? "Stack"
        case .all: "All cards"
        }
    }

    var body: some View {
        // Budgets and expenses are read from the service's caches, which views don't observe; the committed
        // revision is what changes when an expense or a budget is saved, so reading it redraws the page.
        let _ = model.dataRevision
        let status = model.budgetStatus(subject, at: viewing.map(lastDay) ?? .now)
        let cycles = model.budgetCycles(subject, count: 12).filter { $0.isCurrent || $0.spent > 0 }
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let status {
                    headline(status, cycles: cycles)
                    panel { PaceChart(status: status, points: spending(status)) }
                    if viewing == nil, let nudge = nudge(status) { nudge }
                    if !status.lines.isEmpty {
                        section(isStack ? "Cards" : "Categories") {
                            panel {
                                BudgetRings(lines: status.lines, currency: status.currency, symbol: symbol(for:),
                                            total: status.lines.allSatisfy { $0.limit == nil } ? status.spent : nil)
                            }
                        }
                    }
                    let shownCycles = Array(cycles.suffix(7))
                    if shownCycles.count > 1 {
                        section("Months") {
                            panel {
                                PastCyclesChart(results: shownCycles, currency: status.currency, selected: status.cycle.start) { result in
                                    withAnimation(.smooth) { viewing = result.isCurrent ? nil : result.cycle }
                                }
                            }
                        }
                    }
                    if isStack {
                        Text(subject == .all
                             ? "All cards adds up every visible card's monthly budget and spending, by calendar month."
                             : "A stack budget is its cap, or the sum of its cards' monthly budgets. Set the cap under Cards & Stacks.")
                            .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                    }
                } else {
                    empty
                }
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 32)
        }.background(MC.paper)
            .navigationTitle("Budgets").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit budget", systemImage: "pencil") { editing = editTarget() }
                        .tint(.primary) // toolbar icons are black, like Home's
                        .accessibilityIdentifier("budgetSettingsButton")
                }
            }
            .onChange(of: subject) { viewing = nil }
            .sheet(item: $editing) { target in
                BudgetEditor(model: model, cardID: target.id, month: target.month,
                             cardChoices: target.choices.compactMap { id in model.cards.first { $0.id == id } })
                    .scrollEdgeEffectStyle(.soft, for: .all)
            }
    }

    /// The answer first, in plain words: what's left, of how much, for how long, and what that is per day.
    @ViewBuilder private func headline(_ status: BudgetStatus, cycles: [BudgetCycleResult]) -> some View {
        if viewing != nil { pastHeadline(status, cycles: cycles) } else { runningHeadline(status, cycles: cycles) }
    }

    /// The period the page shows; it opens the list of cycles, newest first (always a menu, so every card reads the same).
    private func periodMenu(_ status: BudgetStatus, cycles: [BudgetCycleResult]) -> some View {
        Menu {
            ForEach(cycles.reversed()) { result in
                Button { withAnimation(.smooth) { viewing = result.isCurrent ? nil : result.cycle } } label: {
                    if result.cycle.start == status.cycle.start { Label(result.cycle.label, systemImage: "checkmark") } else { Text(result.cycle.label) }
                    if result.isCurrent { Text("This month") }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Eyebrow(text: status.cycle.label)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .tint(.primary)
        .accessibilityLabel("Period, \(status.cycle.label)")
        .accessibilityIdentifier("budgetPeriodMenu")
    }

    /// Which card or stack, and which month, side by side above the headline.
    private func pickers(_ status: BudgetStatus, cycles: [BudgetCycleResult]) -> some View {
        HStack(spacing: 8) {
            subjectMenu
            periodMenu(status, cycles: cycles)
        }.padding(.leading, -10) // the pills' text lines up with the headline
    }

    /// A finished cycle: how it ended.
    private func pastHeadline(_ status: BudgetStatus, cycles: [BudgetCycleResult]) -> some View {
        let over = status.remaining < 0
        let prefix = status.approximate ? "≈ " : ""
        return VStack(alignment: .leading, spacing: 8) {
            pickers(status, cycles: cycles)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(prefix + Money.format(abs(status.remaining), code: status.currency))
                    .font(.system(size: 44, weight: .semibold)).tracking(-1).monospacedDigit()
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .foregroundStyle(over ? MC.red : .primary)
                Text(over ? "over" : "under").font(.title3.weight(.medium)).foregroundStyle(.secondary)
            }
            Text("Spent \(prefix)\(Money.format(status.spent, code: status.currency)) of \(Money.format(status.limit, code: status.currency))")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4).padding(.top, 8)
    }

    private func lastDay(_ cycle: Cycle) -> Date { cycle.calendar.date(byAdding: .day, value: -1, to: cycle.end) ?? cycle.start }

    private func runningHeadline(_ status: BudgetStatus, cycles: [BudgetCycleResult]) -> some View {
        let over = status.remaining < 0
        let (elapsed, total) = BudgetReport.days(in: status.cycle, now: .now)
        let daysLeft = max(1, total - elapsed + 1)
        let prefix = status.approximate ? "≈ " : ""
        let days = daysLeft == 1 ? "last day" : "\(daysLeft) days left"
        return VStack(alignment: .leading, spacing: 8) {
            pickers(status, cycles: cycles)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(prefix + Money.format(abs(status.remaining), code: status.currency))
                    .font(.system(size: 44, weight: .semibold)).tracking(-1).monospacedDigit()
                    .minimumScaleFactor(0.5).lineLimit(1)
                    .foregroundStyle(over ? MC.red : .primary)
                Text(over ? "over" : "left").font(.title3.weight(.medium)).foregroundStyle(.secondary)
            }
            Text(over ? "of \(Money.format(status.limit, code: status.currency)) · \(days)"
                      : "of \(Money.format(status.limit, code: status.currency)) · \(days) · about \(prefix)\(Money.format(shown(status.remaining / Int64(daysLeft), status.currency), code: status.currency)) a day")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4).padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    /// Spending so far, day by day, from the same report Analytics uses. The report counts in the reporting
    /// currency; scaling it to the budget's own total puts the line in the card's currency (same shape, same days).
    private func spending(_ status: BudgetStatus) -> [SpendPoint] {
        let points = AnalyticsReport.build(data: model.reportingData(for: scope), horizon: .thisCycle, now: viewing.map(lastDay) ?? .now).dailyPoints
            .filter { !$0.isFuture && status.cycle.start <= $0.date && $0.date < status.cycle.end }
        let last = Double(points.last?.cumulativeAmount ?? 0)
        let scale = last > 0 ? Double(status.spent) / last : 0
        return points.map { SpendPoint(date: $0.date, spent: Int64((Double($0.cumulativeAmount ?? 0) * scale).rounded())) }
    }

    private func symbol(for line: BudgetLine) -> String {
        isStack ? "creditcard" : (model.category(line.id)?.symbol ?? "circle.dashed")
    }

    /// One suggestion, only when a category went over: raise its limit, or put the nudge away.
    @ViewBuilder private func nudge(_ status: BudgetStatus) -> (some View)? {
        if case .card(let id) = subject,
           let line = status.lines.filter({ ($0.limit ?? .max) < $0.spent && !dismissedNudges.contains($0.id) })
               .max(by: { $0.spent - ($0.limit ?? 0) < $1.spent - ($1.limit ?? 0) }),
           let limit = line.limit {
            panel {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbol(for: line)).font(.system(size: 15, weight: .semibold)).foregroundStyle(MC.red)
                        .frame(width: 34, height: 34).background(MC.red.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(line.name) is \(Money.format(line.spent - limit, code: status.currency)) over its \(Money.format(limit, code: status.currency)) limit.")
                            .font(.system(size: 14, weight: .semibold))
                        HStack(spacing: 8) {
                            Button("Raise the limit") { editing = editTarget(card: id) }
                                .buttonStyle(.borderedProminent).tint(MC.red).controlSize(.small)
                            Button("Not now") { withAnimation(.smooth) { _ = dismissedNudges.insert(line.id) } }
                                .buttonStyle(.bordered).tint(.secondary).controlSize(.small)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        }
    }

    /// Home's surface: a white panel with 24 pt corners.
    private func panel(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MC.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            // Charts morph between cycles; the clip keeps a sliding line inside its card.
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Home's section style: a 15 pt title over its panel.
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader).padding(.leading, 4)
            content()
        }
    }

    /// The card or stack the page is about, as the navigation bar's title, in Home's scope-badge style.
    private var subjectMenu: some View {
        Menu {
            if model.unhiddenCards.count > 1 {
                Button { picked = .all } label: {
                    if subject == .all { Label("All cards", systemImage: "checkmark") } else { Label("All cards", systemImage: AnalyticsFilterScope.allCards.icon) }
                }
            }
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
            HStack(spacing: 5) {
                Eyebrow(text: subjectName).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .tint(.primary)
        .accessibilityLabel("Budget for \(subjectName)")
        .accessibilityIdentifier("budgetSubjectMenu")
    }

    /// No budget yet: still what this cycle has spent and where, with the invitation to set one.
    @ViewBuilder private var empty: some View {
        let report = AnalyticsReport.build(data: model.reportingData(for: scope), horizon: .thisCycle)
        let currency: String = switch subject {
        case .card(let id): model.currency(ofCard: id)
        case .stack, .all: model.reportingCurrency
        }
        // The report's end date is the last day; a cycle's end is the day after.
        let range = Cycle(start: report.range.startDate, end: Day.calendar.date(byAdding: .day, value: 1, to: report.range.endDate) ?? report.range.endDate)
        let lines = report.categoryPoints.filter { $0.amount > 0 }
            .map { BudgetLine(id: $0.categoryID, name: $0.categoryName, limit: nil, spent: $0.amount) }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                subjectMenu
                Eyebrow(text: range.label)
            }.padding(.leading, -10)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Money.format(report.metrics.totalSpend, code: currency))
                    .font(.system(size: 44, weight: .semibold)).tracking(-1).monospacedDigit()
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text("spent").font(.title3.weight(.medium)).foregroundStyle(.secondary)
            }
            Text("\(report.metrics.transactionCount) \(report.metrics.transactionCount == 1 ? "expense" : "expenses") · about \(Money.format(report.metrics.dailyAverage, code: currency)) a day")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4).padding(.top, 8)
        .accessibilityElement(children: .combine)
        panel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "target").font(.system(size: 15, weight: .semibold)).foregroundStyle(MC.red)
                    .frame(width: 34, height: 34).background(MC.red.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(editable ? "Set a budget for \(subjectName)" : subject == .all ? "No card budgets yet" : "No budget for this stack yet")
                            .font(.system(size: 14, weight: .semibold))
                        Text(editable ? "See what's left each day, how your spending keeps pace, and get a nudge when a category runs over."
                                      : subject == .all ? "Set a budget on a card and it adds up here."
                                      : "A stack's budget comes from its cards' budgets, or a cap set under Stacks.")
                            .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Set a budget") { editing = editTarget() }
                        .buttonStyle(.borderedProminent).tint(MC.red).controlSize(.small)
                }
                Spacer(minLength: 0)
            }
        }
        if !lines.isEmpty {
            section("Where it went") {
                panel { BudgetRings(lines: lines, currency: currency, symbol: symbol(for:), total: report.metrics.totalSpend) }
            }
        }
    }
}

/// Spending so far against the budget's even pace, with how far under or over that pace today is.
private struct PaceChart: View {
    let status: BudgetStatus
    let points: [SpendPoint]

    var body: some View {
        let (elapsed, total) = BudgetReport.days(in: status.cycle, now: .now)
        let pace = shown(Int64((Double(status.limit) * Double(elapsed) / Double(total)).rounded()), status.currency)
        let gap = pace - status.spent
        let elapsedPoints = points
        let calendar = status.cycle.calendar
        let lastDay = calendar.date(byAdding: .day, value: -1, to: status.cycle.end) ?? status.cycle.end
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spending pace").font(.system(size: 15, weight: .semibold))
                Spacer()
                // A finished cycle's gap is the headline's amount; only a running one has a pace to compare.
                if status.cycle.end > .now {
                    Text(gap >= 0 ? "\(Money.format(gap, code: status.currency)) under" : "\(Money.format(-gap, code: status.currency)) over")
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(gap >= 0 ? Color.primary : MC.red)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(gap >= 0 ? Color.primary.opacity(0.06) : MC.red.opacity(0.12), in: Capsule())
                }
            }
            Chart {
                LineMark(x: .value("Day", status.cycle.start), y: .value("Pace", 0), series: .value("Series", "Pace"))
                    .foregroundStyle(Color.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                LineMark(x: .value("Day", lastDay), y: .value("Pace", status.limit), series: .value("Series", "Pace"))
                    .foregroundStyle(Color.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                ForEach(elapsedPoints) { point in
                    AreaMark(x: .value("Day", point.date, unit: .day), y: .value("Spent", point.spent), series: .value("Series", "Spent"))
                        .foregroundStyle(LinearGradient(colors: [MC.red.opacity(0.22), MC.red.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Day", point.date, unit: .day), y: .value("Spent", point.spent), series: .value("Series", "Spent"))
                        .foregroundStyle(MC.red).lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round)).interpolationMethod(.monotone)
                }
                if let last = elapsedPoints.last {
                    PointMark(x: .value("Day", last.date, unit: .day), y: .value("Spent", last.spent)).foregroundStyle(MC.red).symbolSize(44)
                }
            }
            .chartXScale(domain: status.cycle.start...lastDay)
            .chartYScale(domain: 0...max(status.limit, status.spent))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: [status.cycle.start, lastDay]) { value in
                    AxisValueLabel(anchor: value.index == 0 ? .topLeading : .topTrailing) {
                        if let date = value.as(Date.self) { Text(date.formatted(.dateTime.month(.abbreviated).day())).font(.caption2) }
                    }
                }
            }
            .frame(height: 140)
            HStack {
                Label("Spent \(Money.format(status.spent, code: status.currency))", systemImage: "circle.fill")
                    .labelStyle(LegendLabel(color: MC.red))
                Spacer()
                Label("Even pace \(Money.format(pace, code: status.currency))", systemImage: "circle.fill")
                    .labelStyle(LegendLabel(color: .secondary))
            }
            .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spending pace")
        .accessibilityValue("Spent \(Money.format(status.spent, code: status.currency)); an even pace would be \(Money.format(pace, code: status.currency)) by today")
    }
}

struct SpendPoint: Identifiable {
    let date: Date
    let spent: Int64
    var id: Date { date }
}

/// Rounds to the units a currency shows (whole yen or rupiah, cents for dollars), since amounts are kept in hundredths.
private func shown(_ amount: Int64, _ code: String) -> Int64 {
    Money.fractionDigits(code) > 0 ? amount : Int64((Double(amount) / 100).rounded()) * 100
}

private struct LegendLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { configuration.icon.font(.system(size: 6)).foregroundStyle(color); configuration.title }
    }
}

/// Each category as a ring around its own icon: how much of its limit is used, and what's left or over.
private struct BudgetRings: View {
    let lines: [BudgetLine]
    let currency: String
    let symbol: (BudgetLine) -> String
    /// When there's no budget at all, rings show each category's share of this total instead.
    var total: Int64?

    var body: some View {
        let limited = lines.filter { $0.limit != nil }.sorted { share($0) > share($1) }
        let unlimited = lines.filter { $0.limit == nil }.sorted { $0.spent > $1.spent }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(limited + unlimited) { line in ring(line) }
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .padding(.horizontal, -16)
    }

    private func share(_ line: BudgetLine) -> Double { Double(line.spent) / Double(max(1, line.limit ?? 1)) }

    private func ring(_ line: BudgetLine) -> some View {
        let over = line.limit.map { line.spent > $0 } ?? false
        let caption: String = if let limit = line.limit {
            Money.format(abs(limit - line.spent), code: currency) + (over ? " over" : " left")
        } else {
            Money.format(line.spent, code: currency)
        }
        return VStack(spacing: 7) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.07), lineWidth: 6)
                if line.limit != nil {
                    Circle().trim(from: 0, to: min(1, share(line)))
                        .stroke(over ? MC.red : Color.primary.opacity(0.8), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                } else if let total {
                    Circle().trim(from: 0, to: min(1, Double(line.spent) / Double(max(1, total))))
                        .stroke(Color.primary.opacity(0.8), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                } else {
                    Circle().stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4])).padding(3)
                }
                Image(systemName: symbol(line)).font(.system(size: 19, weight: .medium))
                    .foregroundStyle(over ? MC.red : .primary)
            }
            .frame(width: 58, height: 58)
            .padding(.top, 3)
            Text(line.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(line.limit == nil ? (total.map { (Double(line.spent) / Double(max(1, $0))).formatted(.percent.precision(.fractionLength(0))) } ?? "No limit") : caption)
                .font(.system(size: 11.5)).monospacedDigit()
                .foregroundStyle(over ? MC.red : .secondary).lineLimit(1).minimumScaleFactor(0.7)
            if line.limit == nil {
                Text(caption).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(width: 78)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.name)
        .accessibilityValue(line.limit.map { "\(Money.format(line.spent, code: currency)) of \(Money.format($0, code: currency)), \(caption)" } ?? "\(caption) spent, no limit")
    }
}

/// Finished cycles, oldest to newest: the share of each budget that was spent, with the 100% line marked.
/// Tapping a bar picks that cycle.
private struct PastCyclesChart: View {
    let results: [BudgetCycleResult]
    let currency: String
    let selected: Date
    let onSelect: (BudgetCycleResult) -> Void

    var body: some View {
        Chart {
            RuleMark(y: .value("Budget", 1.0)).foregroundStyle(Color.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            ForEach(results) { result in
                let share = Double(result.spent) / Double(max(1, result.limit))
                BarMark(x: .value("Cycle", result.cycle.start.formatted(.dateTime.month(.abbreviated))), y: .value("Share", share), width: .ratio(0.5))
                    .foregroundStyle(result.isOver ? MC.red : Color.primary.opacity(0.75))
                    .opacity(result.cycle.start == selected ? 1 : 0.35)
                    .cornerRadius(6)
                    .annotation(position: .top, spacing: 4) {
                        Text(share.formatted(.percent.precision(.fractionLength(0)))).font(.caption2.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(result.isOver ? MC.red : .secondary)
                    }
            }
        }
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(1.15, (results.map { Double($0.spent) / Double(max(1, $0.limit)) }.max() ?? 1) * 1.15))
        .chartXAxis { AxisMarks { AxisValueLabel().font(.caption2) } }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { location in
                        guard let plot = proxy.plotFrame,
                              let month: String = proxy.value(atX: location.x - geo[plot].origin.x) else { return }
                        // ponytail: bars are keyed by month name; two cycles starting in one month (a transition) pick the later.
                        if let result = results.last(where: { $0.cycle.start.formatted(.dateTime.month(.abbreviated)) == month }) {
                            onSelect(result)
                        }
                    }
            }
        }
        .frame(height: 130)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Past cycles")
        .accessibilityValue(results.map { "\($0.cycle.label): \(Money.format($0.spent, code: currency)) of \(Money.format($0.limit, code: currency))" }.joined(separator: ". "))
    }
}

struct BudgetEditor: View {
    let model: AppModel
    /// The cards the picker offers: the page's card, stack or all visible cards.
    let cardChoices: [Card]
    @State private var cardID: UUID
    /// Any day in the month being edited.
    @State private var month: Date
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var categoryAmounts: [UUID: String] = [:]
    @State private var originalBudget: BudgetVersion?
    @State private var error: String?
    @State private var isTotal = false
    @State private var repeats = true
    @State private var totalUntil = Date.now
    @State private var askingScope = false
    @State private var confirmingRemove = false

    init(model: AppModel, cardID: UUID, month: Date = .now, cardChoices: [Card]) {
        self.model = model
        self.cardChoices = cardChoices
        _cardID = State(initialValue: cardID)
        _month = State(initialValue: Cycle.month(containing: month).start)
    }

    private var history: [BudgetVersion] { model.budgetCardInput(cardID)?.budgets ?? [] }
    private var monthCycle: Cycle { Cycle.month(containing: month) }
    /// The budget in effect for the month being edited, saved for it or carried over from an earlier one.
    private var budget: BudgetVersion? { BudgetHistory.period(containing: monthCycle.start, budgets: history)?.budget }
    private var categories: [ExpenseCategory] { model.activeCategories(for: cardID) }
    private var currency: String { model.currency(ofCard: cardID) }
    /// Cents for dollars and euros; rupiah and yen are whole.
    private var keyboard: UIKeyboardType { Money.fractionDigits(currency) > 0 ? .decimalPad : .numberPad }
    private var monthName: String { Self.name(of: monthCycle.start) }
    /// Next month, this month and the eleven before it.
    private var monthChoices: [Date] { (-1...11).map { AppModel.month(offset: $0).start } }
    /// Earlier months that had a monthly budget for this card, newest first.
    private var copyChoices: [(month: Date, budget: BudgetVersion)] {
        (1...12).compactMap { back in
            guard let start = Calendar.current.date(byAdding: .month, value: -back, to: monthCycle.start),
                  let budget = BudgetHistory.period(containing: start, budgets: history)?.budget, !budget.isGoal else { return nil }
            return (start, budget)
        }
    }

    static func name(of month: Date) -> String {
        month.formatted(Calendar.current.isDate(month, equalTo: .now, toGranularity: .year) ? .dateTime.month(.wide) : .dateTime.month(.wide).year())
    }

    private func resolveInput(_ input: String, preserving previous: Int64?) throws -> Int64 {
        if let previous, input == Money.format(previous, currency: false) { return previous }
        return try Money.parse(input, code: currency)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Card", selection: $cardID) {
                        ForEach(cardChoices) { Text($0.name).tag($0.id) }
                    }.accessibilityIdentifier("budgetEditorCard")
                    Picker("Month", selection: $month) {
                        ForEach(monthChoices, id: \.self) { Text(Self.name(of: $0)).tag($0) }
                    }.accessibilityIdentifier("budgetEditorMonth")
                }
                Section {
                    Picker("Budget", selection: $isTotal) {
                        Text("Monthly").tag(false)
                        Text("Total until").tag(true)
                    }.pickerStyle(.segmented)
                    if isTotal {
                        DatePicker("Last day", selection: $totalUntil, in: monthCycle.start..., displayedComponents: .date)
                    } else {
                        Toggle("Repeat every month", isOn: $repeats).accessibilityIdentifier("budgetRepeats")
                    }
                } footer: {
                    Text(isTotal ? "One amount from \(Day.title(Day.string(monthCycle.start))) through the last day. Use it for a trip or a goal. The monthly budget applies again after it."
                         : repeats ? "The budget carries on every month until you change it."
                         : "For \(monthName) only. The month after, the repeating budget applies again.")
                }
                Section {
                    TextField("Amount", text: $amount.groupedAmount(code: currency)).keyboardType(keyboard)
                    if !copyChoices.isEmpty {
                        Menu {
                            ForEach(copyChoices, id: \.month) { choice in
                                Button { fill(from: choice.budget) } label: {
                                    Text(Self.name(of: choice.month))
                                    Text(Money.format(choice.budget.overallLimit, code: currency))
                                }
                            }
                        } label: {
                            Label("Copy from a previous month", systemImage: "doc.on.doc")
                        }.accessibilityIdentifier("budgetCopyFrom")
                    }
                } header: { Text("Overall budget · \(currency)") }
                Section {
                    ForEach(categories) { category in
                        LabeledContent(category.name) {
                            TextField("No limit", text: Binding(
                                get: { categoryAmounts[category.id] ?? "" },
                                set: { categoryAmounts[category.id] = $0 }
                            ).groupedAmount(code: currency))
                            .keyboardType(keyboard).multilineTextAlignment(.trailing)
                            .accessibilityLabel("\(category.name) limit")
                        }
                    }
                } header: {
                    InfoHeader(title: "Category limits · optional", info: "Category limits are independent from the overall budget. Leave a category blank for no limit.")
                }
                if let error { Section { Text(error).foregroundStyle(MC.red) } }
                if !history.isEmpty {
                    Section {
                        ForEach(history.reversed()) { budget in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("From \(Day.title(budget.effectiveDay))")
                                    Text(budget.isGoal ? budget.totalUntilDay.map { "Total until \(Day.title($0))" } ?? ""
                                         : budget.isOneMonth ? "That month only" : "Monthly")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(Money.format(budget.overallLimit, code: currency)).font(.subheadline.monospacedDigit())
                            }
                        }
                    } header: { Text("History")
                    } footer: {
                        Text("Each change starts on a month, so past months keep the budget they had.")
                    }
                    Section {
                        Button("Remove budget", role: .destructive) { confirmingRemove = true }
                            .accessibilityIdentifier("budgetRemove")
                    }
                }
            }.navigationTitle("Edit budget").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            // Changing a repeating budget: this month only, or this month and later?
                            if !isTotal && repeats, let budget, budget.totalUntilDay == nil { askingScope = true } else { save(repeating: repeats) }
                        }.accessibilityIdentifier("budgetSave")
                    }
                }
                .confirmationDialog("Apply this budget to", isPresented: $askingScope, titleVisibility: .visible) {
                    Button("Just \(monthName)") { save(repeating: false) }
                    Button("\(monthName) and later months") { save(repeating: true) }
                } message: {
                    Text("\(monthName) and later months also replaces any budget you set for a later month.")
                }
                .confirmationDialog("Remove \(model.cards.first { $0.id == cardID }?.name ?? "this card")'s budget?",
                                    isPresented: $confirmingRemove, titleVisibility: .visible) {
                    Button("Remove budget", role: .destructive) {
                        do { try model.removeBudgets(cardID: cardID); dismiss() } catch { self.error = error.localizedDescription }
                    }
                } message: {
                    Text("Every month's budget for this card goes, past months too. Expenses stay.")
                }
                .onAppear(perform: load)
                .onChange(of: cardID) { load() }
                .onChange(of: month) { load() }
        }
    }

    private func load() {
        error = nil
        let budget = budget
        originalBudget = budget
        amount = budget.map { Money.format($0.overallLimit, currency: false) } ?? ""
        isTotal = budget?.isGoal ?? false
        repeats = !(budget?.isOneMonth ?? false)
        totalUntil = budget?.totalUntilDay.flatMap { Day.date($0) }
            ?? Calendar.current.date(byAdding: .day, value: 30, to: monthCycle.start) ?? monthCycle.start
        categoryAmounts = Dictionary(uniqueKeysWithValues: categories.map { category in
            (category.id, budget?.limit(for: category.id).map { Money.format($0, currency: false) } ?? "")
        })
    }

    /// Fills the amounts from an earlier month's budget; nothing is saved until Save.
    private func fill(from source: BudgetVersion) {
        originalBudget = source
        amount = Money.format(source.overallLimit, currency: false)
        categoryAmounts = Dictionary(uniqueKeysWithValues: categories.map { category in
            (category.id, source.limit(for: category.id).map { Money.format($0, currency: false) } ?? "")
        })
    }

    private func save(repeating: Bool) {
        do {
            let limits = try categories.compactMap { category -> CategoryBudget? in
                let value = categoryAmounts[category.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !value.isEmpty else { return nil }
                return CategoryBudget(categoryID: category.id, limit: try resolveInput(value, preserving: originalBudget?.limit(for: category.id)))
            }
            try model.saveBudget(overallLimit: try resolveInput(amount, preserving: originalBudget?.overallLimit), categoryLimits: limits,
                                 month: monthCycle.start, repeats: repeating, totalUntil: isTotal ? totalUntil : nil, cardID: cardID)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
