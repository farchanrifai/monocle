import SwiftUI

struct ShortcutOrderSettingsView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .active

    private var currentOrder: [ShortcutInputField] {
        model.shortcutInputOrder
    }

    var body: some View {
        Form {
            // MARK: 1. Live Sequence Preview
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Current order")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(currentOrder.enumerated()), id: \.element.id) { index, field in
                                HStack(spacing: 6) {
                                    Text("\(index + 1)")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 18, height: 18)
                                        .background(fieldColor(for: field), in: Circle())

                                    Text(field.displayName)
                                        .font(.system(size: 13, weight: .medium))

                                    if index < currentOrder.count - 1 {
                                        Image(systemName: "arrow.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Order")
            }

            // MARK: 2. Reorderable Fields
            Section {
                ForEach(Array(currentOrder.enumerated()), id: \.element.id) { index, field in
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(fieldColor(for: field).opacity(0.15))
                                .frame(width: 32, height: 32)
                            Image(systemName: field.systemImage)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(fieldColor(for: field))
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(field.displayName)
                                .font(.body.weight(.medium))
                            Text("Step \(index + 1) of \(currentOrder.count)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        // Quick 1-tap nudge buttons
                        HStack(spacing: 12) {
                            Button {
                                moveItem(from: index, to: index - 1)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(index > 0 ? Color.accentColor : Color.secondary.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                            .disabled(index == 0)
                            .accessibilityLabel("Move \(field.displayName) up")

                            Button {
                                moveItem(from: index, to: index + 1)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(index < currentOrder.count - 1 ? Color.accentColor : Color.secondary.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                            .disabled(index == currentOrder.count - 1)
                            .accessibilityLabel("Move \(field.displayName) down")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onMove(perform: move)
            } header: {
                Text("Prompt order")
            } footer: {
                Text("Drag rows or tap arrows to reorder which detail Ankka asks for first when running the shortcut.")
            }

            // MARK: 3. Presets
            Section {
                Button {
                    applyPreset([.card, .category, .note, .amount])
                } label: {
                    presetRow(
                        title: "Card first (recommended)",
                        description: "Card → Category → Short Note → Amount",
                        isActive: currentOrder == [.card, .category, .note, .amount]
                    )
                }
                .accessibilityIdentifier("presetCardFirst")

                Button {
                    applyPreset([.amount, .card, .category, .note])
                } label: {
                    presetRow(
                        title: "Amount first",
                        description: "Amount → Card → Category → Short Note",
                        isActive: currentOrder == [.amount, .card, .category, .note]
                    )
                }
                .accessibilityIdentifier("presetAmountFirst")

                Button {
                    applyPreset([.amount, .category, .card, .note])
                } label: {
                    presetRow(
                        title: "Amount and Category first",
                        description: "Amount → Category → Card → Short Note",
                        isActive: currentOrder == [.amount, .category, .card, .note]
                    )
                }
                .accessibilityIdentifier("presetAmountCategoryFirst")

                Button {
                    applyPreset([.category, .card, .note, .amount])
                } label: {
                    presetRow(
                        title: "Category first",
                        description: "Category → Card → Short Note → Amount",
                        isActive: currentOrder == [.category, .card, .note, .amount]
                    )
                }
                .accessibilityIdentifier("presetCategoryFirst")
            } header: {
                Text("Presets")
            }

            // MARK: 4. Information
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Categories follow the card", systemImage: "sparkles")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("When Card is asked before Category, Ankka dynamically filters the category picker to only show active categories configured on that card.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()
                        .padding(.vertical, 2)

                    Label("Pre-filled steps are skipped", systemImage: "arrow.uturn.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("If you pre-fill any parameter in your Apple Shortcut action (or pass data from earlier Shortcut steps), that step is automatically skipped during execution.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } header: {
                Text("How it works")
            }
        }
        .environment(\.editMode, $editMode)
        .navigationTitle("Shortcut Input Order")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fieldColor(for field: ShortcutInputField) -> Color {
        switch field {
        case .card: return .indigo
        case .category: return .orange
        case .note: return .blue
        case .amount: return .green
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var items = model.shortcutInputOrder
        items.move(fromOffsets: source, toOffset: destination)
        model.shortcutInputOrder = items
    }

    private func moveItem(from index: Int, to newIndex: Int) {
        guard currentOrder.indices.contains(index), currentOrder.indices.contains(newIndex) else { return }
        var items = model.shortcutInputOrder
        let item = items.remove(at: index)
        items.insert(item, at: newIndex)
        model.shortcutInputOrder = items
    }

    private func applyPreset(_ preset: [ShortcutInputField]) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            model.shortcutInputOrder = preset
        }
    }

    @ViewBuilder
    private func presetRow(title: String, description: String, isActive: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }
}
