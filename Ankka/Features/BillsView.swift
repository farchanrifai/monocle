import SwiftUI

/// One card's bills, laid out like Budgets: the answer in plain words, then what needs you, what's coming and every bill.
struct BillsView: View {
    @Bindable var model: AppModel
    @State private var editingRule: Bill?
    @State private var isCreating = false
    @State private var showsAllHistory = false
    /// nil: the active card when it has bills, else the first card that does.
    @State private var picked: UUID?

    private var today: String { Day.string(.now) }
    private var cardID: UUID {
        if let picked { return picked }
        let visible = model.unhiddenCards
        if visible.contains(where: { $0.id == model.activeCardID }), !model.bills.isEmpty { return model.activeCardID }
        return visible.first { !model.bills(for: $0.id).isEmpty }?.id ?? model.activeCardID
    }
    private var currency: String { model.currency(ofCard: cardID) }
    private var bills: [Bill] { model.bills(for: cardID) }
    private var occurrences: [BillOccurrence] { model.billOccurrences(for: cardID) }
    private var rules: [Bill] { bills.filter(\.isActive) + bills.filter { !$0.isActive } }
    private var rulesByID: [UUID: Bill] { Dictionary(uniqueKeysWithValues: bills.map { ($0.id, $0) }) }
    private var due: [BillOccurrence] {
        occurrences.filter { $0.status == .pending && $0.dueDay <= today }.sorted { $0.dueDay < $1.dueDay }
    }
    private var upcoming: [BillOccurrence] {
        occurrences.filter { $0.status == .pending && $0.dueDay > today }.sorted { $0.dueDay < $1.dueDay }
    }
    private var history: [BillOccurrence] {
        occurrences.filter { $0.status != .pending }.sorted { $0.dueDay > $1.dueDay }
    }

    /// What the running bills come to in an average month; nil when the sum overflows.
    private var monthly: Int64? {
        try? Money.checkedSum(rules.filter(\.isActive).map { rule in
            switch rule.recurrence {
            case .monthly: rule.amount
            case .weekly: try Money.checkedScale(rule.amount, numerator: 52, denominator: 12)
            case .yearly: rule.amount / 12
            }
        })
    }

    var body: some View {
        // Bills are read from the store, which views don't observe; the committed revision changes with every save.
        let _ = model.dataRevision
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if rules.isEmpty { empty } else { headline }
                if let status = model.billReminderStatus {
                    Text(status).font(.footnote).foregroundStyle(MC.red).padding(.horizontal, 4)
                }
                if !due.isEmpty {
                    section("Due") {
                        panel(padded: false) { rows(due) { dueRow($0) } }
                    }
                }
                if !upcoming.isEmpty {
                    section("Next 30 days") {
                        panel(padded: false) { rows(upcoming) { upcomingRow($0) } }
                    }
                }
                if !rules.isEmpty {
                    section("All bills") {
                        panel(padded: false) { rows(rules) { billRow($0) } }
                    }
                }
                if !history.isEmpty {
                    section("History") {
                        panel(padded: false) {
                            rows(Array(history.prefix(showsAllHistory ? 50 : 5))) { historyRow($0) }
                            if history.count > 5 {
                                Divider().padding(.leading, 16)
                                Button(showsAllHistory ? "Show less" : "Show all \(min(history.count, 50))") {
                                    withAnimation(.smooth) { showsAllHistory.toggle() }
                                }
                                .font(.system(size: 13.5, weight: .semibold)).tint(.primary)
                                .frame(maxWidth: .infinity).frame(height: 48)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 32)
        }
        .background(MC.paper)
        .navigationTitle("Bills").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add bill", systemImage: "plus") { isCreating = true }
                    .tint(.primary) // toolbar icons are black, like Home's
                    .accessibilityIdentifier("addBillButton")
            }
        }
        .onChange(of: cardID) { showsAllHistory = false }
        .sheet(isPresented: $isCreating) {
            BillEditor(model: model, existingRule: nil, card: cardID).scrollEdgeEffectStyle(.soft, for: .all)
        }
        .sheet(item: $editingRule) { rule in
            BillEditor(model: model, existingRule: rule).scrollEdgeEffectStyle(.soft, for: .all)
        }
    }

    /// Which card's bills, in the Budgets pill style.
    private var cardPill: some View {
        let name = model.cards.first { $0.id == cardID }?.name ?? "Card"
        return Menu {
            ForEach(model.unhiddenCards) { card in
                Button { picked = card.id } label: {
                    let count = model.bills(for: card.id).count
                    if card.id == cardID { Label(card.name, systemImage: "checkmark") } else { Text(card.name) }
                    Text(count == 0 ? "No bills" : "\(count) \(count == 1 ? "bill" : "bills")")
                }
            }
        } label: {
            HStack(spacing: 5) {
                Eyebrow(text: name).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: Capsule())
        }
        .tint(.primary)
        .padding(.leading, -10) // the pill's text lines up with the headline
        .accessibilityLabel("Bills for \(name)")
        .accessibilityIdentifier("billsCardMenu")
    }

    /// The answer first: what bills cost a month, how many there are, and what comes next.
    private var headline: some View {
        let running = rules.filter(\.isActive).count
        let next = upcoming.first.flatMap { occurrence in rulesByID[occurrence.billRuleID].map { ($0.name, occurrence.dueDay) } }
        var detail = "\(running) \(running == 1 ? "bill" : "bills")"
        if let next { detail += " · next \(next.0), \(Day.title(next.1))" }
        return VStack(alignment: .leading, spacing: 8) {
            cardPill
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(monthly.map { Money.format($0, code: currency) } ?? "Too large to add up")
                    .font(.system(size: 44, weight: .semibold)).tracking(-1).monospacedDigit()
                    .minimumScaleFactor(0.5).lineLimit(1)
                if monthly != nil { Text("a month").font(.title3.weight(.medium)).foregroundStyle(.secondary) }
            }
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
            if !due.isEmpty {
                Text("\(due.count) waiting for you to add or skip").font(.subheadline.weight(.medium)).foregroundStyle(MC.red)
            }
        }
        .padding(.horizontal, 4).padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    /// No bills yet: what bills do, and the way to add one.
    @ViewBuilder private var empty: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardPill
            Text("No bills yet").font(.system(size: 34, weight: .semibold)).tracking(-0.8)
        }
        .padding(.horizontal, 4).padding(.top, 8)
        panel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 15, weight: .semibold)).foregroundStyle(MC.red)
                    .frame(width: 34, height: 34).background(MC.red.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Add rent, subscriptions and utilities").font(.system(size: 14, weight: .semibold))
                        Text("Ankka reminds you when one is due, then adds it as an expense, by itself or when you say so.")
                            .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Add a bill") { isCreating = true }
                        .buttonStyle(.borderedProminent).tint(MC.red).controlSize(.small)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Rows

    private func dueRow(_ occurrence: BillOccurrence) -> some View {
        let rule = rulesByID[occurrence.billRuleID]
        let overdue = occurrence.dueDay < today
        return VStack(alignment: .leading, spacing: 12) {
            line(rule?.name ?? "Bill", overdue ? "Overdue since \(Day.title(occurrence.dueDay))" : "Due today",
                 amount: rule?.amount ?? 0, detailColor: overdue ? MC.red : nil)
            HStack(spacing: 8) {
                Button("Add") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    model.performUIAction { _ = try model.confirmBillOccurrence(occurrence.id, in: cardID) }
                }
                .buttonStyle(.borderedProminent).tint(MC.red).controlSize(.small)
                .accessibilityIdentifier("confirmBillButton_\(rule?.name ?? "")")
                Button("Skip") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    model.performUIAction { try model.skipBillOccurrence(occurrence.id, in: cardID) }
                }
                .buttonStyle(.bordered).tint(.secondary).controlSize(.small)
                .accessibilityIdentifier("skipBillButton_\(rule?.name ?? "")")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
    }

    private func upcomingRow(_ occurrence: BillOccurrence) -> some View {
        let rule = rulesByID[occurrence.billRuleID]
        let automatic = rule?.recordingMode == .automatic
        return Button { editingRule = rule } label: {
            line(rule?.name ?? "Bill", "\(Day.title(occurrence.dueDay)) · \(automatic ? "adds itself" : "asks first")", amount: rule?.amount ?? 0)
                .padding(.horizontal, 16).frame(minHeight: 58)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Add now", systemImage: "plus") { model.performUIAction { _ = try model.confirmBillOccurrence(occurrence.id, in: cardID) } }
            Button("Skip this one", systemImage: "forward") { model.performUIAction { try model.skipBillOccurrence(occurrence.id, in: cardID) } }
        }
    }

    private func billRow(_ rule: Bill) -> some View {
        let how = rule.isActive ? (rule.recordingMode == .automatic ? "Adds itself" : "Asks first") : "Paused"
        return Button { editingRule = rule } label: {
            HStack(spacing: 10) {
                line(rule.name, "\(rule.recurrence.title) · \(how)", amount: rule.amount, dimmed: !rule.isActive)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).frame(minHeight: 58)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("scheduledBill_\(rule.name)")
    }

    private func historyRow(_ occurrence: BillOccurrence) -> some View {
        let rule = rulesByID[occurrence.billRuleID]
        let added = occurrence.status == .recorded
        return line(rule?.name ?? "Bill", "\(Day.title(occurrence.dueDay)) · \(added ? "Added" : "Skipped")",
                    amount: rule?.amount ?? 0, dimmed: !added)
            .padding(.horizontal, 16).frame(minHeight: 58)
    }

    /// Home's expense row: name over a detail line, amount on the right.
    private func line(_ title: String, _ detail: String, amount: Int64, detailColor: Color? = nil, dimmed: Bool = false) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2.5) {
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 11.5)).foregroundStyle(detailColor ?? .secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(Money.format(amount, code: currency)).font(.system(size: 13.5, weight: .semibold)).monospacedDigit()
        }
        .foregroundStyle(dimmed ? .secondary : .primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: Layout

    /// Rows in one panel, divided like Settings.
    private func rows<Item: Identifiable, Row: View>(_ items: [Item], @ViewBuilder row: @escaping (Item) -> Row) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Divider().padding(.leading, 16) }
                row(item)
            }
        }
    }

    /// Home's surface: a white panel with 24 pt corners.
    private func panel(padded: Bool = true, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0) { content() }
            .padding(padded ? 16 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MC.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// Home's section style: a 15 pt title over its panel.
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 15, weight: .semibold)).accessibilityAddTraits(.isHeader).padding(.leading, 4)
            content()
        }
    }
}

struct BillEditor: View {
    let model: AppModel
    let existingRule: Bill?
    /// A new bill's starting values: name, amount, category, card and day of an expense.
    var template: Expense? = nil
    /// The card a new bill goes on; the active card when nil.
    var card: UUID? = nil
    @Environment(\.dismiss) private var dismiss

    private enum FocusedField: Hashable {
        case name, amount
    }

    @FocusState private var focusedField: FocusedField?
    @State private var name = ""
    @State private var amountText = ""
    @State private var selectedCategoryID: UUID?
    @State private var recurrenceKind: Int = 0 // 0 = Monthly, 1 = Weekly, 2 = Yearly
    @State private var monthlyDay: Int = 1
    @State private var weeklyWeekday: Int = 2 // Monday (1=Sun, 2=Mon)
    @State private var yearlyMonth: Int = 1
    @State private var yearlyDay: Int = 1
    @State private var recordingMode: BillRecordingMode = .pending
    @State private var hasReminder = true
    @State private var reminderLeadDays: Int = 0
    @State private var isPaused = false
    @State private var confirmDelete = false
    @State private var error: String?

    var isEditing: Bool { existingRule != nil }
    private var cardID: UUID { existingRule?.cardID ?? template?.cardID ?? card ?? model.activeCardID }
    private var currency: String { model.currency(ofCard: cardID) }
    private var categories: [ExpenseCategory] { model.activeCategories(for: cardID) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, like Rent or Netflix", text: $name)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("billNameField")
                    HStack {
                        Text(Money.symbol(currency)).foregroundStyle(.secondary)
                        TextField("Amount", text: $amountText.groupedAmount(code: currency))
                            .keyboardType(Money.fractionDigits(currency) > 0 ? .decimalPad : .numberPad)
                            .focused($focusedField, equals: .amount)
                            .accessibilityIdentifier("billAmountField")
                    }
                    Picker("Category", selection: Binding(
                        get: { selectedCategoryID ?? categories.first?.id ?? UUID() },
                        set: { selectedCategoryID = $0 }
                    )) {
                        ForEach(categories) { Label($0.name, systemImage: $0.symbol).tag($0.id) }
                    }
                    .accessibilityIdentifier("billCategoryPicker")
                }

                Section {
                    Picker("Repeats", selection: $recurrenceKind) {
                        Text("Every month").tag(0)
                        Text("Every week").tag(1)
                        Text("Every year").tag(2)
                    }
                    .accessibilityIdentifier("billRecurrencePicker")
                    switch recurrenceKind {
                    case 0:
                        Picker("On day", selection: $monthlyDay) {
                            ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                        }
                    case 1:
                        Picker("On", selection: $weeklyWeekday) {
                            ForEach(1...7, id: \.self) { Text(Day.calendar.weekdaySymbols[$0 - 1]).tag($0) }
                        }
                    default:
                        Picker("Month", selection: $yearlyMonth) {
                            ForEach(1...12, id: \.self) { Text(Day.calendar.monthSymbols[$0 - 1]).tag($0) }
                        }
                        Picker("Day", selection: $yearlyDay) {
                            ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
                        }
                    }
                } footer: {
                    if recurrenceKind != 1 && (recurrenceKind == 0 ? monthlyDay : yearlyDay) > 28 {
                        Text("In a shorter month, it's due on the last day.")
                    }
                }

                Section {
                    Toggle("Add by itself", isOn: Binding(
                        get: { recordingMode == .automatic },
                        set: { recordingMode = $0 ? .automatic : .pending }
                    ))
                    .accessibilityIdentifier("billModePicker")
                } footer: {
                    Text(recordingMode == .automatic
                         ? "On the due day, Ankka adds it as an expense."
                         : "On the due day, it waits under Due on the Bills page until you add or skip it. It counts as spending once added.")
                }

                Section {
                    Toggle("Remind me", isOn: $hasReminder)
                        .accessibilityIdentifier("billReminderToggle")
                    if hasReminder {
                        Picker("When", selection: $reminderLeadDays) {
                            Text("On the day, 9:00").tag(0)
                            Text("1 day before").tag(1)
                            Text("2 days before").tag(2)
                            Text("3 days before").tag(3)
                            Text("A week before").tag(7)
                        }
                    }
                }

                if isEditing {
                    Section {
                        Toggle("Pause", isOn: $isPaused)
                            .accessibilityIdentifier("billPauseToggle")
                    } footer: {
                        Text(isPaused
                             ? "Nothing is due and no reminders come while it's paused. Resuming starts from that day; missed dates aren't added."
                             : "Stops the bill without deleting it.")
                    }
                    Section {
                        Button("Delete bill", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("deleteBillButton")
                    }
                }

                if let error {
                    Section { Text(error).foregroundStyle(MC.red) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit bill" : "New bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                        .accessibilityIdentifier("dismissKeyboardButton")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .accessibilityIdentifier("saveBillButton")
                }
            }
            .confirmationDialog("Delete \(name.isEmpty ? "this bill" : name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete bill", role: .destructive) {
                    if let id = existingRule?.id {
                        model.performUIAction { try model.deleteBill(id, in: cardID) }
                    }
                    dismiss()
                }
            } message: {
                Text("Coming dates go. Expenses it already added stay on the card.")
            }
            .onAppear(perform: loadExistingRule)
        }
    }

    private func loadExistingRule() {
        if let rule = existingRule {
            name = rule.name
            amountText = Money.format(rule.amount, currency: false, code: currency)
            selectedCategoryID = rule.categoryID
            recordingMode = rule.recordingMode
            hasReminder = rule.hasReminder
            reminderLeadDays = rule.reminderLeadDays
            isPaused = !rule.isActive
            switch rule.recurrence {
            case .monthly(let day):
                recurrenceKind = 0
                monthlyDay = day
            case .weekly(let weekday):
                recurrenceKind = 1
                weeklyWeekday = weekday
            case .yearly(let month, let day):
                recurrenceKind = 2
                yearlyMonth = month
                yearlyDay = day
            }
        } else if let expense = template {
            name = model.title(expense)
            amountText = Money.format(expense.amount, currency: false, code: currency)
            selectedCategoryID = expense.splits.max { $0.amount < $1.amount }?.categoryID
            monthlyDay = min(Day.date(expense.day).map { Day.calendar.component(.day, from: $0) } ?? 1, 28)
        } else {
            selectedCategoryID = categories.first?.id
            monthlyDay = min(Day.calendar.component(.day, from: .now), 28)
        }
    }

    private func save() {
        do {
            let parsedAmount: Int64
            do {
                parsedAmount = try Money.parse(amountText, code: currency)
            } catch {
                self.error = "Enter an amount."
                return
            }

            guard let categoryID = selectedCategoryID ?? categories.first?.id else {
                self.error = "Choose a category."
                return
            }

            let recurrence: BillRecurrence
            switch recurrenceKind {
            case 0: recurrence = .monthly(day: monthlyDay)
            case 1: recurrence = .weekly(weekday: weeklyWeekday)
            case 2: recurrence = .yearly(month: yearlyMonth, day: yearlyDay)
            default: recurrence = .monthly(day: monthlyDay)
            }

            let rule = Bill(
                id: existingRule?.id ?? UUID(),
                cardID: cardID,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: parsedAmount,
                categoryID: categoryID,
                recurrence: recurrence,
                recordingMode: recordingMode,
                hasReminder: hasReminder,
                reminderLeadDays: reminderLeadDays,
                createdAt: existingRule?.createdAt ?? .now,
                isActive: !isPaused,
                // The expense already paid its own day: the schedule starts the day after, so it isn't recorded twice.
                scheduleEffectiveDay: template.flatMap { Day.date($0.day) }.flatMap { Day.calendar.date(byAdding: .day, value: 1, to: $0) }.map { Day.string($0) }
            )

            try model.saveBill(rule)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
