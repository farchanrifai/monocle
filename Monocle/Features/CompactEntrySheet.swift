import SwiftUI

struct CompactEntrySheet: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var dragOffset: CGFloat = 0
    @State private var showDatePicker = false
    @State private var showDiscardAlert = false

    private var activeBook: BookProfile {
        if let bookID = model.draft.bookID, let book = model.books.first(where: { $0.id == bookID }) {
            return book
        }
        return model.books.first(where: { $0.id == (model.selectedBookID ?? model.activeBookID) }) ?? model.books.first ?? BookProfile.sample
    }

    private var selectedCategory: ExpenseCategory? {
        if let catID = model.draft.categoryID {
            return model.category(catID)
        }
        return nil
    }

    private var amount: Int64 {
        (try? Money.parse(model.draft.amount)) ?? 0
    }

    private var formattedDate: String {
        let cal = Calendar.current
        if cal.isDateInToday(model.draft.date) {
            return "Today"
        } else if cal.isDateInYesterday(model.draft.date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "d MMM"
            return formatter.string(from: model.draft.date)
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Darkened frosted backdrop
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture {
                    requestClose()
                }

            // Compact Sheet Container
            VStack(spacing: 0) {
                grabberHeader

                VStack(spacing: 12) {
                    // Two-column layout matching reference sketch
                    HStack(alignment: .top, spacing: 12) {
                        leftColumn
                            .frame(maxWidth: .infinity)

                        rightKeypadColumn
                            .frame(width: 156)
                    }

                    // Bottom Action Button
                    recordButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .background {
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(Color(uiColor: .systemBackground).opacity(colorScheme == .dark ? 0.75 : 0.85))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    stops: [
                                        .init(color: .white.opacity(0.32), location: 0.0),
                                        .init(color: .white.opacity(0.10), location: 0.25),
                                        .init(color: .white.opacity(0.02), location: 0.7),
                                        .init(color: .white.opacity(0.06), location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1.0
                            )
                    }
                    .shadow(color: Color.black.opacity(0.25), radius: 28, x: 0, y: 10)
            }
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .offset(y: max(0, dragOffset))
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffset = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 80 || value.velocity.height > 300 {
                            requestClose()
                        } else {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
                                dragOffset = 0
                            }
                        }
                    }
            )
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.80, anchor: .bottom).combined(with: .move(edge: .bottom)).combined(with: .opacity),
                    removal: .scale(scale: 0.85, anchor: .bottom).combined(with: .move(edge: .bottom)).combined(with: .opacity)
                )
            )
        }
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.82), value: model.showEntry)
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker("Expense date", selection: $model.draft.date, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showDatePicker = false }
                        }
                    }
            }
            .presentationDetents([.medium])
        }
        .alert(model.draft.editing ? "Discard changes?" : "Discard this expense?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                if model.discardDraft() {
                    model.showEntry = false
                }
            }
            Button("Keep editing", role: .cancel) {}
        }
    }

    // MARK: - Header with Grabber & Quick Actions

    private var grabberHeader: some View {
        HStack {
            // Expand to Full Sheet Mode (Notes / Splits)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.snappy(duration: 0.2)) {
                    model.draft.mode = .keypad
                }
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(PressFeedbackStyle())
            .liquidGlass(cornerRadius: 16, interactive: true)
            .accessibilityLabel("Expand to full sheet")

            Spacer()

            // Centered Grabber Capsule
            Capsule()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 36, height: 5)
                .accessibilityHidden(true)

            Spacer()

            // Close / Dismiss Button
            Button {
                requestClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(PressFeedbackStyle())
            .liquidGlass(cornerRadius: 16, interactive: true)
            .accessibilityLabel("Close entry")
            .accessibilityIdentifier("closeCompactEntry")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    // MARK: - Left Column: Card, Date, Hero Amount, Category

    private var leftColumn: some View {
        VStack(spacing: 8) {
            // 1. Card Name Dropdown Pill
            Menu {
                ForEach(model.unhiddenBooks) { book in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        model.draft.bookID = book.id
                    } label: {
                        HStack {
                            Text(book.name)
                            if activeBook.id == book.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(CardPalette.color(for: activeBook.colorIndex))
                        .frame(width: 10, height: 10)

                    Text(activeBook.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
            }
            .liquidGlass(cornerRadius: 13, interactive: true)
            .accessibilityIdentifier("compactCardSelector")

            // 2. Date Dropdown Pill
            Menu {
                Button("Today") {
                    UISelectionFeedbackGenerator().selectionChanged()
                    model.draft.date = .now
                }
                Button("Yesterday") {
                    UISelectionFeedbackGenerator().selectionChanged()
                    model.draft.date = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
                }
                Divider()
                Button("Custom date...") {
                    showDatePicker = true
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MC.red)

                    Text(formattedDate)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 38)
            }
            .liquidGlass(cornerRadius: 13, interactive: true)
            .accessibilityIdentifier("compactDateSelector")

            // 3. Amount Hero Box
            VStack(alignment: .leading, spacing: 2) {
                Text("AMOUNT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .foregroundStyle(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Rp")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    if model.draft.amount.isEmpty || model.draft.amount == "0" {
                        Text("0")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .accessibilityIdentifier("compactAmountDisplay")
                    } else {
                        Text(Money.format(amount, currency: false))
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("compactAmountDisplay")
                    }

                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(height: 64)
            .liquidGlass(cornerRadius: 15, specularIntensity: 0.28)

            // 4. Category Dropdown
            Menu {
                ForEach(model.activeCategories) { cat in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        model.draft.categoryID = cat.id
                    } label: {
                        HStack {
                            Label(cat.name, systemImage: cat.symbol)
                            if selectedCategory?.id == cat.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if let cat = selectedCategory {
                        Image(systemName: cat.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MC.red)

                        Text(cat.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    } else {
                        Image(systemName: "tag")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Text("Select Category")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
            }
            .liquidGlass(cornerRadius: 14, interactive: true)
            .accessibilityIdentifier("compactCategorySelector")
        }
    }

    // MARK: - Right Column: Mini Custom Keypad

    private var rightKeypadColumn: some View {
        let keys: [[String]] = [
            ["1", "2", "3"],
            ["4", "5", "6"],
            ["7", "8", "9"],
            ["000", "0", "delete.left"]
        ]

        return VStack(spacing: 6) {
            ForEach(keys, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { key in
                        Button {
                            handleKeypress(key)
                        } label: {
                            Group {
                                if key == "delete.left" {
                                    Image(systemName: key)
                                        .font(.system(size: 15, weight: .semibold))
                                } else {
                                    Text(key)
                                        .font(.system(size: key == "000" ? 12 : 18, weight: .semibold, design: .rounded))
                                }
                            }
                        }
                        .buttonStyle(LiquidGlassKeyStyle(cornerRadius: 11, isDestructiveOrAction: key == "delete.left"))
                        .frame(height: 46)
                        .accessibilityIdentifier("compact-key-\(key)")
                    }
                }
            }
        }
    }

    // MARK: - Record Expense Liquid Glass Button

    private var recordButton: some View {
        let canRecord = amount > 0

        return Button {
            saveAndClose()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: model.draft.editing ? "checkmark" : "plus")
                    .font(.system(size: 16, weight: .semibold))
                Text(model.draft.editing ? "Save Changes" : "Record Expense")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(PressFeedbackStyle())
        .glassEffect(.regular.tint(MC.red.opacity(canRecord ? 0.90 : 0.40)).interactive(canRecord), in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.35), .white.opacity(0.08)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        }
        .environment(\.colorScheme, .dark)
        .disabled(!canRecord)
        .accessibilityIdentifier("compactRecordExpense")
    }

    // MARK: - Handlers

    private func handleKeypress(_ key: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if key == "delete.left" {
            if !model.draft.amount.isEmpty {
                model.draft.amount.removeLast()
            }
        } else if model.draft.amount.count + key.count <= 13 {
            if model.draft.amount == "0" {
                model.draft.amount = ""
            }
            model.draft.amount += key
        }
    }

    private func saveAndClose() {
        guard amount > 0 else { return }

        // If no category is chosen, default to the first active category to avoid error
        if model.draft.categoryID == nil, let first = model.activeCategories.first {
            model.draft.categoryID = first.id
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        model.saveDraft()
    }

    private func requestClose() {
        if model.draftNeedsConfirmation {
            showDiscardAlert = true
        } else {
            if model.discardDraft() {
                model.showEntry = false
            }
        }
    }
}
