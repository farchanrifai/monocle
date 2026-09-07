import AppIntents
import Foundation

struct AddExpenseFromTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense from Text"
    static let description = IntentDescription("Record an expense in monocle's sample book. For example: Coffee 28k. This is a prototype action.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Expense", description: "For example, Coffee 28k") var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let service = AppEnvironment.shared.expenses else { throw EntryError.corruptStore }
        let expense = try service.record(text: text)
        return .result(dialog: "Recorded \(Money.format(expense.amount)) in your sample book.")
    }
}

struct OpenQuickEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quick Entry"
    static let description = IntentDescription("Open monocle ready to record an expense.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .foreground }
    @MainActor func perform() async throws -> some IntentResult {
        AppModel.shared.openEntry()
        return .result()
    }
}

struct MonocleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenQuickEntryIntent(), phrases: ["Record an expense in \(.applicationName)"], shortTitle: "Quick entry", systemImageName: "plus.circle")
        AppShortcut(intent: AddExpenseFromTextIntent(), phrases: ["Add expense with \(.applicationName)"], shortTitle: "Expense from text", systemImageName: "text.bubble")
    }
}
