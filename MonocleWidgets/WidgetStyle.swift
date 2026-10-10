import SwiftUI

enum WMC {
    static let red = Color(red: 0.83, green: 0.16, blue: 0.12)
    static let darkBackground = Color(red: 0.08, green: 0.08, blue: 0.09)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let line = Color.primary.opacity(0.12)

    static func formatIDR(_ amount: Int64, currency: Bool = true) -> String {
        let value = Decimal(amount) / 100
        let number = value.formatted(.number.precision(.fractionLength(0...(amount % 100 == 0 ? 0 : 2))))
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
