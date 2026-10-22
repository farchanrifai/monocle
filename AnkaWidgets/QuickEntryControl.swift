import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct OpenQuickEntryControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quick Entry"
    static let description = IntentDescription("Opens Anka to log a new expense.")
    static var openAppWhenRun: Bool { true }

    @MainActor
    func perform() async throws -> some IntentResult {
        return .result()
    }
}

@available(iOS 18.0, *)
struct QuickEntryControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.farchan.anka.quickEntryControl") {
            ControlWidgetButton(action: OpenQuickEntryControlIntent()) {
                Label("Add Expense", systemImage: "plus")
            }
        }
        .displayName("Add Expense")
        .description("Quickly open Anka to log an expense from Control Center or Lock Screen.")
    }
}
