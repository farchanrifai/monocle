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
    let book: BookProfile
    var onDismiss: () -> Void

    @State private var draft: BookCardCustomization
    @State private var selectedTab: CustomizerTab = .colors
    @State private var customColor: Color = .orange
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var isProcessingPhoto = false
    @State private var photoError: String? = nil

    init(model: AppModel, book: BookProfile, onDismiss: @escaping () -> Void) {
        self.model = model
        self.book = book
        self.onDismiss = onDismiss
        _draft = State(initialValue: model.customization(for: book.id))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Live Preview Card
                    cardPreview
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    // MARK: - Text Tone Picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Text Tone")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        Picker("Text Tone", selection: $draft.textTone) {
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
                .padding(.bottom, 60)
            }
            .scrollBounceBehavior(.always)
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
                        model.updateCustomization(draft, for: book.id)
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
        }
    }

    // MARK: - Card Preview
    private var cardPreview: some View {
        let textStyle = CardPalette.resolvedTextColor(for: draft)
        let total = model.spent(for: book.id)
        let count = model.expenses(for: book.id).count

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(book.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(book.kind == .sample ? "01" : "02")
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
        .background(cardBackgroundView)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
    }

    @ViewBuilder
    private var cardBackgroundView: some View {
        switch draft.style {
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
                Color.gray
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
                        if case .palette(let idx) = draft.style {
                            return (idx % CardPalette.standard.count) == item.id
                        }
                        return false
                    }()

                    Button {
                        draft.style = .palette(index: item.id)
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
                    if case .customColor(let hex) = draft.style {
                        return CardPalette.color(fromHex: hex)
                    }
                    return customColor
                },
                set: { newColor in
                    customColor = newColor
                    draft.style = .customColor(hex: CardPalette.hexString(from: newColor))
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
                        if case .stock(let current) = draft.style {
                            return current == design
                        }
                        return false
                    }()

                    Button {
                        draft.style = .stock(design)
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

            if case .customPhoto(let filename) = draft.style,
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
                            draft.style = .palette(index: 0)
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
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    await MainActor.run {
                        self.photoError = "Could not read photo data."
                        self.isProcessingPhoto = false
                    }
                    return
                }
                let filename = try CardArtworkStore.shared.saveArtwork(data, for: book.id)
                await MainActor.run {
                    self.draft.style = .customPhoto(filename: filename)
                    self.isProcessingPhoto = false
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
