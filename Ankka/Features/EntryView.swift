import SwiftUI
import UIKit

struct EntryView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 60.0
    @ScaledMetric(relativeTo: .title) private var keyHeight = 56.0
    private enum Field: Hashable { case note }
    @FocusState private var focusedField: Field?
    @State private var keyboardUp = false
    @State private var showDate = false
    @State private var showCategories = false
    @State private var showSplits = false
    @State private var showDiscard = false
    @State private var showRate = false
    @State private var selectionTick = 0
    private var amount: Int64 { (try? model.draft.resolvedAmount()) ?? 0 }
    // A hidden field still shows when the expense already has a value for it.
    private var showsDate: Bool { model.isEntryFieldShown(.date) || model.draft.civilDay != Day.string(.now) }
    private var showsNote: Bool { model.isEntryFieldShown(.note) || !model.draft.note.isEmpty }
    private var showsSplit: Bool { model.isEntryFieldShown(.split) || model.draft.isSplit }
    private var draftCurrency: String { model.draft.currency ?? model.reportingCurrency }
    private var showsPaidWith: Bool {
        (model.isEntryFieldShown(.paidWith) && !model.paymentMethods.isEmpty) || model.paymentMethod(model.draft.paidWithID) != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
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
                // Fixed row height (clamped so accessibility sizes can't starve the form), and only once the keyboard is gone: sizing it from the sheet's height, or inserting
                // it while the keyboard was still sliding down, squeezed the form to nothing and Record overlapped its last row.
                if focusedField == nil && !keyboardUp {
                    keypad(rowHeight: min(max(keyHeight, 44), 64))
                        .padding(.horizontal, 24).padding(.top, 12)
                        .transition(.opacity)
                }
                // Hidden while the keyboard is up, where the checkmark in the top bar takes its place.
                if !keyboardUp {
                    RecordButton(
                        title: model.draft.editing ? "Save changes" : "Add expense",
                        symbol: model.draft.editing ? "checkmark" : "plus"
                    ) { save() }.accessibilityIdentifier("recordExpense")
                        .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 10)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: keyboardUp)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardUp = true }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in keyboardUp = false }
            .background(MC.paper)
            .navigationTitle(model.draft.editing ? "Edit expense" : "New expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: requestClose) { Image(systemName: "xmark") }
                        .accessibilityLabel("Close entry")
                        .accessibilityIdentifier("closeEntry")
                }
                // Add expense is hidden under the keyboard, so the bar offers the same save until it goes away.
                if keyboardUp {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm, action: save) { Image(systemName: "checkmark") }
                            .accessibilityLabel(model.draft.editing ? "Save changes" : "Add expense")
                            .accessibilityIdentifier("recordExpenseFromBar")
                    }
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
            .sheet(isPresented: $showRate) { rateEditor }
            .sheet(isPresented: $showCategories) {
                CategoryPicker(categories: model.activeCategories, selectedID: model.draft.categoryID, select: selectCategory)
            }
            .sheet(isPresented: $showSplits) { SplitEditor(model: model).scrollEdgeEffectStyle(.soft, for: .all) }
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
            .sensoryFeedback(.selection, trigger: selectionTick)
            .onAppear {
                model.prefillDraftDefaults()
            }
            .task(id: "\(model.draft.currency ?? "")|\(model.draft.civilDay)") { await model.refreshDraftRate() }
        }.presentationDetents([.large]).presentationDragIndicator(.visible)
            .interactiveDismissDisabled(model.draftNeedsConfirmation)
    }

    private var amountDisplay: some View {
        VStack(spacing: 6) {
            currencyMenu
            Text(Money.format(amount, currency: false))
                // A fixed height: the shrunk glyphs of a long amount would otherwise shorten the row and shift everything below it.
                .font(.system(size: amountSize, weight: .bold)).tracking(-2).lineLimit(1).minimumScaleFactor(0.4)
                .frame(maxWidth: .infinity).frame(height: amountSize * 1.2)
                .foregroundStyle(amount == 0 ? .secondary : .primary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy(duration: 0.18), value: amount)
                .accessibilityLabel("Amount \(Money.format(amount, code: draftCurrency))").accessibilityIdentifier("amountDisplay")
            if model.draft.isForeign(reporting: model.reportingCurrency) { conversionLine }
            detailPills.padding(.top, 6)
        }.frame(maxWidth: .infinity)
    }
    /// Where, when and how it was paid, as one row of pills under the amount; two lines when they don't fit.
    private var detailPills: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { cardPill; datePill; paidWithPill }
            VStack(spacing: 8) {
                HStack(spacing: 8) { cardPill; datePill }
                paidWithPill
            }
        }
    }
    private var draftCard: Card? { model.cards.first { $0.id == (model.draft.cardID ?? model.activeCardID) } }
    /// Cards an expense can move to: the ones not hidden, plus the draft's own if it is.
    private var cardChoices: [Card] { model.unhiddenCards.contains { $0.id == draftCard?.id } ? model.unhiddenCards : model.unhiddenCards + [draftCard].compactMap { $0 } }
    /// The card the expense goes to. Tap to move what's typed to another card; a saved expense keeps its card.
    @ViewBuilder private var cardPill: some View {
        let label = DetailPill(text: draftCard?.name ?? "Card", chevron: !model.draft.editing && cardChoices.count > 1) {
            Circle().fill(draftCard.map(model.cardColor) ?? .secondary).frame(width: 10, height: 10)
        }
        if model.draft.editing || cardChoices.count < 2 {
            label.accessibilityLabel("Card \(draftCard?.name ?? "")").accessibilityIdentifier("entryCard")
        } else {
            Menu {
                Picker("Card", selection: Binding(get: { model.draft.cardID ?? model.activeCardID }, set: { model.moveDraft(to: $0) })) {
                    ForEach(cardChoices) { Text($0.name).tag($0.id) }
                }
            } label: { label }
            .tint(.primary)
            .accessibilityLabel("Card \(draftCard?.name ?? "")").accessibilityIdentifier("entryCard")
        }
    }
    @ViewBuilder private var datePill: some View {
        if showsDate {
            Button { focusedField = nil; showDate = true } label: {
                DetailPill(text: Day.title(model.draft.civilDay), chevron: false) { Image(systemName: "calendar").foregroundStyle(.secondary) }
            }
            .buttonStyle(.plain).accessibilityIdentifier("entryDate")
        }
    }
    @ViewBuilder private var paidWithPill: some View {
        if showsPaidWith {
            let method = model.paymentMethod(model.draft.paidWithID)
            Menu {
                Picker("Paid with", selection: $model.draft.paidWithID) {
                    Text("Not set").tag(UUID?.none)
                    ForEach(model.paymentMethods) { method in Label(method.name, systemImage: method.kind.symbol).tag(UUID?.some(method.id)) }
                }
            } label: {
                DetailPill(text: method?.name ?? "Paid with", chevron: true, dimmed: method == nil) {
                    Image(systemName: method?.kind.symbol ?? "creditcard").foregroundStyle(.secondary)
                }
            }
            .tint(.primary)
            .accessibilityLabel("Paid with \(method?.name ?? "not set")").accessibilityIdentifier("paidWithMenu")
        }
    }
    /// The currency the amount is typed in; any card can record in any currency.
    private var currencyMenu: some View {
        Menu {
            Picker("Currency", selection: Binding(get: { draftCurrency }, set: { code in
                // Spending in another currency is Pro: say so on the pick, not after the amount and rate are in.
                if code != model.reportingCurrency, !model.requirePro(PlanError.foreignCurrency.localizedDescription) { return }
                model.draft.currency = code == model.reportingCurrency ? nil : code
                model.draft.rate = ""; model.draft.rateSource = nil
            })) {
                ForEach(currencyChoices, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            HStack(spacing: 5) {
                Eyebrow(text: draftCurrency)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .tint(.primary)
        .accessibilityLabel("Currency \(draftCurrency)").accessibilityIdentifier("currencyMenu")
    }
    private var rateText: String {
        guard let value = Decimal(string: model.draft.rate, locale: Locale(identifier: "en_US_POSIX")) else { return model.draft.rate }
        return value.formatted(.number.precision(.significantDigits(1...5)))
    }
    /// What the amount comes to in the reporting currency, and the rate behind it. Tap to type a rate.
    private var conversionLine: some View {
        Button { focusedField = nil; showRate = true } label: {
            HStack(spacing: 6) {
                if let equivalent = model.draft.reportingEquivalent(reporting: model.reportingCurrency) {
                    Text("≈ \(Money.format(equivalent, code: model.reportingCurrency))").fontWeight(.semibold).foregroundStyle(.primary)
                    Text("·  1 \(draftCurrency) = \(rateText) \(model.reportingCurrency)").foregroundStyle(.secondary)
                } else if let rateError = model.rateError {
                    Text(rateError).foregroundStyle(MC.red).lineLimit(1)
                } else {
                    Text("Getting the rate…").foregroundStyle(.secondary)
                }
                Image(systemName: "pencil").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            }
            .font(.footnote).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            .frame(minHeight: 32)
        }
        .buttonStyle(.plain).accessibilityIdentifier("conversionLine")
    }
    private var rateEditor: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 8) {
                        Text("1 \(draftCurrency) =").foregroundStyle(.secondary)
                        TextField("Rate", text: Binding(get: { model.draft.rate }, set: { model.draft.rate = $0; model.draft.rateSource = .manual }))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("rateField")
                        Text(model.reportingCurrency).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(model.draft.rateSource == .manual
                         ? "You typed this rate. It is kept with the expense."
                         : "Fetched for the expense's date. Type your bank's rate to use it instead.")
                }
                if model.draft.rateSource == .manual {
                    Button("Use the fetched rate") {
                        model.draft.rateSource = nil
                        Task { await model.refreshDraftRate() }
                    }
                }
            }
            .navigationTitle("Exchange rate").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showRate = false } } }
        }.presentationDetents([.height(250)])
    }
    private var currencyChoices: [String] {
        var codes = [model.reportingCurrency]
        for card in model.cards { codes += [card.currency, card.spendingCurrency].compactMap { $0 } }
        codes += Money.commonCurrencies
        var seen = Set<String>()
        return codes.filter { seen.insert($0).inserted }
    }
    private var splitSummary: some View {
        Button {
            focusedField = nil
            showSplits = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2").foregroundStyle(MC.red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Split across \(model.draft.splitParts.count) \(model.draft.splitParts.count == 1 ? "category" : "categories")").font(.subheadline.weight(.semibold))
                    Text("Edit allocations").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }.padding(14).background(MC.surface, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityIdentifier("editSplits")
    }
    private func keypad(rowHeight: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 10) {
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
                        else { Text(key == "." ? (Locale.current.decimalSeparator ?? ".") : key).font(.system(size: key == "000" ? 21 : 29, weight: .regular)) }
                    }.frame(maxWidth: .infinity).frame(height: rowHeight).contentShape(Rectangle())
                }.buttonStyle(PressFeedbackStyle()).accessibilityLabel(key == "delete.left" ? "Delete digit" : key)
                    .accessibilityIdentifier("key-\(key)")
            }
        }
    }
    private func save() {
        if model.saveDraft() { dismiss() }
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
}

private struct SplitEditor: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// What the expense looked like when the sheet opened, so Cancel can put it back.
    @State private var original: (parts: [DraftSplit], categoryID: UUID?)?
    @State private var cancelled = false
    @State private var adding = false
    @State private var changingID: UUID?
    /// The row that quietly takes whatever is left, until it is typed into.
    @State private var balancingID: UUID?
    @FocusState private var focusedID: UUID?

    private var parts: [DraftSplit] { model.draft.splitParts }
    private var code: String { model.draft.currency ?? model.reportingCurrency }
    private var total: Int64 { (try? model.draft.resolvedAmount()) ?? 0 }
    private var allocated: Int64? { try? model.draft.resolvedAllocatedAmount() }
    private var remaining: Int64? { allocated.map { total - $0 } }
    private var usedIDs: Set<UUID> { Set(parts.map(\.categoryID)) }
    private var isReady: Bool {
        remaining == 0 && parts.count > 1 && usedIDs.count == parts.count
            && parts.allSatisfy { ((try? $0.resolvedAmount(code: model.draft.currency)) ?? 0) > 0 }
    }
    private static let hues: [Color] = [MC.red, .orange, .blue, .green, .purple, .teal, .pink, .yellow]
    private func hue(_ index: Int) -> Color { Self.hues[index % Self.hues.count] }

    var body: some View {
        NavigationStack {
            List {
                Section { summary }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                Section {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                        row(part, index: index)
                    }
                    .onDelete { offsets in
                        let removed = offsets.map { parts[$0].id }
                        withAnimation(reduceMotion ? nil : .snappy) { model.draft.splitParts.remove(atOffsets: offsets) }
                        if let balancingID, removed.contains(balancingID) { self.balancingID = nil }
                        rebalance()
                    }
                    Button { focusedID = nil; adding = true } label: {
                        Label("Add category", systemImage: "plus.circle.fill").font(.body.weight(.medium))
                    }
                    .disabled(usedIDs.count >= model.activeCategories.count)
                    .accessibilityIdentifier("addSplit")
                } footer: {
                    Text(parts.count < 2 ? "Add another category to split this expense. Swipe a row to remove it."
                         : usedIDs.count < parts.count ? "Each category can appear once." : "Swipe a row to remove it.")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Split expense").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") {
                        cancelled = true
                        if let original { model.draft.splitParts = original.parts; model.draft.categoryID = original.categoryID }
                        // Opening the sheet started a one-row split; cancelling it leaves a plain category.
                        if model.draft.splitParts.count == 1 { model.stopSplitting() }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("Split evenly", systemImage: "equal.circle") { splitEvenly() }.disabled(parts.count < 2 || total <= 0)
                        Button("Don't split", systemImage: "arrow.uturn.backward", role: .destructive) { dismiss() ; model.stopSplitting() }
                    } label: { Image(systemName: "ellipsis") }
                        .accessibilityLabel("Split options").accessibilityIdentifier("splitOptions")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("Done")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    if let focusedID, let remaining, remaining != 0, let index = parts.firstIndex(where: { $0.id == focusedID }),
                       let current = try? parts[index].resolvedAmount(code: model.draft.currency), current + remaining >= 0 {
                        Button("Use \(Money.format(current + remaining, code: code))") {
                            if focusedID == balancingID { balancingID = nil }
                            model.draft.splitParts[index].amount = Money.format(current + remaining, currency: false)
                            model.draft.splitParts[index].preservedAmount = nil
                        }
                    }
                    Spacer()
                }
            }
            .sheet(isPresented: $adding) {
                CategoryPicker(categories: model.activeCategories.filter { !usedIDs.contains($0.id) }, selectedID: nil) { id in
                    let left = max(remaining ?? 0, 0)
                    withAnimation(reduceMotion ? nil : .snappy) {
                        model.draft.splitParts.append(.init(categoryID: id, amount: left > 0 ? Money.format(left, currency: false) : ""))
                    }
                }
            }
            .sheet(isPresented: Binding(get: { changingID != nil }, set: { if !$0 { changingID = nil } })) {
                let index = parts.firstIndex { $0.id == changingID }
                CategoryPicker(categories: model.activeCategories.filter { !usedIDs.contains($0.id) || $0.id == index.map { parts[$0].categoryID } },
                               selectedID: index.map { parts[$0].categoryID }) { id in
                    if let index { model.draft.splitParts[index].categoryID = id }
                }
            }
        }
        .onAppear {
            if original == nil {
                original = (parts, model.draft.categoryID)
                // A fresh split starts with the whole amount on its first row; that row keeps the balance.
                if parts.count == 1 { balancingID = parts.first?.id }
            }
        }
        .onChange(of: parts.map(\.amount)) { _, _ in rebalance() }
        // Done, a swipe down or Don't split: one category left is just a category again.
        .onDisappear { if !cancelled && model.draft.splitParts.count == 1 { model.stopSplitting() } }
    }

    private var summary: some View {
        VStack(spacing: 12) {
            Text(Money.format(total, code: code))
                .font(.system(size: 40, weight: .bold)).monospacedDigit()
                .contentTransition(.numericText())
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(Array(parts.enumerated()), id: \.element.id) { index, part in
                        let value = max((try? part.resolvedAmount(code: model.draft.currency)) ?? 0, 0)
                        let share = total > 0 ? min(Double(value) / Double(total), 1) : 0
                        Capsule().fill(hue(index)).frame(width: max(0, (proxy.size.width - CGFloat(parts.count) * 3) * share))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.18), in: Capsule())
            }
            .frame(height: 10)
            .animation(reduceMotion ? nil : .snappy, value: parts.map(\.amount))
            status.font(.subheadline.weight(.medium)).accessibilityIdentifier("splitStatus")
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
    }

    @ViewBuilder private var status: some View {
        if let remaining {
            if remaining > 0 {
                Text("\(Money.format(remaining, code: code)) left to assign").foregroundStyle(.secondary)
            } else if remaining < 0 {
                Text("\(Money.format(-remaining, code: code)) over the total").foregroundStyle(MC.red)
            } else if isReady {
                Label("Balanced", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text(parts.count < 2 ? "Add a second category" : usedIDs.count < parts.count ? "Each category can appear once" : "Give each category an amount")
                    .foregroundStyle(.secondary)
            }
        } else {
            Text("Check the amounts").foregroundStyle(MC.red)
        }
    }

    private func row(_ part: DraftSplit, index: Int) -> some View {
        let category = model.category(part.categoryID)
        return HStack(spacing: 12) {
            Capsule().fill(hue(index)).frame(width: 4, height: 34)
            Button { focusedID = nil; changingID = part.id } label: {
                HStack(spacing: 10) {
                    Image(systemName: category?.symbol ?? "square.grid.2x2").font(.body).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category?.name ?? "Choose category").font(.body.weight(.medium)).lineLimit(1)
                        if part.id == balancingID && parts.count > 1 {
                            Text("Takes what's left").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("split-category-\(index)")
            Spacer(minLength: 8)
            TextField("0", text: Binding(get: {
                // A kept historical amount is stored as exact digits; show it the way it is typed.
                if let kept = part.preservedAmount, part.amount == Money.exactDigits(kept) { return Money.format(kept, currency: false) }
                return Money.groupedInput(part.amount, code: model.draft.currency)
            }, set: { value in
                guard let i = model.draft.splitParts.firstIndex(where: { $0.id == part.id }) else { return }
                if part.id == balancingID { balancingID = nil }
                model.draft.splitParts[i].amount = Money.groupedInput(value, code: model.draft.currency)
            }))
            .multilineTextAlignment(.trailing)
            .keyboardType(Money.fractionDigits(code) > 0 ? .decimalPad : .numberPad)
            .font(.title3.weight(.semibold)).monospacedDigit()
            .frame(maxWidth: 150)
            .focused($focusedID, equals: part.id)
            .accessibilityLabel("\(category?.name ?? "Category") amount")
            .accessibilityIdentifier("split-amount-\(index)")
        }
        .padding(.vertical, 4)
    }

    /// Keeps the balancing row at the total minus the others, while that is not negative.
    private func rebalance() {
        guard let balancingID, let index = parts.firstIndex(where: { $0.id == balancingID }) else { return }
        let others = parts.enumerated().filter { $0.offset != index }
            .reduce(Int64(0)) { $0 + ((try? $1.element.resolvedAmount(code: model.draft.currency)) ?? 0) }
        let value = max(total - others, 0)
        let digits = value > 0 ? Money.format(value, currency: false) : ""
        if model.draft.splitParts[index].amount != digits {
            model.draft.splitParts[index].amount = digits
            model.draft.splitParts[index].preservedAmount = nil
        }
    }

    /// Equal shares in the currency's smallest typed unit (cents, or whole yen and rupiah); leftovers go to the first rows.
    private func splitEvenly() {
        guard parts.count > 1, total > 0 else { return }
        balancingID = nil
        let unit: Int64 = Money.fractionDigits(code) > 0 ? 1 : 100
        let count = Int64(parts.count), units = total / unit
        let share = units / count, extra = units % count
        for index in model.draft.splitParts.indices {
            let value = (share + (Int64(index) < extra ? 1 : 0)) * unit + (index == 0 ? total % unit : 0)
            model.draft.splitParts[index].amount = Money.format(value, currency: false)
            model.draft.splitParts[index].preservedAmount = nil
        }
    }
}

/// One of Add Expense's detail pills: icon, text, optional chevron, in the same capsule as the currency pill.
private struct DetailPill<Icon: View>: View {
    let text: String
    let chevron: Bool
    var dimmed = false
    @ViewBuilder let icon: Icon

    var body: some View {
        HStack(spacing: 6) {
            icon
            Text(text).foregroundStyle(dimmed ? .secondary : .primary).lineLimit(1)
            if chevron { Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary) }
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 12).frame(minHeight: 34)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .contentShape(Capsule())
    }
}
