import AppIntents
import Foundation
import SwiftUI

// MARK: - Category Entity

struct ExpenseCategoryEntity: AppEntity {
    let id: String
    let name: String
    let symbol: String

    init(_ category: ExpenseCategory) {
        id = category.id.uuidString
        name = category.name
        symbol = category.symbol
    }

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Expense Category")
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Category", image: .init(systemName: symbol))
    }
    static let defaultQuery = ExpenseCategoryEntityQuery()
}

struct ExpenseCategoryEntityQuery: EntityStringQuery, EnumerableEntityQuery {
    func entities(for identifiers: [String]) async throws -> [ExpenseCategoryEntity] {
        let categories = await categories()
        return categories.filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [ExpenseCategoryEntity] {
        let categories = await categories()
        return categories.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
    func suggestedEntities() async throws -> [ExpenseCategoryEntity] { await categories() }
    func allEntities() async throws -> [ExpenseCategoryEntity] { await categories() }

    private func categories() async -> [ExpenseCategoryEntity] {
        await MainActor.run { AppEnvironment.shared.model.activeCategories.map(ExpenseCategoryEntity.init) }
    }
}

// MARK: - Card Entity

struct CardEntity: AppEntity {
    let id: String
    let name: String

    init(_ book: BookProfile) {
        id = book.id.uuidString
        name = book.name
    }

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Card / Account")
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Card", image: .init(systemName: "creditcard.fill"))
    }
    static let defaultQuery = CardEntityQuery()
}

struct CardEntityQuery: EntityStringQuery, EnumerableEntityQuery {
    func entities(for identifiers: [String]) async throws -> [CardEntity] {
        let cards = await cards()
        return cards.filter { identifiers.contains($0.id) }
    }
    func entities(matching string: String) async throws -> [CardEntity] {
        let cards = await cards()
        return cards.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
    func suggestedEntities() async throws -> [CardEntity] { await cards() }
    func allEntities() async throws -> [CardEntity] { await cards() }

    private func cards() async -> [CardEntity] {
        await MainActor.run { AppEnvironment.shared.model.unhiddenBooks.map(CardEntity.init) }
    }
}

// MARK: - Rich Receipt Snippet View

struct ExpenseReceiptSnippetView: View {
    let expense: Expense
    let categoryName: String
    let categorySymbol: String
    let cardName: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.88, green: 0.22, blue: 0.21).opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: categorySymbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.88, green: 0.22, blue: 0.21))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.note.isEmpty ? categoryName : expense.note)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(cardName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text(expense.day)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(Money.format(expense.amount))
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Add Expense Intent

struct AddExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense"
    static let description = IntentDescription("Records an expense in Monocle using an amount, category, and optional card.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Amount (IDR)") var amount: Int
    @Parameter(title: "Category") var category: ExpenseCategoryEntity
    @Parameter(title: "Card / Account") var card: CardEntity?
    @Parameter(title: "Note") var note: String?
    @Parameter(title: "Date") var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$amount) rupiah in \(\.$category)") {
            \.$card
            \.$note
            \.$date
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard amount > 0, let categoryID = UUID(uuidString: category.id) else { throw EntryError.invalidAmount }
        guard let service = AppEnvironment.shared.expenses else { throw EntryError.corruptStore }
        let targetBookID = card.flatMap { UUID(uuidString: $0.id) } ?? AppEnvironment.shared.model.selectedBookID ?? AppEnvironment.shared.model.activeBookID
        let expense = try service.record(amountInRupiah: Int64(amount), categoryID: categoryID, note: note, date: date ?? .now, in: targetBookID)
        let bookName = AppEnvironment.shared.model.books.first(where: { $0.id == targetBookID })?.name ?? "Card"
        return .result(
            dialog: "Recorded \(Money.format(expense.amount)) in \(category.name) on \(bookName).",
            view: ExpenseReceiptSnippetView(expense: expense, categoryName: category.name, categorySymbol: category.symbol, cardName: bookName)
        )
    }
}

// MARK: - Add Expense From Text Intent

struct AddExpenseFromTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense from Text"
    static let description = IntentDescription("Record an expense in Monocle using natural text. For example: 'Coffee 28k' or 'Lunch 45k'.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Expense", description: "For example, Coffee 28k") var text: String
    @Parameter(title: "Card / Account") var card: CardEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Record \(\.$text)") {
            \.$card
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let service = AppEnvironment.shared.expenses else { throw EntryError.corruptStore }
        let targetBookID = card.flatMap { UUID(uuidString: $0.id) } ?? AppEnvironment.shared.model.selectedBookID ?? AppEnvironment.shared.model.activeBookID
        let expense = try service.record(text: text, in: targetBookID)
        let bookName = AppEnvironment.shared.model.books.first(where: { $0.id == targetBookID })?.name ?? "Card"
        let cat = AppEnvironment.shared.model.categories.first(where: { $0.id == expense.allocations.first?.categoryID })
        let catName = cat?.name ?? "Expense"
        let catSymbol = cat?.symbol ?? "creditcard"

        return .result(
            dialog: "Recorded \(Money.format(expense.amount)) on \(bookName).",
            view: ExpenseReceiptSnippetView(expense: expense, categoryName: catName, categorySymbol: catSymbol, cardName: bookName)
        )
    }
}

// MARK: - Quick Entry Intent

struct OpenQuickEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quick Entry"
    static let description = IntentDescription("Open Monocle ready to record an expense.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .foreground }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Card / Account") var card: CardEntity?
    @Parameter(title: "Category") var category: ExpenseCategoryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Open quick entry") {
            \.$card
            \.$category
        }
    }

    @MainActor func perform() async throws -> some IntentResult {
        let targetBookID = card.flatMap { UUID(uuidString: $0.id) }
        let targetCatID = category.flatMap { UUID(uuidString: $0.id) }
        AppModel.shared.openEntry(for: targetBookID, categoryID: targetCatID)
        return .result()
    }
}

// MARK: - Spending Session Intents

struct StartSpendingSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Spending Session"
    static let description = IntentDescription("Start a live spending session and Live Activity in Monocle.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Session Name", default: "Shopping Session") var name: String
    @Parameter(title: "Card / Account") var card: CardEntity?
    @Parameter(title: "Budget Limit (IDR)") var budgetLimit: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$name)") {
            \.$card
            \.$budgetLimit
        }
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let targetBookID = card.flatMap { UUID(uuidString: $0.id) } ?? AppEnvironment.shared.model.selectedBookID ?? AppEnvironment.shared.model.activeBookID
        let bookName = AppEnvironment.shared.model.books.first(where: { $0.id == targetBookID })?.name ?? "Card"
        let limit = (budgetLimit.flatMap { $0 > 0 ? Int64($0) : nil }).map { $0 * 100 }
        SpendingSessionManager.shared.startSession(name: name, bookName: bookName, budgetLimit: limit)
        return .result(dialog: "Started spending session '\(name)' on \(bookName).")
    }
}

struct EndSpendingSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "End Spending Session"
    static let description = IntentDescription("End the active spending session and dismiss the Live Activity.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .background }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let manager = SpendingSessionManager.shared
        guard manager.isSessionActive else {
            return .result(dialog: "No active spending session.")
        }
        let total = manager.sessionSpent
        let count = manager.sessionItemCount
        manager.endSession()
        return .result(dialog: "Ended session. Total spent: \(Money.format(total)) across \(count) items.")
    }
}

// MARK: - App Shortcuts Provider

struct MonocleShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .red }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenQuickEntryIntent(),
            phrases: [
                "Record an expense in \(.applicationName)",
                "Open \(.applicationName)"
            ],
            shortTitle: "Quick entry",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense in \(.applicationName)",
                "Add \(\.$category) expense in \(.applicationName)",
                "Record \(\.$category) in \(.applicationName)"
            ],
            shortTitle: "Add expense",
            systemImageName: "plus.circle.fill"
        )
        AppShortcut(
            intent: AddExpenseFromTextIntent(),
            phrases: [
                "Add an expense from text in \(.applicationName)",
                "Log expense in \(.applicationName)"
            ],
            shortTitle: "Expense from text",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: StartSpendingSessionIntent(),
            phrases: [
                "Start spending session in \(.applicationName)",
                "Start shopping in \(.applicationName)"
            ],
            shortTitle: "Start session",
            systemImageName: "cart.fill"
        )
        AppShortcut(
            intent: EndSpendingSessionIntent(),
            phrases: [
                "End spending session in \(.applicationName)",
                "Finish shopping in \(.applicationName)"
            ],
            shortTitle: "End session",
            systemImageName: "cart.badge.minus"
        )
    }
}

