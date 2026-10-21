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

    init(_ card: Card) {
        id = card.id.uuidString
        name = card.name
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
            let unhidden = model.unhiddenCards
            if !unhidden.isEmpty {
                return unhidden.map(CardEntity.init)
            }
            return model.cards.map(CardEntity.init)
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
    static let description = IntentDescription("Adds an expense in Monocle using an amount, category, and optional card.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Amount", requestValueDialog: IntentDialog("How much?")) var amount: Int?
    @Parameter(title: "Category", requestValueDialog: IntentDialog("Which category?")) var category: ExpenseCategoryEntity?
    @Parameter(title: "Card", requestValueDialog: IntentDialog("Which card?")) var card: CardEntity?
    @Parameter(title: "Short Note", requestValueDialog: IntentDialog("Short note (optional)?")) var note: String?
    @Parameter(title: "Input Order") var inputOrder: ShortcutPromptOrder?
    @Parameter(title: "Date") var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Add on \(\.$card) in \(\.$category) note \(\.$note) for \(\.$amount)") {
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

        // If card was not provided, but there is only 1 card, auto-resolve it
        if resolvedCard == nil {
            let unhidden = AppEnvironment.shared.model.unhiddenCards
            if unhidden.count == 1, let single = unhidden.first {
                resolvedCard = CardEntity(single)
            } else if unhidden.isEmpty, let fallback = AppEnvironment.shared.model.cards.first {
                resolvedCard = CardEntity(fallback)
            }
        }

        for field in orderFields {
            switch field {
            case .card:
                if resolvedCard == nil {
                    let availableCards = AppEnvironment.shared.model.unhiddenCards
                    let entities = availableCards.map(CardEntity.init)
                    if entities.count > 1 {
                        resolvedCard = try await $card.requestDisambiguation(among: entities, dialog: IntentDialog("Which card?"))
                    } else if let single = entities.first {
                        resolvedCard = single
                    } else if let fallback = AppEnvironment.shared.model.cards.first {
                        resolvedCard = CardEntity(fallback)
                    }
                }

            case .category:
                if resolvedCategory == nil {
                    let targetCardID = resolvedCard.flatMap { UUID(uuidString: $0.id) } ?? AppEnvironment.shared.model.selectedCardID ?? AppEnvironment.shared.model.activeCardID
                    let active = AppEnvironment.shared.model.activeCategories(for: targetCardID)
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
            let unhidden = AppEnvironment.shared.model.unhiddenCards
            if let first = unhidden.first {
                resolvedCard = CardEntity(first)
            } else if let fallback = AppEnvironment.shared.model.cards.first {
                resolvedCard = CardEntity(fallback)
            }
        }
        guard let targetCard = resolvedCard, let targetCardID = UUID(uuidString: targetCard.id) else {
            throw EntryError.corruptStore
        }

        let active = AppEnvironment.shared.model.activeCategories(for: targetCardID)
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
        let expense = try service.record(amountInRupiah: Int64(validAmount), categoryID: categoryID, note: finalNote, date: date ?? .now, in: targetCardID)
        let cardName = AppEnvironment.shared.model.cards.first(where: { $0.id == targetCardID })?.name ?? targetCard.name
        SpendingSessionManager.shared.recordExpense(amount: expense.amount, note: expense.note, categorySymbol: targetCategory.symbol, cardID: targetCardID)
        return .result(
            dialog: "Added \(Money.format(expense.amount)) in \(targetCategory.name) on \(cardName).",
            view: ExpenseReceiptSnippetView(expense: expense, categoryName: targetCategory.name, categorySymbol: targetCategory.symbol, cardName: cardName)
        )
    }
}

// MARK: - Add Expense From Text Intent

struct AddExpenseFromTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Add Expense from Text"
    static let description = IntentDescription("Add an expense in Monocle using natural text. For example: 'Coffee 28k' or 'Lunch 45k'.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Expense", description: "For example, Coffee 28k", requestValueDialog: IntentDialog("What did you spend on? (e.g. Coffee 28k)")) var text: String
    @Parameter(title: "Card") var card: CardEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$text)") {
            \.$card
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let service = AppEnvironment.shared.expenses else { throw EntryError.corruptStore }
        var resolvedCard = card
        if resolvedCard == nil {
            let availableCards = AppEnvironment.shared.model.unhiddenCards
            let entities = availableCards.map(CardEntity.init)
            if entities.count > 1 {
                resolvedCard = try await $card.requestDisambiguation(among: entities, dialog: IntentDialog("Which card?"))
            } else if let single = entities.first {
                resolvedCard = single
            } else if let fallback = AppEnvironment.shared.model.cards.first {
                resolvedCard = CardEntity(fallback)
            }
        }
        let targetCardID = resolvedCard.flatMap { UUID(uuidString: $0.id) } ?? AppEnvironment.shared.model.selectedCardID ?? AppEnvironment.shared.model.activeCardID
        let expense = try service.record(text: text, in: targetCardID)
        let cardName = AppEnvironment.shared.model.cards.first(where: { $0.id == targetCardID })?.name ?? "Card"
        let cat = AppEnvironment.shared.model.activeCategories(for: targetCardID).first(where: { $0.id == expense.splits.first?.categoryID })
        let catName = cat?.name ?? "Expense"
        let catSymbol = cat?.symbol ?? "creditcard"
        SpendingSessionManager.shared.recordExpense(amount: expense.amount, note: expense.note, categorySymbol: catSymbol, cardID: targetCardID)

        return .result(
            dialog: "Added \(Money.format(expense.amount)) on \(cardName).",
            view: ExpenseReceiptSnippetView(expense: expense, categoryName: catName, categorySymbol: catSymbol, cardName: cardName)
        )
    }
}

// MARK: - Quick Entry Intent

struct OpenQuickEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Quick Entry"
    static let description = IntentDescription("Open Monocle ready to add an expense.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .foreground }
    static var openAppWhenRun: Bool { true }

    @Parameter(title: "Card") var card: CardEntity?
    @Parameter(title: "Category") var category: ExpenseCategoryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Open quick entry") {
            \.$card
            \.$category
        }
    }

    @MainActor func perform() async throws -> some IntentResult {
        let targetCardID = card.flatMap { UUID(uuidString: $0.id) }
        let targetCatID = category.flatMap { UUID(uuidString: $0.id) }
        AppModel.shared.openEntry(for: targetCardID, categoryID: targetCatID)
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
    @Parameter(title: "Card") var card: CardEntity?
    @Parameter(title: "Budget Limit (IDR)") var budgetLimit: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Start \(\.$name)") {
            \.$card
            \.$budgetLimit
        }
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let targetCardID = card.flatMap { UUID(uuidString: $0.id) } ?? AppEnvironment.shared.model.selectedCardID ?? AppEnvironment.shared.model.activeCardID
        let cardName = AppEnvironment.shared.model.cards.first(where: { $0.id == targetCardID })?.name ?? "Card"
        var limit: Int64?
        if let budgetLimit, budgetLimit > 0 {
            let converted = Int64(budgetLimit).multipliedReportingOverflow(by: 100)
            guard !converted.overflow, converted.partialValue <= Money.maximum else { throw EntryError.invalidAmount }
            limit = converted.partialValue
        }
        SpendingSessionManager.shared.startSession(name: name, cardName: cardName, cardID: targetCardID, budgetLimit: limit)
        return .result(dialog: "Started spending session '\(name)' on \(cardName).")
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

// MARK: - Stack Entity

struct StackEntity: AppEntity {
    let id: String
    let name: String

    init(_ stack: Stack) {
        id = stack.id.uuidString
        name = stack.name
    }

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Stack")
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "Stack", image: .init(systemName: "rectangle.stack"))
    }
    static let defaultQuery = StackEntityQuery()
}

struct StackEntityQuery: EntityStringQuery, EnumerableEntityQuery {
    func entities(for identifiers: [String]) async throws -> [StackEntity] { await stacks().filter { identifiers.contains($0.id) } }
    func entities(matching string: String) async throws -> [StackEntity] { await stacks().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    func suggestedEntities() async throws -> [StackEntity] { await stacks() }
    func allEntities() async throws -> [StackEntity] { await stacks() }

    private func stacks() async -> [StackEntity] {
        await MainActor.run { AppEnvironment.shared.model.stacks.map(StackEntity.init) }
    }
}

// MARK: - Ask Intents (read-only answers; nothing here writes an expense)

enum SummaryPeriod: String, AppEnum {
    case thisMonth = "this_month", lastMonth = "last_month", last30Days = "last_30_days", thisCycle = "this_cycle", yearToDate = "year_to_date"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Period")
    static let caseDisplayRepresentations: [SummaryPeriod: DisplayRepresentation] = [
        .thisMonth: "This month", .lastMonth: "Last month", .last30Days: "Last 30 days", .thisCycle: "This budget cycle", .yearToDate: "Year to date",
    ]
}

/// Shared by the ask intents: a tool run on the same on-device code the chat uses, so a Shortcut and the chat never disagree.
@MainActor
enum AskAnswers {
    struct Total: Decodable { let display: String }
    struct Summary: Decodable { let scope: String; let total: Total; let count: Int }
    struct Budget: Decodable {
        let card: String; let hasBudget: Bool
        var limit: Total?; var spent: Total?; var remaining: Total?
    }

    static func scopeName(card: CardEntity?, stack: StackEntity?) -> String? {
        if let stack { return "stack:\(stack.name)" }
        if let card { return "card:\(card.name)" }
        return nil
    }

    static func summary(period: SummaryPeriod, scope: String?, model: AppModel, now: Date = .now) throws -> Summary {
        var input: [String: Any] = ["period": period.rawValue]
        if let scope { input["scope"] = scope }
        return try run("get_summary", input, model: model, now: now)
    }

    static func budget(card: String?, model: AppModel, now: Date = .now) throws -> Budget {
        try run("get_budget_status", card.map { ["card": $0] } ?? [:], model: model, now: now)
    }

    private static func run<T: Decodable>(_ tool: String, _ input: [String: Any], model: AppModel, now: Date) throws -> T {
        let executor = ToolExecutor(model: model, scope: .allCards, now: now)
        let outcome = executor.run(tool, input: try JSONSerialization.data(withJSONObject: input))
        guard !outcome.isError else { throw AskError.failed(outcome.json) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase // ToolExecutor encodes snake_case
        return try decoder.decode(T.self, from: Data(outcome.json.utf8))
    }
}

enum AskError: LocalizedError {
    case failed(String)
    case chatOff
    var errorDescription: String? {
        switch self {
        case .failed(let json): (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["error"] as? String ?? "That didn't work."
        case .chatOff: "Ask Monocle needs Apple Intelligence on this iPhone."
        }
    }
}

struct SpendingSummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "How Much Did I Spend"
    static let description = IntentDescription("Tells you how much you spent in a period, across everything or on one stack or card.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Period", default: .thisMonth) var period: SummaryPeriod
    @Parameter(title: "Stack") var stack: StackEntity?
    @Parameter(title: "Card") var card: CardEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("How much did I spend \(\.$period)") {
            \.$stack
            \.$card
        }
    }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let summary = try AskAnswers.summary(period: period, scope: AskAnswers.scopeName(card: card, stack: stack), model: AppEnvironment.shared.model)
        let noun = summary.count == 1 ? "expense" : "expenses"
        return .result(dialog: "\(summary.total.display) spent on \(summary.scope) (\(summary.count) \(noun)).")
    }
}

struct BudgetLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Budget Left"
    static let description = IntentDescription("Tells you how much is left in a card's budget for the current cycle.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Card") var card: CardEntity?

    static var parameterSummary: some ParameterSummary { Summary("Budget left on \(\.$card)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let budget = try AskAnswers.budget(card: card?.name, model: AppEnvironment.shared.model)
        guard budget.hasBudget, let remaining = budget.remaining, let limit = budget.limit else {
            return .result(dialog: "\(budget.card) has no budget for this cycle.")
        }
        return .result(dialog: "\(remaining.display) left on \(budget.card) (\(budget.spent?.display ?? "nothing") of \(limit.display) spent).")
    }
}

struct RemoveLastExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "Remove Last Expense"
    static let description = IntentDescription("Removes the expense you added most recently, on any card, after you confirm. Undo it in the app.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .background }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppEnvironment.shared.model
        guard let last = model.allExpenses().max(by: { $0.createdAt < $1.createdAt }) else {
            return .result(dialog: "There's no expense to remove.")
        }
        let label = last.note.isEmpty ? Money.format(last.amount) : "\(Money.format(last.amount)) (\(last.note))"
        try await requestConfirmation(result: .result(dialog: IntentDialog(stringLiteral: "Remove \(label)?")))
        model.delete(last)
        guard model.undoExpense?.id == last.id else { return .result(dialog: IntentDialog(stringLiteral: model.error ?? "Couldn't remove the expense.")) }
        return .result(dialog: "Removed \(label).")
    }
}

struct AskMonocleIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Monocle"
    static let description = IntentDescription("Asks Monocle's AI chat a question about your spending, or to prepare an expense. Anything it proposes waits in the app for your confirmation.")
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresLocalDeviceAuthentication }
    static var supportedModes: IntentModes { .background }

    @Parameter(title: "Question", requestValueDialog: IntentDialog("What do you want to ask Monocle?")) var question: String

    static var parameterSummary: some ParameterSummary { Summary("Ask Monocle \(\.$question)") }

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppEnvironment.shared.model
        guard ChatSession.unavailableReason == nil else { throw AskError.chatOff }
        let scope = model.chat.scope ?? ChatScopeMenuItems.homeScope(model)
        let outputs = await model.chat.send(question, model: model, scope: scope)
        return .result(dialog: IntentDialog(stringLiteral: Self.spoken(outputs)))
    }

    /// The reply as one sentence-sized answer; a proposal is never saved from here, so say where to confirm it.
    static func spoken(_ outputs: [ChatAgent.Output]) -> String {
        var parts: [String] = []
        var pending = false
        for output in outputs {
            switch output {
            case .text(let text): parts.append(text)
            case .error(let text): parts.append(text)
            case .proposal, .change, .bill: pending = true
            case .chart, .notice: break
            }
        }
        if pending { parts.append("I prepared a change. Open Monocle to confirm it.") }
        return parts.isEmpty ? "No answer." : parts.joined(separator: " ")
    }
}

// MARK: - App Shortcuts Provider

struct MonocleShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .red }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenQuickEntryIntent(),
            phrases: [
                "Quick entry in \(.applicationName)",
                "Open quick entry in \(.applicationName)"
            ],
            shortTitle: "Quick entry",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add an expense in \(.applicationName)",
                "Add \(\.$category) expense in \(.applicationName)",
                "Add \(\.$category) in \(.applicationName)"
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
            intent: SpendingSummaryIntent(),
            phrases: [
                "How much did I spend in \(.applicationName)",
                "My spending in \(.applicationName)"
            ],
            shortTitle: "How much spent",
            systemImageName: "chart.pie"
        )
        AppShortcut(
            intent: BudgetLeftIntent(),
            phrases: [
                "Budget left in \(.applicationName)",
                "How much budget is left in \(.applicationName)"
            ],
            shortTitle: "Budget left",
            systemImageName: "gauge.with.dots.needle.33percent"
        )
        AppShortcut(
            intent: RemoveLastExpenseIntent(),
            phrases: [
                "Remove last expense in \(.applicationName)",
                "Undo last expense in \(.applicationName)"
            ],
            shortTitle: "Remove last expense",
            systemImageName: "minus.circle"
        )
        AppShortcut(
            intent: AskMonocleIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question"
            ],
            shortTitle: "Ask Monocle",
            systemImageName: "bubble.left.and.text.bubble.right"
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
