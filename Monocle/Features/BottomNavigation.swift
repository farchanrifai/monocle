import SwiftUI

struct BottomNavigation: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDetail: Bool {
        model.selectedBookID != nil
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
                HStack(spacing: 0) {
                    // Left Bubble: Filter & Stack Switcher (only on home screen)
                    if !isDetail {
                        filterMenu
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }

                    // Spacer pushes the add button to the right on home, or centers it on detail
                    Spacer(minLength: 0)

                    // Floating Red Add Button (morphs from bottom-right circle to middle-bottom expanded capsule)
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
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.filterScope)
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

    private var filterMenu: some View {
        Menu {
            Section("Stacks") {
                ForEach(model.stacks) { stack in
                    Button {
                        model.setActiveStack(id: stack.id)
                    } label: {
                        HStack {
                            Label(stack.name, systemImage: stack.icon)
                            if model.activeStackID == stack.id && model.filterScope == .activeStack {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Section {
                Button {
                    model.filterScope = .allCards
                } label: {
                    HStack {
                        Label("All Active Cards", systemImage: "rectangle.stack")
                        if model.filterScope == .allCards {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Section {
                Button {
                    model.stackCustomizerMode = .create
                    model.showStackCustomizer = true
                } label: {
                    Label("New Stack…", systemImage: "plus")
                }
                Button {
                    model.stackCustomizerMode = .manage
                    model.showStackCustomizer = true
                } label: {
                    Label("Manage Stacks & Cards…", systemImage: "slider.horizontal.3")
                }
            }
        } label: {
            Image(systemName: model.filterScope == .activeStack ? "square.stack.3d.up.fill" : "rectangle.stack")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(model.filterScope == .activeStack ? MC.red : Color.primary)
                .frame(width: 56, height: 56)
                .contentTransition(.symbolEffect(.replace))
        } primaryAction: {
            model.toggleFilterScope()
        }
        .buttonStyle(PressFeedbackStyle())
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(model.filterScope == .activeStack ? "Filter active: \(model.currentStack?.name ?? "Stack")" : "All cards")
        .accessibilityIdentifier("activityFilterButton")
    }

    private var addButton: some View {
        Button {
            let targetID = model.selectedBookID ?? model.activeBookID
            model.openEntry(for: targetID)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                if isDetail {
                    Text("Add Expense")
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, isDetail ? 24 : 0)
            .frame(width: isDetail ? nil : 56, height: 56)
        }
        .buttonStyle(PressFeedbackStyle())
        .glassEffect(.regular.tint(MC.red.opacity(0.85)).interactive(), in: .capsule)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel(model.draft.hasContent ? "Continue expense" : "Add expense")
        .accessibilityIdentifier("addExpense")
    }
}
