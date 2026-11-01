import SwiftUI

/// Full-width confirm card for an expense the assistant proposed. Nothing is written until Save.
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
            Text(Money.format(expense.amount)).font(.system(.title, weight: .semibold))
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
        .background(Color.chatSurface, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

/// One card for the several expenses of one reply: a row each (tap to edit, hold to discard) and Save all / Discard all.
struct ExpenseProposalGroup: View {
    struct Item: Identifiable {
        let id: UUID
        let expense: Expense
        let state: ProposalState
        let symbol: String
        let categoryLabel: String
        let cardName: String
    }
    let items: [Item]
    var onEdit: (Item) -> Void
    var onDiscard: (Item) -> Void
    var onSaveAll: () -> Void
    var onDiscardAll: () -> Void

    private var pending: [Item] { items.filter { $0.state == .pending } }
    private func isDropped(_ item: Item) -> Bool { item.state == .discarded || item.state == .undone }
    /// Day and card go in the header when every expense shares them, otherwise on each row.
    private var sharedDay: String? { Set(items.map(\.expense.day)).count == 1 ? items.first?.expense.day : nil }
    private var sharedCard: String? { Set(items.map(\.cardName)).count == 1 ? items.first?.cardName : nil }
    private var total: Int64 { Money.sum(items.filter { !isDropped($0) }.map(\.expense.amount)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(["\(items.count) new expenses", sharedCard, sharedDay.map(Day.title)].compactMap { $0 }.joined(separator: " · "))
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    row(item)
                    if item.id != items.last?.id { Divider().padding(.leading, 44) }
                }
            }
            Divider()
            HStack {
                Text("Total").foregroundStyle(.secondary)
                Spacer()
                Text(Money.format(total)).font(.headline.monospacedDigit())
            }
            .font(.subheadline)
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.chatSurface, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private func row(_ item: Item) -> some View {
        let detail = [item.categoryLabel, sharedDay == nil ? Day.title(item.expense.day) : nil, sharedCard == nil ? item.cardName : nil]
        return Button { if item.state == .pending { onEdit(item) } } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(MC.red)
                    .frame(width: 32, height: 32).background(MC.red.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.expense.note.isEmpty ? item.categoryLabel : item.expense.note)
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(detail.compactMap { $0 }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Money.format(item.expense.amount)).font(.subheadline.weight(.semibold).monospacedDigit())
                switch item.state {
                case .saved: Image(systemName: "checkmark.circle.fill").foregroundStyle(MC.red)
                case .opened: Image(systemName: "square.and.pencil").foregroundStyle(.secondary)
                case .discarded, .undone: Image(systemName: "xmark.circle").foregroundStyle(.secondary)
                case .pending: EmptyView()
                }
            }
            .strikethrough(isDropped(item))
            .opacity(isDropped(item) ? 0.5 : 1)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if item.state == .pending {
                Button("Edit", systemImage: "square.and.pencil") { onEdit(item) }
                Button("Discard", systemImage: "xmark", role: .destructive) { onDiscard(item) }
            }
        }
        .accessibilityHint(item.state == .pending ? "Opens it in the editor" : "")
        .accessibilityIdentifier("proposalRow")
    }

    @ViewBuilder private var footer: some View {
        if pending.isEmpty {
            let saved = items.filter { $0.state == .saved }.count
            let dropped = items.filter(isDropped).count
            let summary = [saved > 0 ? "\(saved) saved" : nil, dropped > 0 ? "\(dropped) discarded" : nil].compactMap { $0 }.joined(separator: " · ")
            Label(summary.isEmpty ? "Opened in editor" : summary, systemImage: saved > 0 ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(saved > 0 ? MC.red : .secondary).font(.subheadline.weight(.semibold))
        } else {
            HStack(spacing: 10) {
                Button("Discard all", role: .destructive, action: onDiscardAll)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("proposalDiscardAll")
                Spacer()
                Button(pending.count == items.count ? "Save all" : "Save \(pending.count)", action: onSaveAll)
                    .buttonStyle(.borderedProminent)
                    .tint(MC.red)
                    .accessibilityIdentifier("proposalSaveAll")
            }
        }
    }
}

/// Confirm card for a recurring bill the assistant proposed. Nothing is written until Save.
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
                Text(Money.format(bill.amount)).font(.system(.title, weight: .semibold))
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
        .background(Color.chatSurface, in: .rect(cornerRadius: 20, style: .continuous))
    }
}

/// Confirm card for the assistant's proposed edit or delete of a saved expense. Applied only on tap, with Undo after.
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
                Text(Money.format(change.original.amount)).font(.system(.title, weight: .semibold))
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
        .background(Color.chatSurface, in: .rect(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private func amount(_ old: Expense, _ new: Expense) -> some View {
        if old.amount == new.amount {
            Text(Money.format(new.amount)).font(.system(.title, weight: .semibold))
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Money.format(old.amount)).strikethrough().foregroundStyle(.secondary).font(.title3)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary).accessibilityLabel("to")
                Text(Money.format(new.amount)).font(.system(.title, weight: .semibold))
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
