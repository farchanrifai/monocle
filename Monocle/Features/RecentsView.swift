import SwiftUI

struct RecentsView: View {
    @Bindable var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var days: [String] { Array(Set(model.expenses.map(\.day))).sorted(by: >) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Personal / sample book")
                        Text("A little more\nclarity, every day.").font(.system(.largeTitle, design: .default, weight: .medium)).tracking(-1.2).fixedSize(horizontal: false, vertical: true)
                    }
                    summary
                    HStack {
                        Text("Recent activity").font(.title3.weight(.semibold)).tracking(-0.5)
                        Spacer()
                        Text("\(model.expenses.count) ENTRIES").font(.caption2.monospaced()).foregroundStyle(.secondary)
                    }
                    if model.expenses.isEmpty {
                        ContentUnavailableView("A fresh page", systemImage: "plus.circle", description: Text("Your next coffee is a good place to start."))
                    }
                    ForEach(days, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Eyebrow(text: Day.title(day))
                                Spacer()
                                Text(Money.format(model.expenses.filter { $0.day == day }.reduce(0) { $0 + $1.amount }))
                                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }.padding(.bottom, 8)
                            ForEach(model.expenses.filter { $0.day == day }) { expense in
                                Button { model.edit(expense) } label: { ExpenseRow(expense: expense, model: model) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("expense-\(expense.note)")
                                    .contextMenu {
                                        Button("Edit", systemImage: "pencil") { model.edit(expense) }
                                        Button("Repeat today", systemImage: "arrow.clockwise") { model.repeatExpense(expense) }
                                        Button("Delete", systemImage: "trash", role: .destructive) { model.delete(expense) }
                                    }
                                Divider().overlay(MC.line)
                            }
                        }
                    }
                    Text("PROTOTYPE 01 · Sample data for exploring the experience")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary).padding(.bottom, 12)
                }.padding(.horizontal, 24).padding(.top, 12)
            }
            .background(MC.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("monocle").font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-1.2)
                        Text(".").font(.system(size: 30, weight: .bold)).foregroundStyle(MC.red)
                    }.fixedSize(horizontal: true, vertical: false).accessibilityElement(children: .combine)
                }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "slider.horizontal.3") { model.showSettings = true }
                        .labelStyle(.iconOnly).accessibilityIdentifier("homeSettings")
                }
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .safeAreaBar(edge: .bottom) {
                VStack(spacing: 10) {
                    if let toast = model.toast {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(MC.red)
                            Text(toast).font(.subheadline)
                            Spacer()
                            if model.undoExpense != nil { Button("Undo") { model.undoDelete() }.font(.subheadline.bold()) }
                            Button { model.toast = nil; model.undoExpense = nil } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }.accessibilityLabel("Dismiss confirmation")
                        }.padding(.horizontal, 14).padding(.vertical, 6).glassEffect(in: .rect(cornerRadius: 16))
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Button { model.openEntry() } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "plus").font(.title3.weight(.medium))
                            Text(model.draft.hasContent ? "Continue expense" : "Add expense").font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if !dynamicTypeSize.isAccessibilitySize {
                                Text("IDR").font(.caption.monospaced()).opacity(0.5)
                            }
                        }.foregroundStyle(.white).padding(.horizontal, 22).frame(minHeight: 58)
                            .background(MC.ink, in: Capsule())
                    }.buttonStyle(PressFeedbackStyle()).accessibilityIdentifier("addExpense")
                }.padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 8)

            }
            .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: model.toast)
            .task(id: model.toastID) {
                guard model.toast != nil, model.undoExpense == nil else { return }
                do { try await Task.sleep(for: .seconds(2.8)) } catch { return }
                guard !Task.isCancelled else { return }
                model.toast = nil
            }
        }
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("THIS CYCLE").font(.caption2.monospaced()).tracking(1.6)
                Spacer()
                Text(model.cycle.label).font(.caption.monospaced())
            }.foregroundStyle(.white.opacity(0.6))
            Text(Money.format(model.spent)).font(.system(size: 38, weight: .medium, design: .monospaced)).tracking(-2).foregroundStyle(.white).minimumScaleFactor(0.6).lineLimit(1)
                .accessibilityLabel("Spent this cycle, \(Money.format(model.spent))")
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule().fill(MC.red).frame(width: geometry.size.width * min(1, max(0, Double(model.spent) / Double(max(1, model.settings.budget)))))
                    }
            }.frame(height: 4).accessibilityHidden(true)
            HStack {
                Text("\(Money.format(abs(model.remaining))) \(model.remaining >= 0 ? "left" : "over budget")").font(.subheadline)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption)
            }.foregroundStyle(.white.opacity(0.8))
        }.padding(22).background(MC.ink, in: RoundedRectangle(cornerRadius: 22))
            .onTapGesture { model.selectedTab = 1 }
            .accessibilityAddTraits(.isButton).accessibilityAction { model.selectedTab = 1 }
    }
}

struct ExpenseRow: View {
    let expense: Expense
    let model: AppModel
    private var category: ExpenseCategory? { model.category(expense.allocations.first?.categoryID) }
    var body: some View {
        HStack(spacing: 13) {
            CategoryMark(symbol: category?.symbol ?? "square.grid.2x2")
            VStack(alignment: .leading, spacing: 4) {
                Text(model.title(expense)).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Text(expense.allocations.count > 1 ? "Split across \(expense.allocations.count) categories" : category?.name ?? "Expense").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 5)
            Text(Money.format(expense.amount)).font(.subheadline.monospacedDigit().weight(.medium)).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.75)
        }.padding(.vertical, 9).contentShape(Rectangle())
            .accessibilityElement(children: .combine)
    }
}
