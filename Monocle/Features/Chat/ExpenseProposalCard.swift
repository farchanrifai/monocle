import SwiftUI

enum ProposalState: Equatable { case pending, saved, discarded }

/// Full-width confirm card for an expense Claude proposed. Nothing is written until Save.
struct ExpenseProposalCard: View {
    let expense: Expense
    let category: ExpenseCategory?
    let cardName: String
    let state: ProposalState
    var onSave: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New expense").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(Money.format(expense.amount)).font(.system(size: 30, weight: .semibold, design: .rounded))
            VStack(alignment: .leading, spacing: 6) {
                Label(category?.name ?? "No category", systemImage: category?.symbol ?? "questionmark.circle")
                if !expense.note.isEmpty { Label(expense.note, systemImage: "text.alignleft") }
                Label(Day.title(expense.day), systemImage: "calendar")
                Label(cardName, systemImage: "creditcard")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            switch state {
            case .pending:
                HStack(spacing: 10) {
                    Button("Discard", role: .destructive, action: onDiscard)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("proposalDiscard")
                    Button("Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .tint(MC.red)
                        .accessibilityIdentifier("proposalSave")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            case .saved:
                Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(MC.red).font(.subheadline.weight(.semibold))
            case .discarded:
                Label("Discarded", systemImage: "xmark.circle").foregroundStyle(.secondary).font(.subheadline.weight(.semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 20, style: .continuous))
    }
}
