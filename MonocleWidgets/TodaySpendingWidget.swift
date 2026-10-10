import SwiftUI
import WidgetKit

struct TodaySpendingTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodaySpendingEntry {
        TodaySpendingEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodaySpendingEntry) -> Void) {
        let snapshot = WidgetSnapshotStore.loadSnapshot()
        completion(TodaySpendingEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodaySpendingEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.loadSnapshot()
        let entry = TodaySpendingEntry(date: .now, snapshot: snapshot)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct TodaySpendingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TodaySpendingWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: TodaySpendingTimelineProvider.Entry

    var body: some View {
        if let reason = entry.snapshot.unavailableReason {
            Text(reason).font(.caption).foregroundStyle(.secondary).widgetURL(URL(string: "monocle://home"))
        } else {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .accessoryCircular:
            circularView
        case .accessoryInline:
            inlineView
        default:
            smallView
        }
        }
    }

    private var today: WidgetTodaySummary {
        entry.snapshot.todaySpending
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("monocle.")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WMC.red)
                Spacer()
                Text("TODAY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text("TOTAL SPENT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(WMC.formatIDR(today.totalSpent))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }

            Spacer()

            HStack {
                Label("\(today.transactionCount) logged", systemImage: "receipt")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.caption)
                    .foregroundStyle(WMC.red)
            }
        }
        .widgetURL(URL(string: "monocle://home"))
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Left: Today summary
            Link(destination: URL(string: "monocle://home")!) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("monocle.")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(WMC.red)
                        Text("· Today")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SPENT TODAY")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(WMC.formatIDR(today.totalSpent))
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    Text("\(today.transactionCount) expenses added")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .overlay(WMC.line)

            // Right: Recent transactions list
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT ACTIVITIES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)

                if today.recentTransactions.isEmpty {
                    Spacer()
                    Text("No expenses yet today.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(today.recentTransactions.prefix(3)) { item in
                        Link(destination: URL(string: item.cardID != nil ? "monocle://card?id=\(item.cardID!.uuidString)" : "monocle://home")!) {
                            HStack(spacing: 8) {
                                Image(systemName: item.categorySymbol)
                                    .font(.caption)
                                    .frame(width: 18, height: 18)
                                    .foregroundStyle(WMC.red)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(item.timeFormatted)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(WMC.formatIDR(item.amount, currency: false))
                                    .font(.caption.weight(.semibold).monospaced())
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
        .widgetURL(URL(string: "monocle://home"))
    }

    private var circularView: some View {
        VStack(spacing: 1) {
            Image(systemName: "receipt")
                .font(.caption)
                .foregroundStyle(WMC.red)
            Text("\(today.transactionCount)")
                .font(.headline.weight(.bold).monospaced())
            Text("today")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private var inlineView: some View {
        Text("Spent \(WMC.compactIDR(today.totalSpent)) today")
    }
}

struct TodaySpendingWidget: Widget {
    let kind: String = "MonocleTodaySpendingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodaySpendingTimelineProvider()) { entry in
            TodaySpendingWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("Today's Spending")
        .description("Track daily expenses and view your latest purchases.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}
