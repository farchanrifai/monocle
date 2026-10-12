import SwiftUI

/// Paid with labels: an optional answer to "what paid for this?". Never a balance.
struct PaymentMethodsView: View {
    @Bindable var model: AppModel
    let cardID: UUID
    @State private var editing: PaymentMethod?

    private var card: Card? { model.cards.first { $0.id == cardID } }
    private var defaultTitle: String { "Default for \(card?.name ?? "this card")" }
    private var defaultSelection: Binding<UUID?> {
        Binding(get: { card?.defaultPaidWithID },
                set: { id in model.performUIAction { try model.setDefaultPaidWith(id, for: cardID) } })
    }

    var body: some View {
        Form {
            Section {
                Picker(defaultTitle, selection: defaultSelection) {
                    Text("None").tag(UUID?.none)
                    ForEach(model.paymentMethods) { method in Text(method.name).tag(UUID?.some(method.id)) }
                }.accessibilityIdentifier("defaultPaidWith")
            } footer: {
                Text("New expenses on this card start with this label. You can change it on each expense.")
            }
            Section {
                ForEach(model.paymentMethods) { method in
                    Button { editing = method } label: {
                        Label(method.name, systemImage: method.kind.symbol).foregroundStyle(.primary)
                    }
                }
                Button("Add label", systemImage: "plus") { editing = PaymentMethod(name: "") }
                    .accessibilityIdentifier("addPaymentMethod")
            } header: { Text("Labels") } footer: {
                Text("Paid with records how you paid, like BCA debit or Cash. Monocle never tracks balances.")
            }
        }
        .navigationTitle("Paid with")
        .sheet(item: $editing) { method in PaymentMethodEditor(model: model, method: method) }
    }
}

private struct PaymentMethodEditor: View {
    let model: AppModel
    @State var method: PaymentMethod
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    private var isNew: Bool { model.paymentMethod(method.id) == nil }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name, like BCA debit", text: $method.name).accessibilityIdentifier("paymentMethodName")
                Picker("Kind", selection: $method.kind) {
                    ForEach(PaymentMethod.Kind.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                if !isNew {
                    Section {
                        Button("Delete label", role: .destructive) {
                            do { try model.deletePaymentMethod(id: method.id); dismiss() } catch { self.error = error.localizedDescription }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(MC.red) } }
            }
            .navigationTitle(isNew ? "New label" : "Edit label").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try model.savePaymentMethod(method); dismiss() } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("savePaymentMethod")
                }
            }
        }.presentationDetents([.medium])
    }
}

/// Workspace reporting currency, and the active card's budget and spending currencies.
struct CurrencySettingsView: View {
    @Bindable var model: AppModel
    let cardID: UUID
    @State private var pendingReporting: String?
    @State private var working = false
    @State private var error: String?

    private var card: Card? { model.cards.first { $0.id == cardID } }
    private var choices: [String] {
        var seen = Set<String>()
        return ([model.reportingCurrency] + Money.commonCurrencies).filter { seen.insert($0).inserted }
    }

    var body: some View {
        Form {
            Section {
                Picker("Reporting currency", selection: Binding(get: { model.reportingCurrency }, set: { pendingReporting = $0 })) {
                    ForEach(choices, id: \.self) { Text($0).tag($0) }
                }.disabled(working).accessibilityIdentifier("reportingCurrency")
            } footer: {
                Text("Stacks, analytics and widgets add up in this currency. Changing it converts every expense at the rate of its own day and makes a safety backup first.")
            }
            if let card {
                Section {
                    Picker("Budget currency", selection: Binding(get: { model.currency(of: card) }, set: { code in
                        run { try await model.setCardCurrencies(budget: code, spending: card.spendingCurrency, for: cardID) }
                    })) {
                        ForEach(choices, id: \.self) { Text($0 == model.reportingCurrency ? "\($0) · reporting" : $0).tag($0) }
                    }.accessibilityIdentifier("cardCurrency")
                    Picker("Spending currency", selection: Binding(get: { card.spendingCurrency ?? model.currency(of: card) }, set: { code in
                        run { try await model.setCardCurrencies(budget: card.currency, spending: code, for: cardID) }
                    })) {
                        ForEach(choices, id: \.self) { Text($0).tag($0) }
                    }.accessibilityIdentifier("spendingCurrency")
                } header: { Text(card.name) } footer: {
                    Text("The card's budget and totals use the budget currency; changing it converts the budget at today's rate. New expenses start in the spending currency, and the card shows an ≈ amount in it, like a Japan trip budgeted in rupiah that you spend in yen.")
                }
            }
            if working { Section { HStack { ProgressView(); Text("Converting…") } } }
            if let error { Section { Text(error).foregroundStyle(MC.red) } }
        }
        .navigationTitle("Currency")
        .alert("Change reporting currency to \(pendingReporting ?? "")?", isPresented: Binding(get: { pendingReporting != nil }, set: { if !$0 { pendingReporting = nil } })) {
            Button("Convert") {
                let code = pendingReporting; pendingReporting = nil
                if let code { run { try await model.changeReportingCurrency(to: code) } }
            }
            Button("Cancel", role: .cancel) { pendingReporting = nil }
        } message: {
            Text("Every expense is converted at the rate of its own day. Budgets, bills and stack caps convert at today's rate. A safety backup is made first.")
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        working = true; error = nil
        Task {
            do { try await operation() } catch { self.error = error.localizedDescription }
            working = false
        }
    }
}

/// Which optional fields the Add Expense form shows.
struct EntryFormSettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(EntryFormField.allCases, id: \.self) { field in
                    Toggle(field.title, isOn: Binding(get: { model.isEntryFieldShown(field) },
                                                      set: { model.setEntryField(field, shown: $0) }))
                        .accessibilityIdentifier("entryField-\(field.rawValue)")
                }
            } footer: {
                Text("Amount, card and category are always shown. A hidden field still appears when an expense already has a value for it. A hidden date means today.")
            }
        }.navigationTitle("Add Expense form")
    }
}
