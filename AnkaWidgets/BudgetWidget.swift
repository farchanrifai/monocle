import SwiftUI
import WidgetKit

struct BudgetTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> BudgetEntry {
        BudgetEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (BudgetEntry) -> Void) {
        let snapshot = WidgetSnapshotStore.loadSnapshot()
        completion(BudgetEntry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BudgetEntry>) -> Void) {
        let snapshot = WidgetSnapshotStore.loadSnapshot()
        let entry = BudgetEntry(date: .now, snapshot: snapshot)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct BudgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct BudgetWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: BudgetTimelineProvider.Entry

    var body: some View {
        if let reason = entry.snapshot.unavailableReason {
            Text(reason).font(.caption).foregroundStyle(.secondary).widgetURL(URL(string: "anka://home"))
        } else {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryInline:
            inlineView
        default:
            smallView
        }
        }
    }

    private var budget: WidgetBudgetSummary {
        entry.snapshot.cycleBudget ?? WidgetBudgetSummary(limit: 0, spent: 0, remaining: 0, percentage: 0, daysRemaining: 0, dailyPaceRemaining: 0, cycleStartDate: entry.date, cycleEndDate: entry.date, cycleLabel: "No budget")
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("anka.")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WMC.red)
                Spacer()
                Text(entry.snapshot.activeCard.name)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text("REMAINING")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(WMC.formatIDR(budget.remaining))
                    .font(.system(size: 18, weight: .bold))
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
            }

            ProgressView(value: min(1.0, max(0.0, budget.percentage)))
                .tint(WMC.red)

            HStack {
                Text("\(budget.daysRemaining) days left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(budget.percentage * 100))%")
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(WMC.red)
            }
        }
        .widgetURL(URL(string: "anka://card?id=\(entry.snapshot.activeCard.id.uuidString)"))
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            // Left Column: Remaining & Progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("anka.")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(WMC.red)
                    Text("· \(entry.snapshot.activeCard.name)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("REMAINING BUDGET")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(WMC.formatIDR(budget.remaining))
                        .font(.system(size: 20, weight: .bold))
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }

                ProgressView(value: min(1.0, max(0.0, budget.percentage)))
                    .tint(WMC.red)

                HStack {
                    Text("Spent \(WMC.compactIDR(budget.spent))")
                    Spacer()
                    Text("of \(WMC.compactIDR(budget.limit))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Divider()
                .overlay(WMC.line)

            // Right Column: Pace & Today
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DAILY PACE")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(WMC.formatIDR(budget.dailyPaceRemaining))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text("for \(budget.daysRemaining) days left")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    Text("SPENT TODAY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text(WMC.formatIDR(entry.snapshot.todaySpending.totalSpent))
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: 130)
        }
        .widgetURL(URL(string: "anka://card?id=\(entry.snapshot.activeCard.id.uuidString)"))
    }

    private var circularView: some View {
        Gauge(value: min(1.0, max(0.0, budget.percentage))) {
            Image(systemName: "banknote")
        } currentValueLabel: {
            Text("\(Int(budget.percentage * 100))%")
                .font(.system(size: 10, weight: .bold))
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("anka.")
                    .font(.caption2.weight(.bold))
                Text("· \(entry.snapshot.activeCard.name)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text("\(WMC.compactIDR(budget.remaining)) left")
                .font(.headline.weight(.semibold).monospaced())
            Text("\(budget.daysRemaining)d left · \(WMC.compactIDR(budget.dailyPaceRemaining))/day")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var inlineView: some View {
        Text("\(WMC.compactIDR(budget.remaining)) left · \(budget.daysRemaining)d")
    }
}

struct BudgetWidget: Widget {
    let kind: String = "AnkaBudgetWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BudgetTimelineProvider()) { entry in
            ProGate { BudgetWidgetEntryView(entry: entry) }
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("Card Budget")
        .description("Glance at remaining budget, daily allowance, and cycle pacing for your active card.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}
