import SwiftUI

enum WMC {
    static let red = Color(red: 0.83, green: 0.16, blue: 0.12)
    static let darkBackground = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let line = Color.primary.opacity(0.12)

    static func formatIDR(_ amount: Int64, currency: Bool = true) -> String {
        let value = Decimal(amount) / 100
        let number = value.formatted(.number.precision(.fractionLength(amount % 100 == 0 ? 0 : 2)))
        return (currency ? WidgetSnapshotStore.currencySymbol : "") + number
    }

    static func compactIDR(_ amount: Int64) -> String {
        let value = Double(amount) / 100.0
        if value >= 1_000_000 {
            let m = value / 1_000_000.0
            return String(format: "%.1fM", m)
        } else if value >= 1_000 {
            let k = value / 1_000.0
            return String(format: "%.0fk", k)
        }
        return "\(Int(value))"
    }
}

/// Home Screen widgets are Pro. The app writes `isPro` to the app group (ProStore) and reloads timelines on change.
struct ProGate<Content: View>: View {
    @ViewBuilder var content: Content

    private var isPro: Bool { UserDefaults(suiteName: WidgetSnapshotStore.appGroupID)?.bool(forKey: "isPro") ?? false }

    var body: some View {
        if isPro {
            content
        } else {
            VStack(spacing: 4) {
                Image(systemName: "lock.fill").font(.title3)
                Text("Ankka Pro").font(.headline)
                Text("Widgets are part of Pro.").font(.caption).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .widgetURL(URL(string: "ankka://"))
        }
    }
}
