import SwiftUI

struct EntryView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 52.0
    private enum Field: Hashable { case text, note }
    @FocusState private var focusedField: Field?
    @State private var message: String?
    @State private var showDate = false
    @State private var showCategories = false
    @State private var showDiscard = false
    @State private var selectionTick = 0
    private var amount: Int64 { (try? Money.parse(model.draft.amount)) ?? 0 }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            modePicker
                            if model.draft.mode == .text { textEntry }
                            amountDisplay
                            CategoryStrip(categories: model.categories, selectedID: model.draft.categoryID, select: selectCategory) {
                                focusedField = nil
                                showCategories = true
                            }
                            HStack(spacing: 10) {
                                Image(systemName: "text.alignleft").foregroundStyle(.secondary).accessibilityHidden(true)
                                TextField("Add a note (optional)", text: $model.draft.note)
                                    .font(.subheadline).submitLabel(.done).focused($focusedField, equals: .note)
                                    .onSubmit { focusedField = nil }.accessibilityIdentifier("expenseNote")
                            }.frame(minHeight: 44)
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
                    RecordButton(title: model.draft.editing ? "Save changes" : "Record expense") {
                        model.saveDraft()
                    }.accessibilityIdentifier("recordExpense")
                        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 10)
                }
            }
            .background(MC.paper)
            .navigationTitle(model.draft.editing ? "Edit expense" : "New expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: requestClose) { Image(systemName: "xmark") }.accessibilityLabel("Close entry")
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
                CategoryPicker(categories: model.categories, selectedID: model.draft.categoryID, select: selectCategory)
            }
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
                    Text(model.draft.editing ? "The saved transaction will stay unchanged." : "The amount, category and note you entered will be cleared.")
                } else { Text(model.error ?? "") }
            }
            .onChange(of: model.draft.text) { _, _ in
                if model.draft.mode == .text { parse(hideKeyboard: false) }
            }
            .sensoryFeedback(.selection, trigger: selectionTick)
            .onChange(of: model.draft.mode) { _, mode in focusedField = mode == .text ? .text : nil }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
            .interactiveDismissDisabled(model.draftNeedsConfirmation)
    }

    private var modePicker: some View {
        Picker("Entry method", selection: $model.draft.mode) {
            ForEach(EntryMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
        }.pickerStyle(.segmented).accessibilityIdentifier("entryMode")
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
                Eyebrow(text: "Amount / IDR")
                Spacer()
                Button { focusedField = nil; showDate = true } label: {
                    Label(Day.title(Day.string(model.draft.date)), systemImage: "calendar").font(.caption)
                }.tint(.secondary).frame(minHeight: 32)
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
    private func keypad(rowHeight: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 4) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9", "000", "0", "delete.left"], id: \.self) { key in
                Button {
                    if key == "delete.left" {
                        if !model.draft.amount.isEmpty { model.draft.amount.removeLast() }
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
        if model.discardDraft() { model.showEntry = false }
    }
    private func parse(hideKeyboard: Bool = true) {
        do {
            let parsed = try ExpenseParser.parse(model.draft.text, categories: model.categories)
            model.draft.amount = Money.digits(parsed.amount)
            model.draft.note = parsed.note
            model.draft.categoryID = parsed.categoryID
            model.draft.source = "text"
            message = parsed.categoryID == nil ? "Amount found. Choose a category to finish." : "Ready to record. You can adjust any detail."
            if hideKeyboard { focusedField = nil }
        } catch {
            model.draft.amount = ""; model.draft.categoryID = nil
            message = error.localizedDescription
        }
    }
}
