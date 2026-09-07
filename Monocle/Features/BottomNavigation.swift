import SwiftUI

struct BottomNavigation: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Namespace private var selection
    private let tabs = [("Recents", "list.bullet"), ("Budgets", "chart.bar.xaxis"), ("Bills", "calendar")]

    var body: some View {
        VStack(spacing: 12) {
            if let toast = model.toast {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(MC.red)
                    Text(toast).font(.subheadline)
                    Spacer()
                    if model.undoExpense != nil { Button("Undo") { model.undoDelete() } }
                    Button { model.toast = nil; model.undoExpense = nil } label: {
                        Image(systemName: "xmark").frame(width: 36, height: 44)
                    }.accessibilityLabel("Dismiss confirmation")
                }.padding(.horizontal, 14).glassEffect(in: .rect(cornerRadius: 18))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 16) {
                    HStack(spacing: 0) {
                        ForEach(tabs.indices, id: \.self) { index in
                            Button { model.selectedTab = index } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: tabs[index].1).font(.system(size: 20, weight: .semibold))
                                    if !typeSize.isAccessibilitySize {
                                        Text(tabs[index].0).font(.system(size: 10, weight: .semibold))
                                    }
                                }.frame(maxWidth: .infinity).frame(height: 54)
                                    .foregroundStyle(model.selectedTab == index ? MC.red : Color.primary)
                                    .background {
                                        if model.selectedTab == index {
                                            Capsule().fill(Color.primary.opacity(0.08)).matchedGeometryEffect(id: "selected", in: selection)
                                        }
                                    }.contentShape(Capsule())
                            }.buttonStyle(.plain)
                                .accessibilityLabel(tabs[index].0)
                                .accessibilityAddTraits(model.selectedTab == index ? .isSelected : [])
                                .accessibilityIdentifier("tab-\(tabs[index].0)")
                        }
                    }.padding(5).glassEffect(in: .capsule)
                    Button { model.openEntry() } label: {
                        Image(systemName: "plus").font(.system(size: 26, weight: .medium))
                            .foregroundStyle(.white).frame(width: 64, height: 64)
                    }.buttonStyle(.plain)
                        .glassEffect(.regular.tint(MC.ink).interactive(), in: .circle)
                        .environment(\.colorScheme, .dark)
                        .accessibilityLabel(model.draft.hasContent ? "Continue expense" : "Add expense")
                        .accessibilityIdentifier("addExpense")
                }
            }
        }.padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 8)
            .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.selectedTab)
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.toast)
            .sensoryFeedback(.selection, trigger: model.selectedTab)
            .task(id: model.toastID) {
                guard model.toast != nil, model.undoExpense == nil else { return }
                do { try await Task.sleep(for: .seconds(2.8)) } catch { return }
                guard !Task.isCancelled else { return }
                model.toast = nil
            }
    }
}
