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

    init(_ global: GlobalCategory) {
        id = global.id.uuidString
        name = global.name
        symbol = global.symbol
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
        await MainActor.run {
            let model = AppEnvironment.shared.model
            let globals = model.globalCategories
            if !globals.isEmpty {
                return globals.map(ExpenseCategoryEntity.init)
            }
            return model.activeCategories.map(ExpenseCategoryEntity.init)
        }
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
        await MainActor.run {
            let model = AppEnvironment.shared.model
            let unhidden = model.unhiddenBooks
            if !unhidden.isEmpty {
                return unhidden.map(CardEntity.init)
            }
            return model.books.map(CardEntity.init)
        }
    }
}

// MARK: - Shortcut Prompt Order AppEnum

enum ShortcutPromptOrder: String, AppEnum {
    case cardCategoryNoteAmount = "cardCategoryNoteAmount"
    case cardCategoryAmountNote = "cardCategoryAmountNote"
    case amountCardCategoryNote = "amountCardCategoryNote"
    case amountCategoryCardNote = "amountCategoryCardNote"
    case amountNoteCategoryCard = "amountNoteCategoryCard"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Shortcut Input Order")
    static let caseDisplayRepresentations: [ShortcutPromptOrder: DisplayRepresentation] = [
        .cardCategoryNoteAmount: DisplayRepresentation(title: "Card → Category → Note → Amount"),
        .cardCategoryAmountNote: DisplayRepresentation(title: "Card → Category → Amount → Note"),
        .amountCardCategoryNote: DisplayRepresentation(title: "Amount → Card → Category → Note"),
        .amountCategoryCardNote: DisplayRepresentation(title: "Amount → Category → Card → Note"),
        .amountNoteCategoryCard: DisplayRepresentation(title: "Amount → Note → Category → Card"),
    ]

    var fields: [ShortcutInputField] {
        switch self {
        case .cardCategoryNoteAmount: return [.card, .category, .note, .amount]
        case .cardCategoryAmountNote: return [.card, .category, .amount, .note]
        case .amountCardCategoryNote: return [.amount, .card, .category, .note]
        case .amountCategoryCardNote: return [.amount, .category, .card, .note]
        case .amountNoteCategoryCard: return [.amount, .note, .category, .card]
        }
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

    @Parameter(title: "Amount (IDR)", requestValueDialog: IntentDialog("How much?")) var amount: Int?
    @Parameter(title: "Category", requestValueDialog: IntentDialog("Which category?")) var category: ExpenseCategoryEntity?
    @Parameter(title: "Card / Account", requestValueDialog: IntentDialog("Which card / account?")) var card: CardEntity?
    @Parameter(title: "Short Note", requestValueDialog: IntentDialog("Short note (optional)?")) var note: String?
    @Parameter(title: "Input Order") var inputOrder: ShortcutPromptOrder?
    @Parameter(title: "Date") var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Record on \(\.$card) in \(\.$category) note \(\.$note) for \(\.$amount)") {
            \.$date
            \.$inputOrder
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let service = AppEnvironment.shared.expenses else { throw EntryError.corruptStore }

        // Determine customizable execution sequence
        let orderFields: [ShortcutInputField] = inputOrder?.fields ?? AppEnvironment.shared.model.shortcutInputOrder

        var resolvedCard = card
        var resolvedCategory = category
        var resolvedNote = note
        var resolvedAmount = amount

        // If card was not provided, but there is only 1 book, auto-resolve it
        if resolvedCard == nil {
            let unhidden = AppEnvironment.shared.model.unhiddenBooks
            if unhidden.count == 1, let single = unhidden.first {
                resolvedCard = CardEntity(single)
            } else if unhidden.isEmpty, let fallback = AppEnvironment.shared.model.books.first {
                resolvedCard = CardEntity(fallback)
            }
        }

        for field in orderFields {
            switch field {
            case .card:
                if resolvedCard == nil {
                    let availableBooks = AppEnvironment.shared.model.unhiddenBooks
                    let entities = availableBooks.map(CardEntity.init)
                    if entities.count > 1 {
                        resolvedCard = try await $card.requestDisambiguation(among: entities, dialog: IntentDialog("Which card?"))
                    } else if let single = entities.first {
                        resolvedCard = single
                    } else if let fallback = AppEnvironment.shared.model.books.first {
                        resolvedCard = CardEntity(fallback)
                    }
                }

            case .category:
                if resolvedCategory == nil {
                    let targetBookID = resolvedCard.flatMap { UUID(uuidString: $0.id) } ?? AppEnvironment.shared.model.selectedBookID ?? AppEnvironment.shared.model.activeBookID
                    let active = AppEnvironment.shared.model.activeCategories(for: targetBookID)
                    let entities = active.map(ExpenseCategoryEntity.init)
                    if entities.count > 1 {
                        resolvedCategory = try await $category.requestDisambiguation(among: entities, dialog: IntentDialog("Which category?"))
                    } else if let single = entities.first {
                        resolvedCategory = single
                    } else {
                        let fallbackEntities = AppEnvironment.shared.model.categories.map(ExpenseCategoryEntity.init)
                        if fallbackEntities.count > 1 {
                            resolvedCategory = try await $category.requestDisambiguation(among: fallbackEntities, dialog: IntentDialog("Which category?"))
                        } else if let single = fallbackEntities.first {
                            resolvedCategory = single
                        }
                    }
                }

            case .note:
                if resolvedNote == nil {
                    do {
                        resolvedNote = try await $note.requestValue(IntentDialog("Short note (optional)?"))
                    } catch {
                        resolvedNote = ""
                    }
                }

            case .amount:
                if resolvedAmount == nil || (resolvedAmount ?? 0) <= 0 {
                    resolvedAmount = try await $amount.requestValue(IntentDialog("How much?"))
                }
            }
        }

        // Final validations and resolution
        if resolvedCard == nil {
            let unhidden = AppEnvironment.shared.model.unhiddenBooks
            if let first = unhidden.first {
                resolvedCard = CardEntity(first)
            } else if let fallback = AppEnvironment.shared.model.books.first {
                resolvedCard = CardEntity(fallback)
            }
        }
        guard let targetCard = resolvedCard, let targetBookID = UUID(uuidString: targetCard.id) else {
            throw EntryError.corruptStore
        }

        let active = AppEnvironment.shared.model.activeCategories(for: targetBookID)
        let resolvedCategoryID = resolvedCategory.flatMap { UUID(uuidString: $0.id) }
        if !active.contains(where: { $0.id == resolvedCategoryID }) {
            let entities = active.map(ExpenseCategoryEntity.init)
            if entities.count > 1 {
                resolvedCategory = try await $category.requestDisambiguation(among: entities, dialog: IntentDialog("Which category?"))
            } else {
                resolvedCategory = entities.first
            }
        }
        guard let targetCategory = resolvedCategory, let categoryID = UUID(uuidString: targetCategory.id) else {
            throw EntryError.missingCategory
        }

        if resolvedAmount == nil || (resolvedAmount ?? 0) <= 0 {
            resolvedAmount = try await $amount.requestValue(IntentDialog("How much?"))
        }
        guard let validAmount = resolvedAmount, validAmount > 0 else {
            throw EntryError.invalidAmount
        }

        let finalNote = resolvedNote ?? ""
        let expense = try service.record(amountInRupiah: Int64(validAmount), categoryID: categoryID, note: finalNote, date: date ?? .now, in: targetBookID)
        let bookName = AppEnvironment.shared.model.books.first(where: { $0.id == targetBookID })?.name ?? targetCard.name
        SpendingSessionManager.shared.recordExpense(amount: expense.amount, note: expense.note, categorySymbol: targetCategory.symbol, bookID: targetBookID)
        return .result(
            dialog: "Recorded \(Money.format(expense.amount)) in \(targetCategory.name) on \(bookName).",
            view: ExpenseReceiptSnippetView(expense: expense, categoryName: targetCategory.name, categorySymbol: targetCategory.symbol, cardName: bookName)
        )
    }
}

// MARK: - Add Expense From Text Intent

struct AddExpenseFromTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense from Text"
    static let description = IntentDescription("Record an expense in Monocle using natural text. For example: 'Coffee 28k' or 'Lunch 45k'.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Expense", description: "For example, Coffee 28k", requestValueDialog: IntentDialog("What did you spend on? (e.g. Coffee 28k)")) var text: String
    @Parameter(title: "Card / Account") var card: CardEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Record \(\.$text)") {
            \.$card
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let service = AppEnvironment.shared.expenses else { throw EntryError.corruptStore }
        var resolvedCard = card
        if resolvedCard == nil {
            let availableBooks = AppEnvironment.shared.model.unhiddenBooks
            let entities = availableBooks.map(CardEntity.init)
            if entities.count > 1 {
                resolvedCard = try await $card.requestDisambiguation(among: entities, dialog: IntentDialog("Which card?"))
            } else if let single = entities.first {
                resolvedCard = single
            } else if let fallback = AppEnvironment.shared.model.books.first {
                resolvedCard = CardEntity(fallback)
            }
        }
        let targetBookID = resolvedCard.flatMap { UUID(uuidString: $0.id) } ?? AppEnvironment.shared.model.selectedBookID ?? AppEnvironment.shared.model.activeBookID
        let expense = try service.record(text: text, in: targetBookID)
        let bookName = AppEnvironment.shared.model.books.first(where: { $0.id == targetBookID })?.name ?? "Card"
        let cat = AppEnvironment.shared.model.activeCategories(for: targetBookID).first(where: { $0.id == expense.allocations.first?.categoryID })
        let catName = cat?.name ?? "Expense"
        let catSymbol = cat?.symbol ?? "creditcard"
        SpendingSessionManager.shared.recordExpense(amount: expense.amount, note: expense.note, categorySymbol: catSymbol, bookID: targetBookID)

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

#if os(iOS)
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
        var limit: Int64?
        if let budgetLimit, budgetLimit > 0 {
            let converted = Int64(budgetLimit).multipliedReportingOverflow(by: 100)
            guard !converted.overflow, converted.partialValue <= Money.maximum else { throw EntryError.invalidAmount }
            limit = converted.partialValue
        }
        SpendingSessionManager.shared.startSession(name: name, bookName: bookName, bookID: targetBookID, budgetLimit: limit)
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
#endif

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
        #if os(iOS)
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
        #endif
    }
}
