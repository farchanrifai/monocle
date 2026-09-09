import SwiftUI
import PhotosUI

enum CustomizerTab: String, CaseIterable, Identifiable {
    case colors = "Colors"
    case stock = "Stock"
    case photo = "Photo"

    var id: String { rawValue }
}

struct CardCustomizerView: View {
    @Bindable var model: AppModel
    let initialBook: BookProfile?
    let isCreatingNewBook: Bool
    var onDismiss: () -> Void

    private let placeholderID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    @State private var customizerBooks: [BookProfile]
    @State private var newBookIDs: Set<UUID>
    @State private var activeBookID: UUID?
    @State private var drafts: [UUID: BookCardCustomization]
    @State private var draftNames: [UUID: String]
    @State private var editingBookNameID: UUID? = nil
    @FocusState private var isNameFieldFocused: Bool
    @State private var selectedTab: CustomizerTab = .colors
    @State private var customColor: Color = .orange
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isProcessingPhoto = false
    @State private var photoError: String? = nil

    init(
        model: AppModel,
        initialBook: BookProfile? = nil,
        books: [BookProfile]? = nil,
        isCreatingNewBook: Bool = false,
        onDismiss: @escaping () -> Void
    ) {
        self.model = model
        self.initialBook = initialBook
        self.isCreatingNewBook = isCreatingNewBook
        self.onDismiss = onDismiss

        let visibleBooks = books ?? {
            let list = model.orderedBooks.filter { !model.hiddenBookIDs.contains($0.id) }
            return list.isEmpty ? model.books : list
        }()

        var booksList: [BookProfile] = []
        var initialDrafts: [UUID: BookCardCustomization] = [:]
        var initialNames: [UUID: String] = [:]
        var initialNewIDs: Set<UUID> = []
        var activeID: UUID?

        if let initBook = initialBook {
            if !visibleBooks.contains(where: { $0.id == initBook.id }) {
                booksList = [initBook] + visibleBooks
            } else {
                booksList = visibleBooks
            }
            activeID = initBook.id
        } else {
            booksList = visibleBooks
            activeID = visibleBooks.first?.id
        }

        for b in booksList {
            initialDrafts[b.id] = model.customization(for: b.id)
            initialNames[b.id] = b.name
        }

        if isCreatingNewBook {
            let newID = UUID()
            let nextIndex = booksList.count + 1
            let defaultName = "New Book \(nextIndex)"
            let defaultPaletteIndex = booksList.count % CardPalette.standard.count
            let newDraftBook = BookProfile(id: newID, name: defaultName, kind: .real, colorIndex: defaultPaletteIndex)

            booksList.append(newDraftBook)
            initialNewIDs.insert(newID)
            initialDrafts[newID] = BookCardCustomization(style: .palette(index: defaultPaletteIndex), textTone: .auto)
            initialNames[newID] = defaultName
            activeID = newID
            _editingBookNameID = State(initialValue: newID)
        }

        _customizerBooks = State(initialValue: booksList)
        _newBookIDs = State(initialValue: initialNewIDs)
        _drafts = State(initialValue: initialDrafts)
        _draftNames = State(initialValue: initialNames)
        _activeBookID = State(initialValue: activeID)

        if let targetID = activeID, let custom = initialDrafts[targetID], case .customColor(let hex) = custom.style {
            _customColor = State(initialValue: CardPalette.color(fromHex: hex))
        }
    }

    init(model: AppModel, book: BookProfile, onDismiss: @escaping () -> Void) {
        self.init(model: model, initialBook: book, books: nil, isCreatingNewBook: false, onDismiss: onDismiss)
    }

    private var currentBookID: UUID {
        activeBookID ?? initialBook?.id ?? customizerBooks.first?.id ?? placeholderID
    }

    private var activeBook: BookProfile {
        customizerBooks.first(where: { $0.id == currentBookID }) ?? initialBook ?? BookProfile.sample
    }

    private var currentDraft: Binding<BookCardCustomization> {
        Binding(
            get: {
                drafts[currentBookID] ?? BookCardCustomization(style: .palette(index: 0), textTone: .auto)
            },
            set: { newCustomization in
                if currentBookID != placeholderID {
                    drafts[currentBookID] = newCustomization
                }
            }
        )
    }

    var body: some View {
        NavigationStack {
            GeometryReader { windowProxy in
                let screenWidth = windowProxy.size.width
                ScrollView {
                    VStack(spacing: 20) {
                        // MARK: - Live Preview Carousel
                        cardCarousel(width: screenWidth)
                            .padding(.top, 8)

                        if currentBookID == placeholderID {
                            placeholderControlsSection
                        } else {
                            // MARK: - Text Tone Picker
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Text Tone")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)

                                Picker("Text Tone", selection: currentDraft.textTone) {
                                    Text("Auto").tag(CardTextTone.auto)
                                    Text("Light").tag(CardTextTone.light)
                                    Text("Dark").tag(CardTextTone.dark)
                                }
                                .pickerStyle(.segmented)
                                .accessibilityIdentifier("cardTextTonePicker")
                            }
                            .padding(.horizontal, 20)

                            // MARK: - Category Tabs
                            Picker("Customization Mode", selection: $selectedTab) {
                                ForEach(CustomizerTab.allCases) { tab in
                                    Text(tab.rawValue).tag(tab)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal, 20)
                            .accessibilityIdentifier("cardCustomizerTabPicker")

                            // MARK: - Tab Content
                            switch selectedTab {
                            case .colors:
                                colorsSection
                            case .stock:
                                stockSection
                            case .photo:
                                photoSection
                            }
                        }
                    }
                    .frame(width: screenWidth)
                    .padding(.bottom, 60)
                }
                .scrollBounceBehavior(.always)
            }
            .navigationTitle(isCreatingNewBook ? "New Book" : "Customize Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let editingID = editingBookNameID {
                            commitEditingName(for: editingID)
                        }

                        // 1. Create newly added books
                        for bookID in newBookIDs {
                            if let book = customizerBooks.first(where: { $0.id == bookID }) {
                                let rawName = draftNames[bookID] ?? book.name
                                let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                                let finalName = trimmed.isEmpty ? "New Book" : String(trimmed.prefix(40))
                                if let created = try? model.createBook(named: finalName) {
                                    if let custom = drafts[bookID] {
                                        model.updateCustomization(custom, for: created.id)
                                    }
                                    model.selectedBookID = created.id
                                }
                            }
                        }

                        // 2. Rename existing books
                        for (bookID, newName) in draftNames where !newBookIDs.contains(bookID) {
                            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty,
                               let book = customizerBooks.first(where: { $0.id == bookID }),
                               book.name != trimmed {
                                try? model.renameBook(id: bookID, to: trimmed)
                            }
                        }

                        // 3. Update customizations for existing books
                        for (bookID, custom) in drafts where !newBookIDs.contains(bookID) {
                            if custom != model.customization(for: bookID) {
                                model.updateCustomization(custom, for: bookID)
                            }
                        }
                        onDismiss()
                    }
                    .font(.headline)
                    .accessibilityIdentifier("saveCardCustomization")
                }
            }
            .onAppear {
                if isCreatingNewBook, let active = activeBookID, newBookIDs.contains(active) {
                    isNameFieldFocused = true
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                loadSelectedPhoto(newItem)
            }
            .onChange(of: activeBookID) { _, newID in
                if let editingID = editingBookNameID, editingID != newID {
                    commitEditingName(for: editingID)
                }
                if let targetID = newID, targetID != placeholderID, let custom = drafts[targetID], case .customColor(let hex) = custom.style {
                    customColor = CardPalette.color(fromHex: hex)
                }
            }
        }
    }

    private func addNewDraftBook() {
        let newID = UUID()
        let nextIndex = customizerBooks.count + 1
        let defaultName = "New Book \(nextIndex)"
        let defaultPaletteIndex = customizerBooks.count % CardPalette.standard.count
        let newBook = BookProfile(id: newID, name: defaultName, kind: .real, colorIndex: defaultPaletteIndex)

        customizerBooks.append(newBook)
        newBookIDs.insert(newID)
        drafts[newID] = BookCardCustomization(style: .palette(index: defaultPaletteIndex), textTone: .auto)
        draftNames[newID] = defaultName

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            activeBookID = newID
        }
        startEditingName(for: newID)
    }

    private func removeDraftBook(_ bookID: UUID) {
        guard newBookIDs.contains(bookID) else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            if let index = customizerBooks.firstIndex(where: { $0.id == bookID }) {
                customizerBooks.remove(at: index)
            }
            newBookIDs.remove(bookID)
            drafts.removeValue(forKey: bookID)
            draftNames.removeValue(forKey: bookID)
            if activeBookID == bookID {
                activeBookID = customizerBooks.last?.id ?? placeholderID
            }
        }
    }

    private func startEditingName(for bookID: UUID) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            editingBookNameID = bookID
            isNameFieldFocused = true
        }
    }

    private func commitEditingName(for bookID: UUID) {
        if let current = draftNames[bookID] {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                let original = customizerBooks.first(where: { $0.id == bookID })?.name ?? "Book"
                draftNames[bookID] = original
            } else {
                draftNames[bookID] = String(trimmed.prefix(40))
            }
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            editingBookNameID = nil
            isNameFieldFocused = false
        }
    }

    // MARK: - Card Carousel
    private func cardCarousel(width: CGFloat) -> some View {
        let sideInset: CGFloat = 36
        let spacing: CGFloat = 12
        let cardWidth = max(240, width - (sideInset * 2))

        return VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: spacing) {
                    ForEach(customizerBooks) { book in
                        previewCard(for: book)
                            .frame(width: cardWidth)
                            .id(book.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if currentBookID != book.id {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                        activeBookID = book.id
                                    }
                                }
                            }
                    }

                    placeholderCard(cardWidth: cardWidth)
                        .frame(width: cardWidth)
                        .id(placeholderID)
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, sideInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $activeBookID)
            .frame(height: 204)

            pageIndicator
        }
        .frame(width: width)
    }

    private var pageIndicator: some View {
        let allIDs = customizerBooks.map(\.id) + [placeholderID]
        return HStack(spacing: 6) {
            ForEach(allIDs, id: \.self) { id in
                let isActive = (id == currentBookID)
                let isPlaceholder = (id == placeholderID)
                if isPlaceholder {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(isActive ? Color.accentColor : Color.secondary.opacity(0.4))
                        .frame(width: isActive ? 18 : 6, height: 6)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                activeBookID = placeholderID
                            }
                        }
                        .accessibilityLabel("Add new book")
                } else {
                    Capsule()
                        .fill(isActive ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: isActive ? 18 : 6, height: 6)
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentBookID)
                        .onTapGesture {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                activeBookID = id
                            }
                        }
                }
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cardCustomizerPageIndicator")
    }

    private func placeholderCard(cardWidth: CGFloat) -> some View {
        let isActive = (currentBookID == placeholderID)
        return Button {
            addNewDraftBook()
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
                    Text("New Book")
                        .font(.headline)
                        .foregroundStyle(Color.primary)
                    Text("Tap to create and customize")
                        .font(.caption)
                        .foregroundStyle(Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)
            .frame(height: 190)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        Color.accentColor.opacity(isActive ? 0.6 : 0.25),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                    )
            )
            .shadow(color: Color.black.opacity(isActive ? 0.08 : 0.02), radius: isActive ? 8 : 3, y: isActive ? 3 : 1)
            .scaleEffect(isActive ? 1.0 : 0.96)
            .animation(.spring(response: 0.35, dampingFraction: 0.82), value: currentBookID)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add new book")
        .accessibilityIdentifier("customizerPlaceholderCard")
    }

    private var placeholderControlsSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            VStack(spacing: 6) {
                Text("Add a New Book")
                    .font(.title3.bold())
                Text("Create and customize a new personal expense book. Each book gets its own card, currency, and categories.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                addNewDraftBook()
            } label: {
                Label("Create New Card", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            .accessibilityIdentifier("createNewCardButton")
        }
        .padding(.top, 24)
    }

    private func previewCard(for book: BookProfile) -> some View {
        let custom = drafts[book.id] ?? model.customization(for: book.id)
        let textStyle = CardPalette.resolvedTextColor(for: custom)
        let isNewDraft = newBookIDs.contains(book.id)
        let total = isNewDraft ? 0 : model.spent(for: book.id)
        let count = isNewDraft ? 0 : model.expenses(for: book.id).count
        let isActive = (book.id == currentBookID)
        let bookIndex = (customizerBooks.firstIndex(where: { $0.id == book.id }) ?? 0) + 1
        let isEditingThisName = (editingBookNameID == book.id)
        let displayName = draftNames[book.id] ?? book.name

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                if isEditingThisName {
                    HStack(spacing: 6) {
                        TextField(
                            "Card Name",
                            text: Binding(
                                get: { draftNames[book.id] ?? book.name },
                                set: { draftNames[book.id] = $0 }
                            )
                        )
                        .font(.headline)
                        .foregroundStyle(textStyle)
                        .textFieldStyle(.plain)
                        .focused($isNameFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            commitEditingName(for: book.id)
                        }
                        .accessibilityIdentifier("cardNameInlineTextField")

                        if !(draftNames[book.id] ?? "").isEmpty {
                            Button {
                                draftNames[book.id] = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(textStyle.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("cardNameInlineClearButton")
                        }

                        Button {
                            commitEditingName(for: book.id)
                        } label: {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(textStyle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cardNameInlineCommitButton")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(textStyle.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(textStyle.opacity(0.3), lineWidth: 1)
                    )
                } else {
                    if isActive {
                        Button {
                            startEditingName(for: book.id)
                        } label: {
                            HStack(spacing: 5) {
                                Text(displayName)
                                    .font(.headline)
                                    .lineLimit(1)
                                Image(systemName: "pencil")
                                    .font(.caption2.weight(.semibold))
                                    .opacity(0.7)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("cardNameButton-\(book.id)")
                    } else {
                        Text(displayName)
                            .font(.headline)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if isNewDraft {
                    Button {
                        removeDraftBook(book.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(textStyle.opacity(0.75))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Discard draft card")
                    .accessibilityIdentifier("discardDraftCardButton-\(book.id)")
                }

                Text(String(format: "%02d", bookIndex))
                    .font(.caption.monospaced())
            }

            Spacer(minLength: 0)

            Text(Money.format(total))
                .font(.title.bold())
                .monospacedDigit()
                .minimumScaleFactor(0.65)
            Text("\(count) TRANSACTIONS")
                .font(.caption.monospaced())
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 190, alignment: .topLeading)
        .foregroundStyle(textStyle)
        .background(cardBackgroundView(for: custom, book: book))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(isActive ? 0.12 : 0.04), radius: isActive ? 10 : 4, y: isActive ? 4 : 2)
        .scaleEffect(isActive ? 1.0 : 0.96)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: currentBookID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("customizer-preview-\(book.id)")
    }

    @ViewBuilder
    private func cardBackgroundView(for custom: BookCardCustomization, book: BookProfile) -> some View {
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
                CardPalette.color(for: book.colorIndex)
            }
        }
    }

    // MARK: - Colors Section
    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Palette")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 12)], spacing: 12) {
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
                            .frame(width: 52, height: 52)
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
                    .accessibilityIdentifier("paletteColor-\(item.id)")
                }
            }

            Divider()
                .padding(.vertical, 4)

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
            .font(.subheadline.weight(.medium))
            .accessibilityIdentifier("customColorPicker")
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Stock Section
    private var stockSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stock Designs")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(StockCardDesign.allCases) { design in
                    let isSelected: Bool = {
                        if case .stock(let current) = currentDraft.wrappedValue.style {
                            return current == design
                        }
                        return false
                    }()

                    Button {
                        currentDraft.wrappedValue.style = .stock(design)
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            StockDesignBackgroundView(design: design)
                                .frame(maxWidth: .infinity)
                                .frame(height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(isSelected ? Color.accentColor : Color.black.opacity(0.12), lineWidth: isSelected ? 2.5 : 0.5)
                                )
                                .overlay(alignment: .topTrailing) {
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(Color.accentColor)
                                            .background(Circle().fill(Color.white))
                                            .padding(6)
                                    }
                                }

                            Text(design.displayName)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(design.displayName)
                    .accessibilityIdentifier("stockDesign-\(design.id)")
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Photo Section
    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Photo")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if case .customPhoto(let filename) = currentDraft.wrappedValue.style,
               let image = CardArtworkStore.shared.loadArtwork(filename: filename) {
                VStack(spacing: 12) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5))

                    HStack(spacing: 12) {
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Label("Replace", systemImage: "arrow.triangle.2.circlepath")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.secondary.opacity(0.12), in: Capsule())
                        }
                        .accessibilityIdentifier("replacePhotoPicker")

                        Button(role: .destructive) {
                            currentDraft.wrappedValue.style = .palette(index: 0)
                        } label: {
                            Label("Remove", systemImage: "trash")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.12), in: Capsule())
                        }
                        .accessibilityIdentifier("removePhoto")
                    }
                }
            } else {
                VStack(spacing: 16) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary)

                            Text("Choose from Photos")
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text("Recommended for horizontal photos and card artwork.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        )
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
        .padding(.horizontal, 20)
    }

    private func loadSelectedPhoto(_ item: PhotosPickerItem) {
        isProcessingPhoto = true
        photoError = nil
        let targetBookID = currentBookID
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    await MainActor.run {
                        self.photoError = "Could not read photo data."
                        self.isProcessingPhoto = false
                    }
                    return
                }
                let filename = try CardArtworkStore.shared.saveArtwork(data, for: targetBookID)
                await MainActor.run {
                    self.drafts[targetBookID]?.style = .customPhoto(filename: filename)
                    self.isProcessingPhoto = false
                    self.selectedPhotoItem = nil
                }
            } catch {
                await MainActor.run {
                    self.photoError = "Failed to save photo: \(error.localizedDescription)"
                    self.isProcessingPhoto = false
                }
            }
        }
    }
}
