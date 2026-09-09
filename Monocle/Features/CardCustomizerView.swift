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
    let initialBook: BookProfile
    let books: [BookProfile]
    var onDismiss: () -> Void

    @State private var activeBookID: UUID?
    @State private var drafts: [UUID: BookCardCustomization]
    @State private var selectedTab: CustomizerTab = .colors
    @State private var customColor: Color = .orange
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isProcessingPhoto = false
    @State private var photoError: String? = nil

    init(model: AppModel, initialBook: BookProfile, books: [BookProfile]? = nil, onDismiss: @escaping () -> Void) {
        self.model = model
        self.initialBook = initialBook
        let visibleBooks = books ?? {
            let list = model.orderedBooks.filter { !model.hiddenBookIDs.contains($0.id) }
            return list.isEmpty ? model.books : list
        }()
        if !visibleBooks.contains(where: { $0.id == initialBook.id }) {
            self.books = [initialBook] + visibleBooks
        } else {
            self.books = visibleBooks
        }
        self.onDismiss = onDismiss
        _activeBookID = State(initialValue: initialBook.id)

        var initialDrafts: [UUID: BookCardCustomization] = [:]
        for b in self.books {
            initialDrafts[b.id] = model.customization(for: b.id)
        }
        _drafts = State(initialValue: initialDrafts)

        let initialCustom = model.customization(for: initialBook.id)
        if case .customColor(let hex) = initialCustom.style {
            _customColor = State(initialValue: CardPalette.color(fromHex: hex))
        }
    }

    init(model: AppModel, book: BookProfile, onDismiss: @escaping () -> Void) {
        self.init(model: model, initialBook: book, books: nil, onDismiss: onDismiss)
    }

    private var currentBookID: UUID {
        activeBookID ?? initialBook.id
    }

    private var activeBook: BookProfile {
        books.first(where: { $0.id == currentBookID }) ?? initialBook
    }

    private var currentDraft: Binding<BookCardCustomization> {
        Binding(
            get: {
                drafts[currentBookID] ?? model.customization(for: currentBookID)
            },
            set: { newCustomization in
                drafts[currentBookID] = newCustomization
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
                    .frame(width: screenWidth)
                    .padding(.bottom, 60)
                }
                .scrollBounceBehavior(.always)
            }
            .navigationTitle("Customize Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        for (bookID, custom) in drafts {
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
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                loadSelectedPhoto(newItem)
            }
            .onChange(of: activeBookID) { _, newID in
                if let targetID = newID, let custom = drafts[targetID], case .customColor(let hex) = custom.style {
                    customColor = CardPalette.color(fromHex: hex)
                }
            }
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
                    ForEach(books) { book in
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
                }
                .scrollTargetLayout()
            }
            .contentMargins(.horizontal, sideInset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $activeBookID)
            .frame(height: 204)

            if books.count > 1 {
                pageIndicator
            }
        }
        .frame(width: width)
    }

    private var pageIndicator: some View {
        HStack(spacing: 6) {
            ForEach(books) { book in
                let isActive = book.id == currentBookID
                Capsule()
                    .fill(isActive ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: isActive ? 18 : 6, height: 6)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentBookID)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            activeBookID = book.id
                        }
                    }
                    .accessibilityLabel("Card \(book.name)")
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cardCustomizerPageIndicator")
    }

    private func previewCard(for book: BookProfile) -> some View {
        let custom = drafts[book.id] ?? model.customization(for: book.id)
        let textStyle = CardPalette.resolvedTextColor(for: custom)
        let total = model.spent(for: book.id)
        let count = model.expenses(for: book.id).count
        let isActive = (book.id == currentBookID)
        let bookIndex = (books.firstIndex(where: { $0.id == book.id }) ?? 0) + 1

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(book.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
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
        .accessibilityElement(children: .combine)
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
