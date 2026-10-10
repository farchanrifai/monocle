import SwiftUI

enum CategoryManagerTab: String, CaseIterable, Identifiable {
    case all = "All Categories"
    case byCard = "By Card"
    var id: String { rawValue }
}

struct CategoryManager: View {
    let model: AppModel
    @State private var selectedTab: CategoryManagerTab = .all
    @State private var selectedBookID: UUID?
    @State private var editingGlobalCategory: GlobalCategory?
    @State private var isCreatingCategory = false
    @State private var deletingGlobalCategory: GlobalCategory?
    @State private var error: String?

    private var activeBookID: UUID {
        if let selected = selectedBookID, model.books.contains(where: { $0.id == selected }) {
            return selected
        }
        return model.activeBookID
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $selectedTab) {
                ForEach(CategoryManagerTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(uiColor: .systemGroupedBackground))

            switch selectedTab {
            case .all:
                allCategoriesView
            case .byCard:
                byCardView
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreatingCategory = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("newCategory")
            }
        }
        .sheet(isPresented: $isCreatingCategory) {
            NewGlobalCategorySheet(model: model)
        }
        .sheet(item: $editingGlobalCategory) { category in
            GlobalCategoryEditor(model: model, category: category)
        }
        .alert("Delete category?", isPresented: Binding(
            get: { deletingGlobalCategory != nil },
            set: { if !$0 { deletingGlobalCategory = nil } }
        )) {
            Button("Delete", role: .destructive) {
                guard let category = deletingGlobalCategory else { return }
                do {
                    try model.deleteGlobalCategory(category)
                } catch {
                    self.error = error.localizedDescription
                }
                deletingGlobalCategory = nil
            }
            Button("Cancel", role: .cancel) {
                deletingGlobalCategory = nil
            }
        } message: {
            Text("This deletes the category across all cards. Categories used by expenses cannot be deleted.")
        }
        .alert("Unable to delete", isPresented: Binding(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - Mode 1: All Categories (Global Catalog)
    private var allCategoriesView: some View {
        List {
            Section {
                ForEach(model.globalCategories) { category in
                    Button {
                        editingGlobalCategory = category
                    } label: {
                        HStack(spacing: 14) {
                            CategoryMark(symbol: category.symbol)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(category.name)
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundStyle(.primary)
                                cardScopeLabel(for: category)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("edit-category-\(category.name)")
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            deletingGlobalCategory = category
                        }
                    }
                }
            } header: {
                Text("Global Catalog (\(model.globalCategories.count))")
            } footer: {
                Text("Tap any category to change its name, icon, card activations, or default availability for future cards.")
            }

            Section {
                NavigationLink("Keyword rules") {
                    CategoryRuleManager(model: model)
                }
                .accessibilityIdentifier("categoryRules")
            } footer: {
                Text("A keyword fills the category automatically during text entry and Siri Shortcuts.")
            }
        }
    }

    private func cardScopeLabel(for category: GlobalCategory) -> some View {
        let activeBookIDs = model.activeBookIDs(for: category.id)
        let totalCount = model.books.count
        if totalCount > 0 && activeBookIDs.count == totalCount {
            return Text("Active on all cards (\(totalCount))")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if activeBookIDs.isEmpty {
            return Text("Inactive")
                .font(.caption)
                .foregroundStyle(MC.red.opacity(0.8))
        } else {
            let cardNames = model.books.filter { activeBookIDs.contains($0.id) }.map(\.name).joined(separator: ", ")
            return Text("Active on: \(cardNames)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Mode 2: By Card (Card-Specific Activation)
    private var byCardView: some View {
        List {
            Section {
                Picker("Card", selection: Binding(
                    get: { activeBookID },
                    set: { selectedBookID = $0 }
                )) {
                    ForEach(model.books) { book in
                        Text(book.name).tag(book.id)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Selected Card")
            }

            Section {
                let currentID = activeBookID
                let activeCount = model.globalCategories.filter { model.isCategoryActive($0.id, on: currentID) }.count

                HStack {
                    Text("\(activeCount) of \(model.globalCategories.count) active")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Activate All") {
                        for cat in model.globalCategories {
                            model.performUIAction { try model.setCategory(cat.id, active: true, for: currentID) }
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.trailing, 8)

                    Button("Reset") {
                        for cat in model.globalCategories {
                            model.performUIAction { try model.setCategory(cat.id, active: cat.defaultActiveForNewCards, for: currentID) }
                        }
                    }
                    .font(.caption.weight(.semibold))
                }
                .padding(.vertical, 2)

                ForEach(model.globalCategories) { category in
                    HStack(spacing: 12) {
                        CategoryMark(symbol: category.symbol)
                        Text(category.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { model.isCategoryActive(category.id, on: currentID) },
                            set: { newValue in
                                do {
                                    try model.setCategory(category.id, active: newValue, for: currentID)
                                } catch {
                                    self.error = error.localizedDescription
                                }
                            }
                        ))
                        .labelsHidden()
                        .sensoryFeedback(.selection, trigger: model.isCategoryActive(category.id, on: currentID))
                    }
                }
            } header: {
                Text("Card Categories")
            } footer: {
                Text("Deactivating a category hides it when logging new expenses on this card. Past expenses in this category are kept.")
            }
        }
    }
}

// MARK: - New Global Category Sheet
struct NewGlobalCategorySheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var symbol: String = "circle.grid.2x2"
    @State private var activateOnAllCards: Bool = true
    @State private var selectedBookIDs: Set<UUID> = []
    @State private var defaultForNewCards: Bool = true
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Shopping", text: $name)
                        .accessibilityIdentifier("categoryName")
                }

                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 12) {
                        ForEach(ExpenseCategory.symbols, id: \.self) { icon in
                            Button {
                                symbol = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 48, height: 48)
                                    .foregroundStyle(symbol == icon ? .white : Color.primary)
                                    .background(symbol == icon ? MC.ink : .clear, in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(PressFeedbackStyle())
                            .accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(symbol == icon ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section("Card Activation") {
                    Toggle("Activate on all cards", isOn: $activateOnAllCards)
                        .onChange(of: activateOnAllCards) { _, all in
                            if all {
                                selectedBookIDs = Set(model.books.map(\.id))
                            }
                        }

                    if !activateOnAllCards {
                        ForEach(model.books) { book in
                            Toggle(book.name, isOn: Binding(
                                get: { selectedBookIDs.contains(book.id) },
                                set: { isOn in
                                    if isOn { selectedBookIDs.insert(book.id) }
                                    else { selectedBookIDs.remove(book.id) }
                                }
                            ))
                        }
                    }
                }

                Section("Future Cards") {
                    Toggle("Default for new cards", isOn: $defaultForNewCards)
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(MC.red)
                    }
                }
            }
            .navigationTitle("New category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            let newCategory = GlobalCategory(
                                id: UUID(),
                                name: name,
                                symbol: symbol,
                                defaultActiveForNewCards: defaultForNewCards
                            )
                            let targets = activateOnAllCards ? Set(model.books.map(\.id)) : selectedBookIDs
                            try model.saveGlobalCategory(newCategory, activeBookIDs: targets)
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .accessibilityIdentifier("saveCategory")
                }
            }
            .onAppear {
                selectedBookIDs = Set(model.books.map(\.id))
            }
            .sensoryFeedback(.selection, trigger: symbol)
        }
    }
}

// MARK: - Global Category Editor
struct GlobalCategoryEditor: View {
    let model: AppModel
    let category: GlobalCategory
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    @State private var selectedBookIDs: Set<UUID>
    @State private var defaultForNewCards: Bool
    @State private var error: String?
    @State private var discard = false
    @State private var confirmDelete = false

    private var hasChanges: Bool {
        name != category.name ||
        symbol != category.symbol ||
        defaultForNewCards != category.defaultActiveForNewCards ||
        selectedBookIDs != model.activeBookIDs(for: category.id)
    }

    init(model: AppModel, category: GlobalCategory) {
        self.model = model
        self.category = category
        _name = State(initialValue: category.name)
        _symbol = State(initialValue: category.symbol)
        _defaultForNewCards = State(initialValue: category.defaultActiveForNewCards)
        _selectedBookIDs = State(initialValue: model.activeBookIDs(for: category.id))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Category name", text: $name)
                        .accessibilityIdentifier("categoryName")
                }

                Section("Icon") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 12) {
                        ForEach(ExpenseCategory.symbols, id: \.self) { icon in
                            Button {
                                symbol = icon
                            } label: {
                                Image(systemName: icon)
                                    .font(.title2)
                                    .frame(width: 48, height: 48)
                                    .foregroundStyle(symbol == icon ? .white : Color.primary)
                                    .background(symbol == icon ? MC.ink : .clear, in: .rect(cornerRadius: 12))
                            }
                            .buttonStyle(PressFeedbackStyle())
                            .accessibilityLabel(icon.replacingOccurrences(of: ".", with: " "))
                            .accessibilityAddTraits(symbol == icon ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    HStack {
                        Text("\(selectedBookIDs.count) of \(model.books.count) cards selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(selectedBookIDs.count == model.books.count ? "Deselect All" : "Select All") {
                            if selectedBookIDs.count == model.books.count {
                                selectedBookIDs.removeAll()
                            } else {
                                selectedBookIDs = Set(model.books.map(\.id))
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }

                    ForEach(model.books) { book in
                        Toggle(book.name, isOn: Binding(
                            get: { selectedBookIDs.contains(book.id) },
                            set: { isOn in
                                if isOn { selectedBookIDs.insert(book.id) }
                                else { selectedBookIDs.remove(book.id) }
                            }
                        ))
                    }
                } header: {
                    Text("Active on Cards")
                } footer: {
                    Text("Turning off a category on a card removes it from that card's entry options without affecting past expenses.")
                }

                Section("Future Cards") {
                    Toggle("Default for new cards", isOn: $defaultForNewCards)
                }

                Section {
                    Button("Delete category", role: .destructive) {
                        confirmDelete = true
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(MC.red)
                    }
                }
            }
            .navigationTitle("Edit category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { discard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            let updated = GlobalCategory(
                                id: category.id,
                                name: name,
                                symbol: symbol,
                                defaultActiveForNewCards: defaultForNewCards
                            )
                            try model.saveGlobalCategory(updated, activeBookIDs: selectedBookIDs)
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .accessibilityIdentifier("saveCategory")
                }
            }
            .alert("Discard changes?", isPresented: $discard) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .alert("Delete category?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    do {
                        try model.deleteGlobalCategory(category)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the category across all cards. Categories used by expenses cannot be deleted.")
            }
            .sensoryFeedback(.selection, trigger: symbol)
        }
        .interactiveDismissDisabled(hasChanges)
    }
}

// MARK: - Backward Compatibility Wrapper for CategoryEditor
struct CategoryEditor: View {
    let model: AppModel
    let category: ExpenseCategory

    var body: some View {
        if let global = model.globalCategories.first(where: { $0.id == category.id }) {
            GlobalCategoryEditor(model: model, category: global)
        } else {
            GlobalCategoryEditor(model: model, category: GlobalCategory(category: category, defaultActiveForNewCards: true))
        }
    }
}

// MARK: - Category Rules
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
                        .swipeActions { Button("Delete", role: .destructive) { model.performUIAction { try model.deleteCategoryRule(rule) } } }
                }
            }
        }
        .navigationTitle("Keyword rules")
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
            }
            .navigationTitle(rule.keyword.isEmpty ? "New rule" : "Edit rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try model.saveCategoryRule(.init(id: rule.id, keyword: keyword, categoryID: categoryID))
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .accessibilityIdentifier("saveCategoryRule")
                }
            }
        }
    }
}

