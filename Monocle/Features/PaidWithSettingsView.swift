import SwiftUI

/// Paid with labels: an optional answer to "what paid for this?". Never a balance.
struct PaymentMethodsView: View {
    @Bindable var model: AppModel
    let bookID: UUID
    @State private var editing: PaymentMethod?

    private var book: BookProfile? { model.books.first { $0.id == bookID } }
    private var defaultTitle: String { "Default for \(book?.name ?? "this card")" }
    private var defaultSelection: Binding<UUID?> {
        Binding(get: { book?.defaultPaidWithID },
                set: { id in model.performUIAction { try model.setDefaultPaidWith(id, for: bookID) } })
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
