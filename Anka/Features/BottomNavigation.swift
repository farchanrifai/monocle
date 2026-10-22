import SwiftUI
import UIKit

struct BottomNavigation: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDetail: Bool {
        model.selectedCardID != nil
    }

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
                }
                .padding(.horizontal, 14)
                .glassEffect(in: .rect(cornerRadius: 18))
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    if !isDetail {
                        chatButton
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                        tabSwitcher
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        Spacer(minLength: 0)
                    }
                    addButton
                    if isDetail {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.toast)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.44, dampingFraction: 0.76), value: isDetail)
        .sensoryFeedback(.selection, trigger: model.filterScope)
        .sensoryFeedback(.selection, trigger: model.activeStackID)
        .task(id: model.toastID) {
            guard model.toast != nil, model.undoExpense == nil else { return }
            do { try await Task.sleep(for: .seconds(2.8)) } catch { return }
            guard !Task.isCancelled else { return }
        model.toast = nil
        }
    }

    private var tabSwitcher: some View {
        NativeTabSwitcher(selection: $model.selectedTab)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .offset(y: 10.5)
    }

    private var chatButton: some View {
        Button {
            model.showChat = true
        } label: {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.primary)
                .frame(width: 60, height: 60)
                .contentShape(Circle())
        }
        .buttonStyle(PressFeedbackStyle())
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Chat")
        .accessibilityIdentifier("chatButton")
    }

    private var addButton: some View {
        Button {
            let targetID = model.selectedCardID ?? model.activeCardID
            model.openEntry(for: targetID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                if isDetail {
                    Text("Add Expense")
                        .font(.system(size: 14.5, weight: .semibold))
                        .lineLimit(1)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isDetail ? 24 : 0)
            .frame(width: isDetail ? nil : 60, height: isDetail ? 56 : 60)
        }
        .buttonStyle(PressFeedbackStyle())
        .glassEffect(.regular.tint(MC.red.opacity(0.85)).interactive(), in: .capsule)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(model.draft.hasContent ? "Continue expense" : "Add expense")
        .accessibilityIdentifier("addExpense")
    }
}

private struct NativeTabSwitcher: UIViewRepresentable {
    @Binding var selection: Int

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeUIView(context: Context) -> UITabBar {
        let tabBar = UITabBar()
        let home = UITabBarItem(title: "Home", image: UIImage(systemName: "house"), selectedImage: UIImage(systemName: "house.fill"))
        let budgets = UITabBarItem(title: "Budgets", image: UIImage(systemName: "chart.pie"), selectedImage: UIImage(systemName: "chart.pie.fill"))
        home.tag = 0
        budgets.tag = 1
        home.accessibilityIdentifier = "homeTab"
        budgets.accessibilityIdentifier = "budgetsTab"
        tabBar.items = [home, budgets]
        tabBar.selectedItem = home
        tabBar.itemPositioning = .fill
        tabBar.delegate = context.coordinator
        return tabBar
    }

    func updateUIView(_ tabBar: UITabBar, context: Context) {
        context.coordinator.selection = $selection
        tabBar.selectedItem = tabBar.items?.first { $0.tag == selection }
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var selection: Binding<Int>

        init(selection: Binding<Int>) { self.selection = selection }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            selection.wrappedValue = item.tag
        }
    }
}

extension View {
    /// For a screen pushed over Home: hides the floating bottom bar while it is on screen.
    func hidesBottomNavigation(_ model: AppModel) -> some View {
        onAppear { model.pushedDepth += 1 }
            .onDisappear { model.pushedDepth = max(0, model.pushedDepth - 1) }
    }
}

// A pushed screen that hides its navigation bar (Analytics keeps its own header) would lose the edge swipe back.
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
