import SwiftUI

struct EntryView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var textFocused: Bool
    @State private var message: String?
    @State private var showDate = false
    @State private var showDiscard = false
    @State private var selectionTick = 0
    private var amount: Int64 { (try? Money.parse(model.draft.amount)) ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Picker("Entry method", selection: $model.draft.mode) {
                        ForEach(EntryMode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("entryMode")
                    if model.draft.mode == .text {
                        VStack(alignment: .leading, spacing: 12) {
                            TextField("Coffee 28k", text: $model.draft.text)
                                .font(.title3).padding(16).background(MC.surface, in: RoundedRectangle(cornerRadius: 14))
                                .focused($textFocused).submitLabel(.done).onSubmit { parse() }
                                .autocorrectionDisabled().accessibilityIdentifier("expenseText")
                            Button("Done typing", systemImage: "checkmark") { parse() }
                                .font(.subheadline.weight(.semibold)).tint(MC.red).accessibilityIdentifier("parseExpense")
                            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Eyebrow(text: "Amount / IDR")
                            Spacer()
                            Button { showDate = true } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar")
                                    Text(Day.title(Day.string(model.draft.date)))
                                }.font(.caption)
                            }.tint(.secondary)
                        }
                        Text(Money.format(amount, currency: false))
                            .font(.system(size: 56, weight: .regular, design: .monospaced)).tracking(-3).lineLimit(1).minimumScaleFactor(0.4)
                            .foregroundStyle(amount == 0 ? .secondary : .primary)
                            .accessibilityLabel("Amount \(Money.format(amount))").accessibilityIdentifier("amountDisplay")
                        Rectangle().fill(MC.line).frame(height: 1)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: "Category")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(model.categories) { category in
                                let selected = model.draft.categoryID == category.id
                                Button {
                                    model.draft.categoryID = category.id; selectionTick += 1
                                } label: {
                                    VStack(spacing: 7) {
                                        Image(systemName: category.symbol).font(.system(size: 19))
                                        Text(category.name).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
                                    }.frame(maxWidth: .infinity).frame(minHeight: 70)
                                        .foregroundStyle(selected ? Color.white : Color.primary)
                                        .background(selected ? MC.ink : MC.surface, in: RoundedRectangle(cornerRadius: 13))
                                        .overlay(alignment: .topTrailing) { if selected { Circle().fill(MC.red).frame(width: 5, height: 5).padding(8) } }
                                }.buttonStyle(.plain).accessibilityLabel(category.name).accessibilityAddTraits(selected ? .isSelected : [])
                                    .accessibilityIdentifier("category-\(category.name)")
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "text.alignleft").foregroundStyle(.secondary)
                        TextField("Add a note (optional)", text: $model.draft.note)
                            .font(.subheadline).submitLabel(.done).accessibilityIdentifier("expenseNote")
                    }.padding(.vertical, 8)
                    if model.draft.mode == .keypad {
                        keypad
                    } else {
                        Text("Check the amount and category above. Switch to Keypad to adjust the amount.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 24).padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(MC.paper)
            .navigationTitle(model.draft.editing ? "Edit expense" : "New expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button { model.persistDraft(); dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close entry") }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Discard draft", systemImage: "trash", role: .destructive) { showDiscard = true }
                    } label: { Image(systemName: "ellipsis") }.accessibilityLabel("Draft options")
                }
            }
            .safeAreaInset(edge: .bottom) {
                RecordButton(title: model.draft.editing ? "Save changes" : "Record expense") {
                    model.saveDraft()
                    if !model.showEntry { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                }.accessibilityIdentifier("recordExpense").padding(.horizontal, 24).padding(.vertical, 10).background(MC.paper)
            }
            .sheet(isPresented: $showDate) {
                NavigationStack {
                    DatePicker("Expense date", selection: $model.draft.date, displayedComponents: .date)
                        .datePickerStyle(.graphical).padding()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showDate = false } } }
                }.presentationDetents([.medium])
            }
            .confirmationDialog("Discard this unfinished expense?", isPresented: $showDiscard, titleVisibility: .visible) {
                Button("Discard draft", role: .destructive) { model.discardDraft(); dismiss() }
            }
            .alert("Check this", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
            .onChange(of: model.draft.text) { _, _ in
                if model.draft.mode == .text { parse(hideKeyboard: false) }
            }
            .sensoryFeedback(.selection, trigger: selectionTick)
            .onChange(of: model.draft.mode) { _, mode in textFocused = mode == .text }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
    }

    private var keypad: some View {
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
                    }.frame(maxWidth: .infinity).frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(key == "delete.left" ? "Delete digit" : key)
                    .accessibilityIdentifier("key-\(key)")
            }
        }
    }
    private func parse(hideKeyboard: Bool = true) {
        do {
            let parsed = try ExpenseParser.parse(model.draft.text, categories: model.categories)
            model.draft.amount = Money.digits(parsed.amount)
            model.draft.note = parsed.note
            model.draft.categoryID = parsed.categoryID
            model.draft.source = "text"
            message = parsed.categoryID == nil ? "Amount found. Choose a category to finish." : "Ready to record. You can adjust any detail."
            if hideKeyboard { textFocused = false }
        } catch {
            // Do not leave a previous successful interpretation recordable after invalid text edits.
            model.draft.amount = ""; model.draft.categoryID = nil
            message = error.localizedDescription
        }
    }
}
