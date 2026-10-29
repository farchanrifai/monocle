import Charts
import SwiftUI

/// The chart under a chat answer: category donut, card bars, daily trend, period comparison or budget bars.
/// Every number comes from ToolExecutor (AnalyticsReport), never from the model.
struct ChatChartView: View {
    let chart: ChatChart

    // ponytail: local palette; share AnalyticsView's categoryPalette if the two ever need to match.
    private static let palette: [Color] = [MC.red, .orange, .blue, .green, .purple, .teal]
    private static func color(_ index: Int) -> Color { palette[index % palette.count] }
    private static func rupiah(_ minor: Int64) -> Double { Double(minor) / 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(chart.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            switch chart.style {
            case .donut: donut
            case .bars: bars
            case .trend: trend
            case .comparison: comparison
            case .budget: budget
            }
        }
        .padding(16)
        .background(Color.chatSurface, in: .rect(cornerRadius: 20, style: .continuous))
        // Hug the content (the donut legend) up to a readable width, left-aligned like the reply under it.
        .frame(maxWidth: 480, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(chart.title)
        .accessibilityValue(chart.items.map { "\($0.label) \(Money.format($0.value))" }.joined(separator: ", "))
    }

    // MARK: - Donut

    /// Top five slices, the rest folded into Other so the legend never scrolls.
    private var slices: [ChatChart.Item] {
        let sorted = chart.items.filter { $0.value > 0 }.sorted { $0.value > $1.value }
        guard sorted.count > 6 else { return sorted }
        return Array(sorted.prefix(5)) + [.init(label: "Other", value: sorted.dropFirst(5).reduce(0) { $0 + $1.value })]
    }

    private var donut: some View {
        let slices = slices
        let total = max(slices.reduce(0) { $0 + $1.value }, 1)
        return HStack(spacing: 20) {
            Chart(Array(slices.enumerated()), id: \.offset) { index, item in
                SectorMark(angle: .value("Spend", Self.rupiah(item.value)), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(Self.color(index))
            }
            .frame(width: 110, height: 110)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(Array(slices.enumerated()), id: \.offset) { index, item in
                    GridRow {
                        Circle().fill(Self.color(index)).frame(width: 8, height: 8)
                        Text(item.label).lineLimit(1)
                        Text(Money.format(item.value)).monospacedDigit().gridColumnAlignment(.trailing)
                        Text("\(Int((Double(item.value) / Double(total) * 100).rounded()))%")
                            .monospacedDigit().foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                    }
                }
            }
            .font(.caption)
        }
    }

    // MARK: - Bars (per card)

    /// A horizontal bar that fills whatever width its grid column has left, so the same card fits iPhone and Mac.
    private static func bar(_ value: Int64, of max: Int64, _ color: Color, height: CGFloat = 10) -> some View {
        let fraction = max > 0 ? Swift.min(CGFloat(Double(value) / Double(max)), 1) : 0
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.chatTrack)
                Capsule().fill(color).frame(width: value > 0 ? Swift.max(proxy.size.width * fraction, height) : 0)
            }
        }
        .frame(minWidth: 60, maxWidth: .infinity)
        .frame(height: height)
    }

    private var bars: some View {
        let top = chart.items.map(\.value).max() ?? 0
        return Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            ForEach(Array(chart.items.enumerated()), id: \.offset) { index, item in
                GridRow {
                    Text(item.label).lineLimit(1)
                    Self.bar(item.value, of: top, Self.color(index))
                    Text(Money.format(item.value)).monospacedDigit().foregroundStyle(.secondary).gridColumnAlignment(.trailing)
                }
            }
        }
        .font(.caption)
    }

    // MARK: - Trend (per day)

    private var trend: some View {
        Chart(Array(chart.items.enumerated()), id: \.offset) { _, item in
            BarMark(x: .value("Day", Day.date(item.label) ?? .now, unit: .day), y: .value("Spent", Self.rupiah(item.value)))
                .foregroundStyle(MC.red)
                .cornerRadius(2)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel { if let amount = value.as(Double.self) { Text(amount, format: .number.notation(.compactName)) } }
            }
        }
        .frame(height: 140)
    }

    // MARK: - Comparison (earlier vs later period)

    private var comparison: some View {
        let top = chart.items.flatMap { [$0.value, $0.reference ?? 0] }.max() ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Label { Text(chart.series.first ?? "Before") } icon: { Circle().fill(Color.secondary.opacity(0.4)).frame(width: 8, height: 8) }
                Label { Text(chart.series.last ?? "After") } icon: { Circle().fill(MC.red).frame(width: 8, height: 8) }
            }
            .font(.caption2).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                ForEach(Array(chart.items.enumerated()), id: \.offset) { index, item in
                    GridRow(alignment: .center) {
                        Text(item.label).lineLimit(1).fontWeight(index == 0 && item.label == "Total" ? .semibold : .regular)
                        VStack(alignment: .leading, spacing: 3) {
                            Self.bar(item.reference ?? 0, of: top, Color.secondary.opacity(0.4), height: 8)
                            Self.bar(item.value, of: top, MC.red, height: 8)
                        }
                        delta(item.value - (item.reference ?? 0)).gridColumnAlignment(.trailing)
                    }
                }
            }
            .font(.caption)
        }
    }

    /// Spending up reads red, down reads green.
    private func delta(_ change: Int64) -> some View {
        Text(change == 0 ? "±0" : "\(change > 0 ? "+" : "−")\(Money.format(abs(change)))")
            .font(.caption2.weight(.semibold)).monospacedDigit()
            .foregroundStyle(change > 0 ? MC.red : change < 0 ? .green : .secondary)
    }

    // MARK: - Budget

    /// Two lines per row: "Rp173,000 of Rp3,000,000" is too wide to share a line with a bar on iPhone.
    private var budget: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(chart.items.enumerated()), id: \.offset) { index, item in
                let limit = item.reference ?? 0
                let over = item.value > limit
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.label).lineLimit(1).fontWeight(index == 0 ? .semibold : .regular)
                        Spacer(minLength: 12)
                        Text("\(Money.format(item.value)) of \(Money.format(limit))")
                            .monospacedDigit().foregroundStyle(over ? MC.red : .secondary)
                    }
                    Self.bar(item.value, of: limit, over ? MC.red : .green, height: 8)
                }
            }
        }
        .font(.caption)
        .frame(minWidth: 260)
    }
}
