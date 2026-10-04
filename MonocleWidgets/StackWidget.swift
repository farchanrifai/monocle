import SwiftUI
import WidgetKit

struct StackTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> StackEntry {
        StackEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (StackEntry) -> Void) {
        let snapshot = WidgetSnapshotStore.loadSnapshot()
        completion(StackEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StackEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.loadSnapshot()
        let entry = StackEntry(date: .now, snapshot: snapshot)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct StackEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct StackWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: StackTimelineProvider.Entry

    var body: some View {
        if let reason = entry.snapshot.unavailableReason {
            Text(reason).font(.caption).foregroundStyle(.secondary).widgetURL(URL(string: "monocle://home"))
        } else {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            smallView
        }
        }
    }

    private var stack: WidgetStackSummary {
        entry.snapshot.activeStack ?? WidgetStackSummary(id: entry.snapshot.activeBook.id, name: "No stack", totalSpent: 0)
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text("monocle.")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WMC.red)
                Spacer()
                Image(systemName: stack.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(stack.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text("STACK SPENT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(WMC.formatIDR(stack.totalSpent))
                    .font(.system(size: 19, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }

            Spacer()

            HStack {
                Label("\(stack.cardCount) \(stack.cardCount == 1 ? "card" : "cards")", systemImage: "rectangle.stack")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.forward")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WMC.red)
            }
        }
        .widgetURL(URL(string: "monocle://stack?id=\(stack.id.uuidString)"))
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Left Column: Stack info
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("monocle.")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WMC.red)
                    Text("· Stack")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Image(systemName: stack.icon)
                        .font(.subheadline)
                        .foregroundStyle(WMC.red)
                    Text(stack.name)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("TOTAL STACK SPEND")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(WMC.formatIDR(stack.totalSpent))
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(stack.cardCount) cards in this stack")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .overlay(WMC.line)

            // Right Column: Cards in stack
            VStack(alignment: .leading, spacing: 8) {
                Text("CARDS IN STACK")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                if stack.cardNames.isEmpty {
                    Spacer()
                    Text("No cards assigned.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(Array(stack.cardNames.prefix(4).enumerated()), id: \.offset) { _, cardName in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(WMC.red)
                                .frame(width: 6, height: 6)
                            Text(cardName)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                    if stack.cardNames.count > 4 {
                        Text("+\(stack.cardNames.count - 4) more")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .widgetURL(URL(string: "monocle://stack?id=\(stack.id.uuidString)"))
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: stack.icon)
                Text(stack.name)
                    .font(.caption.weight(.semibold))
            }
            Text("\(WMC.compactIDR(stack.totalSpent)) spent")
                .font(.headline.weight(.semibold).monospaced())
            Text("\(stack.cardCount) cards in stack")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var inlineView: some View {
        Text("\(stack.name) stack · \(WMC.compactIDR(stack.totalSpent))")
    }
}

struct StackWidget: Widget {
    let kind: String = "MonocleStackWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StackTimelineProvider()) { entry in
            StackWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("Stack Overview")
        .description("View your active card stack, card count, and total stack spending.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
