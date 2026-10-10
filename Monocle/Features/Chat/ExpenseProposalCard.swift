import SwiftUI

/// Full-width confirm card for an expense Claude proposed. Nothing is written until Save.
struct ExpenseProposalCard: View {
    let expense: Expense
    let category: ExpenseCategory?
    /// Set for a split: every part with its amount.
    var splitLabel: String? = nil
    let cardName: String
    let state: ProposalState
    var onSave: () -> Void
    var onDiscard: () -> Void
    var onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New expense").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(Money.format(expense.amount)).font(.system(.title, design: .rounded, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                if let splitLabel { Label(splitLabel, systemImage: "square.split.2x1") }
                else { Label(category?.name ?? "No category", systemImage: category?.symbol ?? "questionmark.circle") }
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
                    Spacer()
                    Button("Edit", action: onEdit)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("proposalEdit")
                    Button("Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .tint(MC.red)
                        .accessibilityIdentifier("proposalSave")
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            case .saved:
                Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(MC.red).font(.subheadline.weight(.semibold))
            case .opened:
                Label("Opened in editor", systemImage: "square.and.pencil").foregroundStyle(.secondary).font(.subheadline.weight(.semibold))
            case .discarded, .undone:
                Label("Discarded", systemImage: "xmark.circle").foregroundStyle(.secondary).font(.subheadline.weight(.semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 20, style: .continuous))
    }
}

/// Confirm card for a recurring bill Claude proposed. Nothing is written until Save.
struct BillProposalCard: View {
    let bill: Bill
    let categoryName: String
    let cardName: String
    let state: ProposalState
    var onSave: () -> Void
    var onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New bill").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.name).font(.headline)
                Text(Money.format(bill.amount)).font(.system(.title, design: .rounded, weight: .semibold))
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(bill.recurrence.title, systemImage: "repeat")
                Label(categoryName, systemImage: "tag")
                Label(bill.recordingMode.title, systemImage: bill.recordingMode == .automatic ? "bolt" : "hand.tap")
                if bill.hasReminder { Label("Reminder on the due day", systemImage: "bell") }
                Label(cardName, systemImage: "creditcard")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            switch state {
            case .pending:
                HStack(spacing: 10) {
                    Spacer()
                    Button("Discard", role: .destructive, action: onDiscard)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("billProposalDiscard")
                    Button("Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .tint(MC.red)
                        .accessibilityIdentifier("billProposalSave")
                }
            case .saved:
                Label("Saved to Bills", systemImage: "checkmark.circle.fill").foregroundStyle(MC.red).font(.subheadline.weight(.semibold))
            case .discarded, .opened, .undone:
                Label("Discarded", systemImage: "xmark.circle").foregroundStyle(.secondary).font(.subheadline.weight(.semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 20, style: .continuous))
    }
}

/// Confirm card for Claude's proposed edit or delete of a saved expense. Applied only on tap, with Undo after.
struct ExpenseChangeCard: View {
    let change: ExpenseChange
    /// Category name for an expense, split categories joined.
    let categoryName: (Expense) -> String
    let cardName: String
    let state: ProposalState
    var onApply: () -> Void
    var onKeep: () -> Void
    var onUndo: () -> Void

    private var isDelete: Bool { change.updated == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isDelete ? "Delete expense" : "Edit expense").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let updated = change.updated {
                amount(change.original, updated)
                VStack(alignment: .leading, spacing: 6) {
                    field("tag", categoryName(change.original), categoryName(updated))
                    field("text.alignleft", change.original.note, updated.note)
                    field("calendar", Day.title(change.original.day), Day.title(updated.day))
                    Label(cardName, systemImage: "creditcard")
                }
                .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text(Money.format(change.original.amount)).font(.system(.title, design: .rounded, weight: .semibold))
                    .strikethrough(state == .saved)
                VStack(alignment: .leading, spacing: 6) {
                    Label(categoryName(change.original), systemImage: "tag")
                    if !change.original.note.isEmpty { Label(change.original.note, systemImage: "text.alignleft") }
                    Label(Day.title(change.original.day), systemImage: "calendar")
                    Label(cardName, systemImage: "creditcard")
                }
                .font(.subheadline).foregroundStyle(.secondary)
            }

            switch state {
            case .pending:
                HStack(spacing: 10) {
                    Spacer()
                    Button(isDelete ? "Keep" : "Discard", action: onKeep)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("changeKeep")
                    Button(isDelete ? "Delete" : "Save", role: isDelete ? .destructive : nil, action: onApply)
                        .buttonStyle(.borderedProminent)
                        .tint(MC.red)
                        .accessibilityIdentifier("changeApply")
                }
            case .saved:
                HStack {
                    Label(isDelete ? "Deleted" : "Updated", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(MC.red).font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Undo", action: onUndo).buttonStyle(.bordered).accessibilityIdentifier("changeUndo")
                }
            case .undone:
                Label("Undone", systemImage: "arrow.uturn.backward.circle").foregroundStyle(.secondary).font(.subheadline.weight(.semibold))
            case .discarded, .opened:
                Label(isDelete ? "Kept" : "Discarded", systemImage: "xmark.circle").foregroundStyle(.secondary).font(.subheadline.weight(.semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func amount(_ old: Expense, _ new: Expense) -> some View {
        if old.amount == new.amount {
            Text(Money.format(new.amount)).font(.system(.title, design: .rounded, weight: .semibold))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Money.format(old.amount)).strikethrough().foregroundStyle(.secondary).font(.title3)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary).accessibilityLabel("to")
                Text(Money.format(new.amount)).font(.system(.title, design: .rounded, weight: .semibold))
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// One line per field; a changed field reads "old → new", an empty unchanged one is hidden.
    @ViewBuilder
    private func field(_ icon: String, _ old: String, _ new: String) -> some View {
        if old != new {
            Label { Text("\(old.isEmpty ? "—" : old) → \(new.isEmpty ? "—" : new)").foregroundStyle(.primary) } icon: { Image(systemName: icon) }
                .accessibilityLabel("\(old.isEmpty ? "none" : old) to \(new.isEmpty ? "none" : new)")
        } else if !new.isEmpty {
            Label(new, systemImage: icon)
        }
    }
}
