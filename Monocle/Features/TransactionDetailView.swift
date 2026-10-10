import SwiftUI

struct TransactionDetailView: View {
    let initialExpense: Expense
    @Bindable var model: AppModel
    let onDismiss: () -> Void

    @State private var showDeleteConfirmation = false
    @State private var showingEditSheet = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Live expense lookup so updates made in the edit sheet immediately reflect here
    private var expense: Expense {
        let all = model.activities(selectedCardID: nil, allCards: true)
        return all.first { $0.id == initialExpense.id } ?? initialExpense
    }

    private var category: ExpenseCategory? {
        model.category(expense.splits.first?.categoryID)
    }

    private var card: Card? {
        model.cards.first { $0.id == expense.cardID }
    }

    private var primaryCategorySymbol: String {
        category?.symbol ?? "creditcard"
    }

    private var formattedTime: String {
        expense.createdAt.formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    heroSection
                    detailsCard
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(MC.paper.ignoresSafeArea())
            .navigationTitle("Expense Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDismiss) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 16))
                        }
                    }
                    .accessibilityIdentifier("transactionDetailBack")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        startEdit()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(MC.red)
                    .accessibilityIdentifier("transactionDetailEdit")
                }
            }
            .sheet(isPresented: Binding(
                get: { showingEditSheet || (model.showEntry && model.draft.editing && model.pendingEntry == nil) },
                set: { if !$0 { showingEditSheet = false; model.showEntry = false } }
            ), onDismiss: {
                if !model.draftNeedsConfirmation { model.discardDraft() }
            }) {
                EntryView(model: model)
            }
            .confirmationDialog(
                "Delete Expense?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Expense", role: .destructive) {
                    model.delete(expense)
                    onDismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to delete this expense? You can undo this action from the confirmation toast.")
            }
        }
    }

    private func startEdit() {
        if model.draftNeedsConfirmation {
            model.edit(expense)
        } else {
            model.edit(expense)
            model.showEntry = false
            showingEditSheet = true
        }
    }

    // MARK: - Hero Section

    private var heroSection: some View {
        VStack(spacing: 12) {
            // Category Icon Badge
            ZStack {
                Circle()
                    .fill(MC.red.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: primaryCategorySymbol)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(MC.red)
            }
            .padding(.top, 8)

            // Title / Note
            Text(model.title(expense))
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            // Formatted Amount
            Text(expense.paidText)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.primary)
                .accessibilityIdentifier("transactionDetailAmount")
            if let note = expense.reportingNote {
                Text(note).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }

            // Timestamp Subtitle
            Text("\(Day.title(expense.day)) · \(formattedTime)")
                .font(.system(size: 13.5, weight: .regular))
                .foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Details Platter

    private var detailsCard: some View {
        VStack(spacing: 0) {
            // Category Row
            detailRow(label: "Category") {
                HStack(spacing: 8) {
                    Image(systemName: primaryCategorySymbol)
                        .font(.system(size: 14))
                        .foregroundStyle(MC.red)
                    Text(category?.name ?? "Uncategorized")
                        .font(.system(size: 15, weight: .medium))
                }
            }

            Divider().padding(.leading, 16)

            // Account / Card Row
            if let card {
                detailRow(label: "Card") {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(CardPalette.color(for: card.colorIndex))
                            .frame(width: 22, height: 14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                        Text(card.name)
                            .font(.system(size: 15, weight: .medium))
                    }
                }
                Divider().padding(.leading, 16)
            }

            if let code = expense.originalCurrency, let rate = expense.rate {
                detailRow(label: "Rate") {
                    Text("1 \(code) = \(rate) \(model.reportingCurrency)\(expense.rateSource == .manual ? " · entered" : "")")
                        .font(.system(size: 15, weight: .medium)).monospacedDigit()
                }
                Divider().padding(.leading, 16)
            }

            if let method = model.paymentMethod(expense.paidWithID) {
                detailRow(label: "Paid with") {
                    Label(method.name, systemImage: method.kind.symbol)
                        .font(.system(size: 15, weight: .medium))
                }
                Divider().padding(.leading, 16)
            }

            // Date Row
            detailRow(label: "Date") {
                Text(expense.day)
                    .font(.system(size: 15, weight: .medium))
                    .monospacedDigit()
            }

            Divider().padding(.leading, 16)

            // Source Row
            detailRow(label: "Entry Method") {
                Text(sourceTitle(expense.source))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Note Row (if not empty)
            if !expense.note.isEmpty {
                Divider().padding(.leading, 16)
                detailRow(label: "Note") {
                    Text(expense.note)
                        .font(.system(size: 15, weight: .regular))
                        .multilineTextAlignment(.trailing)
                }
            }

            // Split Breakdown (if multiple splits)
            if expense.splits.count > 1 {
                Divider().padding(.leading, 16)
                VStack(alignment: .leading, spacing: 10) {
                    Text("SPLIT ALLOCATIONS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                        .padding(.horizontal, 16)

                    ForEach(expense.splits, id: \.categoryID) { alloc in
                        let cat = model.category(alloc.categoryID)
                        HStack(spacing: 8) {
                            Image(systemName: cat?.symbol ?? "tag")
                                .font(.system(size: 13))
                                .foregroundStyle(MC.red)
                                .frame(width: 20)
                            Text(cat?.name ?? "Category")
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text(Money.format(alloc.amount))
                                .font(.system(size: 14, weight: .semibold))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                    .padding(.bottom, 10)
                }
            }
        }
        .background(MC.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func detailRow<TrailingContent: View>(label: String, @ViewBuilder content: () -> TrailingContent) -> some View {
        HStack(alignment: .center) {
            Text(label)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary)
            Spacer()
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func sourceTitle(_ source: String) -> String {
        switch source.lowercased() {
        case "text": return "Text Parsing"
        case "shortcut": return "Siri / Shortcut"
        case "sample": return "Sample Data"
        default: return "Manual Entry"
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Edit Button
            Button {
                startEdit()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Edit Expense")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(PressFeedbackStyle())
            .glassEffect(.regular.tint(MC.red.opacity(0.88)).interactive(), in: .capsule)
            .environment(\.colorScheme, .dark)

            // Delete Button
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Delete Expense")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(Color.red)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.red.opacity(0.1), in: Capsule())
            }
            .buttonStyle(PressFeedbackStyle())
            .accessibilityIdentifier("transactionDetailDelete")
        }
        .padding(.top, 8)
    }
}
