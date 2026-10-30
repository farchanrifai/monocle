import SwiftUI

/// A fixed-height capture shortcut; the complete list has its own scrolling surface.
struct CategoryStrip: View {
    let categories: [ExpenseCategory]
    let selectedID: UUID?
    let select: (UUID) -> Void
    let expand: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Category")
            HStack(spacing: 10) {
                ScrollViewReader { reader in
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(categories) { category in
                                let selected = selectedID == category.id
                                Button { select(category.id) } label: {
                                    Label(category.name, systemImage: category.symbol)
                                        .font(.subheadline.weight(.medium)).lineLimit(1)
                                        .padding(.horizontal, 14).frame(minHeight: 46)
                                        .foregroundStyle(selected ? .white : Color.primary)
                                        .background(selected ? MC.ink : MC.surface, in: Capsule())
                                        .overlay(Capsule().stroke(selected ? MC.red : MC.line, lineWidth: selected ? 1.5 : 0.5))
                                }.buttonStyle(PressFeedbackStyle()).id(category.id)
                                    .accessibilityAddTraits(selected ? .isSelected : [])
                                    .accessibilityIdentifier("category-\(category.name)")
                            }
                        }.padding(.vertical, 3)
                    }
                    .scrollIndicators(.hidden)
                    // Chips fade out under the grid button instead of being cut at the scroll edge.
                    .contentMargins(.trailing, 20, for: .scrollContent)
                    .mask {
                        HStack(spacing: 0) {
                            Color.black
                            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 28)
                        }
                    }
                    .accessibilityIdentifier("categoryStrip")
                    .onAppear { if let selectedID { reader.scrollTo(selectedID, anchor: .center) } }
                    .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: selectedID)
                }
                Button(action: expand) {
                    Image(systemName: "square.grid.2x2").frame(width: 24, height: 28)
                }.buttonStyle(.glass).controlSize(.regular).tint(.primary)
                    .accessibilityLabel("All categories").accessibilityIdentifier("allCategories")
            }
        }
    }
}

struct CategoryPicker: View {
    let categories: [ExpenseCategory]
    let selectedID: UUID?
    let select: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var filtered: [ExpenseCategory] {
        search.isEmpty ? categories : categories.filter { $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                    ForEach(filtered) { category in
                        Button {
                            select(category.id)
                            dismiss()
                        } label: {
                            VStack(spacing: 12) {
                                Image(systemName: category.symbol).font(.title2)
                                Text(category.name).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity).frame(minHeight: 100)
                            .padding(8)
                            .foregroundStyle(selectedID == category.id ? .white : Color.primary)
                            .background(selectedID == category.id ? MC.ink : MC.surface, in: .rect(cornerRadius: 20))
                            .overlay(alignment: .topTrailing) {
                                if selectedID == category.id { Image(systemName: "checkmark.circle.fill").foregroundStyle(MC.red).padding(8) }
                            }
                        }.buttonStyle(PressFeedbackStyle())
                            .accessibilityIdentifier("picker-category-\(category.name)")
                            .accessibilityAddTraits(selectedID == category.id ? .isSelected : [])
                    }
                }.padding(20)
            }
            .background(MC.paper)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .overlay { if filtered.isEmpty { ContentUnavailableView.search(text: search) } }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a category")
            .navigationTitle("Categories").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
