import SwiftUI
import Charts

struct AnalyticsView: View {
    @Bindable var model: AppModel
    var showsDismissButton = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedHorizon: AnalyticsTimeHorizon = .thisCycle
    @State private var selectedScope: AnalyticsFilterScope = .allCards
    @State private var scrubbedDate: Date? = nil
    @State private var selectedCategoryID: UUID? = nil
    @State private var selectedChartAngle: Int64? = nil

    private var direction: BookVisualDirection { model.effectiveDirection(for: colorScheme) }

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

    private let categoryPalette: [Color] = [
        MC.red,
        Color.orange,
        Color.blue,
        Color.green,
        Color.purple,
        Color.teal,
        Color.pink,
        Color.indigo,
        Color.mint,
        Color.yellow,
        Color.cyan,
        Color.brown
    ]

    var body: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top
            ZStack(alignment: .top) {
                paper.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        controlsHeader
                        kpiSummaryCard
                        burnUpTrajectoryCard
                        dailyRhythmCard
                        monthOverMonthCard
                        categoryBreakdownCard
                        if !selectedScope.isCard && bookPoints.count > 1 {
                            crossBookBreakdownCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 68)
                    .padding(.bottom, 96)
                }

                topBar(safeAreaTop: safeAreaTop)
                    .zIndex(1000)
            }
            .onAppear {
                syncScopeWithHomeContext()
            }
            .onChange(of: model.filterScope) { _, _ in
                syncScopeWithHomeContext()
            }
            .onChange(of: model.activeStackID) { _, _ in
                syncScopeWithHomeContext()
            }
            .onChange(of: model.selectedBookID) { _, _ in
                syncScopeWithHomeContext()
            }
        }
    }

    private func topBar(safeAreaTop: CGFloat) -> some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: safeAreaTop)
            header
        }
        .background(alignment: .top) {
            progressiveBlurHeaderBackground(safeAreaTop: safeAreaTop)
        }
        .ignoresSafeArea(edges: .top)
    }

    private var header: some View {
        HStack {
            if showsDismissButton {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MC.red)
                }
                .accessibilityIdentifier("dismissAnalyticsView")
            } else {
                Color.clear
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text("Analytics & Trends")
                .font(.headline)
                .foregroundStyle(ink)
                .accessibilityIdentifier("analyticsTitle")

            Spacer()

            Color.clear
                .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .frame(height: 52)
    }

    private func progressiveBlurHeaderBackground(safeAreaTop: CGFloat) -> some View {
        let toolbarHeight: CGFloat = 52
        // Shorten the full fade from 88 pt to 66 pt (25%), ending closer to the toolbar.
        let featherHeight: CGFloat = 22
        let totalHeight = safeAreaTop + toolbarHeight + featherHeight
        let fadeStart = safeAreaTop + 8
        let fadeLength = totalHeight - fadeStart

        // A smoothstep has zero slope at both ends: no hard shoulder beneath
        // the toolbar and no visible cutoff at the bottom of the material.
        let stops: [Gradient.Stop] = [.init(color: .black, location: 0)] + (0...16).map { step in
            let t = CGFloat(step) / 16
            let opacity = 1 - t * t * (3 - 2 * t)
            return .init(color: .black.opacity(Double(opacity)),
                         location: (fadeStart + fadeLength * t) / totalHeight)
        }

        return Rectangle()
            .fill(.ultraThinMaterial)
            .overlay(paper.opacity(0.52))
            // Composite first, then fade once so tint and material share an edge.
            .mask {
                LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
            }
            .frame(height: totalHeight)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
    }

    private func syncScopeWithHomeContext() {
        if let cardID = model.selectedBookID, let card = model.books.first(where: { $0.id == cardID }) {
            selectedScope = .card(id: card.id, name: card.name)
        } else if model.filterScope == .activeStack, let stack = model.currentStack {
            selectedScope = .stack(id: stack.id, name: stack.name)
        } else {
            selectedScope = .allCards
        }
    }

    // MARK: - Filtered Data Queries

    private var targetExpenses: [Expense] {
        switch selectedScope {
        case .stack(let id, _):
            guard let stack = model.stacks.first(where: { $0.id == id }) else {
                return model.allExpenses()
            }
            let cardIDs = Set(stack.cardIDs)
            return model.allExpenses().filter { exp in
                guard let bid = exp.bookID else { return false }
                return cardIDs.contains(bid)
            }
        case .card(let id, _):
            return model.expenses(for: id)
        case .allCards:
            return model.allExpenses()
        }
    }

    private var currentRange: (startDate: Date, endDate: Date, startDay: String, endDay: String) {
        AnalyticsEngine.dateRange(
            for: selectedHorizon,
            currentCycle: model.cycle
        )
    }

    private var horizonExpenses: [Expense] {
        AnalyticsEngine.filterExpenses(
            targetExpenses,
            startDay: currentRange.startDay,
            endDay: currentRange.endDay
        )
    }

    private var budgetLimit: Int64? {
        guard !selectedScope.isAllCards, (selectedHorizon == .thisCycle || selectedHorizon == .thisMonth) else {
            return nil
        }
        return model.activeBudget.overallLimit
    }

    private var dailyPoints: [DailySpendPoint] {
        AnalyticsEngine.calculateDailySpendPoints(
            expenses: horizonExpenses,
            startDate: currentRange.startDate,
            endDate: currentRange.endDate,
            overallBudgetLimit: budgetLimit
        )
    }

    private var categoryPoints: [CategorySpendPoint] {
        let limits: [UUID: Int64]
        if !selectedScope.isAllCards {
            limits = Dictionary(uniqueKeysWithValues: model.categories.compactMap { cat in
                model.activeBudget.limit(for: cat.id).map { (cat.id, $0) }
            })
        } else {
            limits = [:]
        }

        return AnalyticsEngine.calculateCategoryDistribution(
            expenses: horizonExpenses,
            categories: model.categories,
            budgetLimits: limits
        )
    }

    private var bookPoints: [BookSpendPoint] {
        let allByBook = model.allExpensesByBook()
        let relevantBooks: [BookProfile]
        let relevantMap: [UUID: [Expense]]

        switch selectedScope {
        case .stack(let id, _):
            if let stack = model.stacks.first(where: { $0.id == id }) {
                let cardIDs = Set(stack.cardIDs)
                relevantBooks = model.books.filter { cardIDs.contains($0.id) }
                relevantMap = allByBook.filter { cardIDs.contains($0.key) }
            } else {
                relevantBooks = model.books
                relevantMap = allByBook
            }
        case .card(let id, _):
            relevantBooks = model.books.filter { $0.id == id }
            relevantMap = allByBook.filter { $0.key == id }
        case .allCards:
            relevantBooks = model.books
            relevantMap = allByBook
        }

        return AnalyticsEngine.calculateBookDistribution(
            expensesByBook: relevantMap.mapValues { values in
                AnalyticsEngine.filterExpenses(values, startDay: currentRange.startDay, endDay: currentRange.endDay)
            },
            books: relevantBooks
        )
    }

    private var momPoints: [ComparativePeriodPoint] {
        AnalyticsEngine.calculateMonthOverMonthComparison(expenses: targetExpenses)
    }

    private var metrics: AnalyticsMetrics {
        AnalyticsEngine.calculateMetrics(
            dailyPoints: dailyPoints,
            categoryPoints: categoryPoints,
            startDate: currentRange.startDate,
            endDate: currentRange.endDate,
            overallBudgetLimit: budgetLimit
        )
    }

    // MARK: - Controls Header

    private var controlsHeader: some View {
        VStack(spacing: 12) {
            scopeMenu

            // Horizon Chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AnalyticsTimeHorizon.allCases) { horizon in
                        let isSelected = selectedHorizon == horizon
                        Button {
                            selectedHorizon = horizon
                            scrubbedDate = nil
                        } label: {
                            Text(horizon.rawValue)
                                .font(.caption.weight(isSelected ? .semibold : .medium))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? MC.red : MC.surface, in: Capsule())
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                        }
                        .buttonStyle(PressFeedbackStyle())
                        .accessibilityIdentifier("horizon-\(horizon.rawValue)")
                    }
                }
            }
        }
    }

    private var scopeMenu: some View {
        Menu {
            if !model.stacks.isEmpty {
                Section("Stacks") {
                    ForEach(model.stacks) { stack in
                        Button {
                            selectedScope = .stack(id: stack.id, name: stack.name)
                            model.setActiveStack(id: stack.id)
                        } label: {
                            HStack {
                                Label(stack.name, systemImage: stack.icon)
                                if case .stack(let id, _) = selectedScope, id == stack.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            Section("Cards") {
                ForEach(model.unhiddenBooks) { card in
                    Button {
                        selectedScope = .card(id: card.id, name: card.name)
                    } label: {
                        HStack {
                            Label(card.name, systemImage: "creditcard")
                            if case .card(let id, _) = selectedScope, id == card.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section {
                Button {
                    selectedScope = .allCards
                    model.filterScope = .allCards
                } label: {
                    HStack {
                        Label("All Cards", systemImage: "rectangle.stack")
                        if case .allCards = selectedScope {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedScope.icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MC.red)

                Text(selectedScope.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)

                Text(selectedScope.subtitle)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(MC.surface, in: RoundedRectangle(cornerRadius: 14))
        }
        .accessibilityIdentifier("analyticsScopeMenu")
    }

    // MARK: - KPI Summary Card

    private var kpiSummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "\(selectedHorizon.rawValue) spending")
                    Text(Money.format(metrics.totalSpend))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.primary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .accessibilityIdentifier("totalSpendMetric")
                }
                Spacer()

                if let pace = metrics.paceStatus {
                    paceBadge(pace)
                }
            }

            Divider()

            HStack(spacing: 16) {
                metricColumn(title: "Transactions", value: "\(metrics.transactionCount)")
                metricColumn(title: "Daily average", value: Money.format(metrics.dailyAverage))
                if selectedHorizon == .thisCycle || selectedHorizon == .thisMonth {
                    metricColumn(title: "Projected", value: Money.format(metrics.projectedPeriodTotal))
                } else if let highest = metrics.highestSpendDay {
                    metricColumn(title: "Peak day", value: Money.format(highest.amount))
                } else {
                    metricColumn(title: "Peak day", value: "-")
                }
            }
        }
        .padding(20)
        .background(MC.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private func metricColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paceBadge(_ status: SpendingPaceStatus) -> some View {
        HStack(spacing: 4) {
            Image(systemName: paceIcon(for: status))
                .font(.caption2.weight(.bold))
            Text(status.label)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(paceColor(for: status).opacity(0.15), in: Capsule())
        .foregroundStyle(paceColor(for: status))
    }

    private func paceIcon(for status: SpendingPaceStatus) -> String {
        switch status {
        case .underPace: return "arrow.down.right"
        case .onTrack: return "checkmark"
        case .accelerated: return "arrow.up.right"
        }
    }

    private func paceColor(for status: SpendingPaceStatus) -> Color {
        switch status {
        case .underPace: return .green
        case .onTrack: return .blue
        case .accelerated: return MC.red
        }
    }

    // MARK: - Chart 1: Cumulative Trajectory (Burn-Up)

    private var activeScrubbedPoint: DailySpendPoint? {
        guard let scrubbed = scrubbedDate else { return nil }
        let elapsed = dailyPoints.filter { !$0.isFuture }
        return elapsed.min { p1, p2 in
            abs(p1.date.timeIntervalSince(scrubbed)) < abs(p2.date.timeIntervalSince(scrubbed))
        }
    }

    private var burnUpTrajectoryCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cumulative Trajectory")
                        .font(.headline)
                    Text("Pacing vs period budget")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let scrub = activeScrubbedPoint, let cum = scrub.cumulativeAmount {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Day.title(scrub.day))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Text(Money.format(cum))
                                .font(.footnote.weight(.bold).monospacedDigit())
                                .foregroundStyle(MC.red)
                            if scrub.amount > 0 {
                                Text("(+\(compactMoney(scrub.amount)))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if dailyPoints.isEmpty {
                emptyChartPlaceholder(message: "No expense activity in this period")
            } else {
                Chart {
                    // Series 1: Actual Cumulative Spend (Area + Line) for elapsed days
                    ForEach(dailyPoints.filter { !$0.isFuture }) { pt in
                        if let cum = pt.cumulativeAmount {
                            AreaMark(
                                x: .value("Date", pt.date, unit: .day),
                                y: .value("Cumulative", cum),
                                series: .value("Series", "Actual Spend")
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [MC.red.opacity(0.22), MC.red.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .interpolationMethod(.monotone)

                            LineMark(
                                x: .value("Date", pt.date, unit: .day),
                                y: .value("Cumulative", cum),
                                series: .value("Series", "Actual Spend")
                            )
                            .foregroundStyle(MC.red)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)
                        }
                    }

                    // Series 2: Budget Pace Projection (Linear Dashed Line) across entire period
                    ForEach(dailyPoints) { pt in
                        if let target = pt.targetCumulativeAmount {
                            LineMark(
                                x: .value("Date", pt.date, unit: .day),
                                y: .value("Budget Pace", target),
                                series: .value("Series", "Budget Pace")
                            )
                            .foregroundStyle(Color.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .interpolationMethod(.linear)
                        }
                    }

                    // Visible anchor point on latest elapsed data point (ensures single-day datasets are visible)
                    if let lastElapsed = dailyPoints.filter({ !$0.isFuture }).last, let cum = lastElapsed.cumulativeAmount {
                        PointMark(
                            x: .value("Date", lastElapsed.date, unit: .day),
                            y: .value("Cumulative", cum)
                        )
                        .foregroundStyle(MC.red)
                        .symbolSize(36)
                    }

                    if let scrub = activeScrubbedPoint, let cum = scrub.cumulativeAmount {
                        RuleMark(x: .value("Scrubbed", scrub.date, unit: .day))
                            .foregroundStyle(Color.primary.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        PointMark(
                            x: .value("Scrubbed", scrub.date, unit: .day),
                            y: .value("Cumulative", cum)
                        )
                        .foregroundStyle(MC.red)
                        .symbolSize(60)
                    }
                }
                .chartXSelection(value: $scrubbedDate)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        if let intVal = value.as(Int64.self) {
                            AxisValueLabel {
                                Text(compactMoney(intVal))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, dailyPoints.count / 5))) { value in
                        if let d = value.as(Date.self) {
                            AxisValueLabel {
                                Text(dayMonthLabel(d))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .accessibilityIdentifier("burnUpTrajectoryChart")

                HStack(spacing: 16) {
                    legendItem(color: MC.red, label: "Actual Spend", dashed: false)
                    if dailyPoints.contains(where: { $0.targetCumulativeAmount != nil }) {
                        legendItem(color: Color.secondary.opacity(0.7), label: "Budget Pace", dashed: true)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(MC.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Chart 2: Daily Spending Rhythm

    private var dailyRhythmCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily Rhythm")
                        .font(.headline)
                    Text("Day-by-day transaction totals")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let scrub = activeScrubbedPoint {
                    Text("\(Money.format(scrub.amount)) · \(dayMonthLabel(scrub.date))")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(MC.red)
                } else if metrics.dailyAverage > 0 {
                    Text("Avg \(compactMoney(metrics.dailyAverage))/day")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            let elapsedPoints = dailyPoints.filter { !$0.isFuture }
            if elapsedPoints.isEmpty {
                emptyChartPlaceholder(message: "No daily data")
            } else {
                Chart {
                    ForEach(elapsedPoints) { pt in
                        let isPeak = pt.amount > 0 && pt.amount == metrics.highestSpendDay?.amount
                        let isScrubbed = activeScrubbedPoint?.day == pt.day
                        BarMark(
                            x: .value("Date", pt.date, unit: .day),
                            y: .value("Spend", pt.amount)
                        )
                        .foregroundStyle(isScrubbed ? MC.red : (isPeak ? MC.red.opacity(0.85) : MC.red.opacity(0.40)))
                        .cornerRadius(3)
                    }

                    if metrics.dailyAverage > 0 {
                        RuleMark(y: .value("Average", metrics.dailyAverage))
                            .foregroundStyle(Color.primary.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                            .annotation(position: .top, alignment: .trailing) {
                                Text("Average")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.trailing, 4)
                            }
                    }

                    if let scrub = activeScrubbedPoint {
                        RuleMark(x: .value("Scrubbed", scrub.date, unit: .day))
                            .foregroundStyle(Color.primary.opacity(0.25))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    }
                }
                .chartXSelection(value: $scrubbedDate)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        if let intVal = value.as(Int64.self) {
                            AxisValueLabel {
                                Text(compactMoney(intVal))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                        AxisGridLine()
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: max(1, elapsedPoints.count / 5))) { value in
                        if let d = value.as(Date.self) {
                            AxisValueLabel {
                                Text(dayMonthLabel(d))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .frame(height: 170)
                .accessibilityIdentifier("dailyRhythmChart")
            }
        }
        .padding(20)
        .background(MC.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    private var currentMonthName: String {
        let cal = Calendar.current
        let m = cal.component(.month, from: .now)
        return cal.monthSymbols[m - 1]
    }

    private var previousMonthName: String {
        let cal = Calendar.current
        let prev = cal.date(byAdding: .month, value: -1, to: .now) ?? .now
        let m = cal.component(.month, from: prev)
        return cal.monthSymbols[m - 1]
    }

    private func category(forAngle angle: Int64) -> UUID? {
        var accumulated: Int64 = 0
        for cat in categoryPoints {
            accumulated += cat.amount
            if angle <= accumulated {
                return cat.categoryID
            }
        }
        return categoryPoints.first?.categoryID
    }

    // MARK: - Chart 3: Month-over-Month Velocity

    private var monthOverMonthCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Month-over-Month Velocity")
                    .font(.headline)
                Text("Calendar day 1 to 31 comparative curve")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if momPoints.isEmpty || !momPoints.contains(where: { ($0.currentPeriodCumulative ?? 0) > 0 || ($0.previousPeriodCumulative ?? 0) > 0 }) {
                emptyChartPlaceholder(message: "Not enough monthly history to compare")
            } else {
                Chart {
                    ForEach(momPoints) { pt in
                        if let cur = pt.currentPeriodCumulative {
                            LineMark(
                                x: .value("Day", pt.dayIndex),
                                y: .value("This Month", cur),
                                series: .value("Series", "This Month")
                            )
                            .foregroundStyle(MC.red)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.monotone)
                        }

                        if let prev = pt.previousPeriodCumulative {
                            LineMark(
                                x: .value("Day", pt.dayIndex),
                                y: .value("Last Month", prev),
                                series: .value("Series", "Last Month")
                            )
                            .foregroundStyle(Color.secondary.opacity(0.65))
                            .lineStyle(StrokeStyle(lineWidth: 1.8, dash: [4, 4]))
                            .interpolationMethod(.monotone)
                        }
                    }

                    // Anchor point on current month's latest point for single-day periods
                    if let lastCur = momPoints.last(where: { $0.currentPeriodCumulative != nil }), let cur = lastCur.currentPeriodCumulative {
                        PointMark(
                            x: .value("Day", lastCur.dayIndex),
                            y: .value("This Month", cur)
                        )
                        .foregroundStyle(MC.red)
                        .symbolSize(36)
                    }
                }
                .chartXScale(domain: 1...31)
                .chartXAxis {
                    AxisMarks(values: [1, 7, 14, 21, 28, 31]) { val in
                        AxisValueLabel {
                            if let day = val.as(Int.self) {
                                Text("d\(day)")
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        if let intVal = value.as(Int64.self) {
                            AxisValueLabel {
                                Text(compactMoney(intVal))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                        AxisGridLine()
                    }
                }
                .frame(height: 180)
                .accessibilityIdentifier("monthOverMonthChart")

                HStack(spacing: 20) {
                    legendItem(color: MC.red, label: currentMonthName, dashed: false)
                    legendItem(color: Color.secondary.opacity(0.7), label: previousMonthName, dashed: true)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(MC.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Chart 4: Category Breakdown

    private var categoryBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Category Breakdown")
                    .font(.headline)
                Text("\(categoryPoints.count) active categories")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if categoryPoints.isEmpty {
                emptyChartPlaceholder(message: "No category transactions")
            } else {
                // Donut Chart
                HStack(spacing: 20) {
                    Chart(categoryPoints) { cat in
                        let isSelected = selectedCategoryID == cat.categoryID
                        SectorMark(
                            angle: .value("Spend", cat.amount),
                            innerRadius: .ratio(0.62),
                            outerRadius: isSelected ? .ratio(1.04) : .ratio(0.96),
                            angularInset: 1.5
                        )
                        .cornerRadius(3)
                        .foregroundStyle(colorForCategory(cat.categoryID))
                        .opacity(selectedCategoryID == nil || isSelected ? 1.0 : 0.4)
                    }
                    .chartAngleSelection(value: $selectedChartAngle)
                    .onChange(of: selectedChartAngle) { _, newAngle in
                        if let newAngle {
                            selectedCategoryID = category(forAngle: newAngle)
                        }
                    }
                    .chartBackground { chartProxy in
                        GeometryReader { geo in
                            if let plotFrame = chartProxy.plotFrame {
                                let frame = geo[plotFrame]
                                VStack(spacing: 2) {
                                    if let selected = categoryPoints.first(where: { $0.categoryID == selectedCategoryID }) {
                                        Text(selected.categoryName)
                                            .font(.caption2.weight(.medium))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                        Text(Money.format(selected.amount))
                                            .font(.caption.weight(.bold).monospacedDigit())
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                        Text("\(Int(round(selected.percentage * 100)))%")
                                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(MC.red)
                                    } else {
                                        Text("Total")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        Text(compactMoney(metrics.totalSpend))
                                            .font(.caption.weight(.bold).monospacedDigit())
                                    }
                                }
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                            }
                        }
                    }
                    .frame(width: 140, height: 140)
                    .accessibilityIdentifier("categoryDonutChart")

                    // Top 3 summary
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(categoryPoints.prefix(3)) { cat in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(colorForCategory(cat.categoryID))
                                    .frame(width: 8, height: 8)
                                Text(cat.categoryName)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                Spacer()
                                Text("\(Int(round(cat.percentage * 100)))%")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)

                Divider()

                // Ranked Category Rows
                VStack(spacing: 12) {
                    ForEach(categoryPoints) { cat in
                        let isSelected = selectedCategoryID == cat.categoryID
                        Button {
                            if selectedCategoryID == cat.categoryID {
                                selectedCategoryID = nil
                            } else {
                                selectedCategoryID = cat.categoryID
                            }
                        } label: {
                            HStack(spacing: 12) {
                                CategoryMark(symbol: cat.categorySymbol)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(cat.categoryName)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text(Money.format(cat.amount))
                                            .font(.subheadline.weight(.semibold).monospacedDigit())
                                            .foregroundStyle(.primary)
                                        if let limit = cat.budgetLimit, limit > 0, cat.amount > limit {
                                            Image(systemName: "exclamationmark.circle.fill")
                                                .foregroundStyle(MC.red)
                                                .font(.caption2)
                                        }
                                    }

                                    GeometryReader { g in
                                        ZStack(alignment: .leading) {
                                            Capsule()
                                                .fill(Color.primary.opacity(0.08))
                                                .frame(height: 5)
                                            Capsule()
                                                .fill(colorForCategory(cat.categoryID))
                                                .frame(width: max(4, g.size.width * CGFloat(cat.percentage)), height: 5)
                                        }
                                    }
                                    .frame(height: 5)

                                    HStack {
                                        Text("\(cat.transactionCount) transactions")
                                        Spacer()
                                        if let limit = cat.budgetLimit, limit > 0 {
                                            if cat.amount > limit {
                                                Text("Over limit of \(compactMoney(limit))")
                                                    .font(.caption2.weight(.semibold))
                                                    .foregroundStyle(MC.red)
                                            } else {
                                                Text("of \(compactMoney(limit)) budget")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else {
                                            Text("\(Int(round(cat.percentage * 100)))% of spend")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .background(isSelected ? MC.red.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("categoryRow-\(cat.categoryName)")
                    }
                }
            }
        }
        .padding(20)
        .background(MC.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Chart 5: Cross-Book Breakdown

    private var crossBookBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Spending by Card")
                    .font(.headline)
                Text(selectedScope.isStack ? "Distribution across cards in this stack" : "Distribution across active cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if bookPoints.isEmpty {
                emptyChartPlaceholder(message: "No card spending found")
            } else {
                Chart(bookPoints) { bp in
                    BarMark(
                        x: .value("Spend", bp.amount),
                        y: .value("Card", bp.bookName)
                    )
                    .foregroundStyle(CardPalette.color(for: bp.colorIndex))
                    .cornerRadius(4)
                }
                .chartYScale(domain: bookPoints.map(\.bookName).reversed())
                .chartXAxis {
                    AxisMarks { value in
                        if let intVal = value.as(Int64.self) {
                            AxisValueLabel {
                                Text(compactMoney(intVal))
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .frame(height: CGFloat(max(100, bookPoints.count * 44)))
                .accessibilityIdentifier("crossBookChart")

                VStack(spacing: 8) {
                    ForEach(bookPoints) { bp in
                        HStack(spacing: 10) {
                            Circle()
                                .fill(CardPalette.color(for: bp.colorIndex))
                                .frame(width: 10, height: 10)
                            Text(bp.bookName)
                                .font(.subheadline)
                            Spacer()
                            Text(Money.format(bp.amount))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                            Text("(\(Int(round(bp.percentage * 100)))%)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(MC.surface, in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Helpers

    private func colorForCategory(_ id: UUID) -> Color {
        if id == AnalyticsEngine.uncategorizedCategoryID {
            return Color.gray
        }
        if id == AnalyticsEngine.otherCategoryID {
            return Color.secondary
        }
        let allIDs = model.categories.map(\.id)
        if let idx = allIDs.firstIndex(of: id) {
            return categoryPalette[idx % categoryPalette.count]
        }
        return Color.secondary
    }

    private func compactMoney(_ amount: Int64) -> String {
        let whole = amount / 100
        if whole >= 1_000_000 {
            let m = Double(whole) / 1_000_000.0
            return String(format: "%.1fM", m)
        } else if whole >= 1_000 {
            let k = Double(whole) / 1_000.0
            return String(format: "%.0fk", k)
        }
        return "\(whole)"
    }

    private func dayMonthLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let d = cal.component(.day, from: date)
        let m = cal.component(.month, from: date)
        return "\(d)/\(m)"
    }

    private func legendItem(color: Color, label: String, dashed: Bool) -> some View {
        HStack(spacing: 6) {
            if dashed {
                HStack(spacing: 2) {
                    Rectangle().fill(color).frame(width: 5, height: 2)
                    Rectangle().fill(color).frame(width: 5, height: 2)
                }
            } else {
                Rectangle().fill(color).frame(width: 14, height: 2.5)
            }
            Text(label)
        }
    }

    private func emptyChartPlaceholder(message: String) -> some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title2)
                    .foregroundStyle(.secondary.opacity(0.5))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 32)
            Spacer()
        }
    }
}
