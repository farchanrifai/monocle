import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct OpenQuickEntryControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quick Entry"
    static let description = IntentDescription("Opens Ankka to log a new expense.")

    /// The app handles ankka://entry (AnkkaApp.onOpenURL) by opening Add Expense; this extension can't reach the app's model.
    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "ankka://entry")!))
    }
}

@available(iOS 18.0, *)
struct QuickEntryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.farchan.ankka.quickEntryControl") {
            ControlWidgetButton(action: OpenQuickEntryControlIntent()) {
                Label("Add Expense", systemImage: "plus")
            }
        }
        .displayName("Add Expense")
        .description("Quickly open Ankka to log an expense from Control Center or Lock Screen.")
    }
}
