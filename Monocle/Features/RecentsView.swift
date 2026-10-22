import SwiftUI

struct ExpenseRow: View {
    let expense: Expense
    let model: AppModel
    private var category: ExpenseCategory? { model.category(expense.splits.first?.categoryID) }
    var body: some View {
        HStack(spacing: 13) {
            CategoryMark(symbol: category?.symbol ?? "square.grid.2x2")
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title(expense)).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Text(expense.splits.count > 1 ? "Split across \(expense.splits.count) categories" : category?.name ?? "Expense").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            VStack(alignment: .trailing, spacing: 1) {
                Text(expense.paidText).font(.subheadline.monospacedDigit().weight(.medium)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.75)
                if let note = expense.reportingNote { Text(note).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
            }
        }.padding(.vertical, 9).contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
}
