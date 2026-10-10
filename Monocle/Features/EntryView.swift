import SwiftUI

struct EntryView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 52.0
    private enum Field: Hashable { case text, note }
    @FocusState private var focusedField: Field?
    @State private var message: String?
    @State private var showDate = false
    @State private var showCategories = false
    @State private var showSplits = false
    @State private var showDiscard = false
    @State private var selectionTick = 0
    private var amount: Int64 { (try? model.draft.resolvedAmount()) ?? 0 }
    // A hidden field still shows when the expense already has a value for it.
    private var showsDate: Bool { model.isEntryFieldShown(.date) || model.draft.civilDay != Day.string(.now) }
    private var showsNote: Bool { model.isEntryFieldShown(.note) || !model.draft.note.isEmpty }
    private var showsSplit: Bool { model.isEntryFieldShown(.split) || model.draft.isSplit }
    private var showsCurrency: Bool { model.isEntryFieldShown(.currency) || model.draft.isForeign(reporting: model.reportingCurrency) }
    private var draftCurrency: String { model.draft.currency ?? model.reportingCurrency }
    private var showsPaidWith: Bool {
        (model.isEntryFieldShown(.paidWith) && !model.paymentMethods.isEmpty) || model.paymentMethod(model.draft.paidWithID) != nil
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if model.draft.mode == .text { textEntry }
                            amountDisplay
                            if model.draft.isSplit {
                                splitSummary
                            } else {
                                CategoryStrip(categories: model.activeCategories, selectedID: model.draft.categoryID, select: selectCategory) {
                                    focusedField = nil
                                    showCategories = true
                                }
                                if showsSplit { Button {
                                    focusedField = nil
                                    model.beginSplitting()
                                    showSplits = model.draft.isSplit
                                } label: {
                                    Label("Split across categories", systemImage: "square.grid.2x2")
                                        .font(.subheadline.weight(.semibold))
                                 }.tint(MC.red).accessibilityIdentifier("editSplits") }
                            }
                            if showsCurrency { currencySection }
                            if showsPaidWith { paidWithMenu }
                            if showsNote {
                                HStack(spacing: 10) {
                                    Image(systemName: "text.alignleft").foregroundStyle(.secondary).accessibilityHidden(true)
                                    TextField("Add a note (optional)", text: $model.draft.note)
                                        .font(.subheadline).submitLabel(.done).focused($focusedField, equals: .note)
                                        .onSubmit { focusedField = nil }.accessibilityIdentifier("expenseNote")
                                }.frame(minHeight: 44)
                            }
                        }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 12)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .frame(maxHeight: .infinity)
                    // The keypad is outside the scrolling form: Record can never cover its last row.
                    if model.draft.mode == .keypad && focusedField == nil {
                        keypad(rowHeight: min(58, max(44, geometry.size.height * 0.075)))
                            .padding(.horizontal, 24).padding(.top, 4)
                            .transition(.opacity)
                    }
                    RecordButton(
                        title: model.draft.editing ? "Save changes" : "Add expense",
                        symbol: model.draft.editing ? "checkmark" : "plus"
                    ) {
                        if model.saveDraft() { dismiss() }
                    }.accessibilityIdentifier("recordExpense")
                        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 10)
                }
            }
            .background(MC.paper)
            .navigationTitle(model.draft.editing ? "Edit expense" : "New expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: requestClose) { Image(systemName: "xmark") }
                        .accessibilityLabel("Close entry")
                        .accessibilityIdentifier("closeEntry")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .background {
                EntryDismissalGuard(needsConfirmation: model.draftNeedsConfirmation) { showDiscard = true }
                    .frame(width: 0, height: 0)
            }
            .sheet(isPresented: $showDate) {
                NavigationStack {
                    DatePicker("Expense date", selection: $model.draft.date, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDate = false } } }
                }.presentationDetents([.medium])
            }
            .sheet(isPresented: $showCategories) {
                CategoryPicker(categories: model.activeCategories, selectedID: model.draft.categoryID, select: selectCategory)
            }
            .sheet(isPresented: $showSplits) { SplitEditor(model: model) }
            .alert(showDiscard ? (model.draft.editing ? "Discard your changes?" : "Discard this expense?") : "Check this", isPresented: Binding(get: { showDiscard || model.error != nil }, set: {
                if !$0 { showDiscard = false; model.error = nil }
            })) {
                if showDiscard {
                    Button("Discard", role: .destructive) { closeAndDiscard() }
                    Button("Keep editing", role: .cancel) {}
                } else {
                    Button("OK") { model.error = nil }
                }
            } message: {
                if showDiscard {
                    Text(model.draft.editing ? "The saved expense will stay unchanged." : "The amount, category and note you entered will be cleared.")
                } else { Text(model.error ?? "") }
            }
            .onChange(of: model.draft.text) { _, _ in
                if model.draft.mode == .text { parse(hideKeyboard: false) }
            }
            .sensoryFeedback(.selection, trigger: selectionTick)
            .onChange(of: model.draft.mode) { _, mode in focusedField = mode == .text ? .text : nil }
            .onAppear {
                model.prefillDraftDefaults()
                if model.draft.mode == .text { focusedField = .text }
            }
            .task(id: "\(model.draft.currency ?? "")|\(model.draft.civilDay)") { await model.refreshDraftRate() }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
            .interactiveDismissDisabled(model.draftNeedsConfirmation)
    }

    private var textEntry: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Coffee 28k", text: $model.draft.text)
                .font(.title3).padding(14).background(MC.surface, in: RoundedRectangle(cornerRadius: 14))
                .focused($focusedField, equals: .text).submitLabel(.done).onSubmit { parse() }
                .autocorrectionDisabled().accessibilityIdentifier("expenseText")
            Button("Done typing", systemImage: "checkmark") { parse() }
                .font(.subheadline.weight(.semibold)).tint(MC.red).accessibilityIdentifier("parseExpense")
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var amountDisplay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Eyebrow(text: "Amount / \(draftCurrency)")
                Spacer()
                if showsDate {
                    Button { focusedField = nil; showDate = true } label: {
                        Label(Day.title(model.draft.civilDay), systemImage: "calendar").font(.caption)
                    }.tint(.secondary).frame(minHeight: 32)
                }
            }
            Text(Money.format(amount, currency: false))
                .font(.system(size: amountSize, weight: .regular, design: .monospaced)).tracking(-2).lineLimit(1).minimumScaleFactor(0.4)
                .foregroundStyle(amount == 0 ? .secondary : .primary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: amount)
                .accessibilityLabel("Amount \(Money.format(amount))").accessibilityIdentifier("amountDisplay")
            Rectangle().fill(MC.line).frame(height: 1)
        }
    }
    /// Currency the amount is typed in, with the rate to the reporting currency (fetched, or typed to override).
    private var currencySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                Picker("Currency", selection: Binding(get: { draftCurrency }, set: { code in
                    model.draft.currency = code == model.reportingCurrency ? nil : code
                    model.draft.rate = ""; model.draft.rateSource = nil
                })) {
                    ForEach(currencyChoices, id: \.self) { Text($0).tag($0) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "dollarsign.arrow.circlepath").foregroundStyle(.secondary)
                    Text("Currency").foregroundStyle(.secondary)
                    Spacer()
                    Text(draftCurrency).foregroundStyle(.primary)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                }.font(.subheadline).frame(minHeight: 44)
            }.accessibilityIdentifier("currencyMenu")
            if model.draft.isForeign(reporting: model.reportingCurrency) {
                HStack(spacing: 8) {
                    Text("1 \(draftCurrency) =").foregroundStyle(.secondary)
                    TextField("Rate", text: Binding(get: { model.draft.rate }, set: { model.draft.rate = $0; model.draft.rateSource = .manual }))
                        .keyboardType(.decimalPad).frame(maxWidth: 120).accessibilityIdentifier("rateField")
                    Text(model.reportingCurrency).foregroundStyle(.secondary)
                    Spacer()
                    if model.draft.rateSource == .manual {
                        Button("Use fetched") {
                            model.draft.rateSource = nil
                            Task { await model.refreshDraftRate() }
                        }.font(.caption)
                    }
                }.font(.subheadline)
                if let expense = try? model.draft.expense(reporting: model.reportingCurrency) {
                    Text("≈ \(Money.format(expense.amount, code: model.reportingCurrency))").font(.caption).foregroundStyle(.secondary)
                } else if let rateError = model.rateError {
                    Text(rateError).font(.caption).foregroundStyle(MC.red)
                }
            }
        }
    }
    private var currencyChoices: [String] {
        var codes = [model.reportingCurrency]
        for card in model.cards { codes += [card.currency, card.spendingCurrency].compactMap { $0 } }
        codes += Money.commonCurrencies
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }
    private var paidWithMenu: some View {
        Menu {
            Picker("Paid with", selection: $model.draft.paidWithID) {
                Text("Not set").tag(UUID?.none)
                ForEach(model.paymentMethods) { method in Label(method.name, systemImage: method.kind.symbol).tag(UUID?.some(method.id)) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: model.paymentMethod(model.draft.paidWithID)?.kind.symbol ?? "creditcard").foregroundStyle(.secondary)
                Text("Paid with").foregroundStyle(.secondary)
                Spacer()
                Text(model.paymentMethod(model.draft.paidWithID)?.name ?? "Not set").foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline).frame(minHeight: 44)
        }.accessibilityIdentifier("paidWithMenu")
    }
    private var splitSummary: some View {
        Button {
            focusedField = nil
            showSplits = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2").foregroundStyle(MC.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Split across \(model.draft.splitAllocations.count) categories").font(.subheadline.weight(.semibold))
                    Text("Edit allocations").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(14).background(MC.surface, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityIdentifier("editSplits")
    }
    private func keypad(rowHeight: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 4) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", Money.fractionDigits(draftCurrency) > 0 ? "." : "000", "0", "delete.left"], id: \.self) { key in
                Button {
                    if key == "delete.left" {
                        if !model.draft.amount.isEmpty { model.draft.amount.removeLast() }
                    } else if key == "." {
                        let separator = Locale.current.decimalSeparator ?? "."
                        if !model.draft.amount.contains(separator) { model.draft.amount += model.draft.amount.isEmpty ? "0" + separator : separator }
                    } else if model.draft.amount.count + key.count <= 13 {
                        if model.draft.amount == "0" { model.draft.amount = "" }
                        model.draft.amount += key
                    }
                    selectionTick += 1
                } label: {
                    Group {
                        if key == "delete.left" { Image(systemName: key).font(.title2) }
                        else { Text(key).font(.system(size: key == "000" ? 21 : 29, weight: .regular, design: .rounded)) }
                    }.frame(maxWidth: .infinity).frame(height: rowHeight).contentShape(Rectangle())
                }.buttonStyle(PressFeedbackStyle()).accessibilityLabel(key == "delete.left" ? "Delete digit" : key)
                    .accessibilityIdentifier("key-\(key)")
            }
        }
    }
    private func selectCategory(_ id: UUID) {
        if model.draft.categoryID != id { selectionTick += 1 }
        model.draft.categoryID = id
    }
    private func requestClose() {
        if model.draftNeedsConfirmation { showDiscard = true }
        else { closeAndDiscard() }
    }
    private func closeAndDiscard() {
        if model.discardDraft() {
            model.showEntry = false
            dismiss()
        }
    }
    private func parse(hideKeyboard: Bool = true) {
        do {
            let parsed = try ExpenseParser.parse(model.draft.text, categories: model.activeCategories, rules: model.settings.categoryRules)
            model.draft.amount = Money.digits(parsed.amount)
            model.draft.note = parsed.note
            model.draft.categoryID = parsed.categoryID
            model.draft.source = "text"
            message = parsed.categoryID == nil ? "Amount found. Choose a category to finish." : "Ready to add. You can adjust any detail."
            if hideKeyboard { focusedField = nil }
        } catch {
            model.draft.amount = ""; model.draft.categoryID = nil
            message = error.localizedDescription
        }
    }
}

private struct SplitEditor: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var choosingIndex: Int?
    @State private var useOneCategoryAfterDismissal = false

    private var total: Int64 { (try? model.draft.resolvedAmount()) ?? 0 }
    private var allocated: Int64? { try? model.draft.resolvedAllocatedAmount() }
    private var allocationError: String? {
        do { _ = try model.draft.resolvedAllocatedAmount(); return nil }
        catch { return error.localizedDescription }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Allocations") {
                    ForEach(model.draft.splitAllocations.indices, id: \.self) { index in
                        let split = model.draft.splitAllocations[index]
                        VStack(alignment: .leading, spacing: 10) {
                            Button {
                                choosingIndex = index
                            } label: {
                                HStack {
                                    CategoryMark(symbol: model.category(split.categoryID)?.symbol ?? "square.grid.2x2")
                                    Text(model.category(split.categoryID)?.name ?? "Choose category")
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("split-category-\(index)")
                            TextField("Amount", text: $model.draft.splitAllocations[index].amount)
                                .keyboardType(.numberPad).accessibilityIdentifier("split-amount-\(index)")
                            if model.draft.splitAllocations.count > 1 {
                                Button("Remove allocation", role: .destructive) { model.draft.splitAllocations.remove(at: index) }
                                    .font(.footnote)
                            }
                        }.padding(.vertical, 4)
                    }
                    Button("Add category", systemImage: "plus") { model.addSplitAllocation() }.accessibilityIdentifier("addSplit")
                }
                Section("Check") {
                    LabeledContent("Expense total") { Text(Money.format(total)) }
                    if let allocated {
                        let remaining = total - allocated
                        LabeledContent("Allocated") { Text(Money.format(allocated)) }
                        LabeledContent("Remaining") { Text(Money.format(abs(remaining))).foregroundStyle(remaining == 0 ? .green : MC.red) }
                        if remaining == 0 && model.draft.splitAllocations.count > 1 &&
                            Set(model.draft.splitAllocations.map(\.categoryID)).count == model.draft.splitAllocations.count &&
                            model.draft.splitAllocations.allSatisfy({ (try? $0.resolvedAmount()) != nil }) {
                            Label("Ready to add", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        } else {
                            Text("Use at least two categories and make allocations match the expense total.").font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        LabeledContent("Allocated", value: "Unavailable")
                        Text(allocationError ?? "Check the split amounts.").font(.footnote).foregroundStyle(MC.red)
                    }
                }
                Section {
                    Button("Use one category instead", role: .destructive) {
                        useOneCategoryAfterDismissal = true
                        dismiss()
                    }
                }
            }
            .navigationTitle("Split expense").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onDisappear {
                if useOneCategoryAfterDismissal { model.stopSplitting() }
            }
            .sheet(isPresented: Binding(get: { choosingIndex != nil }, set: { if !$0 { choosingIndex = nil } })) {
                CategoryPicker(categories: model.activeCategories, selectedID: choosingIndex.flatMap { index in model.draft.splitAllocations.indices.contains(index) ? model.draft.splitAllocations[index].categoryID : nil }) { categoryID in
                    if let index = choosingIndex, model.draft.splitAllocations.indices.contains(index) {
                        model.draft.splitAllocations[index].categoryID = categoryID
                    }
                    choosingIndex = nil
                }
            }
        }
    }
}
