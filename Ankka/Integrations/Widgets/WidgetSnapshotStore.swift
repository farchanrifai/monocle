import Foundation
import WidgetKit
import OSLog

public enum WidgetSnapshotStore {
    public static let appGroupID = "group.com.farchan.ankka"
    public static let snapshotFileName = "widget_snapshot.json"
    private static let logger = Logger(subsystem: "com.farchan.ankka", category: "WidgetSnapshot")

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
    public static var snapshotFileURL: URL? { containerURL?.appendingPathComponent(snapshotFileName) }

    /// Symbol of the last loaded snapshot's reporting currency, for widget formatting.
    nonisolated(unsafe) public static var currencySymbol = "Rp"

    public static func loadSnapshot(from fileURL: URL? = snapshotFileURL, now: Date = .now) -> WidgetSnapshot {
        guard let fileURL else {
            logger.error("Shared widget container is unavailable")
            return .unavailable("Open Ankka to refresh")
        }
        do {
            let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(contentsOf: fileURL))
            currencySymbol = snapshot.currencySymbol ?? "Rp"
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .current
            let parts = calendar.dateComponents([.year, .month, .day], from: now)
            let reportingDay = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            guard snapshot.reportingDay == reportingDay,
                  calendar.isDate(snapshot.updatedAt, inSameDayAs: now), snapshot.updatedAt <= now.addingTimeInterval(60) else {
                return .unavailable("Open Ankka to refresh today's totals")
            }
            return snapshot
        } catch {
            logger.error("Widget snapshot cannot be read")
            return .unavailable("Open Ankka to refresh")
        }
    }

    public static func writeSnapshot(_ snapshot: WidgetSnapshot, to fileURL: URL? = snapshotFileURL) throws {
        guard let fileURL else { logger.error("Shared widget container is unavailable"); throw CocoaError(.fileNoSuchFile) }
        do {
            try JSONEncoder().encode(snapshot).write(to: fileURL, options: .atomic)
            WidgetCenter.shared.reloadAllTimelines()
        } catch { logger.error("Widget snapshot cannot be written"); throw error }
    }
}
