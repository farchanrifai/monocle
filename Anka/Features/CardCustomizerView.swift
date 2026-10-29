import SwiftUI
import PhotosUI

struct CardCustomizerView: View {
    @Bindable var model: AppModel
    let initialCard: Card?
    let isCreatingNewCard: Bool
    /// Unsaved drafts, mirrored out so Home shows edits behind the sheet. Cleared by Home when the sheet goes away.
    @Binding var previewOverrides: [UUID: CardCustomization]
    var onDismiss: () -> Void

    private let placeholderID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    @State private var customizerCards: [Card]
    @State private var newCardIDs: Set<UUID>
    @State private var activeCardID: UUID?
    @State private var settledCardID: UUID
    @State private var drafts: [UUID: CardCustomization]
    @State private var draftNames: [UUID: String]
    @FocusState private var isNameFieldFocused: Bool
    @State private var detent: PresentationDetent = .large
    @State private var customColor: Color = .orange
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isProcessingPhoto = false
    @State private var photoError: String? = nil
    @State private var cardCategorySelections: [UUID: Set<UUID>]
    @State private var editingCategoriesForCardID: UUID? = nil

    private let previewSideInset: CGFloat = 28
    private let swatchWidth: CGFloat = 96

    init(
        model: AppModel,
        initialCard: Card? = nil,
        cards: [Card]? = nil,
        isCreatingNewCard: Bool = false,
        previewOverrides: Binding<[UUID: CardCustomization]> = .constant([:]),
        onDismiss: @escaping () -> Void
    ) {
        self.model = model
        self.initialCard = initialCard
        self.isCreatingNewCard = isCreatingNewCard
        self._previewOverrides = previewOverrides
        self.onDismiss = onDismiss

        let visibleCards = cards ?? {
            let list = model.orderedCards.filter { !model.hiddenCardIDs.contains($0.id) }
            return list.isEmpty ? model.cards : list
        }()

        var cardsList: [Card] = []
        var initialDrafts: [UUID: CardCustomization] = [:]
        var initialNames: [UUID: String] = [:]
        var initialNewIDs: Set<UUID> = []
        var activeID: UUID?

        if let initCard = initialCard {
            if !visibleCards.contains(where: { $0.id == initCard.id }) {
                cardsList = [initCard] + visibleCards
            } else {
                cardsList = visibleCards
            }
            activeID = initCard.id
        } else {
            cardsList = visibleCards
            activeID = visibleCards.first?.id
        }

        var initialCategorySelections: [UUID: Set<UUID>] = [:]
        for b in cardsList {
            initialDrafts[b.id] = model.customization(for: b.id)
            initialNames[b.id] = b.name
            initialCategorySelections[b.id] = model.activeCategoryIDs(for: b.id)
        }

        if isCreatingNewCard {
            let newID = UUID()
            let nextIndex = cardsList.count + 1
            let defaultName = "New Card \(nextIndex)"
            let defaultPaletteIndex = cardsList.count % CardPalette.standard.count
            let newDraftCard = Card(id: newID, name: defaultName, kind: .real, colorIndex: defaultPaletteIndex)

            cardsList.append(newDraftCard)
            initialNewIDs.insert(newID)
            initialDrafts[newID] = CardCustomization(style: .palette(index: defaultPaletteIndex), textTone: .auto)
            initialNames[newID] = defaultName
            let defaults = Set(model.globalCategories.filter(\.defaultActiveForNewCards).map(\.id))
            initialCategorySelections[newID] = defaults.isEmpty ? Set(model.globalCategories.map(\.id)) : defaults
            activeID = newID
        }

        _cardCategorySelections = State(initialValue: initialCategorySelections)
        _customizerCards = State(initialValue: cardsList)
        _newCardIDs = State(initialValue: initialNewIDs)
        _drafts = State(initialValue: initialDrafts)
        _draftNames = State(initialValue: initialNames)
        _activeCardID = State(initialValue: activeID)
        let initialSettledID = activeID ?? cardsList.first?.id ?? placeholderID
        _settledCardID = State(initialValue: initialSettledID)

        if let targetID = activeID, let custom = initialDrafts[targetID], case .customColor(let hex) = custom.style {
            _customColor = State(initialValue: CardPalette.color(fromHex: hex))
        }
    }

    init(model: AppModel, card: Card, onDismiss: @escaping () -> Void) {
        self.init(model: model, initialCard: card, cards: nil, isCreatingNewCard: false, onDismiss: onDismiss)
    }

    private var currentCardID: UUID {
        activeCardID ?? settledCardID
    }

    private var activeCard: Card {
        customizerCards.first(where: { $0.id == currentCardID }) ?? initialCard ?? Card.demo
    }

    private var currentDraft: Binding<CardCustomization> {
        Binding(
            get: {
                drafts[currentCardID] ?? CardCustomization(style: .palette(index: 0), textTone: .auto)
            },
            set: { newCustomization in
                if currentCardID != placeholderID {
                    drafts[currentCardID] = newCustomization
                }
            }
        )
    }

    private var currentName: Binding<String> {
        Binding(
            get: { draftNames[currentCardID] ?? customizerCards.first(where: { $0.id == currentCardID })?.name ?? activeCard.name },
            set: { draftNames[currentCardID] = String($0.prefix(40)) }
        )
    }

    /// Trimmed names; a blank one falls back to the card's current name.
    private func finalNames() -> [UUID: String] {
        draftNames.reduce(into: [:]) { result, entry in
            let trimmed = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
            let original = customizerCards.first(where: { $0.id == entry.key })?.name ?? "Card"
            result[entry.key] = trimmed.isEmpty ? original : String(trimmed.prefix(40))
        }
    }

    var body: some View {
        NavigationStack {
          VStack(spacing: 0) {
            // Live preview stays put while the controls scroll under it.
            cardCarousel
                .padding(.top, 8)
                .padding(.bottom, 4)
            Form {
                if currentCardID == placeholderID {
                    Section {
                        placeholderControlsSection
                    }
                    .listRowBackground(Color.clear)
                } else {
                    nameSection
                    styleSection
                    colorSection
                    photoSection
                    textToneSection
                    categoriesSection
                }
            }
            .contentMargins(.top, 8, for: .scrollContent)
          }
          .background(Color(uiColor: .systemGroupedBackground))
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(isCreatingNewCard ? "New Card" : "Customize Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .accessibilityIdentifier("cancelCardCustomization")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try model.applyCardCustomizations(names: finalNames(), customizations: drafts,
                                                              newCardIDs: Set(newCardIDs), selections: cardCategorySelections)
                            onDismiss()
                        } catch { model.report(error) }
                    }
                    .font(.headline)
                    .accessibilityIdentifier("saveCardCustomization")
                }
            }
            .sheet(isPresented: Binding(
                get: { editingCategoriesForCardID != nil },
                set: { if !$0 { editingCategoriesForCardID = nil } }
            )) {
                if let cardID = editingCategoriesForCardID {
                    let cardName = draftNames[cardID] ?? customizerCards.first(where: { $0.id == cardID })?.name ?? "Card"
                    CardCategoryPickerSheet(
                        cardName: cardName,
                        globalCategories: model.globalCategories,
                        selectedIDs: Binding(
                            get: { cardCategorySelections[cardID] ?? [] },
                            set: { cardCategorySelections[cardID] = $0 }
                        )
                    )
                }
            }
            .onAppear {
                if isCreatingNewCard, let active = activeCardID, newCardIDs.contains(active) {
                    isNameFieldFocused = true
                }
            }
            .onDisappear {
                photoTask?.cancel()
                let retained = Set(model.workspacePreferences.cardCustomizations.values.compactMap { custom -> String? in
                    if case .customPhoto(let filename) = custom.style { return filename }
                    return nil
                })
                for filename in preparedPhotoFilenames where !retained.contains(filename) {
                    CardArtworkStore.shared.deleteArtwork(filename: filename)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                loadSelectedPhoto(newItem)
            }
            .onChange(of: drafts) { _, newDrafts in
                previewOverrides = newDrafts.filter { !newCardIDs.contains($0.key) }
            }
            .onChange(of: activeCardID) { oldID, newID in
                if let newID, newID != oldID {
                    UISelectionFeedbackGenerator().selectionChanged()
                    settledCardID = newID
                    if newID != placeholderID, let custom = drafts[newID], case .customColor(let hex) = custom.style {
                        customColor = CardPalette.color(fromHex: hex)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationBackground(Color(.systemGroupedBackground))
        .presentationDragIndicator(.visible)
    }

    private func addNewDraftCard() {
        let newID = UUID()
        let nextIndex = customizerCards.count + 1
        let defaultName = "New Card \(nextIndex)"
        let defaultPaletteIndex = customizerCards.count % CardPalette.standard.count
        let newCard = Card(id: newID, name: defaultName, kind: .real, colorIndex: defaultPaletteIndex)

        customizerCards.append(newCard)
        newCardIDs.insert(newID)
        drafts[newID] = CardCustomization(style: .palette(index: defaultPaletteIndex), textTone: .auto)
        draftNames[newID] = defaultName

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            activeCardID = newID
            settledCardID = newID
        }
        isNameFieldFocused = true
    }

    private func removeDraftCard(_ cardID: UUID) {
        guard newCardIDs.contains(cardID) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            if let index = customizerCards.firstIndex(where: { $0.id == cardID }) {
                customizerCards.remove(at: index)
            }
            newCardIDs.remove(cardID)
            drafts.removeValue(forKey: cardID)
            draftNames.removeValue(forKey: cardID)
            if activeCardID == cardID {
                let nextID = customizerCards.last?.id ?? placeholderID
                activeCardID = nextID
                settledCardID = nextID
            }
        }
    }

    // MARK: - Card Carousel
    private var cardCarousel: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(customizerCards) { card in
                        previewCard(for: card)
                            .containerRelativeFrame(.horizontal) { width, _ in max(240, width - previewSideInset * 2) }
                            .scrollTransition(.interactive) { content, phase in
                                content
                                    .scaleEffect(phase.isIdentity ? 1.0 : 0.92)
                                    .opacity(phase.isIdentity ? 1.0 : 0.65)
                            }
                            .id(card.id)
                            .onTapGesture {
                                if currentCardID != card.id {
                                    settledCardID = card.id
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        activeCardID = card.id
                                    }
                                }
                            }
                    }

                    placeholderCard
                        .containerRelativeFrame(.horizontal) { width, _ in max(240, width - previewSideInset * 2) }
                        .scrollTransition(.interactive) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1.0 : 0.92)
                                .opacity(phase.isIdentity ? 1.0 : 0.65)
                        }
                        .id(placeholderID)
                }
                .scrollTargetLayout()
                .padding(.vertical, 10)
            }
            .contentMargins(.horizontal, previewSideInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $activeCardID)
            .scrollClipDisabled()

            pageIndicator
        }
        .padding(.vertical, 4)
    }

    private var pageIndicator: some View {
        let allIDs = customizerCards.map(\.id) + [placeholderID]
        return HStack(spacing: 6) {
            ForEach(allIDs, id: \.self) { id in
                let isActive = (id == currentCardID)
                let isPlaceholder = (id == placeholderID)
                if isPlaceholder {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: isActive ? 18 : 6, height: 6)
                        .onTapGesture {
                            settledCardID = placeholderID
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                activeCardID = placeholderID
                            }
                        }
                        .accessibilityLabel("Add new card")
                } else {
                    Capsule()
                        .fill(isActive ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: isActive ? 18 : 6, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentCardID)
                        .onTapGesture {
                            settledCardID = id
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                activeCardID = id
                            }
                        }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cardCustomizerPageIndicator")
    }

    private var placeholderCard: some View {
        let isActive = (currentCardID == placeholderID)
        return Button {
            addNewDraftCard()
        } label: {
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 52, height: 52)
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(spacing: 4) {
                    Text("New Card")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text("Tap to create and customize")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            .aspectRatio(1 / CardStackMetrics.aspect, contentMode: .fit)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        Color.accentColor.opacity(isActive ? 0.6 : 0.25),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            )
            .shadow(color: Color.black.opacity(isActive ? 0.08 : 0.02), radius: isActive ? 8 : 3, y: isActive ? 3 : 1)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: currentCardID)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add new card")
        .accessibilityIdentifier("customizerPlaceholderCard")
    }

    private var placeholderControlsSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text("Add a New Card")
                    .font(.title3.bold())
                Text("Create and customize a new card. Make a card for every purpose, like Daily or a trip. Each card has its own budget and expenses.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }

            Button {
                addNewDraftCard()
            } label: {
                Label("Create New Card", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("createNewCardButton")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func previewCard(for card: Card) -> some View {
        let custom = drafts[card.id] ?? model.customization(for: card.id)
        let textStyle = CardPalette.resolvedTextColor(for: custom)
        let isNewDraft = newCardIDs.contains(card.id)
        let total = isNewDraft ? 0 : model.spent(for: card.id)
        let count = isNewDraft ? 0 : model.expenses(for: card.id).count
        let isActive = (card.id == currentCardID)
        let cardIndex = (customizerCards.firstIndex(where: { $0.id == card.id }) ?? 0) + 1
        let displayName = draftNames[card.id] ?? card.name

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isNewDraft {
                    Button {
                        removeDraftCard(card.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(textStyle.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Discard draft card")
                    .accessibilityIdentifier("discardDraftCardButton-\(card.id)")
                }

                Text(String(format: "%02d", cardIndex))
                    .font(.caption.monospaced())
            }

            Spacer(minLength: 0)

            Text(Money.format(total))
                .font(.title.bold())
                .monospacedDigit()
                .minimumScaleFactor(0.65)
            Text("\(count) EXPENSES")
                .font(.caption.monospaced())
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .aspectRatio(1 / CardStackMetrics.aspect, contentMode: .fit)
        .foregroundStyle(textStyle)
        .background(cardBackgroundView(for: custom, card: card))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(isActive ? 0.12 : 0.04), radius: isActive ? 10 : 4, y: isActive ? 4 : 2)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: currentCardID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("customizer-preview-\(card.id)")
    }

    @ViewBuilder
    private func cardBackgroundView(for custom: CardCustomization, card: Card) -> some View {
        switch custom.style {
        case .palette(let index):
            CardPalette.color(for: index)
        case .customColor(let hex):
            CardPalette.color(fromHex: hex)
        case .stock(let design):
            StockDesignBackgroundView(design: design)
        case .customPhoto(let filename):
            if let image = CardArtworkStore.shared.loadArtwork(filename: filename) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                CardPalette.color(for: card.colorIndex)
            }
        }
    }

    // MARK: - Name
    private var nameSection: some View {
        Section("Name") {
            HStack(spacing: 8) {
                TextField("Card Name", text: currentName)
                    .focused($isNameFieldFocused)
                    .submitLabel(.done)
                    .accessibilityIdentifier("cardNameInlineTextField")

                if !currentName.wrappedValue.isEmpty {
                    Button {
                        currentName.wrappedValue = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear name")
                    .accessibilityIdentifier("cardNameInlineClearButton")
                }
            }
        }
    }

    // MARK: - Style
    private var styleSection: some View {
        Section("Style") {
            ScrollView(.horizontal, showsIndicators: false) {
                let rowHeight = swatchWidth * CardStackMetrics.aspect + 26
                LazyHGrid(rows: [GridItem(.fixed(rowHeight), spacing: 12), GridItem(.fixed(rowHeight))], spacing: 12) {
                    ForEach(StockCardDesign.allCases) { design in
                        stockSwatch(design)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .listRowInsets(EdgeInsets())
        }
    }

    private func stockSwatch(_ design: StockCardDesign) -> some View {
        let isSelected: Bool = {
            if case .stock(let current) = currentDraft.wrappedValue.style { return current == design }
            return false
        }()

        return Button {
            currentDraft.wrappedValue.style = .stock(design)
        } label: {
            VStack(spacing: 6) {
                StockDesignBackgroundView(design: design)
                    .frame(width: swatchWidth, height: swatchWidth * CardStackMetrics.aspect)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2.5 : 0.5)
                    )
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(Color.accentColor)
                                .background(Circle().fill(Color.white))
                                .padding(5)
                        }
                    }

                Text(design.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: swatchWidth)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(design.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("stockDesign-\(design.id)")
    }

    // MARK: - Color
    private var colorSection: some View {
        Section("Color") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(CardPalette.standard) { item in
                        let isSelected: Bool = {
                            if case .palette(let idx) = currentDraft.wrappedValue.style {
                                return (idx % CardPalette.standard.count) == item.id
                            }
                            return false
                        }()

                        Button {
                            currentDraft.wrappedValue.style = .palette(index: item.id)
                        } label: {
                            Circle()
                                .fill(item.color)
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
                                )
                                .overlay {
                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.headline.bold())
                                            .foregroundStyle(CardPalette.isDark(hex: item.hex) ? .white : .black)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.name)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .accessibilityIdentifier("paletteColor-\(item.id)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .listRowInsets(EdgeInsets())

            ColorPicker("Custom Color", selection: Binding(
                get: {
                    if case .customColor(let hex) = currentDraft.wrappedValue.style {
                        return CardPalette.color(fromHex: hex)
                    }
                    return customColor
                },
                set: { newColor in
                    customColor = newColor
                    currentDraft.wrappedValue.style = .customColor(hex: CardPalette.hexString(from: newColor))
                }
            ), supportsOpacity: false)
            .accessibilityIdentifier("customColorPicker")
        }
    }

    // MARK: - Text Tone
    private var textToneSection: some View {
        Section("Text") {
            Picker("Text Tone", selection: currentDraft.textTone) {
                Text("Auto").tag(CardTextTone.auto)
                Text("Light").tag(CardTextTone.light)
                Text("Dark").tag(CardTextTone.dark)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("cardTextTonePicker")
        }
    }

    // MARK: - Categories
    private var categoriesSection: some View {
        Section("Categories") {
            Button {
                editingCategoriesForCardID = currentCardID
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tag.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(MC.ink)
                        .frame(width: 32, height: 32)
                        .background(MC.ink.opacity(0.08), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Categories")
                            .foregroundStyle(Color.primary)
                        let count = (cardCategorySelections[currentCardID] ?? Set(model.globalCategories.filter(\.defaultActiveForNewCards).map(\.id))).count
                        Text("\(count) of \(model.globalCategories.count) active on this card")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("cardCategoriesButton")
        }
    }

    // MARK: - Photo
    private var photoSection: some View {
        Section("Photo") {
            if case .customPhoto(let filename) = currentDraft.wrappedValue.style,
               let image = CardArtworkStore.shared.loadArtwork(filename: filename) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Replace Photo", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("replacePhotoPicker")

                Button(role: .destructive) {
                    currentDraft.wrappedValue.style = .palette(index: 0)
                } label: {
                    Label("Remove Photo", systemImage: "trash")
                }
                .accessibilityIdentifier("removePhoto")
            } else {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Choose from Photos", systemImage: "photo.badge.plus")
                }
                .accessibilityIdentifier("choosePhotoPicker")

                if isProcessingPhoto {
                    ProgressView("Preparing image...")
                        .font(.caption)
                }

                if let photoError {
                    Text(photoError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    @State private var preparedPhotoFilenames: Set<String> = []
    @State private var photoTask: Task<Void, Never>?

    private func loadSelectedPhoto(_ item: PhotosPickerItem) {
        photoTask?.cancel()
        isProcessingPhoto = true
        photoError = nil
        let targetCardID = currentCardID
        photoTask = Task {
            defer { if !Task.isCancelled { isProcessingPhoto = false } }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw BackupError.invalid
                }
                try Task.checkCancellation()
                let filename = try await Task.detached(priority: .userInitiated) {
                    try CardArtworkStore.shared.saveArtwork(data, for: targetCardID)
                }.value
                guard !Task.isCancelled else {
                    CardArtworkStore.shared.deleteArtwork(filename: filename)
                    return
                }
                preparedPhotoFilenames.insert(filename)
                drafts[targetCardID]?.style = .customPhoto(filename: filename)
                selectedPhotoItem = nil
            } catch {
                if !Task.isCancelled { photoError = "Failed to save photo: \(error.localizedDescription)" }
            }
        }
    }
}

struct CardCategoryPickerSheet: View {
    let cardName: String
    let globalCategories: [GlobalCategory]
    @Binding var selectedIDs: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("\(selectedIDs.count) of \(globalCategories.count) active")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(selectedIDs.count == globalCategories.count ? "Deselect All" : "Select All") {
                            if selectedIDs.count == globalCategories.count {
                                selectedIDs.removeAll()
                            } else {
                                selectedIDs = Set(globalCategories.map(\.id))
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.vertical, 2)

                    ForEach(globalCategories) { category in
                        HStack(spacing: 12) {
                            CategoryMark(symbol: category.symbol)
                            Text(category.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { selectedIDs.contains(category.id) },
                                set: { isOn in
                                    if isOn { selectedIDs.insert(category.id) }
                                    else { selectedIDs.remove(category.id) }
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                } header: {
                    Text("Active Categories for \(cardName)")
                } footer: {
                    Text("Only active categories will appear when adding or editing expenses on this card.")
                }
            }
            .navigationTitle("Card Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
