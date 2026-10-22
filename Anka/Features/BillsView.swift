import StoreKit
import SwiftUI

struct BillsView: View {
    @Bindable var model: AppModel
    @State private var editingRule: Bill?
    @State private var isCreating = false
    @State private var showHistory = false

    private var todayString: String {
        Day.string(.now)
    }

    private var activeRules: [Bill] {
        model.bills.filter(\.isActive) + model.bills.filter { !$0.isActive }
    }

    private var rulesByID: [UUID: Bill] {
        Dictionary(uniqueKeysWithValues: model.bills.map { ($0.id, $0) })
    }

    private var dueOccurrences: [BillOccurrence] {
        model.billOccurrences
            .filter { $0.status == .pending && $0.dueDay <= todayString }
            .sorted { $0.dueDay < $1.dueDay }
    }

    private var upcomingOccurrences: [BillOccurrence] {
        model.billOccurrences
            .filter { $0.status == .pending && $0.dueDay > todayString }
            .sorted { $0.dueDay < $1.dueDay }
    }

    private var historyOccurrences: [BillOccurrence] {
        model.billOccurrences
            .filter { $0.status != .pending }
            .sorted { $0.dueDay > $1.dueDay }
    }

    private var monthlyCommitment: Int64? {
        do {
            return try Money.checkedSum(activeRules.map { rule in
                switch rule.recurrence {
                case .monthly: return rule.amount
                case .weekly: return try Money.checkedScale(rule.amount, numerator: 52, denominator: 12)
                case .yearly: return rule.amount / 12
                }
            })
        } catch { return nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                    Eyebrow(text: "Recurring bills")
                    Text("Fewer things\non your mind.")
                        .font(.largeTitle.weight(.medium))
                        .tracking(-1)

                    if let status = model.billReminderStatus {
                        Text(status).font(.footnote).foregroundStyle(MC.red)
                    }

                    // Summary Card
                    VStack(alignment: .leading, spacing: 14) {
                        Eyebrow(text: "Estimated Monthly Total")
                        Text(monthlyCommitment.map { Money.format($0) } ?? "Exceeds supported total")
                            .font(.system(size: 34, weight: .medium))
                            .tracking(-1)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        HStack(spacing: 12) {
                            Text("\(activeRules.count) active \(activeRules.count == 1 ? "bill" : "bills")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !dueOccurrences.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                    Text("\(dueOccurrences.count) action required")
                                }
                                .font(.caption.weight(.medium))
                                .foregroundStyle(MC.red)
                            }
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(MC.surface, in: RoundedRectangle(cornerRadius: 22))

                    // Action Required / Due Bills Section
                    if !dueOccurrences.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Action Required").font(.title3.weight(.semibold))
                                Spacer()
                                Eyebrow(text: "\(dueOccurrences.count) due")
                            }

                            ForEach(dueOccurrences) { occ in
                                if let rule = rulesByID[occ.billRuleID] {
                                    dueCard(occurrence: occ, rule: rule)
                                }
                            }
                        }
                    }

                    // Scheduled Bills Section
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("Scheduled Bills").font(.title3.weight(.semibold))
                            Spacer()
                            Button {
                                isCreating = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(MC.red)
                            }
                            .accessibilityIdentifier("addBillButton")
                        }

                        if activeRules.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.secondary)
                                Text("No recurring bills yet")
                                    .font(.headline)
                                Text("Add your subscriptions, rent, utilities, and other regular payments to keep track.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                RecordButton(title: "Add your first bill", symbol: "plus") {
                                    isCreating = true
                                }
                                .padding(.top, 6)
                            }
                            .padding(24)
                            .frame(maxWidth: .infinity)
                            .background(MC.surface, in: RoundedRectangle(cornerRadius: 22))
                        } else {
                            VStack(spacing: 12) {
                                ForEach(activeRules) { rule in
                                    scheduledBillRow(rule: rule)
                                }
                            }
                        }
                    }

                    // Upcoming Bills Section
                    if !upcomingOccurrences.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                Text("Upcoming").font(.title3.weight(.semibold))
                                Spacer()
                                Eyebrow(text: "Next 30 days")
                            }

                            VStack(spacing: 10) {
                                ForEach(upcomingOccurrences) { occ in
                                    if let rule = rulesByID[occ.billRuleID] {
                                        upcomingRow(occurrence: occ, rule: rule)
                                    }
                                }
                            }
                        }
                    }

                    // History Section
                    if !historyOccurrences.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            DisclosureGroup(isExpanded: $showHistory) {
                                VStack(spacing: 10) {
                                    ForEach(historyOccurrences.prefix(20)) { occ in
                                        let ruleName = rulesByID[occ.billRuleID]?.name ?? "Bill"
                                        let catSymbol = model.category(rulesByID[occ.billRuleID]?.categoryID)?.symbol ?? "clock"
                                        let amount = rulesByID[occ.billRuleID]?.amount ?? 0
                                        historyRow(occurrence: occ, name: ruleName, symbol: catSymbol, amount: amount)
                                    }
                                }
                                .padding(.top, 8)
                            } label: {
                                HStack {
                                    Text("Payment History")
                                        .font(.title3.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(historyOccurrences.count)")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(MC.paper)
            .navigationTitle("Bills")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isCreating) {
                BillEditor(model: model, existingRule: nil)
            }
            .sheet(item: $editingRule) { rule in
                BillEditor(model: model, existingRule: rule)
            }
    }

    private func dueCard(occurrence: BillOccurrence, rule: Bill) -> some View {
        let cat = model.category(rule.categoryID)
        let isOverdue = occurrence.dueDay < todayString
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: isOverdue ? "exclamationmark.triangle.fill" : "calendar.badge.clock")
                    Text(isOverdue ? "Overdue · \(Day.title(occurrence.dueDay))" : "Due today")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isOverdue ? MC.red : .primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    (isOverdue ? MC.red : Color.primary).opacity(0.1),
                    in: Capsule()
                )

                Spacer()

                if rule.hasReminder {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                CategoryMark(symbol: cat?.symbol ?? "creditcard")
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name).font(.headline)
                    Text(rule.recurrence.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Money.format(rule.amount))
                    .font(.system(size: 20, weight: .semibold))
            }

            Divider()

            HStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    model.performUIAction { _ = try model.confirmBillOccurrence(occurrence.id) }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Add")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(MC.red, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressFeedbackStyle())
                .accessibilityIdentifier("confirmBillButton_\(rule.name)")

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    model.performUIAction { try model.skipBillOccurrence(occurrence.id) }
                } label: {
                    Text("Skip")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(PressFeedbackStyle())
                .accessibilityIdentifier("skipBillButton_\(rule.name)")
            }
        }
        .padding(18)
        .background(MC.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isOverdue ? MC.red.opacity(0.3) : MC.line, lineWidth: 1)
        )
    }

    private func scheduledBillRow(rule: Bill) -> some View {
        let cat = model.category(rule.categoryID)
        return Button {
            editingRule = rule
        } label: {
            HStack(spacing: 14) {
                CategoryMark(symbol: cat?.symbol ?? "creditcard")
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    HStack(spacing: 8) {
                        Text(rule.recurrence.title).font(.caption).foregroundStyle(.secondary)
                        if !rule.isActive {
                            HStack(spacing: 2) {
                                Image(systemName: "pause.fill")
                                Text("Paused")
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.orange)
                        } else if rule.recordingMode == .automatic {
                            HStack(spacing: 2) {
                                Image(systemName: "bolt.fill")
                                Text("Auto")
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Color.green)
                        } else {
                            HStack(spacing: 2) {
                                Image(systemName: "hand.tap")
                                Text("Confirm")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                        if rule.hasReminder {
                            Image(systemName: "bell.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text(Money.format(rule.amount))
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .background(MC.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(PressFeedbackStyle())
        .accessibilityIdentifier("scheduledBill_\(rule.name)")
    }

    private func upcomingRow(occurrence: BillOccurrence, rule: Bill) -> some View {
        let cat = model.category(rule.categoryID)
        return HStack(spacing: 12) {
            CategoryMark(symbol: cat?.symbol ?? "creditcard")
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).font(.subheadline.weight(.medium))
                Text("Due \(Day.title(occurrence.dueDay))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(Money.format(rule.amount))
                    .font(.system(size: 15, weight: .medium))
                if rule.recordingMode == .automatic {
                    Text("Auto-adds").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Button("Pay now") {
                        model.performUIAction { _ = try model.confirmBillOccurrence(occurrence.id) }
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MC.red)
                }
            }
        }
        .padding(14)
        .background(MC.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func historyRow(occurrence: BillOccurrence, name: String, symbol: String, amount: Int64) -> some View {
        HStack(spacing: 12) {
            Image(systemName: occurrence.status == .recorded ? "checkmark.circle.fill" : "arrow.uturn.right.circle.fill")
                .font(.subheadline)
                .foregroundStyle(occurrence.status == .recorded ? Color.green : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.subheadline)
                Text(Day.title(occurrence.dueDay)).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(amount))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(occurrence.status == .recorded ? .primary : .secondary)
                Text(occurrence.status.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(MC.surface, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct BillEditor: View {
    let model: AppModel
    let existingRule: Bill?
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

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Bill name (e.g. Netflix, Rent)", text: $name)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("billNameField")

                    HStack {
                        Text("Rp").foregroundStyle(.secondary)
                        TextField("Amount (whole IDR)", text: $amountText)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .amount)
                            .accessibilityIdentifier("billAmountField")
                    }

                    Picker("Category", selection: Binding(
                        get: { selectedCategoryID ?? model.categories.first?.id ?? UUID() },
                        set: { selectedCategoryID = $0 }
                    )) {
                        ForEach(model.categories) { cat in
                            HStack {
                                Image(systemName: cat.symbol)
                                Text(cat.name)
                            }
                            .tag(cat.id)
                        }
                    }
                    .accessibilityIdentifier("billCategoryPicker")
                }

                Section("Schedule") {
                    Picker("Frequency", selection: $recurrenceKind) {
                        Text("Monthly").tag(0)
                        Text("Weekly").tag(1)
                        Text("Yearly").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("billRecurrencePicker")

                    if recurrenceKind == 0 {
                        Picker("Due day of month", selection: $monthlyDay) {
                            ForEach(1...31, id: \.self) { day in
                                Text("Day \(day)").tag(day)
                            }
                        }
                    } else if recurrenceKind == 1 {
                        Picker("Weekday", selection: $weeklyWeekday) {
                            ForEach(1...7, id: \.self) { weekday in
                                let name = Day.calendar.weekdaySymbols[weekday - 1]
                                Text(name).tag(weekday)
                            }
                        }
                    } else {
                        HStack {
                            Picker("Month", selection: $yearlyMonth) {
                                ForEach(1...12, id: \.self) { month in
                                    let name = Day.calendar.monthSymbols[month - 1]
                                    Text(name).tag(month)
                                }
                            }
                            Picker("Day", selection: $yearlyDay) {
                                ForEach(1...31, id: \.self) { day in
                                    Text("\(day)").tag(day)
                                }
                            }
                        }
                    }
                }

                Section {
                    Picker("On the due date", selection: $recordingMode) {
                        Text("Keep pending until confirmed").tag(BillRecordingMode.pending)
                        Text("Add automatically").tag(BillRecordingMode.automatic)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("billModePicker")
                } header: {
                    Text("When due")
                } footer: {
                    Text(recordingMode == .automatic
                         ? "An expense is added automatically on the due date and counts toward spending."
                         : "Upcoming bills appear in your Action Required queue and will not count as spending until you confirm.")
                }

                Section("Notification") {
                    Toggle("Remind me when due", isOn: $hasReminder)
                        .accessibilityIdentifier("billReminderToggle")

                    if hasReminder {
                        Picker("Reminder timing", selection: $reminderLeadDays) {
                            Text("On due date (9:00 AM)").tag(0)
                            Text("1 day before").tag(1)
                            Text("2 days before").tag(2)
                            Text("3 days before").tag(3)
                            Text("7 days before").tag(7)
                        }
                    }
                }

                if isEditing {
                    Section {
                        Toggle("Pause bill", isOn: $isPaused)
                            .accessibilityIdentifier("billPauseToggle")
                    } footer: {
                        Text(isPaused
                             ? "No new occurrences or reminders while paused. Resuming starts again from today; missed dates are not added."
                             : "Pause to stop this bill without deleting it.")
                    }

                    Section {
                        Button("Delete bill", role: .destructive) {
                            confirmDelete = true
                        }
                        .accessibilityIdentifier("deleteBillButton")
                    }
                }

                if let error {
                    Section {
                        Text(error).foregroundStyle(MC.red)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isEditing ? "Edit Bill" : "New Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Dismiss") {
                        focusedField = nil
                    }
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
            .alert("Delete this bill?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    if let id = existingRule?.id {
                        model.performUIAction { try model.deleteBill(id) }
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Future occurrences will be removed. Expenses already added stay on the card.")
            }
            .onAppear(perform: loadExistingRule)
        }
    }

    private func loadExistingRule() {
        if let rule = existingRule {
            name = rule.name
            amountText = String(rule.amount / 100)
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
        } else {
            selectedCategoryID = model.categories.first?.id
            monthlyDay = min(Day.calendar.component(.day, from: .now), 28)
        }
    }

    private func save() {
        do {
            let parsedAmount: Int64
            do {
                parsedAmount = try Money.parse(amountText)
            } catch {
                self.error = "Please enter a valid amount."
                return
            }

            guard let categoryID = selectedCategoryID ?? model.categories.first?.id else {
                self.error = "Please choose a category."
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
                cardID: existingRule?.cardID ?? model.activeCardID,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: parsedAmount,
                categoryID: categoryID,
                recurrence: recurrence,
                recordingMode: recordingMode,
                hasReminder: hasReminder,
                reminderLeadDays: reminderLeadDays,
                createdAt: existingRule?.createdAt ?? .now,
                isActive: !isPaused
            )

            try model.saveBill(rule)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct SettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    private var activeCard: Card {
        model.cards.first(where: { $0.id == (model.selectedCardID ?? model.activeCardID) })
            ?? model.cards.first
            ?? model.settings.card
    }

    var body: some View {
        NavigationStack {
            Form {
                if model.pro != nil { SubscriptionSection(model: model) }

                // MARK: 1. Active Card & Categories
                Section {
                    if activeCard.kind == .real {
                        NavigationLink {
                            RenameCardView(model: model, card: activeCard)
                        } label: {
                            LabeledContent {
                                Text(activeCard.name)
                                    .foregroundStyle(.secondary)
                            } label: {
                                Label {
                                    Text("Card name")
                                } icon: {
                                    SettingsIcon(symbol: "creditcard.fill", color: .indigo)
                                }
                            }
                        }
                        .accessibilityIdentifier("renameRealBook")
                    } else {
                        LabeledContent {
                            Text(activeCard.name).foregroundStyle(.secondary)
                        } label: {
                            Label("Card name", systemImage: "creditcard.fill")
                        }
                    }

                    NavigationLink {
                        CategoryManager(model: model)
                    } label: {
                        LabeledContent {
                            Text("\(model.globalCategories.count)")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label {
                                Text("Categories")
                            } icon: {
                                SettingsIcon(symbol: "tag.fill", color: .orange)
                            }
                        }
                    }
                    .accessibilityIdentifier("manageCategories")

                    NavigationLink {
                        PaymentMethodsView(model: model, cardID: activeCard.id)
                    } label: {
                        LabeledContent {
                            Text(model.paymentMethod(activeCard.defaultPaidWithID)?.name ?? "\(model.paymentMethods.count)")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label {
                                Text("Paid with")
                            } icon: {
                                SettingsIcon(symbol: "creditcard.and.123", color: .mint)
                            }
                        }
                    }
                    .accessibilityIdentifier("paidWithSettings")

                    NavigationLink {
                        CurrencySettingsView(model: model, cardID: activeCard.id)
                    } label: {
                        LabeledContent {
                            Text(model.currency(of: activeCard) == model.reportingCurrency ? model.reportingCurrency
                                 : "\(model.currency(of: activeCard)) · reports \(model.reportingCurrency)")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label {
                                Text("Currency")
                            } icon: {
                                SettingsIcon(symbol: "banknote.fill", color: .green)
                            }
                        }
                    }
                    .accessibilityIdentifier("currencySettings")
                } header: {
                    Text("Active Card")
                }

                // MARK: 2. Data & Storage
                Section {
                    NavigationLink {
                        BackupView(model: model)
                    } label: {
                        Label {
                            Text("Backup & restore")
                        } icon: {
                            SettingsIcon(symbol: "arrow.triangle.2.circlepath", color: .blue)
                        }
                    }
                    .accessibilityIdentifier("backupSettings")

                    NavigationLink {
                        CSVInterchangeView(model: model, showsDismissButton: false)
                    } label: {
                        Label {
                            Text("CSV export & import")
                        } icon: {
                            SettingsIcon(symbol: "tablecells.fill", color: .teal)
                        }
                    }
                    .accessibilityIdentifier("csvInterchangeSettings")

                    NavigationLink {
                        ResetDataView(model: model)
                    } label: {
                        Label {
                            Text("Reset data")
                        } icon: {
                            SettingsIcon(symbol: "trash.fill", color: MC.red)
                        }
                    }
                    .accessibilityIdentifier("resetDataSettings")
                } header: {
                    Text("Data & Storage")
                } footer: {
                    Text("Export full JSON snapshots, import spreadsheets, or reset data to start fresh.")
                }

                // MARK: 3. Expense Input
                Section {
                    NavigationLink {
                        EntryFormSettingsView(model: model)
                    } label: {
                        Label {
                            Text("Add Expense form")
                        } icon: {
                            SettingsIcon(symbol: "list.bullet.rectangle", color: .indigo)
                        }
                    }
                    .accessibilityIdentifier("entryFormSettings")
                } header: {
                    Text("Expense Input")
                }

                // MARK: 4. Shortcuts & Siri
                Section {
                    NavigationLink {
                        ShortcutOrderSettingsView(model: model)
                    } label: {
                        LabeledContent {
                            Text(model.shortcutInputOrder.map(\.displayName).joined(separator: " → "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } label: {
                            Label {
                                Text("Shortcut prompt order")
                            } icon: {
                                SettingsIcon(symbol: "arrow.up.arrow.down.square.fill", color: .pink)
                            }
                        }
                    }
                    .accessibilityIdentifier("shortcutOrderSettings")
                } header: {
                    Text("Shortcuts & Siri")
                } footer: {
                    Text("Configure the sequence Anka asks for details when adding expenses via Apple Shortcuts.")
                }

                // MARK: 5. Appearance
                Section {
                    Toggle(isOn: $model.autoAppearance) {
                        Label {
                            Text("Auto switch")
                        } icon: {
                            SettingsIcon(symbol: "circle.lefthalf.filled", color: .blue)
                        }
                    }
                    .accessibilityIdentifier("autoAppearanceToggle")

                    Picker("Appearance", selection: Binding(
                        get: {
                            if model.autoAppearance {
                                return colorScheme == .dark ? AppearanceMode.dark : AppearanceMode.light
                            }
                            return model.manualAppearance
                        },
                        set: { newMode in
                            model.manualAppearance = newMode
                        }
                    )) {
                        Text("Light").tag(AppearanceMode.light)
                        Text("Dark").tag(AppearanceMode.dark)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("appearanceModePicker")

                    Picker(selection: Binding(
                        get: { model.visualDirection },
                        set: { newDir in
                            model.visualDirection = newDir
                        }
                    )) {
                        ForEach(CardVisualDirection.allCases) { dir in
                            Text(dir.rawValue).tag(dir)
                        }
                    } label: {
                        Label {
                            Text("Theme style")
                        } icon: {
                            SettingsIcon(symbol: "paintpalette.fill", color: .purple)
                        }
                    }
                    .accessibilityIdentifier("themeStylePicker")
                } header: {
                    Text("Appearance")
                } footer: {
                    if model.autoAppearance {
                        Text("anka automatically matches your iOS system appearance.")
                    } else {
                        Text("Appearance is locked to your selection.")
                    }
                }

                // MARK: 5. Security & Privacy
                Section {
                    NavigationLink {
                        AppLockSettingsView(model: model)
                    } label: {
                        LabeledContent {
                            Text(model.settings.appLockTimeout?.title ?? "Off")
                                .foregroundStyle(.secondary)
                        } label: {
                            Label {
                                Text("App lock")
                            } icon: {
                                SettingsIcon(symbol: "lock.shield.fill", color: MC.red)
                            }
                        }
                    }
                    .accessibilityIdentifier("appLockSettings")
                } header: {
                    Text("Security")
                } footer: {
                    Text("Require Face ID or device passcode when returning to Anka.")
                }

                // MARK: 6. About
                Section {
                    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.7.2"
                    let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "61"
                    LabeledContent {
                        Text("\(version) (\(build))")
                            .foregroundStyle(.secondary)
                    } label: {
                        Label {
                            Text("Version")
                        } icon: {
                            SettingsIcon(symbol: "info.circle.fill", color: .gray)
                        }
                    }
                    Link(destination: AppLinks.privacy) {
                        Label { Text("Privacy policy") } icon: { SettingsIcon(symbol: "hand.raised.fill", color: .gray) }
                    }
                    Link(destination: AppLinks.terms) {
                        Label { Text("Terms of use") } icon: { SettingsIcon(symbol: "doc.text.fill", color: .gray) }
                    }
                } header: {
                    Text("About")
                } footer: {
                    Text("Anka keeps your spending on this device.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Pro status, upgrade, restore and offer codes. Apple's own sheets handle managing and redeeming.
private struct SubscriptionSection: View {
    let model: AppModel
    @State private var managing = false
    @State private var redeeming = false
    @State private var restoring = false

    var body: some View {
        Section {
            if model.isPro {
                LabeledContent {
                    Text("Active").foregroundStyle(.secondary)
                } label: {
                    Label { Text("Anka Pro") } icon: { SettingsIcon(symbol: "star.fill", color: MC.red) }
                }
                Button("Manage subscription") { managing = true }
            } else {
                Button { model.paywall = "" } label: {
                    Label { Text("Upgrade to Pro") } icon: { SettingsIcon(symbol: "star.fill", color: MC.red) }
                }
                .accessibilityIdentifier("upgradeToPro")
            }
            Button(restoring ? "Restoring…" : "Restore purchases") {
                restoring = true
                Task {
                    do { try await model.pro?.restore() } catch { model.error = error.localizedDescription }
                    restoring = false
                }
            }
            .disabled(restoring)
            Button("Redeem code") { redeeming = true }
        } header: {
            Text("Subscription")
        } footer: {
            if !model.isPro { Text("Free includes one card, \(Plan.freeBills) bills and \(Plan.freeQuestionsPerDay) chat questions a day.") }
        }
        .manageSubscriptionsSheet(isPresented: $managing)
        .offerCodeRedemption(isPresented: $redeeming) { _ in Task { await model.pro?.refresh() } }
    }
}

private struct RenameCardView: View {
    let model: AppModel
    let card: Card
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        Form {
            TextField("Card name", text: $name).accessibilityIdentifier("renameBookName")
        }
        .navigationTitle("Rename card").navigationBarTitleDisplayMode(.inline)
        .onAppear { name = card.name }
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                do { try model.renameCard(id: card.id, to: name); dismiss() }
                catch { self.error = error.localizedDescription }
            }
        } }
        .alert("Could not rename card", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}


struct AppLockSettingsView: View {
    let model: AppModel
    @State private var error: String?
    @State private var saving = false

    var body: some View {
        Form {
            Section {
                if let timeout = model.settings.appLockTimeout {
                    LabeledContent { Text(timeout.title) } label: { Text("Current setting") }
                    Button("Turn off app lock", role: .destructive) { update(nil) }
                        .disabled(saving)
                } else {
                    Text("Off").foregroundStyle(.secondary)
                }
                ForEach(AppLockTimeout.allCases) { timeout in
                    Button { update(timeout) } label: {
                        HStack {
                            Text(timeout.title)
                            Spacer()
                            if timeout == model.settings.appLockTimeout { Image(systemName: "checkmark").foregroundStyle(MC.red) }
                        }
                    }
                    .disabled(saving || timeout == model.settings.appLockTimeout)
                }
            } header: {
                Text("Lock after leaving anka")
            } footer: {
                Text("Turning this on or changing its timeout confirms your device authentication. anka covers its interface while it is in the app switcher, then asks for Face ID or your device passcode when the timeout has elapsed.")
            }
            Section("Shortcuts") {
                Text("Both anka Shortcuts always use the system device-authentication policy. A background text shortcut can add an expense only after that system check; it does not unlock the app screen. Quick entry may still show this lock when anka opens.")
            }
            if saving { HStack { Spacer(); ProgressView("Saving app lock…"); Spacer() } }
            if let error { Text(error).foregroundStyle(MC.red) }
        }
        .navigationTitle("App lock").navigationBarTitleDisplayMode(.inline)
    }

    private func update(_ timeout: AppLockTimeout?) {
        saving = true
        Task {
            let result = await model.setAppLockTimeout(timeout)
            saving = false
            if case let .failure(error) = result { self.error = error.localizedDescription }
        }
    }
}
