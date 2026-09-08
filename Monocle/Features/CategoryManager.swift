import SwiftUI

struct CategoryManager: View {
    let model: AppModel
    @State private var editing: ExpenseCategory?
    @State private var deleting: ExpenseCategory?
    @State private var error: String?
    private var activeCategories: [ExpenseCategory] { model.categories.filter { !model.isArchived($0) } }
    private var archivedCategories: [ExpenseCategory] { model.categories.filter { model.isArchived($0) } }
    var body: some View {
        List {
            Section {
                ForEach(activeCategories) { category in
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
            } header: { Text("Active") } footer: { Text("Archiving hides a category from new expenses but preserves every recorded expense. Only unused categories can be deleted.") }
            if !archivedCategories.isEmpty {
                Section {
                    ForEach(archivedCategories) { category in
                        ArchivedCategoryRow(category: category) { restore(category) }
                    }
                } header: { Text("Archived") }
            }
            Section {
                NavigationLink("Keyword rules") { CategoryRuleManager(model: model) }
                    .accessibilityIdentifier("categoryRules")
            } footer: { Text("A keyword fills the category for text entry and the text Shortcut.") }
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

    private func restore(_ category: ExpenseCategory) {
        do { try model.restoreCategory(category) }
        catch let failure { error = failure.localizedDescription }
    }
}

private struct ArchivedCategoryRow: View {
    let category: ExpenseCategory
    let restore: () -> Void
    private var accessibilityID: String { "restore-category-" + category.name }
    var body: some View {
        HStack {
            CategoryMark(symbol: category.symbol).opacity(0.55)
            Text(category.name).foregroundStyle(.secondary)
            Spacer()
            Button("Restore", action: restore).accessibilityIdentifier(accessibilityID)
        }
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
    @State private var confirmArchive = false
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
                if !category.name.isEmpty {
                    Section { Button("Archive category", role: .destructive) { confirmArchive = true } }
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
                .alert("Archive category?", isPresented: $confirmArchive) {
                    Button("Archive", role: .destructive) {
                        do { try model.archiveCategory(category); dismiss() } catch { self.error = error.localizedDescription }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("It will remain on existing expenses but no longer appear when recording a new expense.") }
                .sensoryFeedback(.selection, trigger: symbol)
        }.interactiveDismissDisabled(changed)
    }
}

struct CategoryRuleManager: View {
    let model: AppModel
    @State private var editing: CategoryRule?
    private var rules: [CategoryRule] { model.settings.categoryRules }

    var body: some View {
        List {
            if rules.isEmpty {
                ContentUnavailableView("No keyword rules", systemImage: "text.badge.plus", description: Text("Add one for a word you type often."))
            } else {
                ForEach(rules) { rule in
                    CategoryRuleRow(rule: rule, categoryName: model.category(rule.categoryID)?.name ?? "Missing category") { editing = rule }
                        .swipeActions { Button("Delete", role: .destructive) { try? model.deleteCategoryRule(rule) } }
                }
            }
        }.navigationTitle("Keyword rules")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("New rule", systemImage: "plus") { newRule() } } }
            .sheet(item: $editing) { rule in CategoryRuleEditor(model: model, rule: rule) }
    }

    private func newRule() { editing = CategoryRule(id: UUID(), keyword: "", categoryID: model.activeCategories.first?.id ?? UUID()) }
}

private struct CategoryRuleRow: View {
    let rule: CategoryRule
    let categoryName: String
    let edit: () -> Void
    var body: some View {
        Button(action: edit) {
            HStack { Text(rule.keyword).foregroundStyle(.primary); Spacer(); Text(categoryName).foregroundStyle(.secondary) }
        }
    }
}

private struct CategoryRuleEditor: View {
    let model: AppModel
    let rule: CategoryRule
    @Environment(\.dismiss) private var dismiss
    @State private var keyword: String
    @State private var categoryID: UUID
    @State private var error: String?

    init(model: AppModel, rule: CategoryRule) {
        self.model = model; self.rule = rule
        _keyword = State(initialValue: rule.keyword); _categoryID = State(initialValue: rule.categoryID)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Keyword, e.g. boba", text: $keyword).textInputAutocapitalization(.never)
                Picker("Category", selection: $categoryID) {
                    ForEach(model.activeCategories) { category in Text(category.name).tag(category.id) }
                }
                if let error { Text(error).foregroundStyle(MC.red) }
            }.navigationTitle(rule.keyword.isEmpty ? "New rule" : "Edit rule")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do { try model.saveCategoryRule(.init(id: rule.id, keyword: keyword, categoryID: categoryID)); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.accessibilityIdentifier("saveCategoryRule")
                    }
                }
        }
    }
}
