import SwiftUI

struct ResetDataView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var freshCardName = "My expenses"
    @State private var confirmClearActive = false
    @State private var confirmClearAll = false
    @State private var confirmResetAll = false
    @State private var message: String?

    private var activeCardName: String {
        let activeID = model.selectedCardID ?? model.activeCardID
        return model.cards.first(where: { $0.id == activeID })?.name ?? model.settings.card.name
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("Safety Backup Guaranteed")
                            .font(.subheadline.weight(.semibold))
                    } icon: {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundStyle(.blue)
                    }
                    Text("A safety backup is created automatically before any reset. You can export or restore it at any time in Backup & Restore.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            // MARK: Clear Transactions
            Section {
                Button(role: .destructive) {
                    confirmClearActive = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear this card's expenses")
                                .foregroundStyle(.red)
                            Text("\(activeCardName) · \(model.expenses.count) entries")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                }
                .accessibilityIdentifier("clearActiveCardButton")

                if model.cards.count > 1 {
                    Button(role: .destructive) {
                        confirmClearAll = true
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Clear expenses on all cards")
                                    .foregroundStyle(.red)
                                Text("Across all \(model.cards.count) cards")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "trash.fill")
                                .foregroundStyle(.red)
                        }
                    }
                    .accessibilityIdentifier("clearAllCardsButton")
                }
            } header: {
                Text("Expenses")
            } footer: {
                Text("Deletes added expenses. Your cards, budgets, categories and bills are kept.")
            }

            // MARK: Complete Fresh Start
            Section {
                TextField("Fresh card name", text: $freshCardName)
                    .accessibilityIdentifier("freshCardNameField")

                Button(role: .destructive) {
                    confirmResetAll = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Erase all data and start fresh")
                                .font(.body.weight(.medium))
                                .foregroundStyle(.red)
                            Text("Factory reset for daily expense tracking")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.counterclockwise.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
                .accessibilityIdentifier("resetAllDataButton")
            } header: {
                Text("Complete Fresh Start")
            } footer: {
                Text("Wipes all expenses, recurring bills, and extra cards. Starts fresh with a single clean card in real mode and restores default categories.")
            }
        }
        .navigationTitle("Reset data")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Clear expenses on \"\(activeCardName)\"?", isPresented: $confirmClearActive) {
            Button("Clear expenses", role: .destructive) {
                do {
                    try model.clearActiveCardExpenses()
                    dismiss()
                } catch {
                    message = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All expenses on \"\(activeCardName)\" will be removed. Your categories, card design, and bills are kept. A safety backup is created first.")
        }
        .alert("Clear expenses on all cards?", isPresented: $confirmClearAll) {
            Button("Clear all expenses", role: .destructive) {
                do {
                    try model.clearAllTransactions()
                    dismiss()
                } catch {
                    message = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All expenses on all cards will be removed. A safety backup is created first.")
        }
        .alert("Erase all data & start fresh?", isPresented: $confirmResetAll) {
            Button("Erase all and start fresh", role: .destructive) {
                do {
                    try model.resetAllData(cardName: freshCardName)
                    dismiss()
                } catch {
                    message = error.localizedDescription
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all cards, expenses, and recurring bills, creating a clean new card \"\(freshCardName.isEmpty ? "My expenses" : freshCardName)\" with default categories. A safety backup is created first.")
        }
        .alert("Reset data", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }
}
