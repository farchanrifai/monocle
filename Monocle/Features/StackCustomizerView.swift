import SwiftUI

private struct MiniCardLayer: Identifiable {
    let id: UUID
    let index: Int
    let color: Color
}

struct StackCustomizerView: View {
    @Bindable var model: AppModel
    var initialMode: StackCustomizerMode = .manage
    var onDismiss: () -> Void

    @State private var workingStacks: [CardStack]
    @State private var currentStackID: UUID
    @State private var editingName: String = ""
    @State private var selectedIcon: String = "rectangle.stack"
    @State private var alwaysHiddenIDs: Set<UUID>
    @State private var showingDeleteAlert = false
    @FocusState private var isNameFocused: Bool

    private let availableIcons = [
        "rectangle.stack", "airplane", "house", "cart",
        "briefcase", "creditcard", "fork.knife", "sparkles",
        "car", "cross.case", "sportscourt", "bag"
    ]

    init(model: AppModel, initialMode: StackCustomizerMode = .manage, onDismiss: @escaping () -> Void) {
        self.model = model
        self.initialMode = initialMode
        self.onDismiss = onDismiss

        var initialStacks = model.stacks
        if initialStacks.isEmpty {
            let initialIDs = model.orderedBooks.map(\.id).filter { !model.alwaysHiddenBookIDs.contains($0) }
            let def = CardStack(id: UUID(), name: "Daily", icon: "rectangle.stack", cardIDs: initialIDs)
            initialStacks = [def]
        }

        var activeID = model.activeStackID ?? initialStacks.first?.id ?? UUID()

        if initialMode == .create {
            let newID = UUID()
            let nextIndex = initialStacks.count + 1
            let newStack = CardStack(id: newID, name: "Stack \(nextIndex)", icon: "airplane", cardIDs: [])
            initialStacks.append(newStack)
            activeID = newID
        }

        _workingStacks = State(initialValue: initialStacks)
        _currentStackID = State(initialValue: activeID)
        _alwaysHiddenIDs = State(initialValue: model.alwaysHiddenBookIDs)

        if let curr = initialStacks.first(where: { $0.id == activeID }) {
            _editingName = State(initialValue: curr.name)
            _selectedIcon = State(initialValue: curr.icon)
        }
    }

    private var currentStackIndex: Int? {
        workingStacks.firstIndex(where: { $0.id == currentStackID })
    }

    private var activeStack: CardStack {
        workingStacks.first(where: { $0.id == currentStackID }) ?? workingStacks.first!
    }

    private func cardColor(for book: BookProfile) -> Color {
        let custom = model.customization(for: book.id)
        switch custom.style {
        case .palette(let index):
            return CardPalette.color(for: index)
        case .customColor(let hex):
            return CardPalette.color(fromHex: hex)
        default:
            return CardPalette.color(for: book.colorIndex)
        }
    }

    private func miniCardLayers(for assignedCards: [BookProfile]) -> [MiniCardLayer] {
        let topCards = Array(assignedCards.prefix(3))
        var layers: [MiniCardLayer] = []
        for (idx, book) in topCards.enumerated() {
            let color = cardColor(for: book)
            layers.append(MiniCardLayer(id: book.id, index: idx, color: color))
        }
        return layers.reversed()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // MARK: - Mini Stack Carousel Preview
                    stackPreviewSection

                    // MARK: - Stack Identity
                    stackIdentitySection

                    // MARK: - Cards in This Stack
                    cardsInStackSection

                    // MARK: - Always Hidden / Archive Section
                    archiveSection

                    // MARK: - Delete Stack (if more than 1)
                    if workingStacks.count > 1 {
                        Button(role: .destructive) {
                            showingDeleteAlert = true
                        } label: {
                            Label("Delete This Stack", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MC.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(MC.red.opacity(0.08))
                                )
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                        .accessibilityIdentifier("deleteStackButton")
                    }
                }
                .padding(.vertical, 16)
                .padding(.bottom, 40)
            }
            .scrollBounceBehavior(.always)
            .navigationTitle(initialMode == .create ? "New Stack" : "Manage Stacks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        saveChanges()
                        onDismiss()
                    }
                    .font(.headline)
                    .accessibilityIdentifier("saveStackCustomizer")
                }
            }
            .alert("Delete Stack?", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    deleteCurrentStack()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Cards in this stack will not be deleted, only this stack grouping.")
            }
        }
    }

    // MARK: - Stack Preview Section
    private var stackPreviewSection: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(workingStacks) { stack in
                        stackCardPreview(for: stack)
                            .onTapGesture {
                                selectStack(stack.id)
                            }
                    }

                    // Add Stack Button
                    Button {
                        addNewStack()
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(MC.red)
                            Text("New Stack")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(width: 140, height: 110)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.primary.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("addNewStackButton")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
        }
    }

    private func assignedCards(for stack: CardStack) -> [BookProfile] {
        var result: [BookProfile] = []
        let books = model.books
        for id in stack.cardIDs {
            if !alwaysHiddenIDs.contains(id), let book = books.first(where: { $0.id == id }) {
                result.append(book)
            }
        }
        return result
    }

    private func stackCardPreview(for stack: CardStack) -> some View {
        let isSelected = stack.id == currentStackID
        let assigned = assignedCards(for: stack)
        let layers = miniCardLayers(for: assigned)

        return VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if layers.isEmpty {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.primary.opacity(0.08))
                        .overlay(
                            Text("No cards")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        )
                } else {
                    ForEach(layers) { layer in
                        RoundedRectangle(cornerRadius: 14)
                            .fill(layer.color)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
                            )
                            .offset(x: CGFloat(layer.index) * 6, y: CGFloat(layer.index) * 5)
                            .scaleEffect(1.0 - CGFloat(layer.index) * 0.05, anchor: .topLeading)
                            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 2)
                    }
                }
            }
            .frame(width: 140, height: 80)
            .padding(.trailing, 12)
            .padding(.bottom, 6)

            HStack(spacing: 4) {
                Image(systemName: stack.icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(isSelected ? MC.red : .secondary)
                Text(stack.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }

            Text("\(assigned.count) \(assigned.count == 1 ? "card" : "cards")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(isSelected ? MC.red.opacity(0.08) : Color.primary.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(isSelected ? MC.red : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Stack \(stack.name), \(assigned.count) cards")
        .accessibilityIdentifier("stackPreview-\(stack.name)")
    }

    // MARK: - Stack Identity Section
    private var stackIdentitySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Stack Name & Icon")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                Image(systemName: selectedIcon)
                    .font(.title2)
                    .foregroundStyle(MC.red)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(MC.red.opacity(0.12)))

                TextField("Stack Name", text: $editingName)
                    .font(.headline)
                    .textFieldStyle(.plain)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .onChange(of: editingName) { _, newName in
                        if let idx = currentStackIndex {
                            workingStacks[idx].name = newName.isEmpty ? "Untitled Stack" : String(newName.prefix(40))
                        }
                    }
                    .accessibilityIdentifier("stackNameTextField")

                if !editingName.isEmpty {
                    Button {
                        editingName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.primary.opacity(0.05))
            )

            // Icon strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(availableIcons, id: \.self) { icon in
                        let isChosen = (selectedIcon == icon)
                        Button {
                            selectedIcon = icon
                            if let idx = currentStackIndex {
                                workingStacks[idx].icon = icon
                            }
                        } label: {
                            Image(systemName: icon)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(isChosen ? MC.red : Color.primary)
                                .frame(width: 40, height: 40)
                                .background(
                                    Circle()
                                        .fill(isChosen ? MC.red.opacity(0.15) : Color.primary.opacity(0.05))
                                        .overlay(
                                            Circle()
                                                .strokeBorder(isChosen ? MC.red : Color.clear, lineWidth: 1.5)
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Cards in Stack Section
    private var cardsInStackSection: some View {
        let currentAssigned = assignedCards(for: activeStack)
        let unassignedCards = model.books.filter { !alwaysHiddenIDs.contains($0.id) && !activeStack.cardIDs.contains($0.id) }

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Cards in This Stack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(currentAssigned.count) \(currentAssigned.count == 1 ? "card" : "cards")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("The top card (#1) is the front face of this stack. Tap arrows to reorder.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if currentAssigned.isEmpty {
                Text("No cards in this stack yet. Tap + below to add cards.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(currentAssigned.enumerated()), id: \.element.id) { index, book in
                        let cardCol = cardColor(for: book)

                        HStack(spacing: 10) {
                            // Rank / Front badge
                            HStack(spacing: 4) {
                                if index == 0 {
                                    Text("FRONT")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(MC.red)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(MC.red.opacity(0.12)))
                                } else {
                                    Text("#\(index + 1)")
                                        .font(.caption2.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 44, alignment: .leading)

                            RoundedRectangle(cornerRadius: 8)
                                .fill(cardCol)
                                .frame(width: 36, height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(Money.format(model.spent(for: book.id)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 4)

                            // Up Button
                            Button {
                                moveCardUp(at: index)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(index > 0 ? Color.primary : Color.secondary.opacity(0.25))
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Color.primary.opacity(index > 0 ? 0.06 : 0.02)))
                            }
                            .disabled(index == 0)
                            .buttonStyle(.plain)
                            .accessibilityLabel("Move \(book.name) up")
                            .accessibilityIdentifier("moveUp-\(book.name)")

                            // Down Button
                            Button {
                                moveCardDown(at: index)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(index < currentAssigned.count - 1 ? Color.primary : Color.secondary.opacity(0.25))
                                    .frame(width: 28, height: 28)
                                    .background(Circle().fill(Color.primary.opacity(index < currentAssigned.count - 1 ? 0.06 : 0.02)))
                            }
                            .disabled(index >= currentAssigned.count - 1)
                            .buttonStyle(.plain)
                            .accessibilityLabel("Move \(book.name) down")
                            .accessibilityIdentifier("moveDown-\(book.name)")

                            // Remove Button
                            Button {
                                removeCard(book.id)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(MC.red)
                                    .frame(width: 28, height: 28)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove \(book.name) from stack")
                            .accessibilityIdentifier("removeCard-\(book.name)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.primary.opacity(0.04))
                        )
                    }
                }
            }

            // Available Cards (to add)
            if !unassignedCards.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add Available Cards")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .padding(.top, 6)

                    ForEach(unassignedCards) { book in
                        let cardCol = cardColor(for: book)

                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(cardCol)
                                .frame(width: 36, height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(book.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(Money.format(model.spent(for: book.id)))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 4)

                            Button {
                                addCard(book.id)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add")
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(MC.red)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(MC.red.opacity(0.10)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Add \(book.name) to stack")
                            .accessibilityIdentifier("addCard-\(book.name)")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.primary.opacity(0.02))
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Archive & Always Hidden Section
    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Card Visibility & Archive")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text("Always Hidden cards never appear on the home deck or in 'All Activities'. They remain safely stored and accessible via the top Options Menu.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(model.books) { book in
                    let isAlwaysHidden = alwaysHiddenIDs.contains(book.id)
                    let cardCol = cardColor(for: book)

                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(cardCol)
                            .frame(width: 38, height: 26)
                            .opacity(isAlwaysHidden ? 0.4 : 1.0)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5)
                            )

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(book.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(isAlwaysHidden ? .secondary : .primary)
                                if isAlwaysHidden {
                                    Text("Archived")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(MC.red)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Capsule().fill(MC.red.opacity(0.12)))
                                }
                            }
                            Text(Money.format(model.spent(for: book.id)))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Toggle("Always Hidden", isOn: Binding(
                            get: { alwaysHiddenIDs.contains(book.id) },
                            set: { shouldHide in
                                toggleAlwaysHidden(for: book.id, isHidden: shouldHide)
                            }
                        ))
                        .labelsHidden()
                        .tint(MC.red)
                        .accessibilityIdentifier("alwaysHiddenToggle-\(book.name)")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.primary.opacity(0.03))
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Actions
    private func selectStack(_ id: UUID) {
        currentStackID = id
        if let stack = workingStacks.first(where: { $0.id == id }) {
            editingName = stack.name
            selectedIcon = stack.icon
        }
    }

    private func addNewStack() {
        let newID = UUID()
        let nextIndex = workingStacks.count + 1
        let newStack = CardStack(id: newID, name: "Stack \(nextIndex)", icon: "airplane", cardIDs: [])
        workingStacks.append(newStack)
        selectStack(newID)
        isNameFocused = true
    }

    private func deleteCurrentStack() {
        guard workingStacks.count > 1 else { return }
        let toDelete = currentStackID
        workingStacks.removeAll { $0.id == toDelete }
        if let next = workingStacks.first {
            selectStack(next.id)
        }
    }

    private func moveCardUp(at index: Int) {
        guard let sIdx = currentStackIndex else { return }
        var cardIDs = workingStacks[sIdx].cardIDs
        guard index > 0 && index < cardIDs.count else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        withAnimation(.snappy(duration: 0.22)) {
            cardIDs.swapAt(index, index - 1)
            workingStacks[sIdx].cardIDs = cardIDs
        }
    }

    private func moveCardDown(at index: Int) {
        guard let sIdx = currentStackIndex else { return }
        var cardIDs = workingStacks[sIdx].cardIDs
        guard index >= 0 && index < cardIDs.count - 1 else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        withAnimation(.snappy(duration: 0.22)) {
            cardIDs.swapAt(index, index + 1)
            workingStacks[sIdx].cardIDs = cardIDs
        }
    }

    private func removeCard(_ bookID: UUID) {
        guard let sIdx = currentStackIndex else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        withAnimation(.snappy(duration: 0.22)) {
            workingStacks[sIdx].cardIDs.removeAll { $0 == bookID }
        }
    }

    private func addCard(_ bookID: UUID) {
        guard let sIdx = currentStackIndex else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        withAnimation(.snappy(duration: 0.22)) {
            if !workingStacks[sIdx].cardIDs.contains(bookID) {
                workingStacks[sIdx].cardIDs.append(bookID)
            }
        }
    }

    private func toggleAlwaysHidden(for bookID: UUID, isHidden: Bool) {
        if isHidden {
            alwaysHiddenIDs.insert(bookID)
            for i in workingStacks.indices {
                workingStacks[i].cardIDs.removeAll { $0 == bookID }
            }
        } else {
            alwaysHiddenIDs.remove(bookID)
            if let idx = currentStackIndex, !workingStacks[idx].cardIDs.contains(bookID) {
                workingStacks[idx].cardIDs.append(bookID)
            }
        }
    }

    private func saveChanges() {
        if let idx = currentStackIndex {
            let trimmed = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
            workingStacks[idx].name = trimmed.isEmpty ? "Stack" : String(trimmed.prefix(40))
            workingStacks[idx].icon = selectedIcon
        }

        for book in model.books {
            let shouldBeHidden = alwaysHiddenIDs.contains(book.id)
            let wasHidden = model.alwaysHiddenBookIDs.contains(book.id)
            if shouldBeHidden != wasHidden {
                model.setCardAlwaysHidden(id: book.id, isHidden: shouldBeHidden)
            }
        }

        model.stacks = workingStacks
        model.activeStackID = currentStackID
        model.filterScope = .activeStack
        model.persistWorkspacePreferences()
    }
}
