import SwiftUI

struct CategoryManager: View {
    let model: AppModel
    @State private var editing: ExpenseCategory?
    @State private var deleting: ExpenseCategory?
    @State private var error: String?
    var body: some View {
        List {
            Section {
                ForEach(model.categories) { category in
                    Button { editing = category } label: {
                        HStack {
                            CategoryMark(symbol: category.symbol)
                            Text(category.name).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("edit-category-\(category.name)")
                        .swipeActions { Button("Delete", role: .destructive) { deleting = category } }
                }
            } footer: { Text("Rename categories without losing their history. Only unused categories can be deleted. Swipe left for Delete.") }
        }.navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New category", systemImage: "plus") { editing = ExpenseCategory(id: UUID(), name: "", symbol: "circle.grid.2x2") }
                        .accessibilityIdentifier("newCategory")
                }
            }
            .sheet(item: $editing) { category in CategoryEditor(model: model, category: category) }
            .alert("Delete category?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete", role: .destructive) {
                    guard let deleting else { return }
                    do { try model.deleteCategory(deleting) } catch { self.error = error.localizedDescription }
                    self.deleting = nil
                }
                Button("Cancel", role: .cancel) { deleting = nil }
            } message: { Text("This removes the category from your book.") }
            .alert("Unable to delete", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
}

struct CategoryEditor: View {
    let model: AppModel
    let category: ExpenseCategory
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    @State private var error: String?
    @State private var discard = false
    private var changed: Bool { name != category.name || symbol != category.symbol }
    init(model: AppModel, category: ExpenseCategory) {
        self.model = model; self.category = category
        _name = State(initialValue: category.name); _symbol = State(initialValue: category.symbol)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("e.g. Pets", text: $name).accessibilityIdentifier("categoryName") }
                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 12) {
                        ForEach(ExpenseCategory.symbols, id: \.self) { icon in
                            Button { symbol = icon } label: {
                                Image(systemName: icon).font(.title2).frame(width: 48, height: 48)
                                    .foregroundStyle(symbol == icon ? .white : Color.primary)
                                    .background(symbol == icon ? MC.ink : .clear, in: .rect(cornerRadius: 12))
                            }.buttonStyle(PressFeedbackStyle()).accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
                                .accessibilityAddTraits(symbol == icon ? .isSelected : [])
                        }
                    }.padding(.vertical, 8)
                }
                if let error { Text(error).foregroundStyle(MC.red) }
            }.navigationTitle(category.name.isEmpty ? "New category" : "Edit category").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if changed { discard = true } else { dismiss() } } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do {
                                try model.saveCategory(ExpenseCategory(id: category.id, name: name, symbol: symbol))
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("saveCategory")
                    }
                }
                .background { EntryDismissalGuard(needsConfirmation: changed) { discard = true }.frame(width: 0, height: 0) }
                .alert("Discard category changes?", isPresented: $discard) {
                    Button("Discard", role: .destructive) { dismiss() }
                    Button("Keep editing", role: .cancel) {}
                }
                .sensoryFeedback(.selection, trigger: symbol)
        }.interactiveDismissDisabled(changed)
    }
}
