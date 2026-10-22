import SwiftUI

/// Quick numbers beside a card on its page: what is left of the budget, spend, daily average and the biggest category.
struct MacCardStats: View {
    let model: AppModel
    let card: Card

    var body: some View {
        let _ = model.dataRevision // refresh after edits
        let status = model.budgetStatus(.card(card.id))
        let code = model.currency(of: card)
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: columns, spacing: 12) {
            if let status {
                let elapsed = BudgetReport.days(in: status.cycle, now: .now).elapsed
                let top = status.lines.max { $0.spent < $1.spent }.flatMap { $0.spent > 0 ? $0 : nil }
                StatTile(title: status.remaining < 0 ? "Over budget" : (status.isGoal ? "Left until the end" : "Left this cycle"),
                         value: Money.format(abs(status.remaining), code: code), progress: status.fraction, over: status.remaining < 0,
                         detail: "of \(Money.format(status.limit, code: code)) · \(status.cycle.label)")
                StatTile(title: "Spent", value: Money.format(status.spent, code: code),
                         detail: status.pace.map(\.label) ?? status.cycle.label)
                StatTile(title: "Daily average", value: Money.format(status.spent / Int64(max(1, elapsed)), code: code),
                         detail: status.projected.map { "On pace for \(Money.format($0, code: code))" } ?? "Per day this cycle")
                StatTile(title: "Top category", value: top?.name ?? "—", mono: false,
                         detail: top.map { "\(Money.format($0.spent, code: code)) · \(Int((Double($0.spent) / Double(max(1, status.spent)) * 100).rounded()))%" } ?? "No spending yet")
            } else {
                // No budget on this card: all-time numbers only.
                let expenses = model.expenses(for: card.id)
                StatTile(title: "All time", value: Money.format(model.spent(for: card.id), code: code), detail: "Since the first expense")
                StatTile(title: "Expenses", value: "\(expenses.count)", detail: expenses.map(\.day).max().map { "Latest \(Day.title($0))" } ?? "None yet")
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }
}

private struct StatTile: View {
    let title: String
    let value: String
    var mono = true
    var progress: Double?
    var over = false
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(mono ? .system(.title3, weight: .semibold) : .title3.weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.6)
            if let progress {
                ProgressView(value: min(1, max(0, progress))).tint(over ? MC.red : nil).controlSize(.small)
            }
            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.vertical, 8).frame(maxWidth: .infinity, minHeight: 70, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}
