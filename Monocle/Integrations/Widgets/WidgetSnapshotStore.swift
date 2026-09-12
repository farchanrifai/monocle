import Foundation
import WidgetKit

public enum WidgetSnapshotStore {
    public static let appGroupID = "group.com.farchan.monocle"
    public static let snapshotFileName = "widget_snapshot.json"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
    }

    public static var snapshotFileURL: URL? {
        containerURL?.appendingPathComponent(snapshotFileName)
    }

    public static func loadSnapshot() -> WidgetSnapshot {
        guard let fileURL = snapshotFileURL,
              let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .sample
        }
        return snapshot
    }

    public static func writeSnapshot(_ snapshot: WidgetSnapshot) {
        guard let fileURL = snapshotFileURL else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Silently fallback if container write fails
        }
    }
}
