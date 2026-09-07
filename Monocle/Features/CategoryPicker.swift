import SwiftUI

/// A fixed-height capture shortcut; the complete list has its own scrolling surface.
struct CategoryStrip: View {
    let categories: [ExpenseCategory]
    let selectedID: UUID?
    let select: (UUID) -> Void
    let expand: () -> Void

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
                    .accessibilityIdentifier("categoryStrip")
                    .onChange(of: selectedID) { _, id in
                        if let id { reader.scrollTo(id, anchor: .center) }
                    }
                    .onAppear { if let selectedID { reader.scrollTo(selectedID, anchor: .center) } }
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
            List(filtered) { category in
                Button {
                    select(category.id)
                    dismiss()
                } label: {
                    HStack(spacing: 14) {
                        CategoryMark(symbol: category.symbol)
                        Text(category.name).font(.body).foregroundStyle(.primary)
                        Spacer()
                        if selectedID == category.id {
                            Image(systemName: "checkmark").foregroundStyle(MC.red).accessibilityHidden(true)
                        }
                    }.padding(.vertical, 5).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("picker-category-\(category.name)")
                    .accessibilityAddTraits(selectedID == category.id ? .isSelected : [])
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .overlay { if filtered.isEmpty { ContentUnavailableView.search(text: search) } }
            .searchable(text: $search, prompt: "Find a category")
            .navigationTitle("Categories").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
    }
}
