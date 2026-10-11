import SwiftUI
import Charts

/// Shared by the iOS and Mac budget and analytics screens; they only draw what `BudgetStatus` and `BudgetCycleResult` hold.

/// Names a card whose budget is being edited, for `.sheet(item:)`.
struct BudgetEditTarget: Identifiable {
    let id: UUID
}

/// Rows of spent against limit. Rows without a limit show only the spend, as a share of the biggest row.
struct BudgetLineRows: View {
    let lines: [BudgetLine]
    let currency: String
    /// Adds an edit button to each row.
    var onEdit: ((UUID) -> Void)? = nil

    var body: some View {
        let peak = max(1, lines.map(\.spent).max() ?? 1)
        VStack(spacing: 18) {
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(line.name).lineLimit(1)
                        if let onEdit {
                            Button { onEdit(line.id) } label: { Image(systemName: "pencil").font(.caption) }
                                .buttonStyle(.borderless).accessibilityLabel("Edit \(line.name) budget")
                        }
                        Spacer()
                        Text(line.limit.map { "\(Money.format(line.spent, code: currency)) / \(Money.format($0, code: currency))" } ?? Money.format(line.spent, code: currency))
                            .monospacedDigit().foregroundStyle(line.limit.map { line.spent > $0 } == true ? MC.red : .primary)
                    }.font(.subheadline)
                    ProgressView(value: line.limit.map { min(1, Double(line.spent) / Double(max(1, $0))) } ?? Double(line.spent) / Double(peak))
                        .tint(line.limit.map { line.spent > $0 } == true ? MC.red : (line.limit == nil ? .secondary : .primary))
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Limit beside spent for each cycle, oldest first. A cycle that went over its limit is red.
struct BudgetCyclesChart: View {
    let results: [BudgetCycleResult]
    let currency: String

    private func label(_ result: BudgetCycleResult) -> String {
        result.cycle.start.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
    }

    var body: some View {
        Chart {
            ForEach(results) { result in
                BarMark(x: .value("Cycle", label(result)), y: .value("Amount", Double(result.limit) / 100))
                    .position(by: .value("Kind", "Limit"))
                    .foregroundStyle(Color.secondary.opacity(0.3))
                BarMark(x: .value("Cycle", label(result)), y: .value("Amount", Double(result.spent) / 100))
                    .position(by: .value("Kind", "Spent"))
                    .foregroundStyle(result.isOver ? MC.red : Color.primary.opacity(0.8))
                    .opacity(result.isCurrent ? 0.55 : 1)
            }
        }
        .chartYAxis { AxisMarks(position: .leading) { AxisGridLine(); AxisValueLabel() } }
        .frame(height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Budget against spending by cycle")
        .accessibilityValue(results.map { "\(label($0)): spent \(Money.format($0.spent, code: currency)) of \(Money.format($0.limit, code: currency))" }.joined(separator: ". "))
    }
}
