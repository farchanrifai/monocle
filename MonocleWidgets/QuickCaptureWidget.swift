import SwiftUI
import WidgetKit

struct QuickCaptureWidget: Widget {
    let kind: String = "MonocleQuickCaptureWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodaySpendingTimelineProvider()) { entry in
            ProGate { QuickCaptureWidgetView(entry: entry) }
                .containerBackground(for: .widget) {
                    Color(uiColor: .systemBackground)
                }
        }
        .configurationDisplayName("Quick Log")
        .description("Quickly open expense capture with your top categories.")
        .supportedFamilies([.systemMedium])
    }
}

struct QuickCaptureWidgetView: View {
    let entry: TodaySpendingEntry

    var body: some View {
        if let reason = entry.snapshot.unavailableReason {
            Text(reason).font(.caption).foregroundStyle(.secondary).widgetURL(URL(string: "monocle://home"))
        } else {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("monocle.")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WMC.red)
                Text("· Quick Log")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Spent \(WMC.formatIDR(entry.snapshot.todaySpending.totalSpent))")
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                ForEach(entry.snapshot.quickCategories) { category in
                    Link(destination: URL(string: "monocle://entry?book=\(entry.snapshot.activeCard.id.uuidString)&category=\(category.id.uuidString)")!) {
                        VStack(spacing: 6) {
                            Image(systemName: category.symbol)
                                .font(.system(size: 20))
                                .frame(width: 44, height: 44)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(WMC.red)
                            Text(category.name)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Link(destination: URL(string: "monocle://entry?book=\(entry.snapshot.activeCard.id.uuidString)")!) {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .background(WMC.red, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(.white)
                        Text("Add")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        }
    }
}
