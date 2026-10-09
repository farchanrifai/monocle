import Charts
import SwiftUI

/// Full-width category donut for a chat answer. Amounts come from AnalyticsReport, never from the model.
struct ChatSummaryChart: View {
    let points: [CategorySpendPoint]

    // ponytail: local palette; share AnalyticsView's categoryPalette when real summaries land (CHAT_SPEC §11 step 5).
    private let palette: [Color] = [MC.red, .orange, .blue, .green, .purple, .teal]
    private func color(_ index: Int) -> Color { palette[index % palette.count] }

    var body: some View {
        if points.isEmpty {
            Text("No spending in this period yet.").font(.subheadline).foregroundStyle(.secondary)
        } else {
            HStack(spacing: 20) {
                Chart(Array(points.enumerated()), id: \.element.id) { index, point in
                    SectorMark(angle: .value("Spend", point.amount), innerRadius: .ratio(0.62), angularInset: 1.5)
                        .cornerRadius(3)
                        .foregroundStyle(color(index))
                }
                .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(points.prefix(5).enumerated()), id: \.element.id) { index, point in
                        HStack(spacing: 6) {
                            Circle().fill(color(index)).frame(width: 8, height: 8)
                            Text(point.categoryName).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(Money.format(point.amount)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 20, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Spending by category")
        }
    }
}
