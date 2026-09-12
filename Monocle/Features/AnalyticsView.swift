import SwiftUI
import Charts

struct AnalyticsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedHorizon: AnalyticsTimeHorizon = .thisCycle
    @State private var selectedScope: AnalyticsScope = .activeBook
    @State private var scrubbedDate: Date? = nil
    @State private var selectedCategoryID: UUID? = nil

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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    controlsHeader
                    kpiSummaryCard
                    burnUpTrajectoryCard
                    dailyRhythmCard
                    monthOverMonthCard
                    categoryBreakdownCard
                    if selectedScope == .allBooks {
                        crossBookBreakdownCard
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(MC.paper)
            .navigationTitle("Analytics & Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("dismissAnalyticsView")
                }
            }
        }
    }

    // MARK: - Filtered Data Queries

    private var targetExpenses: [Expense] {
        switch selectedScope {
        case .activeBook:
            return model.expenses(for: model.activeBookID)
        case .allBooks:
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

    private var dailyPoints: [DailySpendPoint] {
        let budgetLimit = (selectedScope == .activeBook && (selectedHorizon == .thisCycle || selectedHorizon == .thisMonth))
            ? model.activeBudget.overallLimit
            : nil

        return AnalyticsEngine.calculateDailySpendPoints(
            expenses: horizonExpenses,
            startDate: currentRange.startDate,
            endDate: currentRange.endDate,
            overallBudgetLimit: budgetLimit
        )
    }

    private var categoryPoints: [CategorySpendPoint] {
        let limits: [UUID: Int64]
        if selectedScope == .activeBook {
            limits = Dictionary(uniqueKeysWithValues: model.activeCategories.compactMap { cat in
                model.activeBudget.limit(for: cat.id).map { (cat.id, $0) }
            })
        } else {
            limits = [:]
        }

        return AnalyticsEngine.calculateCategoryDistribution(
            expenses: horizonExpenses,
            categories: model.activeCategories,
            budgetLimits: limits
        )
    }

    private var bookPoints: [BookSpendPoint] {
        AnalyticsEngine.calculateBookDistribution(
            expensesByBook: model.allExpensesByBook().mapValues { values in
                AnalyticsEngine.filterExpenses(values, startDay: currentRange.startDay, endDay: currentRange.endDay)
            },
            books: model.books
        )
    }

    private var momPoints: [ComparativePeriodPoint] {
        AnalyticsEngine.calculateMonthOverMonthComparison(expenses: targetExpenses)
    }

    private var metrics: AnalyticsMetrics {
        let budgetLimit = (selectedScope == .activeBook && (selectedHorizon == .thisCycle || selectedHorizon == .thisMonth))
            ? model.activeBudget.overallLimit
            : nil

        return AnalyticsEngine.calculateMetrics(
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
            // Scope Picker
            Picker("Scope", selection: $selectedScope) {
                ForEach(AnalyticsScope.allCases) { scope in
                    Text(scope.rawValue).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("analyticsScopePicker")

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
        let cal = Calendar.current
        return dailyPoints.min { p1, p2 in
            abs(cal.dateComponents([.minute], from: p1.date, to: scrubbed).minute ?? Int.max) <
            abs(cal.dateComponents([.minute], from: p2.date, to: scrubbed).minute ?? Int.max)
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
                if let scrub = activeScrubbedPoint {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(Day.title(scrub.day))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text(Money.format(scrub.cumulativeAmount))
                            .font(.footnote.weight(.bold).monospacedDigit())
                            .foregroundStyle(MC.red)
                    }
                }
            }

            if dailyPoints.isEmpty {
                emptyChartPlaceholder(message: "No expense activity in this period")
            } else {
                Chart {
                    ForEach(dailyPoints) { pt in
                        AreaMark(
                            x: .value("Date", pt.date, unit: .day),
                            y: .value("Cumulative", pt.cumulativeAmount)
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
                            y: .value("Cumulative", pt.cumulativeAmount)
                        )
                        .foregroundStyle(MC.red)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.monotone)

                        if let target = pt.targetCumulativeAmount {
                            LineMark(
                                x: .value("Date", pt.date, unit: .day),
                                y: .value("Budget Pace", target)
                            )
                            .foregroundStyle(Color.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        }
                    }

                    if let scrub = activeScrubbedPoint {
                        RuleMark(x: .value("Scrubbed", scrub.date, unit: .day))
                            .foregroundStyle(Color.primary.opacity(0.35))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        PointMark(
                            x: .value("Scrubbed", scrub.date, unit: .day),
                            y: .value("Cumulative", scrub.cumulativeAmount)
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
                if metrics.dailyAverage > 0 {
                    Text("Avg \(compactMoney(metrics.dailyAverage))/day")
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if dailyPoints.isEmpty {
                emptyChartPlaceholder(message: "No daily data")
            } else {
                Chart {
                    ForEach(dailyPoints) { pt in
                        BarMark(
                            x: .value("Date", pt.date, unit: .day),
                            y: .value("Spend", pt.amount)
                        )
                        .foregroundStyle(pt.day == metrics.highestSpendDay?.day ? MC.red : MC.red.opacity(0.40))
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
                .frame(height: 170)
                .accessibilityIdentifier("dailyRhythmChart")
            }
        }
        .padding(20)
        .background(MC.surface, in: RoundedRectangle(cornerRadius: 20))
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
                    legendItem(color: MC.red, label: "This Month", dashed: false)
                    legendItem(color: Color.secondary.opacity(0.7), label: "Last Month", dashed: true)
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
                                        Text("\(Int(round(cat.percentage * 100)))% of spend")
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
                Text("Spending by Book")
                    .font(.headline)
                Text("Distribution across active cards")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if bookPoints.isEmpty {
                emptyChartPlaceholder(message: "No book spending found")
            } else {
                Chart(bookPoints) { bp in
                    BarMark(
                        x: .value("Spend", bp.amount),
                        y: .value("Book", bp.bookName)
                    )
                    .foregroundStyle(CardPalette.color(for: bp.colorIndex))
                    .cornerRadius(4)
                }
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
        let allIDs = model.activeCategories.map(\.id)
        if let idx = allIDs.firstIndex(of: id) {
            return categoryPalette[idx % categoryPalette.count]
        }
        return MC.red
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
