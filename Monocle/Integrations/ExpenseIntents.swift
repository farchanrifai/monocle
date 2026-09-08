import AppIntents
import Foundation

struct ExpenseCategoryEntity: AppEntity {
    let id: String
    let name: String
    let symbol: String

    init(_ category: ExpenseCategory) {
        id = category.id.uuidString
        name = category.name
        symbol = category.symbol
    }

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Expense category")
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Category", image: .init(systemName: symbol))
    }
    static let defaultQuery = ExpenseCategoryEntityQuery()
}

struct ExpenseCategoryEntityQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ExpenseCategoryEntity] {
        let categories = await categories()
        return categories.filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [ExpenseCategoryEntity] {
        let categories = await categories()
        return categories.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
    func suggestedEntities() async throws -> [ExpenseCategoryEntity] { await categories() }

    private func categories() async -> [ExpenseCategoryEntity] {
        await MainActor.run { AppEnvironment.shared.expenses?.categories.map(ExpenseCategoryEntity.init) ?? [] }
    }
}

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription("Records one IDR expense in monocle's sample book using an amount and category.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Amount (IDR)") var amount: Int
    @Parameter(title: "Category") var category: ExpenseCategoryEntity
    @Parameter(title: "Note") var note: String?
    @Parameter(title: "Date") var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) rupiah in \(\.$category)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard amount > 0, let categoryID = UUID(uuidString: category.id) else { throw EntryError.invalidAmount }
        guard let service = AppEnvironment.shared.expenses else { throw EntryError.corruptStore }
        let expense = try service.record(amountInRupiah: Int64(amount), categoryID: categoryID, note: note, date: date ?? .now)
        return .result(dialog: "Recorded \(Money.format(expense.amount)) in \(category.name).")
    }
}

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
        AppShortcut(intent: AddExpenseIntent(), phrases: ["Add an expense in \(.applicationName)"], shortTitle: "Add expense", systemImageName: "plus.circle.fill")
        AppShortcut(intent: AddExpenseFromTextIntent(), phrases: ["Add an expense from text in \(.applicationName)"], shortTitle: "Expense from text", systemImageName: "text.bubble")
    }
}
