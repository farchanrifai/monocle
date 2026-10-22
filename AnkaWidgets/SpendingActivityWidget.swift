import ActivityKit
import SwiftUI
import WidgetKit

struct SpendingActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SpendingActivityAttributes.self) { context in
            // Lock Screen / StandBy / Banner presentation
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(WMC.red)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Presentation
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.sessionName)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            Text(context.attributes.cardName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(context.attributes.startTime, style: .timer)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(WMC.formatIDR(context.state.currentSpent))
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(WMC.red)
                        Text("\(context.state.itemCount) \(context.state.itemCount == 1 ? "item" : "items")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if let limit = context.state.sessionBudgetLimit {
                            let ratio = min(1.0, Double(context.state.currentSpent) / Double(max(1, limit)))
                            ProgressView(value: ratio)
                                .tint(ratio > 0.9 ? WMC.red : .primary)
                            HStack {
                                Text("Budget: \(WMC.compactIDR(limit))")
                                Spacer()
                                Text("\(WMC.compactIDR(max(0, limit - context.state.currentSpent))) left")
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        } else if let note = context.state.latestItemNote, !note.isEmpty {
                            HStack(spacing: 6) {
                                if let sym = context.state.latestItemCategorySymbol {
                                    Image(systemName: sym).font(.caption2).foregroundStyle(WMC.red)
                                }
                                Text("Latest: \(note)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                            }
                        }

                        HStack {
                            Spacer()
                            Link(destination: URL(string: "anka://entry")!) {
                                Label("Add expense", systemImage: "plus")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(WMC.red, in: Capsule())
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.latestItemCategorySymbol ?? "cart.fill")
                    .font(.caption2)
                    .foregroundStyle(WMC.red)
            } compactTrailing: {
                Text(WMC.compactIDR(context.state.currentSpent))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(WMC.red)
            } minimal: {
                Text(WMC.compactIDR(context.state.currentSpent))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(WMC.red)
            }
            .widgetURL(URL(string: "anka://session"))
        }
    }
}

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<SpendingActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(WMC.red)
                        .frame(width: 7, height: 7)
                    Text("anka.")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WMC.red)
                    Text("· \(context.attributes.sessionName)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                Text(context.attributes.startTime, style: .timer)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            // Middle: Spent amount & items
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SESSION SPENT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(WMC.formatIDR(context.state.currentSpent))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundStyle(WMC.red)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(context.state.itemCount) \(context.state.itemCount == 1 ? "expense" : "expenses")")
                        .font(.caption.weight(.medium))
                    if let limit = context.state.sessionBudgetLimit {
                        Text("\(WMC.compactIDR(max(0, limit - context.state.currentSpent))) remaining")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let limit = context.state.sessionBudgetLimit {
                let ratio = min(1.0, Double(context.state.currentSpent) / Double(max(1, limit)))
                ProgressView(value: ratio)
                    .tint(ratio > 0.9 ? WMC.red : .white)
            }

            // Footer
            HStack {
                if let note = context.state.latestItemNote, !note.isEmpty {
                    HStack(spacing: 4) {
                        if let sym = context.state.latestItemCategorySymbol {
                            Image(systemName: sym).font(.caption2).foregroundStyle(WMC.red)
                        }
                        Text("Latest: \(note)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Adding to \(context.attributes.cardName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Link(destination: URL(string: "anka://entry")!) {
                    Label("Add", systemImage: "plus")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(WMC.red, in: Capsule())
                }
            }
        }
        .padding(16)
        .widgetURL(URL(string: "anka://session"))
    }
}
