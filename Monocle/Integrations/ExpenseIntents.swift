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
        let model = AppModel.shared
        guard model.startupError == nil else { throw EntryError.corruptStore }
        let parsed = try ExpenseParser.parse(text, categories: model.categories)
        guard let categoryID = parsed.categoryID else { throw EntryError.missingCategory }
        let expense = Expense(amount: parsed.amount, day: Day.string(.now), note: parsed.note, allocations: [.init(categoryID: categoryID, amount: parsed.amount)], source: "shortcut")
        try model.save(expense)
        return .result(dialog: "Recorded \(Money.format(parsed.amount)) in your sample book.")
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
