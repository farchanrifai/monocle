import SwiftUI

struct BottomNavigation: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                HStack {
                    // Left Bubble: Filter & Stack Switcher
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
                    } primaryAction: {
                        model.toggleFilterScope()
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(model.filterScope == .activeStack ? "Filter active: \(model.currentStack?.name ?? "Stack")" : "All cards")
                    .accessibilityIdentifier("activityFilterButton")

                    Spacer()

                    // Right Bubble: Add Expense Button
                    Button {
                        model.openEntry()
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.tint(MC.red.opacity(0.85)).interactive(), in: .circle)
                    .environment(\.colorScheme, .dark)
                    .accessibilityLabel(model.draft.hasContent ? "Continue expense" : "Add expense")
                    .accessibilityIdentifier("addExpense")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: model.filterScope)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: model.toast)
        .sensoryFeedback(.selection, trigger: model.filterScope)
        .task(id: model.toastID) {
            guard model.toast != nil, model.undoExpense == nil else { return }
            do { try await Task.sleep(for: .seconds(2.8)) } catch { return }
            guard !Task.isCancelled else { return }
            model.toast = nil
        }
    }
}
