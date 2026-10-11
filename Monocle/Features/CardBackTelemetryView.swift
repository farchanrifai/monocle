import SwiftUI

/// Teenage Engineering-inspired monospace telemetry back-face for Monocle card cards.
struct CardBackTelemetryView: View {
    @Bindable var model: AppModel
    let card: Card
    let index: Int
    let onFlipBack: () -> Void
    let onOpenAnalytics: () -> Void
    let onCustomize: () -> Void

    var body: some View {
        let report = AnalyticsReport.build(data: model.reportingData(for: .card(id: card.id, name: card.name)), horizon: .thisCycle)
        CardBackReportView(model: model, card: card, index: index, onFlipBack: onFlipBack,
                           onOpenAnalytics: onOpenAnalytics, onCustomize: onCustomize, report: report)
    }
}

private struct CardBackReportView: View {
    @Bindable var model: AppModel
    let card: Card
    let index: Int
    let onFlipBack: () -> Void
    let onOpenAnalytics: () -> Void
    let onCustomize: () -> Void

    let report: AnalyticsReport
    @ScaledMetric(relativeTo: .caption) private var tagSize = 10

    private var customization: CardCustomization {
        model.customization(for: card.id)
    }

    private var activeBudget: BudgetVersion? { report.period?.budget }

    private var technicalTag: String {
        let clean = card.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(4).uppercased()
        return "MONO-\(String(format: "%02d", index + 1)) // #\(clean)"
    }

    private var todayString: String {
        Day.string(.now)
    }

    private var dateRange: (startDate: Date, endDate: Date, startDay: String, endDay: String) { report.range }
    private var metrics: AnalyticsMetrics { report.metrics }
    private var nextUpcomingBill: (name: String, dueDay: String, amount: Int64)? {
        let pending = report.data.billOccurrences.filter { $0.status == .pending && $0.dueDay >= todayString && $0.dueDay <= dateRange.endDay }
            .min { $0.dueDay < $1.dueDay }
        guard let occurrence = pending, let rule = report.data.bills.first(where: { $0.id == occurrence.billRuleID }) else { return nil }
        return (rule.name, occurrence.dueDay, rule.amount)
    }

    private var daysRemaining: Int {
        let calendar = Day.calendar
        let today = calendar.startOfDay(for: .now)
        let end = calendar.startOfDay(for: dateRange.endDate)
        let days = calendar.dateComponents([.day], from: today, to: end).day ?? 0
        return max(0, days)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: Technical Tag + Flip Back action
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(technicalTag)
                        .font(.system(size: tagSize, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                        .tracking(1.2)
                    Text(card.name.uppercased())
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                    onFlipBack()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2.weight(.bold))
                        Text("FLIP")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.18), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Flip back to front of card")
                .accessibilityIdentifier("cardFlipBackButton")
            }

            // Monospace Telemetry Grid
            if let error = report.errorMessage {
                Text(error).font(.caption).foregroundStyle(.white)
            } else {
            HStack(spacing: 8) {
                // Compartment 1: Cycle & Pace
                VStack(alignment: .leading, spacing: 4) {
                    Text("CYCLE & PACE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .tracking(0.5)

                    HStack(spacing: 4) {
                        paceIndicatorDot
                        Text(paceText)
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }

                    Text("\(daysRemaining)D REMAINING")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))

                // Compartment 2: Daily Burn & Target
                VStack(alignment: .leading, spacing: 4) {
                    Text("DAILY BURN")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .tracking(0.5)

                    Text(compactMoney(metrics.dailyAverage))
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    if let activeBudget {
                        let targetDaily = (try? Money.checkedScale(activeBudget.overallLimit, numerator: 1, denominator: max(1, metrics.totalDaysInPeriod))) ?? 0
                        Text("TARGET \(compactMoney(targetDaily))")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    } else {
                        Text("NO BUDGET")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))

                // Compartment 3: Remaining / Limit
                VStack(alignment: .leading, spacing: 4) {
                    Text("REMAINING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.55))
                        .tracking(0.5)

                    if let activeBudget {
                        let remaining = activeBudget.overallLimit - metrics.totalSpend
                        Text(compactMoney(remaining))
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(remaining >= 0 ? Color.green : Color.red)
                            .lineLimit(1)

                        Text("OF \(compactMoney(activeBudget.overallLimit))")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    } else {
                        Text("UNCAPPED")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white)

                        Text("NO LIMIT")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
            }

            }
            // Next commitment banner
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))

                if let next = nextUpcomingBill {
                    Text("NEXT BILL: \(next.name.uppercased()) · \(formatDueDay(next.dueDay)) (\(compactMoney(next.amount)))")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)
                } else {
                    Text("NO PENDING BILLS THIS CYCLE")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))

            Spacer(minLength: 0)

            // Bottom Quick Action Buttons
            HStack(spacing: 10) {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onOpenAnalytics()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.xyaxis.line")
                            .font(.caption.weight(.bold))
                        Text("TRENDS & ANALYTICS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.18))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cardBackAnalyticsButton")

                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    onCustomize()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "paintbrush")
                            .font(.caption.weight(.bold))
                        Text("ARTWORK")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.18))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.white.opacity(0.3), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("cardBackCustomizeButton")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            ZStack {
                cardBackBackground(for: customization, card: card)
                Color.black.opacity(0.52)
                LinearGradient(
                    colors: [Color.white.opacity(0.08), Color.clear, Color.black.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onFlipBack()
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.75)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - Subviews & Helpers

    @ViewBuilder
    private var paceIndicatorDot: some View {
        Circle()
            .fill(paceColor)
            .frame(width: 6, height: 6)
    }

    private var paceColor: Color {
        guard let pace = metrics.paceStatus else { return .secondary }
        switch pace {
        case .underPace: return .green
        case .onTrack: return .blue
        case .accelerated, .beyondRange: return .orange
        }
    }

    private var paceText: String {
        guard let pace = metrics.paceStatus else { return "TRACKING" }
        switch pace {
        case .underPace(let pct): return "\(pct)% UNDER"
        case .onTrack: return "ON PACE"
        case .accelerated(let pct): return "\(pct)% AHEAD"
        case .beyondRange: return "PACE EXCEEDS RANGE"
        }
    }

    private func formatDueDay(_ dueDay: String) -> String {
        let parts = dueDay.split(separator: "-")
        guard parts.count == 3 else { return dueDay }
        return "\(parts[1])/\(parts[2])"
    }

    private func compactMoney(_ amount: Int64) -> String {
        let absAmount = abs(amount)
        let sign = amount < 0 ? "-" : ""
        if absAmount >= 1_000_000_000 {
            let val = Double(absAmount) / 1_000_000_000.0
            return String(format: "%@Rp %.1fB", sign, val)
        } else if absAmount >= 1_000_000 {
            let val = Double(absAmount) / 1_000_000.0
            return String(format: "%@Rp %.1fM", sign, val)
        } else if absAmount >= 1_000 {
            let val = Double(absAmount) / 1_000.0
            return String(format: "%@Rp %.0fk", sign, val)
        } else {
            return "\(sign)Rp \(absAmount)"
        }
    }

    @ViewBuilder
    private func cardBackBackground(for customization: CardCustomization, card: Card) -> some View {
        switch customization.style {
        case .palette(let index):
            CardPalette.color(for: index)
        case .customColor(let hex):
            CardPalette.color(fromHex: hex)
        case .stock(let design):
            StockDesignBackgroundView(design: design)
        case .customPhoto(let filename):
            if let image = CardArtworkStore.shared.loadArtwork(filename: filename) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                CardPalette.color(for: card.colorIndex)
            }
        }
    }
}
