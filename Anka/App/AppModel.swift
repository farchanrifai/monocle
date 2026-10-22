import Foundation
import Observation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    var id: Self { self }
}

enum CustomizerTarget: Identifiable, Equatable {
    case existing(Card)
    case newCard

    var id: String {
        switch self {
        case .existing(let card):
            return card.id.uuidString
        case .newCard:
            return "new-book"
        }
    }
}

enum StackCustomizerMode: Identifiable, Equatable {
    case manage
    case create

    var id: String {
        switch self {
        case .manage: return "manage"
        case .create: return "create"
        }
    }
}

@MainActor @Observable
final class AppModel {
    static var shared: AppModel { AppEnvironment.shared.model }
    var expenses: [Expense] { expenseService?.expenses ?? [] }
    var categories: [ExpenseCategory] { expenseService?.categories ?? [] }
    var bills: [Bill] { expenseService?.bills ?? [] }
    /// Bumps on every committed write; key memoized views on it.
    var dataRevision: UInt64 { expenseService?.committedRevision ?? 0 }
    var billOccurrences: [BillOccurrence] { expenseService?.billOccurrences ?? [] }
    var activeCategories: [ExpenseCategory] {
        let currentInactive = workspacePreferences.cardInactiveCategoryIDs[activeCardID] ?? []
        return categories.filter { !settings.archivedCategoryIDs.contains($0.id) && !currentInactive.contains($0.id) }
    }
    var globalCategories: [GlobalCategory] {
        get { workspacePreferences.globalCategories }
        set {
            workspacePreferences.globalCategories = newValue
            persistWorkspacePreferences()
        }
    }
    var shortcutInputOrder: [ShortcutInputField] {
        get {
            var order = workspacePreferences.shortcutInputOrder
            if order.isEmpty {
                order = [.card, .category, .note, .amount]
            }
            return order
        }
        set {
            workspacePreferences.shortcutInputOrder = newValue
            persistWorkspacePreferences()
        }
    }
    var draft = ExpenseDraft()
    private(set) var originalDraft: ExpenseDraft?
    var settings = PrototypeSettings()
    var showEntry = false
    var showSettings = false
    /// Making a new stack is Pro; managing the current one is free.
    var showStackCustomizer = false {
        didSet { if showStackCustomizer, stackCustomizerMode == .create, !requirePro("Stacks are part of Pro.") { showStackCustomizer = false } }
    }
    var stackCustomizerMode: StackCustomizerMode = .manage
    /// Export is free; opening on Import (tab 1) is Pro.
    var showCSVInterchange = false {
        didSet { if showCSVInterchange, csvInterchangeInitialTab == 1, !requirePro("CSV import is part of Pro.") { showCSVInterchange = false } }
    }
    var csvInterchangeInitialTab = 0
    var showAnalytics = false {
        didSet { if showAnalytics, !requirePro("Analytics is part of Pro.") { showAnalytics = false } }
    }
    var showChat = false
    /// Text for the chat composer, set by `anka://chat?q=`; ChatView takes it.
    var chatPrefill: String?
    /// Replaced by AppEnvironment with a file-backed session; tests keep this in-memory one.
    var chat = ChatSession()
    /// The Pro subscription. nil in tests and on the Mac until it ships, which leaves every feature open.
    @ObservationIgnored var pro: ProStore? {
        didSet { pro?.onChange = { [weak self] in self?.applyPlan() }; applyPlan() }
    }
    var isPro: Bool { pro?.isPro ?? true }
    /// Set at launch from `needsOnboarding`; onboarding clears it once its last step is done.
    var showOnboarding = false
    /// Why the paywall is open ("" for no particular reason), or nil when closed.
    var paywall: String?
    var showPaywall: Bool {
        get { paywall != nil }
        set { if !newValue { paywall = nil } }
    }
    var selectedTab = 0
    var error: String?
    var startupError: String?
    var backups: BackupService?
    let appLock: AppLockController
    var toast: String?
    var toastID = UUID()
    var saveFeedback = 0
    var pendingEntry: Expense?
    var sessionManager: SpendingSessionManager { SpendingSessionManager.shared }
    var showStartSessionSheet = false {
        didSet { if showStartSessionSheet, !requirePro("Spending sessions and Live Activities are part of Pro.") { showStartSessionSheet = false } }
    }
    var sessionSheetName: String = ""
    var sessionSheetBudget: String = ""
    /// How many screens are pushed over Home; the floating bottom bar hides while any is.
    var pushedDepth = 0
    var pendingRepeat = false
    var undoExpense: Expense?
    private(set) var undoOccurrences: [BillOccurrence] = []
    @ObservationIgnored private var durablePreferences = WorkspacePreferences()
    let expenseService: ExpenseService?
    private let state: (any LocalStateStore)?

    var cards: [Card] { expenseService?.cards ?? [settings.card] }
    var activeCardID: UUID { expenseService?.activeCardID ?? settings.card.id }
    var selectedCardID: UUID?
    var workspacePreferences = WorkspacePreferences()
    var hiddenCardIDs: Set<UUID> = []
    var alwaysHiddenCardIDs: Set<UUID> = []
    /// A second real card, or any card's look, is Pro.
    var customizerTarget: CustomizerTarget? = nil {
        didSet {
            switch customizerTarget {
            case .newCard where cards.contains(where: { $0.kind == .real }):
                if !requirePro(PlanError.cardLimit.localizedDescription) { customizerTarget = nil }
            case .existing:
                if !requirePro("Card looks are part of Pro.") { customizerTarget = nil }
            default: break
            }
        }
    }
    var customizingCard: Card? {
        get {
            if case .existing(let card) = customizerTarget {
                return card
            }
            return nil
        }
        set {
            if let newValue {
                customizerTarget = .existing(newValue)
            } else {
                customizerTarget = nil
            }
        }
    }

    var autoAppearance: Bool {
        get { workspacePreferences.autoAppearance }
        set {
            guard workspacePreferences.autoAppearance != newValue else { return }
            workspacePreferences.autoAppearance = newValue
            persistWorkspacePreferences()
        }
    }

    var manualAppearance: AppearanceMode {
        get {
            (visualDirection == .light || visualDirection == .ledger) ? .light : .dark
        }
        set {
            autoAppearance = false
            switch newValue {
            case .light:
                visualDirection = .light
            case .dark:
                visualDirection = .instrument
            }
        }
    }

    var visualDirection: CardVisualDirection {
        get { workspacePreferences.direction }
        set {
            guard workspacePreferences.direction != newValue else { return }
            workspacePreferences.direction = newValue
            workspacePreferences.autoAppearance = false
            persistWorkspacePreferences()
        }
    }

    func effectiveDirection(for systemScheme: ColorScheme) -> CardVisualDirection {
        if autoAppearance {
            return systemScheme == .dark ? .instrument : .light
        } else {
            return visualDirection
        }
    }

    var preferredColorScheme: ColorScheme? {
        if autoAppearance {
            return nil
        }
        return (visualDirection == .light || visualDirection == .ledger) ? .light : .dark
    }

    var filterScope: StackFilterScope {
        get { workspacePreferences.filterScope }
        set {
            workspacePreferences.filterScope = newValue
            persistWorkspacePreferences()
        }
    }

    var stacks: [Stack] {
        get { workspacePreferences.stacks }
        set {
            workspacePreferences.stacks = newValue
            persistWorkspacePreferences()
        }
    }

    var activeStackID: UUID? {
        get { workspacePreferences.activeStackID }
        set {
            workspacePreferences.activeStackID = newValue
            persistWorkspacePreferences()
        }
    }

    var currentStack: Stack? {
        if let id = activeStackID, let stack = stacks.first(where: { $0.id == id }) {
            return stack
        }
        return stacks.first
    }

    var orderedCards: [Card] {
        let current = cards
        var result: [Card] = []
        for id in workspacePreferences.cardOrder {
            if let card = current.first(where: { $0.id == id }) {
                result.append(card)
            }
        }
        for card in current where !result.contains(where: { $0.id == card.id }) {
            result.append(card)
        }
        return result
    }

    var unhiddenCards: [Card] {
        orderedCards.filter { !alwaysHiddenCardIDs.contains($0.id) }
    }

    var cardsInCurrentStack: [Card] {
        guard let stack = currentStack else { return unhiddenCards }
        let current = cards
        var result: [Card] = []
        for id in stack.cardIDs {
            if !alwaysHiddenCardIDs.contains(id), let card = current.first(where: { $0.id == id }) {
                result.append(card)
            }
        }
        return result
    }

    var homeDeckCards: [Card] {
        switch filterScope {
        case .activeStack:
            return cardsInCurrentStack
        case .allCards:
            return unhiddenCards
        }
    }

    var visibleCards: [Card] {
        homeDeckCards
    }

    var budgetHistory: [BudgetVersion] { expenseService?.budgets ?? [] }
    var activeBudget: BudgetVersion {
        BudgetHistory.active(on: .now, budgets: budgetHistory) ?? BudgetVersion.initial(overallLimit: settings.budget, startDay: settings.startDay)
    }
    var currentBudgetPeriod: BudgetPeriod {
        BudgetHistory.period(containing: .now, budgets: budgetHistory)
            ?? BudgetPeriod(budget: activeBudget, cycle: Cycle.containing(.now, startDay: activeBudget.startDay))
    }
    var cycle: Cycle { currentBudgetPeriod.cycle }
    var cycleExpenses: [Expense] {
        let currentCycle = cycle
        return expenses.filter { currentCycle.contains($0) }
    }
    /// In the active card's currency, like its budget.
    var spent: Int64 {
        guard let card = cards.first(where: { $0.id == activeCardID }) else { return Money.sum(cycleExpenses.map(\.amount)) }
        return Money.sum(cycleExpenses.map { cardAmount($0, in: card) })
    }
    var remaining: Int64 { activeBudget.overallLimit - spent }

    init(expenses: ExpenseService, state: any LocalStateStore, draft: ExpenseDraft = ExpenseDraft(), settings: PrototypeSettings = PrototypeSettings(), appLock: AppLockController? = nil, backups: BackupService? = nil) {
        self.expenseService = expenses
        self.state = state
        self.draft = draft
        self.settings = settings
        self.appLock = appLock ?? AppLockController(timeout: settings.appLockTimeout)
        self.backups = backups
        do {
            let prefs = try state.loadWorkspacePreferences()
            var categoryMap: [UUID: [ExpenseCategory]] = [:]
            for card in expenses.cards { categoryMap[card.id] = try expenses.categories(for: card.id) }
            try prefs.validate(cards: expenses.cards, categoriesByCard: categoryMap)
            let settingsCards = expenses.cards.map { CardBackupItem(card: $0, categories: categoryMap[$0.id] ?? [], expenses: [], budgets: []) }
            try self.settings.validate(cards: settingsCards, globalCategories: prefs.globalCategories, allowLegacySampleProfile: true)
            if let stored = expenses.cards.first(where: { $0.id == settings.card.id }) { self.settings.card = stored }
            else if settings.card == .demo, let active = expenses.cards.first(where: { $0.id == expenses.activeCardID }) { self.settings.card = active }
            if self.settings.card != settings.card { try state.saveSettings(self.settings) }
            publishPreferences(prefs)
            try ensureGlobalCategories()
            try ensureDefaultStack()
            try ensureSingleStackPerCard()
            try expenses.reconcileBills()
            expenses.onCommit = { [weak self] in self?.committedWorkspaceChanged() }
            syncWidgetSnapshot()
            Task { [weak self] in await self?.prefetchCardRates() }
        } catch {
            startupError = error.localizedDescription
            expenses.isBlocked = true
        }
    }

    init(startupFailure: String) {
        expenseService = nil
        state = nil
        appLock = AppLockController(timeout: nil)
        startupError = startupFailure
    }

    func ensureDefaultStack() throws {
        var proposed = workspacePreferences
        if proposed.cardOrder.isEmpty { proposed.cardOrder = cards.map(\.id) }
        if proposed.stacks.isEmpty {
            let initial = Stack(id: UUID(), name: "Daily", icon: "rectangle.stack", cardIDs: orderedCards.map(\.id).filter { !alwaysHiddenCardIDs.contains($0) })
            proposed.stacks = [initial]; proposed.activeStackID = initial.id
        } else if !proposed.stacks.contains(where: { $0.id == proposed.activeStackID }) { proposed.activeStackID = proposed.stacks.first?.id }
        if proposed != workspacePreferences { try commitPresentationPreferences(proposed) }
    }

    /// One-time cleanup for workspaces saved before cards were limited to one stack.
    func ensureSingleStackPerCard() throws {
        var proposed = workspacePreferences
        guard proposed.keepEachCardInOneStack() > 0 else { return }
        try commitPresentationPreferences(proposed)
        showToast("Each card now belongs to one stack")
    }

    private func commitPresentationPreferences(_ proposed: WorkspacePreferences) throws {
        guard startupError == nil, expenseService?.isBlocked != true else { throw BackupError.recoveryRequired }
        var proposed = proposed
        proposed.keepEachCardInOneStack()
        var categoriesByCard: [UUID: [ExpenseCategory]] = [:]
        for card in cards { categoriesByCard[card.id] = try expenseService?.categories(for: card.id) }
        try proposed.validate(cards: cards, categoriesByCard: categoriesByCard)
        try requireState().saveWorkspacePreferences(proposed)
        publishPreferences(proposed); syncWidgetSnapshot()
    }

    func ensureGlobalCategories() throws {
        guard workspacePreferences.globalCategories.isEmpty, let expenseService else { return }
        var catalog: [GlobalCategory] = []
        var seenNames = Set<String>()
        var seenIDs = Set<UUID>()
        for card in cards {
            for cat in try expenseService.categories(for: card.id) {
                let name = cat.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                guard seenNames.insert(name).inserted else { continue }
                let id = seenIDs.insert(cat.id).inserted ? cat.id : UUID()
                catalog.append(GlobalCategory(id: id, name: cat.name, symbol: cat.symbol, defaultActiveForNewCards: true))
            }
        }
        if catalog.isEmpty { catalog = GlobalCategory.defaults }
        let mapping = try expenseService.categoryMigrationMapping(to: catalog)
        var preferences = workspacePreferences
        preferences.globalCategories = catalog
        for (cardID, ids) in preferences.cardInactiveCategoryIDs {
            preferences.cardInactiveCategoryIDs[cardID] = ids.map { mapping[cardID]?[$0] ?? $0 }
        }
        var updatedSettings = settings
        let settingsMap = mapping[settings.card.id] ?? [:]
        updatedSettings.archivedCategoryIDs = Set(settings.archivedCategoryIDs.map { settingsMap[$0] ?? $0 })
        updatedSettings.categoryRules = settings.categoryRules.map { rule in
            var value = rule; value.categoryID = settingsMap[rule.categoryID] ?? rule.categoryID; return value
        }
        var drafts: [UUID: ExpenseDraft] = [:]
        for card in cards {
            var value = card.id == (draft.cardID ?? settings.card.id) ? draft : try requireState().loadDraft(for: card.id)
            value.cardID = card.id
            if let categoryID = value.categoryID { value.categoryID = mapping[card.id]?[categoryID] ?? categoryID }
            value.splitParts = value.splitParts.map { split in
                var result = split; result.categoryID = mapping[card.id]?[split.categoryID] ?? split.categoryID; return result
            }
            drafts[card.id] = value
        }
        try performWorkspaceCommand {
            try expenseService.unifyCategoriesToGlobalCatalog(catalog)
            for (cardID, value) in drafts { try requireState().saveDraft(value, for: cardID) }
            try requireState().saveSettings(updatedSettings)
            try requireState().saveWorkspacePreferences(preferences)
        }
        settings = updatedSettings
        expenseService.configure(categoryRules: settings.categoryRules, archivedCategoryIDs: settings.archivedCategoryIDs)
        if let value = drafts[draft.cardID ?? settings.card.id] { draft = value }
        publishPreferences(preferences)
    }

    private func performWorkspaceCommand(_ operation: () throws -> Void) throws {
        guard let expenseService, startupError == nil else { throw BackupError.recoveryRequired }
        do {
            if let backups {
                try backups.withRecovery(currentDraft: draft, settings: settings) {
                    try expenseService.performTransaction(operation)
                }
            } else {
                let local = try requireState()
                let oldSettings = try local.loadSettings()
                let oldPreferences = try local.loadWorkspacePreferences()
                var oldDrafts: [UUID: ExpenseDraft] = [:]
                for card in cards { oldDrafts[card.id] = try local.loadDraft(for: card.id) }
                do { try expenseService.performTransaction(operation) }
                catch {
                    let originalError = error
                    do {
                        try local.saveSettings(oldSettings)
                        try local.saveWorkspacePreferences(oldPreferences)
                        for (id, value) in oldDrafts { try local.saveDraft(value, for: id) }
                    } catch {
                        expenseService.isBlocked = true
                        startupError = BackupError.recoveryRequired.localizedDescription
                        throw BackupError.recoveryRequired
                    }
                    throw originalError
                }
            }
        } catch {
            if backups?.requiresRecovery == true { startupError = BackupError.recoveryRequired.localizedDescription }
            throw error
        }
    }

    private func publishPreferences(_ preferences: WorkspacePreferences) {
        Money.reportingCurrency = preferences.reportingCurrency
        workspacePreferences = preferences
        durablePreferences = preferences
        hiddenCardIDs = Set(preferences.visibleCardIDs.isEmpty ? [] : cards.map(\.id).filter { !preferences.visibleCardIDs.contains($0) })
        alwaysHiddenCardIDs = Set(preferences.alwaysHiddenCardIDs)
        memoizedActivities = nil
    }

    func reload() throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.reload()
        try expenseService.reconcileBills()
        invalidateExpenseCaches()
        try ensureDefaultStack()
        try ensureSingleStackPerCard()
        try ensureGlobalCategories()
        appLock.applyPersistedConfiguration(settings.appLockTimeout)
    }
    func category(_ id: UUID?) -> ExpenseCategory? {
        guard let id else { return nil }
        if let cat = categories.first(where: { $0.id == id }) {
            return cat
        }
        if let global = globalCategories.first(where: { $0.id == id }) {
            return global.toExpenseCategory()
        }
        return nil
    }
    func title(_ expense: Expense) -> String { expense.note.isEmpty ? category(expense.splits.first?.categoryID)?.name ?? "Expense" : expense.note }
    func spent(in category: ExpenseCategory) -> Int64 {
        let card = cards.first { $0.id == activeCardID }
        return Money.sum(cycleExpenses.compactMap { expense -> Int64? in
            guard let part = expense.splits.first(where: { $0.categoryID == category.id }) else { return nil }
            guard let card, currency(of: card) != reportingCurrency else { return part.amount }
            return (try? Money.checkedScale(cardAmount(expense, in: card), numerator: Int(truncatingIfNeeded: part.amount),
                                            denominator: Int(truncatingIfNeeded: max(1, expense.amount)))) ?? 0
        })
    }
    var draftNeedsConfirmation: Bool {
        if draft.editing {
            if let originalDraft {
                return draft != originalDraft
            }
            let saved = expenses.first(where: { $0.id == draft.id })
                ?? cards.lazy.compactMap { self.expenses(for: $0.id).first(where: { $0.id == self.draft.id }) }.first
            guard let saved else { return false }
            return (try? draft.expense()) != saved
        }
        return draft.hasContent
    }

    func openEntry(for cardID: UUID? = nil, categoryID: UUID? = nil) {
        originalDraft = nil
        let targetCardID = cardID ?? selectedCardID ?? activeCardID
        if targetCardID != activeCardID || draft.cardID != targetCardID {
            guard selectCard(targetCardID) else { return }
        }
        draft.cardID = targetCardID
        if let categoryID, let cat = activeCategories(for: targetCardID).first(where: { $0.id == categoryID }) {
            draft.categoryID = cat.id
        }
        showEntry = true
    }
    func edit(_ expense: Expense) {
        if draftNeedsConfirmation { pendingRepeat = false; pendingEntry = expense; return }
        draft = ExpenseDraft(expense: expense)
        if draft.cardID == nil {
            draft.cardID = expense.cardID ?? activeCardID
        }
        originalDraft = draft
        showEntry = true
    }
    func persistDraft() {
        guard startupError == nil else { return }
        do {
            if let cardID = draft.cardID {
                try requireState().saveDraft(draft, for: cardID)
            } else {
                try requireState().saveDraft(draft)
            }
        } catch { self.error = "Your draft could not be saved: \(error.localizedDescription)" }
    }
    @discardableResult
    func discardDraft() -> Bool {
        originalDraft = nil
        var cleared = ExpenseDraft(); cleared.cardID = draft.cardID ?? activeCardID
        do {
            if let cardID = draft.cardID {
                try requireState().saveDraft(cleared, for: cardID)
            } else {
                try requireState().saveDraft(cleared)
            }
            draft = cleared; return true
        }
        catch { self.error = "Your draft could not be discarded: \(error.localizedDescription)"; return false }
    }
    func discardAndOpenPendingEntry() {
        guard let pendingEntry, discardDraft() else { return }
        self.pendingEntry = nil
        if pendingRepeat { repeatExpense(pendingEntry) } else { edit(pendingEntry) }
    }

    func openCardInHome(id: UUID) {
        selectedTab = 0
        showEntry = false
        showSettings = false
        if !visibleCards.contains(where: { $0.id == id }) {
            if let stack = stacks.first(where: { $0.cardIDs.contains(id) }) {
                setActiveStack(id: stack.id)
            } else {
                filterScope = .allCards
            }
        }
        selectCard(id)
    }

    func openStackInHome(id: UUID) {
        selectedTab = 0
        showEntry = false
        showSettings = false
        selectedCardID = nil
        setActiveStack(id: id)
    }

    @discardableResult
    func selectCard(_ id: UUID) -> Bool {
        guard let expenseService, cards.contains(where: { $0.id == id }) else {
            error = "The selected card is no longer available."
            return false
        }
        do {
            if draft.cardID != id {
                try requireState().saveDraft(draft, for: draft.cardID ?? activeCardID)
            }
            let targetDraft = try requireState().loadDraft(for: id)
            try expenseService.selectCard(id)
            selectedCardID = id
            if draft.cardID != id {
                draft = targetDraft
                draft.cardID = id
                originalDraft = nil
            }
            invalidateExpenseCaches()
            return true
        } catch {
            self.error = "The selected card could not be opened: \(error.localizedDescription)"
            return false
        }
    }

    func createCard(named name: String, selectedCategoryIDs: Set<UUID>? = nil) throws -> Card {
        guard let expenseService else { throw EntryError.corruptStore }
        let initialCategories = globalCategories.filter { selectedCategoryIDs?.contains($0.id) ?? $0.defaultActiveForNewCards }
        var created: Card?
        var proposed = workspacePreferences
        try performWorkspaceCommand {
            let card = try expenseService.createCard(named: name, initialCategories: initialCategories)
            created = card
            proposed.cardOrder.append(card.id)
            if let index = proposed.stacks.firstIndex(where: { $0.id == proposed.activeStackID }) { proposed.stacks[index].cardIDs.append(card.id) }
            try requireState().saveWorkspacePreferences(proposed)
        }
        guard let created else { throw EntryError.corruptStore }
        publishPreferences(proposed); invalidateExpenseCaches(); showToast("Card created")
        return created
    }

    func renameCard(id: UUID, to name: String) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        guard let existing = cards.first(where: { $0.id == id }) else { throw BackupError.invalid }
        var renamed = existing
        renamed.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try renamed.validate()
        var proposed = settings
        if proposed.card.id == id { proposed.card = renamed }
        try performWorkspaceCommand {
            try expenseService.renameCard(id: id, to: name)
            try requireState().saveSettings(proposed)
        }
        settings = proposed; invalidateExpenseCaches(); showToast("Card renamed")
    }

    func deleteCard(id: UUID) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        var proposed = workspacePreferences
        var updatedSettings = settings
        let remainingCards = cards.filter { $0.id != id }
        guard !remainingCards.isEmpty else { throw BackupError.invalid }
        let ownsDeletedDraft = (draft.cardID ?? settings.card.id) == id
        let replacementDraftID = activeCardID == id ? remainingCards[0].id : activeCardID
        let replacementDraft = ownsDeletedDraft ? try requireState().loadDraft(for: replacementDraftID) : nil
        if updatedSettings.card.id == id, let replacement = remainingCards.first {
            updatedSettings.card = replacement
            if let budget = BudgetHistory.active(on: .now, budgets: try expenseService.budgets(for: replacement.id)) {
                updatedSettings.budget = budget.overallLimit; updatedSettings.startDay = budget.startDay
            }
        }
        let oldCustom = proposed.cardCustomizations.removeValue(forKey: id)
        proposed.cardInactiveCategoryIDs.removeValue(forKey: id)
        proposed.cardOrder.removeAll { $0 == id }
        proposed.visibleCardIDs.removeAll { $0 == id }
        proposed.alwaysHiddenCardIDs.removeAll { $0 == id }
        for index in proposed.stacks.indices { proposed.stacks[index].cardIDs.removeAll { $0 == id } }
        try performWorkspaceCommand {
            try expenseService.deleteCard(id: id)
            try requireState().saveSettings(updatedSettings)
            try requireState().saveWorkspacePreferences(proposed)
        }
        settings = updatedSettings
        expenseService.configure(categoryRules: settings.categoryRules, archivedCategoryIDs: settings.archivedCategoryIDs)
        publishPreferences(proposed)
        if selectedCardID == id { selectedCardID = nil }
        if var replacementDraft { replacementDraft.cardID = activeCardID; draft = replacementDraft; originalDraft = nil }
        if let oldCustom, case .customPhoto(let filename) = oldCustom.style,
           !proposed.cardCustomizations.values.contains(where: { $0.style == oldCustom.style }) {
            CardArtworkStore.shared.deleteArtwork(filename: filename)
        }
        invalidateExpenseCaches(); showToast("Card deleted")
    }

    func applyCardCustomizations(names: [UUID: String], customizations: [UUID: CardCustomization],
                                 newCardIDs: Set<UUID>, selections: [UUID: Set<UUID>]) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        var proposed = workspacePreferences
        var updatedSettings = settings
        var lastCreated: UUID?
        try performWorkspaceCommand {
            for placeholder in newCardIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                let raw = names[placeholder]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let selected = selections[placeholder]
                let initial = globalCategories.filter { selected?.contains($0.id) ?? $0.defaultActiveForNewCards }
                let card = try expenseService.createCard(named: raw.isEmpty ? "New Card" : String(raw.prefix(40)), initialCategories: initial)
                lastCreated = card.id
                proposed.cardOrder.append(card.id)
                if let index = proposed.stacks.firstIndex(where: { $0.id == proposed.activeStackID }) { proposed.stacks[index].cardIDs.append(card.id) }
                proposed.cardCustomizations[card.id] = customizations[placeholder]
            }
            for card in cards where !newCardIDs.contains(card.id) {
                if let name = names[card.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name != card.name {
                    var renamed = card
                    renamed.name = String(name.prefix(40))
                    try renamed.validate()
                    try expenseService.renameCard(id: card.id, to: renamed.name)
                    if updatedSettings.card.id == card.id { updatedSettings.card = renamed }
                }
                if let customization = customizations[card.id] { proposed.cardCustomizations[card.id] = customization }
                if let selection = selections[card.id] {
                    for category in globalCategories {
                        var inactive = proposed.cardInactiveCategoryIDs[card.id] ?? []
                        if selection.contains(category.id) {
                            try expenseService.activateCategory(category, in: card.id)
                            inactive.removeAll { $0 == category.id }
                        } else {
                            try expenseService.deactivateCategory(category.id, in: card.id)
                            if !inactive.contains(category.id) { inactive.append(category.id) }
                        }
                        proposed.cardInactiveCategoryIDs[card.id] = inactive
                    }
                }
            }
            try requireState().saveSettings(updatedSettings)
            try requireState().saveWorkspacePreferences(proposed)
        }
        settings = updatedSettings
        publishPreferences(proposed); invalidateExpenseCaches()
        if let lastCreated { selectCard(lastCreated) }
        showToast("Cards saved")
    }

    func performUIAction(_ action: () throws -> Void) {
        do { try action() } catch { report(error) }
    }

    func customization(for cardID: UUID) -> CardCustomization {
        if let custom = workspacePreferences.cardCustomizations[cardID] {
            return custom
        }
        let colorIdx = cards.first { $0.id == cardID }?.colorIndex ?? 0
        return CardCustomization.defaultFor(colorIndex: colorIdx)
    }

    func updateCustomization(_ customization: CardCustomization, for cardID: UUID) {
        var proposed = workspacePreferences
        proposed.cardCustomizations[cardID] = customization
        do { try commitPresentationPreferences(proposed) } catch { report(error) }
    }

    func setCardHidden(id: UUID, isHidden: Bool) {
        var hidden = hiddenCardIDs
        if isHidden { hidden.insert(id) } else { hidden.remove(id) }
        var proposed = workspacePreferences
        proposed.visibleCardIDs = cards.map(\.id).filter { !hidden.contains($0) }
        do { try commitPresentationPreferences(proposed) } catch { report(error) }
    }

    func setCardAlwaysHidden(id: UUID, isHidden: Bool) {
        var proposed = workspacePreferences
        var hidden = Set(proposed.alwaysHiddenCardIDs)
        var ordinary = hiddenCardIDs
        if isHidden {
            hidden.insert(id); ordinary.insert(id)
            for index in proposed.stacks.indices { proposed.stacks[index].cardIDs.removeAll { $0 == id } }
        } else {
            hidden.remove(id); ordinary.remove(id)
            if let index = proposed.stacks.firstIndex(where: { $0.id == proposed.activeStackID }), !proposed.stacks[index].cardIDs.contains(id) { proposed.stacks[index].cardIDs.append(id) }
        }
        proposed.alwaysHiddenCardIDs = Array(hidden)
        proposed.visibleCardIDs = cards.map(\.id).filter { !ordinary.contains($0) }
        do {
            try commitPresentationPreferences(proposed)
            if isHidden, selectedCardID == id { selectedCardID = nil }
            showToast(isHidden ? "Card hidden" : "Card unhidden")
        } catch { report(error) }
    }

    func saveStackConfiguration(_ stacks: [Stack], activeStackID: UUID?, alwaysHiddenIDs: Set<UUID>) throws {
        var proposed = workspacePreferences
        proposed.stacks = stacks; proposed.activeStackID = activeStackID
        proposed.alwaysHiddenCardIDs = Array(alwaysHiddenIDs)
        proposed.visibleCardIDs = cards.map(\.id).filter { !alwaysHiddenIDs.contains($0) }
        proposed.filterScope = .activeStack
        try commitPresentationPreferences(proposed)
        if let selectedCardID, alwaysHiddenIDs.contains(selectedCardID) { self.selectedCardID = nil }
    }

    func toggleFilterScope() {
        cycleFilterOrStack()
    }

    func cycleFilterOrStack() {
        var proposed = workspacePreferences
        if filterScope == .allCards {
            if let first = stacks.first { proposed.activeStackID = first.id }
            proposed.filterScope = .activeStack
        } else {
            if stacks.count > 1, let currentID = activeStackID, let currentIndex = stacks.firstIndex(where: { $0.id == currentID }) {
                let nextIndex = currentIndex + 1
                if nextIndex < stacks.count {
                    proposed.activeStackID = stacks[nextIndex].id
                    proposed.filterScope = .activeStack
                } else {
                    proposed.filterScope = .allCards
                }
            } else {
                proposed.filterScope = .allCards
            }
        }
        do { try commitPresentationPreferences(proposed) } catch { report(error) }
    }

    func setActiveStack(id: UUID) {
        guard stacks.contains(where: { $0.id == id }) else { return }
        var proposed = workspacePreferences; proposed.activeStackID = id; proposed.filterScope = .activeStack
        do { try commitPresentationPreferences(proposed) } catch { report(error) }
    }

    @discardableResult
    func createStack(name: String, icon: String = "rectangle.stack", cardIDs: [UUID] = []) throws -> Stack {
        guard isPro else { throw PlanError.stacks }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "New Stack" : String(trimmed.prefix(40))
        let stack = Stack(id: UUID(), name: finalName, icon: icon, cardIDs: cardIDs)
        var proposed = workspacePreferences
        proposed.stacks.append(stack); proposed.activeStackID = stack.id; proposed.filterScope = .activeStack
        proposed.keepEachCardInOneStack(preferring: stack.id) // adding a card moves it here
        try commitPresentationPreferences(proposed)
        showToast("Stack '\(finalName)' created")
        return stack
    }

    func updateStack(_ stack: Stack) throws {
        guard let index = stacks.firstIndex(where: { $0.id == stack.id }) else { throw BackupError.invalid }
        var proposed = workspacePreferences; proposed.stacks[index] = stack
        proposed.keepEachCardInOneStack(preferring: stack.id)
        try commitPresentationPreferences(proposed)
    }

    func deleteStack(id: UUID) {
        guard stacks.count > 1 else { showToast("Cannot delete the only stack"); return }
        var proposed = workspacePreferences
        proposed.stacks.removeAll { $0.id == id }
        if proposed.activeStackID == id { proposed.activeStackID = proposed.stacks.first?.id }
        do { try commitPresentationPreferences(proposed); showToast("Stack deleted") }
        catch { report(error) }
    }

    func moveCardToFront(_ cardID: UUID) {
        var proposed = workspacePreferences
        if filterScope == .activeStack, let stackID = activeStackID, let idx = stacks.firstIndex(where: { $0.id == stackID }) {
            var cardIDs = stacks[idx].cardIDs.filter { $0 != cardID }
            cardIDs.insert(cardID, at: 0)
            proposed.stacks[idx].cardIDs = cardIDs
        } else {
            var currentOrder = orderedCards.map(\.id).filter { $0 != cardID }
            currentOrder.insert(cardID, at: 0)
            proposed.cardOrder = currentOrder
        }
        do { try commitPresentationPreferences(proposed); showToast("Moved to front") }
        catch { report(error) }
    }

    func reorderCardsInCurrentStack(fromOffsets: IndexSet, toOffset: Int) {
        if filterScope == .activeStack, let stackID = activeStackID, let idx = stacks.firstIndex(where: { $0.id == stackID }) {
            var cardIDs = stacks[idx].cardIDs
            cardIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)
            var proposed = workspacePreferences; proposed.stacks[idx].cardIDs = cardIDs
            do { try commitPresentationPreferences(proposed) } catch { report(error) }
        } else {
            reorderCards(fromOffsets: fromOffsets, toOffset: toOffset)
        }
    }

    func reorderCards(fromOffsets: IndexSet, toOffset: Int) {
        var currentOrder = orderedCards.map(\.id)
        currentOrder.move(fromOffsets: fromOffsets, toOffset: toOffset)
        var proposed = workspacePreferences; proposed.cardOrder = currentOrder
        do { try commitPresentationPreferences(proposed) } catch { report(error) }
    }

    func persistWorkspacePreferences() {
        guard startupError == nil else { return }
        workspacePreferences.keepEachCardInOneStack()
        workspacePreferences.visibleCardIDs = cards.map(\.id).filter { !hiddenCardIDs.contains($0) }
        workspacePreferences.alwaysHiddenCardIDs = Array(alwaysHiddenCardIDs)
        do {
            try requireState().saveWorkspacePreferences(workspacePreferences)
            let changedScope = durablePreferences.stacks != workspacePreferences.stacks ||
                durablePreferences.activeStackID != workspacePreferences.activeStackID ||
                durablePreferences.visibleCardIDs != workspacePreferences.visibleCardIDs ||
                durablePreferences.alwaysHiddenCardIDs != workspacePreferences.alwaysHiddenCardIDs ||
                durablePreferences.filterScopeRaw != workspacePreferences.filterScopeRaw
            durablePreferences = workspacePreferences
            if changedScope { memoizedActivities = nil; syncWidgetSnapshot() }
        } catch {
            publishPreferences(durablePreferences)
            report(error)
        }
    }

    @ObservationIgnored private var expensesCache: [UUID: [Expense]] = [:]
    @ObservationIgnored private var expenseByIDCache: [UUID: Expense]? = nil
    @ObservationIgnored private var spentCache: [UUID: Int64] = [:]
    @ObservationIgnored private var memoizedActivities: [Expense]? = nil
    @ObservationIgnored private var memoizedActivitiesKey: String = ""

    var billReminderStatus: String? { expenseService?.notifications.lastError }

    private func committedWorkspaceChanged() {
        if let refreshError = expenseService?.projectionRefreshError {
            expensesCache.removeAll(); spentCache.removeAll(); memoizedActivities = nil
            error = "Your change was saved, but the display could not refresh: \(refreshError)"
            do { try WidgetSnapshotStore.writeSnapshot(.unavailable("Open Anka to refresh")) }
            catch { BackendDiagnostics.widgetPublicationFailed() }
        } else { invalidateExpenseCaches() }
    }

    func invalidateExpenseCaches() {
        expensesCache.removeAll()
        expenseByIDCache = nil
        spentCache.removeAll()
        memoizedActivities = nil
        memoizedActivitiesKey = ""
        syncWidgetSnapshot()
    }

    /// Widgets add up in the reporting currency; a card budget in another currency is shown at today's cached rate.
    private var widgetBudget: BudgetVersion {
        var budget = activeBudget
        let code = activeCardCurrency
        guard code != reportingCurrency else { return budget }
        budget.overallLimit = approximate(budget.overallLimit, from: code, to: reportingCurrency) ?? budget.overallLimit
        budget.categoryLimits = budget.categoryLimits.map { .init(categoryID: $0.categoryID, limit: approximate($0.limit, from: code, to: reportingCurrency) ?? $0.limit) }
        return budget
    }

    func syncWidgetSnapshot() {
        guard startupError == nil, expenseService?.projectionRefreshError == nil else { return }
        guard let activeCard = cards.first(where: { $0.id == activeCardID }) ?? cards.first else { return }
        var stack = currentStack
        stack?.cardIDs.removeAll { alwaysHiddenCardIDs.contains($0) }
        let stackExp: [Expense] = {
            if let stack {
                return cards.filter { stack.cardIDs.contains($0.id) && !alwaysHiddenCardIDs.contains($0.id) }.flatMap { expenses(for: $0.id) }
            }
            return expenses
        }()
        WidgetSnapshotUpdater.update(
            activeCard: activeCard,
            activeStack: stack,
            allCards: cards,
            expenses: expenses,
            stackExpenses: stackExp,
            categories: categories,
            captureCategories: activeCategories(for: activeCardID),
            budget: widgetBudget,
            cycle: cycle,
            revision: expenseService?.committedRevision
        )
    }

    func expenses(for cardID: UUID) -> [Expense] {
        if cardID == activeCardID {
            return expenses
        }
        if let cached = expensesCache[cardID] {
            return cached
        }
        let result = (try? expenseService?.expenses(for: cardID)) ?? []
        expensesCache[cardID] = result
        return result
    }

    /// All-time total in the card's currency.
    func spent(for cardID: UUID) -> Int64 {
        if let cached = spentCache[cardID] {
            return cached
        }
        let card = cards.first { $0.id == cardID }
        let total = Money.sum(expenses(for: cardID).map { expense in card.map { cardAmount(expense, in: $0) } ?? expense.amount })
        spentCache[cardID] = total
        return total
    }

    /// Sum of the stack's cards' current monthly budgets, or the stack's cap. "Total until" budgets don't count.
    func stackBudgetLimit(_ stack: Stack) -> Int64? {
        let cards = stack.cardIDs.compactMap { id in cards.first { $0.id == id } }.filter { !alwaysHiddenCardIDs.contains($0.id) }
        let limits = cards.compactMap { card -> Int64? in
            guard let budgets = try? expenseService?.budgets(for: card.id),
                  let active = BudgetHistory.active(on: .now, budgets: budgets), active.totalUntilDay == nil else { return nil }
            return active.overallLimit
        }
        return stack.budgetLimit(cardLimits: limits)
    }

    // MARK: - Budget reports

    func budgetCardInput(_ cardID: UUID) -> BudgetCardInput? {
        guard let card = cards.first(where: { $0.id == cardID }), let budgets = try? expenseService?.budgets(for: cardID) else { return nil }
        return BudgetCardInput(card: card, budgets: budgets, expenses: expenses(for: cardID), categories: activeCategories(for: cardID),
                               currency: currency(of: card), amount: { [self] in cardAmount($0, in: card) })
    }

    /// The running (or goal / transition) period of a card's budget; a card with no budget history gets the settings fallback.
    func budgetPeriod(for cardID: UUID) -> BudgetPeriod {
        let budgets = (try? expenseService?.budgets(for: cardID)) ?? []
        if let period = BudgetHistory.period(containing: .now, budgets: budgets) { return period }
        let fallback = BudgetVersion.initial(overallLimit: settings.budget, startDay: settings.startDay)
        return BudgetPeriod(budget: fallback, cycle: Cycle.containing(.now, startDay: fallback.startDay))
    }

    func budgetStackInput(_ stackID: UUID) -> BudgetStackInput? {
        guard let stack = stacks.first(where: { $0.id == stackID }) else { return nil }
        let inputs = stack.cardIDs.filter { !alwaysHiddenCardIDs.contains($0) }.compactMap(budgetCardInput)
        return BudgetStackInput(stack: stack, cards: inputs, reportingCurrency: reportingCurrency,
                                convert: { [self] in approximate($0, from: $1, to: $2) })
    }

    func budgetStatus(_ subject: BudgetSubject) -> BudgetStatus? {
        switch subject {
        case .card(let id): budgetCardInput(id).flatMap { BudgetReport.card($0) }
        case .stack(let id): budgetStackInput(id).flatMap { BudgetReport.stack($0) }
        }
    }

    /// Running and past cycles, oldest first.
    func budgetCycles(_ subject: BudgetSubject, count: Int = 6) -> [BudgetCycleResult] {
        switch subject {
        case .card(let id): budgetCardInput(id).map { BudgetReport.cardHistory($0, count: count) } ?? []
        case .stack(let id): budgetStackInput(id).map { BudgetReport.stackHistory($0, count: count) } ?? []
        }
    }

    /// One row per card with a budget this cycle, in the reporting currency (a card in another currency: spending at each expense's own rate, its limit at today's rate, marked ≈).
    func budgetLinesAcrossCards() -> (lines: [BudgetLine], approximate: Bool) {
        var lines: [BudgetLine] = [], mixed = false
        for card in unhiddenCards {
            guard let status = budgetStatus(.card(card.id)) else { continue }
            var limit = status.limit, spent = status.spent
            if status.currency != reportingCurrency {
                mixed = true
                // Only the limit has no date, so only it converts at today's rate; spending is the sum of each expense's own
                // reporting amount (already converted at its day's rate), so the ≈ marks the limit alone.
                limit = approximate(limit, from: status.currency, to: reportingCurrency) ?? limit
                spent = Money.sum(expenses(for: card.id).filter { status.cycle.contains($0) }.map(\.amount))
            }
            lines.append(BudgetLine(id: card.id, name: card.name, limit: limit, spent: spent))
        }
        return (lines, mixed)
    }

    // MARK: - Currency

    var reportingCurrency: String { workspacePreferences.reportingCurrency }
    @ObservationIgnored var rates = ExchangeRates.shared
    /// Why the entry form has no rate yet, shown under the rate field.
    var rateError: String?
    /// Offered once after a card's first expense in another currency: (card, currency).
    var spendingCurrencySuggestion: (cardID: UUID, code: String)?

    /// A card's budget and totals currency.
    func currency(of card: Card) -> String { card.currency ?? reportingCurrency }
    func currency(ofCard id: UUID) -> String { cards.first { $0.id == id }.map(currency(of:)) ?? reportingCurrency }
    var activeCardCurrency: String { currency(ofCard: activeCardID) }
    /// The secondary "≈" line: the card's spending currency, else the reporting currency, if either differs.
    func secondaryCurrency(of card: Card) -> String? {
        let code = card.spendingCurrency ?? reportingCurrency
        return code == currency(of: card) ? nil : code
    }

    /// An expense's amount in the card's currency: the paid amount if paid in it, else converted from the reporting
    /// amount at that day's rate. Display only; never saved.
    func cardAmount(_ expense: Expense, in card: Card) -> Int64 {
        let code = currency(of: card)
        if code == reportingCurrency { return expense.amount }
        if expense.originalCurrency == code, let original = expense.originalAmount { return original }
        // ponytail: falls back to the reporting amount until the day's rate is cached (prefetchCardRates fills it).
        guard let rate = rates.cachedRate(from: reportingCurrency, to: code, on: expense.day) else { return expense.amount }
        return (try? Money.convert(expense.amount, rate: rate, to: code)) ?? expense.amount
    }

    /// Converts `amount` (in `from`) for display in `to` with the newest cached rate, if any.
    func approximate(_ amount: Int64, from: String, to: String) -> Int64? {
        guard let rate = rates.cachedRate(from: from, to: to, on: Day.string(.now)) else { return nil }
        return try? Money.convert(amount, rate: rate, to: to)
    }

    /// Fetches rates that card totals and "≈" lines need, then refreshes the views that use them.
    func prefetchCardRates() async {
        guard cards.contains(where: { currency(of: $0) != reportingCurrency || ($0.spendingCurrency.map { $0 != reportingCurrency } ?? false) })
        else { return } // nothing to fetch: no network request for single-currency users
        let today = Day.string(.now)
        var pairs = Set<String>()
        for card in cards {
            let code = currency(of: card)
            for other in [code, card.spendingCurrency ?? reportingCurrency] where other != reportingCurrency { pairs.insert(other) }
            if code != reportingCurrency, let first = expenses(for: card.id).map(\.day).min() {
                try? await rates.prefetch(from: reportingCurrency, to: code, start: first, end: today)
            }
        }
        for code in pairs {
            try? await rates.prefetch(from: reportingCurrency, to: code, start: today, end: today)
            try? await rates.prefetch(from: code, to: reportingCurrency, start: today, end: today)
        }
        invalidateExpenseCaches()
    }

    /// Fetches the draft's rate unless the user typed one.
    func refreshDraftRate() async {
        guard let code = draft.currency, draft.isForeign(reporting: reportingCurrency), draft.rateSource != .manual else { rateError = nil; return }
        let day = draft.civilDay
        do {
            let rate = try await rates.rate(from: code, to: reportingCurrency, on: day)
            guard draft.currency == code, draft.civilDay == day, draft.rateSource != .manual else { return }
            draft.rate = "\(rate)"; draft.rateSource = .fetched; rateError = nil
        } catch {
            rateError = error.localizedDescription
        }
    }

    /// Sets a card's budget currency and spending currency. Changing the budget currency converts its budgets at today's rate.
    func setCardCurrencies(budget: String?, spending: String?, for cardID: UUID) async throws {
        // A card in another currency than the workspace's, or spending in one, is Pro.
        if !isPro, (budget.map { $0 != reportingCurrency } ?? false) || (spending.map { $0 != (budget ?? reportingCurrency) } ?? false) {
            throw PlanError.foreignCurrency
        }
        guard let expenseService else { throw EntryError.corruptStore }
        guard var card = cards.first(where: { $0.id == cardID }) else { throw BackupError.invalid }
        let budget = budget == reportingCurrency ? nil : budget
        let spending = spending == (budget ?? reportingCurrency) ? nil : spending
        let old = currency(of: card), new = budget ?? reportingCurrency
        var converted: [BudgetVersion] = []
        if old != new {
            let rate = try await rates.rate(from: old, to: new, on: Day.string(.now))
            converted = try expenseService.budgets(for: cardID).map { version in
                var value = version
                value.overallLimit = try Money.convert(version.overallLimit, rate: rate, to: new)
                value.categoryLimits = try version.categoryLimits.map { .init(categoryID: $0.categoryID, limit: try Money.convert($0.limit, rate: rate, to: new)) }
                return value
            }
        }
        card.currency = budget; card.spendingCurrency = spending
        try performWorkspaceCommand {
            try expenseService.updateCard(card)
            for version in converted { try expenseService.save(version, in: cardID) }
        }
        if settings.card.id == cardID {
            var proposed = settings; proposed.card = card
            try requireState().saveSettings(proposed); settings = proposed
        }
        invalidateExpenseCaches()
        await prefetchCardRates()
    }

    var spendingCurrencyQuestion: String {
        guard let suggestion = spendingCurrencySuggestion else { return "" }
        let name = cards.first { $0.id == suggestion.cardID }?.name ?? "this card"
        return "Use \(suggestion.code) as \(name)'s spending currency?"
    }

    func acceptSpendingCurrencySuggestion() async {
        guard let suggestion = spendingCurrencySuggestion, let card = cards.first(where: { $0.id == suggestion.cardID }) else { return }
        spendingCurrencySuggestion = nil
        do { try await setCardCurrencies(budget: card.currency, spending: suggestion.code, for: card.id) }
        catch { report(error) }
    }

    /// Suggest a spending currency after the first expense on a card paid in a currency the card doesn't use yet.
    func suggestSpendingCurrency(after expense: Expense) {
        guard let code = expense.originalCurrency, let id = expense.cardID, let card = cards.first(where: { $0.id == id }),
              card.spendingCurrency == nil, currency(of: card) != code,
              expenses(for: id).filter({ $0.originalCurrency == code }).count == 1 else { return }
        spendingCurrencySuggestion = (id, code)
    }

    /// Re-converts every expense from what was paid, at its own day's rate; a manual rate is kept by chaining it through
    /// the old reporting currency. Budgets, bills and stack caps in the reporting currency convert at today's rate.
    /// Runs as one workspace command, so a safety backup is written first and a failure changes nothing.
    func changeReportingCurrency(to new: String) async throws {
        guard let expenseService else { throw EntryError.corruptStore }
        let old = reportingCurrency
        guard new != old, Money.isCurrencyCode(new) else { return }
        let today = Day.string(.now)
        var byCard: [UUID: [Expense]] = [:]
        for card in cards { byCard[card.id] = try expenseService.expenses(for: card.id) }
        let all = byCard.values.flatMap { $0 }
        // One request per currency pair, covering the whole history.
        var spans: [String: (String, String)] = [:]
        for expense in all {
            for source in Set([expense.originalCurrency ?? old, old]) where source != new {
                let span = spans[source] ?? (expense.day, expense.day)
                spans[source] = (min(span.0, expense.day), max(span.1, expense.day))
            }
        }
        spans[old] = (min(spans[old]?.0 ?? today, today), today)
        for (source, span) in spans { try await rates.prefetch(from: source, to: new, start: span.0, end: span.1) }
        func rate(_ from: String, on day: String) throws -> Decimal {
            guard let value = rates.cachedRate(from: from, to: new, on: day) else { throw RateError.unavailable }
            return value
        }

        var updated: [UUID: [Expense]] = [:]
        for (cardID, expenses) in byCard {
            updated[cardID] = try expenses.map { expense in
                var value = expense
                let source = expense.originalCurrency ?? old
                let paid = expense.originalAmount ?? expense.amount
                if source == new {
                    value.amount = paid
                    value.originalAmount = nil; value.originalCurrency = nil; value.rate = nil; value.rateSource = nil
                } else {
                    let manual = expense.rateSource == .manual ? expense.rate.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) } : nil
                    let newRate = try manual.map { $0 * (try rate(old, on: expense.day)) } ?? rate(source, on: expense.day)
                    value.amount = try Money.convert(paid, rate: newRate, to: new)
                    value.originalAmount = paid; value.originalCurrency = source
                    value.rate = "\(newRate)"; value.rateSource = manual == nil ? .fetched : .manual
                }
                value.splits = try Self.rescale(expense.splits, from: expense.amount, to: value.amount)
                return value
            }
        }
        let todayRate = try rate(old, on: today)
        var budgets: [UUID: [BudgetVersion]] = [:]
        var bills: [UUID: [Bill]] = [:]
        for card in cards where card.currency == nil || card.currency == old {
            budgets[card.id] = try expenseService.budgets(for: card.id).map { version in
                var value = version
                value.overallLimit = try Money.convert(version.overallLimit, rate: todayRate, to: new)
                value.categoryLimits = try version.categoryLimits.map { .init(categoryID: $0.categoryID, limit: try Money.convert($0.limit, rate: todayRate, to: new)) }
                return value
            }
        }
        for card in cards {
            bills[card.id] = try expenseService.bills(for: card.id).map { bill in
                var value = bill; value.amount = try Money.convert(bill.amount, rate: todayRate, to: new); return value
            }
        }
        var proposed = workspacePreferences
        proposed.reportingCurrency = new
        proposed.stacks = try proposed.stacks.map { stack in
            var value = stack; value.capLimit = try stack.capLimit.map { try Money.convert($0, rate: todayRate, to: new) }; return value
        }
        // A card that named the new currency explicitly now just follows the reporting currency.
        let cards = cards.map { card -> Card in
            var value = card
            if value.currency == new { value.currency = nil }
            if value.spendingCurrency == new { value.spendingCurrency = nil }
            return value
        }
        try performWorkspaceCommand {
            for card in cards { try expenseService.updateCard(card) }
            for (cardID, values) in updated { try expenseService.saveExpenses(values, in: cardID) }
            for (cardID, values) in budgets { for version in values { try expenseService.save(version, in: cardID) } }
            for (cardID, values) in bills { for bill in values { try expenseService.saveBill(bill, in: cardID) } }
            try requireState().saveWorkspacePreferences(proposed)
        }
        publishPreferences(proposed)
        var proposedSettings = settings
        proposedSettings.budget = activeBudget.overallLimit
        if let card = cards.first(where: { $0.id == settings.card.id }) { proposedSettings.card = card }
        try requireState().saveSettings(proposedSettings); settings = proposedSettings
        invalidateExpenseCaches()
        await prefetchCardRates()
    }

    /// Keeps each part's share when a total changes; rounding goes to the largest part.
    static func rescale(_ splits: [Split], from oldTotal: Int64, to newTotal: Int64) throws -> [Split] {
        guard splits.count > 1 else { return splits.map { .init(categoryID: $0.categoryID, amount: newTotal) } }
        var parts = try splits.map {
            Split(categoryID: $0.categoryID, amount: try Money.checkedScale(newTotal, numerator: Int(truncatingIfNeeded: $0.amount), denominator: Int(truncatingIfNeeded: max(1, oldTotal))))
        }
        let difference = newTotal - Money.sum(parts.map(\.amount))
        if let largest = parts.indices.max(by: { parts[$0].amount < parts[$1].amount }) { parts[largest].amount += difference }
        guard parts.allSatisfy({ $0.amount > 0 }) else { throw EntryError.splitMismatch }
        return parts
    }

    // MARK: - Paid with and the Add Expense form

    var paymentMethods: [PaymentMethod] { workspacePreferences.paymentMethods }
    func paymentMethod(_ id: UUID?) -> PaymentMethod? { id.flatMap { id in paymentMethods.first { $0.id == id } } }

    /// Amount, Card and Category are always shown; the rest follow the user's form settings.
    func isEntryFieldShown(_ field: EntryFormField) -> Bool { !workspacePreferences.hiddenEntryFields.contains(field) }

    /// The saved order, with any missing line appended in its default place, so a stale or partial list never hides a row.
    var entryRowOrder: [EntryFormRow] {
        var seen = Set<EntryFormRow>()
        return (workspacePreferences.entryRowOrder + EntryFormRow.allCases).filter { seen.insert($0).inserted }
    }

    func moveEntryRows(from source: IndexSet, to destination: Int) {
        var order = entryRowOrder
        order.move(fromOffsets: source, toOffset: destination)
        var proposed = workspacePreferences
        proposed.entryRowOrder = order
        do { try commitPresentationPreferences(proposed) } catch { report(error) }
    }

    func setEntryField(_ field: EntryFormField, shown: Bool) {
        var proposed = workspacePreferences
        proposed.hiddenEntryFields.removeAll { $0 == field }
        if !shown { proposed.hiddenEntryFields.append(field) }
        do { try commitPresentationPreferences(proposed) } catch { report(error) }
    }

    @discardableResult
    func savePaymentMethod(_ method: PaymentMethod) throws -> PaymentMethod {
        var method = method
        method.name = method.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !method.name.isEmpty, method.name.count <= 40 else { throw PaymentMethodError.invalidName }
        guard !paymentMethods.contains(where: { $0.id != method.id && $0.name.caseInsensitiveCompare(method.name) == .orderedSame }) else {
            throw PaymentMethodError.duplicateName
        }
        var proposed = workspacePreferences
        if let index = proposed.paymentMethods.firstIndex(where: { $0.id == method.id }) { proposed.paymentMethods[index] = method }
        else { proposed.paymentMethods.append(method) }
        try commitPresentationPreferences(proposed)
        return method
    }

    /// Like categories, a label in use can't be deleted. Card defaults that point at it are cleared.
    func deletePaymentMethod(id: UUID) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        let used = expenseService.expenseCount(paidWith: id)
        guard used == 0 else { throw PaymentMethodError.inUse(used) }
        for var card in cards where card.defaultPaidWithID == id {
            card.defaultPaidWithID = nil
            try expenseService.updateCard(card)
        }
        var proposed = workspacePreferences
        proposed.paymentMethods.removeAll { $0.id == id }
        try commitPresentationPreferences(proposed)
        if draft.paidWithID == id { draft.paidWithID = nil }
    }

    func setDefaultPaidWith(_ id: UUID?, for cardID: UUID) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        guard var card = cards.first(where: { $0.id == cardID }) else { throw BackupError.invalid }
        guard id == nil || paymentMethod(id) != nil else { throw BackupError.invalid }
        card.defaultPaidWithID = id
        try expenseService.updateCard(card)
        if settings.card.id == cardID {
            var proposed = settings; proposed.card = card
            try requireState().saveSettings(proposed); settings = proposed
        }
        invalidateExpenseCaches()
    }

    /// A new expense starts with its card's default Paid with and spending currency.
    func prefillDraftDefaults() {
        guard !draft.editing else { return }
        let cardID = draft.cardID ?? selectedCardID ?? activeCardID
        guard let card = cards.first(where: { $0.id == cardID }) else { return }
        if draft.paidWithID == nil { draft.paidWithID = card.defaultPaidWithID }
        if draft.currency == nil, !draft.hasContent {
            let code = card.spendingCurrency ?? card.currency
            if let code, code != reportingCurrency { draft.currency = code; draft.rate = ""; draft.rateSource = nil }
        }
    }

    /// Cards a scope covers; stacks keep their own card order.
    func cards(in scope: AnalyticsFilterScope) -> [Card] {
        switch scope {
        case .card(let id, _): return cards.filter { $0.id == id }
        case .stack(let id, _):
            let ids = stacks.first(where: { $0.id == id })?.cardIDs ?? []
            return ids.compactMap { id in cards.first { $0.id == id } }.filter { !alwaysHiddenCardIDs.contains($0.id) }
        case .allCards: return unhiddenCards
        }
    }

    /// Categories a new expense on this card may use: not archived, not deactivated for the card.
    func activeCategories(in cardID: UUID) throws -> [ExpenseCategory] {
        guard let expenseService else { throw EntryError.corruptStore }
        let inactive = workspacePreferences.cardInactiveCategoryIDs[cardID] ?? []
        return try expenseService.categories(for: cardID).filter { !settings.archivedCategoryIDs.contains($0.id) && !inactive.contains($0.id) }
    }

    func reportingData(for scope: AnalyticsFilterScope) -> AnalyticsReportingData {
        let selected = cards(in: scope)
        var data = AnalyticsReportingData()
        data.cards = selected
        do {
            guard let expenseService else { throw EntryError.corruptStore }
            var seen = Set<UUID>()
            for card in selected {
                let values = try expenseService.expenses(for: card.id)
                data.expensesByCard[card.id] = values
                data.expenses.append(contentsOf: values)
                data.categories += try expenseService.categories(for: card.id).filter { seen.insert($0.id).inserted }
                data.bills += try expenseService.bills(for: card.id)
                data.billOccurrences += try expenseService.billOccurrences(for: card.id)
            }
            if case .card(let id, _) = scope { data.budgets = try expenseService.budgets(for: id) }
            if case .stack(let id, _) = scope, let stack = stacks.first(where: { $0.id == id }), let limit = stackBudgetLimit(stack) {
                // A stack budget runs on the calendar month (or its cap's start day) and has no category limits.
                data.budgets = [BudgetVersion(id: stack.id, effectiveDay: "2000-01-01", overallLimit: limit, startDay: stack.capStartDay ?? 1)]
            }
        } catch { data.errorMessage = error.localizedDescription }
        return data
    }

    func allExpenses() -> [Expense] {
        var result: [Expense] = []
        for card in cards {
            result.append(contentsOf: expenses(for: card.id))
        }
        return result
    }

    func expense(id: UUID) -> Expense? {
        if expenseByIDCache == nil {
            expenseByIDCache = Dictionary(allExpenses().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        return expenseByIDCache?[id]
    }

    func allExpensesByCard() -> [UUID: [Expense]] {
        var map: [UUID: [Expense]] = [:]
        for card in cards {
            map[card.id] = expenses(for: card.id)
        }
        return map
    }

    func activities(selectedCardID: UUID?, allCards: Bool) -> [Expense] {
        if let selectedCardID {
            return expenses(for: selectedCardID)
        }
        let key = "\(allCards)-\(filterScope.rawValue)-\(activeStackID?.uuidString ?? "nil")-\(unhiddenCards.count)-\(homeDeckCards.count)"
        if memoizedActivitiesKey == key, let cached = memoizedActivities {
            return cached
        }

        var all: [Expense] = []
        let targetCards = allCards ? unhiddenCards : homeDeckCards
        for b in targetCards {
            all.append(contentsOf: expenses(for: b.id))
        }
        let sorted = all.sorted { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
        memoizedActivities = sorted
        memoizedActivitiesKey = key
        return sorted
    }

    func startEmptyRealCard(named name: String) throws {
        guard let backups else { throw BackupError.unsupported }
        let settings = try recoveryCommand { try backups.startEmptyRealCard(named: name, currentDraft: draft, settings: settings) }
        self.settings = settings
        draft = ExpenseDraft(); draft.cardID = settings.card.id
        undoExpense = nil; pendingEntry = nil
        invalidateExpenseCaches()
        showToast("Your card is ready")
    }
    func renameRealCard(to name: String) throws {
        guard let backups else { throw BackupError.unsupported }
        try recoveryCommand { settings = try backups.renameRealCard(to: name, currentDraft: draft, settings: settings) }
        invalidateExpenseCaches()
        showToast("Card renamed")
    }

    func clearActiveCardExpenses() throws {
        guard let backups else { throw BackupError.unsupported }
        let targetID = selectedCardID ?? activeCardID
        try recoveryCommand { try backups.clearExpenses(in: targetID, currentDraft: draft, settings: settings) }
        draft = ExpenseDraft(); draft.cardID = activeCardID
        originalDraft = nil
        undoExpense = nil; pendingEntry = nil
        try reload()
        showToast("Expenses cleared")
    }

    func clearAllTransactions() throws {
        guard let backups else { throw BackupError.unsupported }
        try recoveryCommand { try backups.clearExpenses(in: nil, currentDraft: draft, settings: settings) }
        chat.clear()
        draft = ExpenseDraft(); draft.cardID = activeCardID
        originalDraft = nil
        undoExpense = nil; pendingEntry = nil
        try reload()
        showToast("All expenses cleared")
    }

    func resetAllData(cardName: String) throws {
        guard let backups else { throw BackupError.unsupported }
        let newSettings = try recoveryCommand { try backups.resetAllData(cardName: cardName, currentDraft: draft, settings: settings) }
        chat.clear()
        self.settings = newSettings
        publishPreferences(try requireState().loadWorkspacePreferences())
        expenseService?.configure(categoryRules: newSettings.categoryRules, archivedCategoryIDs: newSettings.archivedCategoryIDs)
        self.draft = ExpenseDraft(); self.draft.cardID = newSettings.card.id
        self.originalDraft = nil
        self.undoExpense = nil; pendingEntry = nil
        self.hiddenCardIDs = []
        self.alwaysHiddenCardIDs = []
        self.customizerTarget = nil
        self.selectedCardID = newSettings.card.id
        try reload()
        showToast("App reset to clean state")
    }

    private func recoveryCommand<T>(_ command: () throws -> T) throws -> T {
        do { return try command() }
        catch {
            if backups?.requiresRecovery == true || expenseService?.isBlocked == true { startupError = BackupError.recoveryRequired.localizedDescription }
            throw error
        }
    }

    func showToast(_ text: String) { toast = text; toastID = UUID() }

    func importExpenses(_ batch: [Expense], to cardID: UUID) throws {
        try expenseService?.saveExpenses(batch, in: cardID)
        invalidateExpenseCaches()
        showToast("Imported \(batch.count) \(batch.count == 1 ? "expense" : "expenses")")
    }

    func csvExportText(
        for cardID: UUID?,
        dateRange: CSVDateRangeScope,
        customStartDate: Date = .now,
        customEndDate: Date = .now
    ) -> String {
        let calendar = Day.calendar
        var targetExpenses: [Expense]
        if let cardID {
            targetExpenses = expenses(for: cardID)
        } else {
            var all: [Expense] = []
            for b in cards {
                all.append(contentsOf: expenses(for: b.id))
            }
            targetExpenses = all
        }

        let now = Date.now
        switch dateRange {
        case .allTime:
            break
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let startDay = Day.string(start)
            let endDay = Day.string(calendar.date(byAdding: .month, value: 1, to: start) ?? now)
            targetExpenses = targetExpenses.filter { $0.day >= startDay && $0.day < endDay }
        case .lastMonth:
            guard let prevMonth = calendar.date(byAdding: .month, value: -1, to: now) else { break }
            let comps = calendar.dateComponents([.year, .month], from: prevMonth)
            guard let startOfLast = calendar.date(from: comps),
                  let startOfThis = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) else { break }
            let startDay = Day.string(startOfLast)
            let endDay = Day.string(startOfThis)
            targetExpenses = targetExpenses.filter { $0.day >= startDay && $0.day < endDay }
        case .custom:
            let startDay = Day.string(min(customStartDate, customEndDate))
            let endDay = Day.string(max(customStartDate, customEndDate))
            targetExpenses = targetExpenses.filter { $0.day >= startDay && $0.day <= endDay }
        }

        targetExpenses.sort { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
        let rawCategories: [ExpenseCategory]
        if let cardID {
            rawCategories = (try? expenseService?.categories(for: cardID)) ?? categories
        } else {
            rawCategories = cards.flatMap { (try? expenseService?.categories(for: $0.id)) ?? [] }
        }
        var seenCategoryIDs = Set<UUID>()
        let allCats = rawCategories.filter { seenCategoryIDs.insert($0.id).inserted }
        return CSVExportGenerator.generate(expenses: targetExpenses, categories: allCats, cards: cards, paymentMethods: paymentMethods)
    }

    @discardableResult
    func saveDraft() -> Bool {
        do {
            var expense = try draft.expense()
            let targetID = draft.cardID ?? selectedCardID ?? activeCardID
            expense.cardID = targetID
            try save(expense)
            let editing = draft.editing
            originalDraft = nil
            var cleared = ExpenseDraft(); cleared.cardID = targetID
            draft = cleared
            // The expense is already durable. Cleanup failure must never invite a second save.
            do { try requireState().saveDraft(cleared, for: targetID) }
            catch { self.error = "Expense saved, but its draft could not be cleared: \(error.localizedDescription)" }
            showEntry = false
            undoExpense = nil
            saveFeedback += 1
            if !editing { recordInSpendingSession(expense) }
            suggestSpendingCurrency(after: expense)
            showToast(editing ? "Expense updated" : "Expense added")
            return true
        } catch {
            report(error)
            return false
        }
    }
    func save(_ expense: Expense) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        var expense = expense
        // A label deleted while this draft was open is dropped rather than saved as a dangling reference.
        if let id = expense.paidWithID, paymentMethod(id) == nil { expense.paidWithID = nil }
        try expenseService.save(expense)
        invalidateExpenseCaches()
    }
    func delete(_ expense: Expense) {
        do {
            guard let expenseService else { throw EntryError.corruptStore }
            let owner = expense.cardID ?? activeCardID
            let linked = try expenseService.billOccurrences(for: owner).filter { $0.expenseID == expense.id }
            try expenseService.delete(expense.id, in: owner)
            undoOccurrences = linked
            invalidateExpenseCaches()
            undoExpense = expense; showToast("Expense deleted")
        } catch { report(error) }
    }
    func undoDelete() {
        guard let undoExpense else { return }
        restore(undoExpense, occurrences: undoOccurrences)
    }
    /// Restores a deleted expense with the bill occurrences it was linked to (macOS keeps several of these on its undo stack).
    func restore(_ expense: Expense, occurrences: [BillOccurrence]) {
        do {
            guard let expenseService else { throw EntryError.corruptStore }
            try expenseService.restoreExpense(expense, occurrences: occurrences, in: expense.cardID ?? activeCardID)
            if undoExpense?.id == expense.id { undoExpense = nil; undoOccurrences = [] }
            invalidateExpenseCaches(); showToast("Expense restored")
        }
        catch { report(error) }
    }
    func saveBill(_ bill: Bill, in cardID: UUID? = nil) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.saveBill(bill, in: cardID)
        invalidateExpenseCaches()
        showToast("Bill saved")
    }
    func deleteBill(_ id: UUID, in cardID: UUID? = nil) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.deleteBill(id, in: cardID)
        invalidateExpenseCaches()
        showToast("Bill deleted")
    }
    @discardableResult
    func confirmBillOccurrence(
        _ occurrenceID: UUID,
        customDate: Date? = nil,
        customAmount: Int64? = nil,
        customNote: String? = nil,
        in cardID: UUID? = nil
    ) throws -> Expense {
        guard let expenseService else { throw EntryError.corruptStore }
        let expense = try expenseService.confirmBillOccurrence(
            occurrenceID,
            customDate: customDate,
            customAmount: customAmount,
            customNote: customNote,
            in: cardID
        )
        invalidateExpenseCaches()
        showToast("Bill added")
        return expense
    }
    func skipBillOccurrence(_ occurrenceID: UUID, in cardID: UUID? = nil) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.skipBillOccurrence(occurrenceID, in: cardID)
        showToast("Bill skipped")
    }
    func reconcileBills(asOf date: Date = .now, in cardID: UUID? = nil) {
        guard let expenseService else { return }
        do { try expenseService.reconcileBills(asOf: date, in: cardID) }
        catch { report(error) }
        invalidateExpenseCaches()
    }
    /// Chat Save: the same write and Live Activity update as the keypad, without the entry sheet.
    func saveFromChat(_ expense: Expense) throws {
        try save(expense)
        recordInSpendingSession(expense)
    }

    private func recordInSpendingSession(_ expense: Expense) {
        guard SpendingSessionManager.shared.isSessionActive, let cardID = expense.cardID else { return }
        let cat = activeCategories(for: cardID).first(where: { $0.id == expense.splits.first?.categoryID })
        SpendingSessionManager.shared.recordExpense(amount: expense.amount, note: expense.note, categorySymbol: cat?.symbol, cardID: cardID)
    }

    /// Opens an unsaved chat proposal in the entry sheet so the user can adjust it before saving.
    func openInEntry(_ expense: Expense) {
        showChat = false
        Task {
            // Let the chat cover finish dismissing before presenting the sheet.
            try? await Task.sleep(for: .milliseconds(450))
            // ponytail: an unfinished draft takes the repeat path (dated today) after its discard prompt.
            if draftNeedsConfirmation { pendingRepeat = true; pendingEntry = expense; return }
            draft = ExpenseDraft(expense: expense); draft.editing = false
            draft.cardID = expense.cardID ?? activeCardID
            showEntry = true
        }
    }

    func repeatExpense(_ expense: Expense) {
        if draftNeedsConfirmation { pendingRepeat = true; pendingEntry = expense; return }
        draft = ExpenseDraft(expense: expense); draft.id = UUID(); draft.editing = false
        draft.createdAt = .now; draft.date = .now; draft.source = "repeat"
        draft.cardID = expense.cardID ?? activeCardID
        showEntry = true
    }
    func saveCategory(_ category: ExpenseCategory) throws {
        let validated = try category.validated(against: categories)
        try saveGlobalCategory(GlobalCategory(category: validated, defaultActiveForNewCards: true), activeCardIDs: activeCardIDs(for: validated.id).union([activeCardID]))
    }

    func isCategoryActive(_ categoryID: UUID, on cardID: UUID) -> Bool {
        if let inactive = workspacePreferences.cardInactiveCategoryIDs[cardID], inactive.contains(categoryID) {
            return false
        }
        let cardCategories = (try? expenseService?.categories(for: cardID)) ?? []
        return cardCategories.contains(where: { $0.id == categoryID })
    }

    func activeCardIDs(for categoryID: UUID) -> Set<UUID> {
        Set(cards.map(\.id).filter { isCategoryActive(categoryID, on: $0) })
    }

    func activeCategoryIDs(for cardID: UUID) -> Set<UUID> {
        let inactive = Set(workspacePreferences.cardInactiveCategoryIDs[cardID] ?? [])
        let cardCategories = (try? expenseService?.categories(for: cardID)) ?? []
        return Set(cardCategories.map(\.id).filter { !inactive.contains($0) })
    }

    func activeCategories(for cardID: UUID) -> [ExpenseCategory] {
        let inactive = Set(workspacePreferences.cardInactiveCategoryIDs[cardID] ?? [])
        let cardCategories = (try? expenseService?.categories(for: cardID)) ?? []
        return cardCategories.filter { !inactive.contains($0.id) && !settings.archivedCategoryIDs.contains($0.id) }
    }

    func setCategory(_ categoryID: UUID, active: Bool, for cardID: UUID) throws {
        guard let expenseService, let global = globalCategories.first(where: { $0.id == categoryID }) else { throw EntryError.missingCategory }
        var proposed = workspacePreferences
        var inactive = proposed.cardInactiveCategoryIDs[cardID] ?? []
        if active { inactive.removeAll { $0 == categoryID } }
        else if !inactive.contains(categoryID) { inactive.append(categoryID) }
        proposed.cardInactiveCategoryIDs[cardID] = inactive
        try performWorkspaceCommand {
            if active { try expenseService.activateCategory(global, in: cardID) }
            else { try expenseService.deactivateCategory(categoryID, in: cardID) }
            try requireState().saveWorkspacePreferences(proposed)
        }
        publishPreferences(proposed); invalidateExpenseCaches()
    }

    func saveGlobalCategory(_ category: GlobalCategory, activeCardIDs: Set<UUID>) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        let validated = try category.validated(against: globalCategories)
        var proposed = workspacePreferences
        proposed.globalCategories.removeAll { $0.id == validated.id }
        proposed.globalCategories.append(validated)
        try performWorkspaceCommand {
            try expenseService.updateGlobalCategoryMetadata(id: validated.id, name: validated.name, symbol: validated.symbol)
            for card in cards {
                var inactive = proposed.cardInactiveCategoryIDs[card.id] ?? []
                if activeCardIDs.contains(card.id) {
                    try expenseService.activateCategory(validated, in: card.id)
                    inactive.removeAll { $0 == validated.id }
                } else {
                    try expenseService.deactivateCategory(validated.id, in: card.id)
                    if !inactive.contains(validated.id) { inactive.append(validated.id) }
                }
                proposed.cardInactiveCategoryIDs[card.id] = inactive
            }
            try requireState().saveWorkspacePreferences(proposed)
        }
        publishPreferences(proposed); invalidateExpenseCaches()
    }

    func deleteGlobalCategory(_ category: GlobalCategory) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        guard undoExpense?.splits.contains(where: { $0.categoryID == category.id }) != true,
              !settings.categoryRules.contains(where: { $0.categoryID == category.id }) else { throw CategoryError.inUse }
        for card in cards {
            let savedDraft = card.id == draft.cardID ? draft : try requireState().loadDraft(for: card.id)
            guard savedDraft.categoryID != category.id, !savedDraft.splitParts.contains(where: { $0.categoryID == category.id }),
                  !(try expenseService.expenses(for: card.id)).contains(where: { $0.splits.contains(where: { $0.categoryID == category.id }) }),
                  !(try expenseService.bills(for: card.id)).contains(where: { $0.categoryID == category.id }),
                  !(try expenseService.budgets(for: card.id)).contains(where: { $0.categoryLimits.contains(where: { $0.categoryID == category.id }) }) else { throw CategoryError.inUse }
        }
        var proposed = workspacePreferences
        proposed.globalCategories.removeAll { $0.id == category.id }
        for card in cards { proposed.cardInactiveCategoryIDs[card.id]?.removeAll { $0 == category.id } }
        try performWorkspaceCommand {
            for card in cards { try expenseService.deactivateCategory(category.id, in: card.id) }
            try requireState().saveWorkspacePreferences(proposed)
        }
        publishPreferences(proposed); invalidateExpenseCaches()
    }

    func isArchived(_ category: ExpenseCategory) -> Bool { settings.archivedCategoryIDs.contains(category.id) }
    func archiveCategory(_ category: ExpenseCategory) throws {
        guard draft.categoryID != category.id, !draft.splitParts.contains(where: { $0.categoryID == category.id }),
              !settings.categoryRules.contains(where: { $0.categoryID == category.id }) else { throw CategoryError.inUse }
        var proposed = settings; proposed.archivedCategoryIDs.insert(category.id)
        try saveSettings(proposed)
    }
    func restoreCategory(_ category: ExpenseCategory) throws {
        var proposed = settings; proposed.archivedCategoryIDs.remove(category.id)
        try saveSettings(proposed)
    }
    func saveCategoryRule(_ rule: CategoryRule) throws {
        let rule = try rule.validated(against: categories, archivedIDs: settings.archivedCategoryIDs)
        guard !settings.categoryRules.contains(where: { $0.id != rule.id && $0.keyword == rule.keyword }) else { throw CategoryError.duplicateRule }
        var proposed = settings
        proposed.categoryRules.removeAll { $0.id == rule.id }
        proposed.categoryRules.append(rule)
        try saveSettings(proposed)
    }
    func deleteCategoryRule(_ rule: CategoryRule) throws {
        var proposed = settings; proposed.categoryRules.removeAll { $0.id == rule.id }
        try saveSettings(proposed)
    }
    func beginSplitting() {
        guard draft.splitParts.isEmpty else { return }
        guard let categoryID = draft.categoryID ?? activeCategories.first?.id else { error = EntryError.missingCategory.localizedDescription; return }
        draft.categoryID = categoryID
        let value = try? draft.resolvedAmount()
        draft.splitParts = [.init(categoryID: categoryID, amount: value.map(Money.exactDigits) ?? draft.amount, preservedAmount: value)]
    }
    func addSplitPart() {
        beginSplitting()
        let used = Set(draft.splitParts.map(\.categoryID))
        guard let category = activeCategories.first(where: { !used.contains($0.id) }) else {
            error = "Create another category before adding a further split."
            return
        }
        draft.splitParts.append(.init(categoryID: category.id, amount: ""))
    }
    func stopSplitting() {
        categoryIDFromSplit()
        draft.splitParts = []
    }
    private func categoryIDFromSplit() {
        if let categoryID = draft.splitParts.first?.categoryID { draft.categoryID = categoryID }
    }
    func deleteCategory(_ category: ExpenseCategory) throws {
        guard let global = globalCategories.first(where: { $0.id == category.id }) else { throw EntryError.missingCategory }
        try deleteGlobalCategory(global)
    }

    func restoreBackup(_ backup: CardBackup) throws {
        try restoreWorkspaceBackup(WorkspaceBackup(singleCard: backup))
    }

    func restoreWorkspaceBackup(_ source: WorkspaceBackup) throws {
        let backup = try source.normalized()
        guard let backups else { throw BackupError.unsupported }
        do {
            try backups.restoreWorkspace(backup, currentDraft: draft, settings: settings)
            chat.clear()
            let restoredCardID = expenseService?.activeCardID ?? backup.cards[0].card.id
            if let active = backup.cards.first(where: { $0.card.id == restoredCardID }) {
                draft = active.draft ?? ExpenseDraft()
            }
            draft.cardID = restoredCardID
            selectedCardID = restoredCardID
            settings = backup.settings
            appLock.applyPersistedConfiguration(settings.appLockTimeout, requireAuthentication: true)
            publishPreferences(backup.preferences)
            workspacePreferences = backup.preferences
            hiddenCardIDs = backup.preferences.visibleCardIDs.isEmpty
                ? []
                : Set(cards.map(\.id).filter { !backup.preferences.visibleCardIDs.contains($0) })
            expenseService?.configure(categoryRules: settings.categoryRules, archivedCategoryIDs: settings.archivedCategoryIDs)
            undoExpense = nil; pendingEntry = nil; toast = nil
            invalidateExpenseCaches()
        } catch {
            if backups.requiresRecovery { startupError = error.localizedDescription }
            throw error
        }
    }

    /// `totalUntil` makes a "Total until" budget (a goal): one amount from the current period's start through that day.
    func saveBudget(overallLimit: Int64, startDay: Int, categoryLimits: [CategoryBudget], applyToNextCycle: Bool,
                    totalUntil: Date? = nil, date: Date = .now, calendar: Calendar = .current, cardID: UUID? = nil) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        // Another card's budget saves the same way but leaves the active card's settings alone.
        let cardID = cardID ?? activeCardID
        let isActive = cardID == activeCardID
        let history = try expenseService.budgets(for: cardID)
        let fallback = BudgetVersion.initial(overallLimit: settings.budget, startDay: settings.startDay, date: date, calendar: calendar)
        let current = BudgetHistory.period(containing: date, budgets: history, calendar: calendar)
            ?? BudgetPeriod(budget: fallback, cycle: Cycle.containing(date, startDay: fallback.startDay, calendar: calendar))
        let effectiveStart: Date
        let transitionEndDay: String?
        let isTransition = current.budget.transitionEndDay == Day.string(current.cycle.end, calendar: calendar)
        if totalUntil != nil || current.budget.totalUntilDay != nil {
            // Switching kind, or editing a goal, replaces the version from the same start; no transition period.
            effectiveStart = current.cycle.start
            transitionEndDay = nil
        } else if startDay == current.budget.startDay {
            effectiveStart = applyToNextCycle ? current.cycle.end : current.cycle.start
            transitionEndDay = applyToNextCycle ? nil : (isTransition ? current.budget.transitionEndDay : nil)
        } else {
            effectiveStart = current.cycle.end
            transitionEndDay = Day.string(BudgetHistory.transitionEnd(after: effectiveStart, startDay: startDay, calendar: calendar), calendar: calendar)
        }
        let effectiveDay = Day.string(effectiveStart, calendar: calendar)
        let id = history.first(where: { $0.effectiveDay == effectiveDay })?.id ?? UUID()
        let totalUntilDay = totalUntil.map { Day.string($0, calendar: calendar) }
        if let totalUntilDay { guard totalUntilDay >= effectiveDay else { throw BudgetError.invalidEffectiveDate } }
        let budget = BudgetVersion(id: id, effectiveDay: effectiveDay, overallLimit: overallLimit,
                                   startDay: startDay, categoryLimits: categoryLimits, transitionEndDay: transitionEndDay,
                                   totalUntilDay: totalUntilDay)
        var proposed = settings
        // A goal doesn't change the fallback cycle budget that applies once the goal has ended.
        if totalUntilDay == nil { proposed.budget = overallLimit; proposed.startDay = startDay }
        try performWorkspaceCommand {
            try expenseService.save(budget, in: cardID)
            if isActive { try requireState().saveSettings(proposed) }
        }
        if isActive { settings = proposed }
        invalidateExpenseCaches()
    }

    func saveSettings(_ proposed: PrototypeSettings) throws {
        guard proposed.budget > 0, (1...31).contains(proposed.startDay) else { throw EntryError.invalidAmount }
        var proposed = proposed
        proposed.budget = activeBudget.overallLimit
        proposed.startDay = activeBudget.startDay
        try requireState().saveSettings(proposed); settings = proposed
        expenseService?.configure(categoryRules: proposed.categoryRules, archivedCategoryIDs: proposed.archivedCategoryIDs)
    }
    func setAppLockTimeout(_ timeout: AppLockTimeout?) async -> Result<Void, AppLockError> {
        let previous = settings.appLockTimeout
        guard let timeout else {
            do {
                var proposed = settings; proposed.appLockTimeout = nil
                try saveSettings(proposed)
                appLock.disable()
                return .success(())
            } catch { return .failure(.settingsCouldNotSave(error.localizedDescription)) }
        }
        let result = await appLock.enable(timeout: timeout)
        guard case .success = result else { return result }
        do {
            var proposed = settings; proposed.appLockTimeout = timeout
            try saveSettings(proposed)
            return .success(())
        } catch {
            appLock.restorePersistedConfiguration(previous)
            return .failure(.settingsCouldNotSave(error.localizedDescription))
        }
    }
    private func requireState() throws -> any LocalStateStore {
        guard let state else { throw EntryError.corruptStore }
        return state
    }
}

// MARK: - Free and Pro

extension AppModel {
    /// The real card a Free workspace keeps writing to. Chosen once; in UserDefaults so backups can't change it.
    var keptCardID: UUID? {
        get { UserDefaults.standard.string(forKey: "keptCardID").flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: "keptCardID"); applyPlan() }
    }

    /// A lapsed subscriber with several real cards picks the one to keep (again, if that card is gone).
    var needsKeptCardChoice: Bool {
        guard pro != nil, !isPro else { return false }
        let real = cards.filter { $0.kind == .real }
        return real.count > Plan.freeCards && !real.contains { $0.id == keptCardID }
    }

    func applyPlan() {
        expenseService?.plan = pro.map { Plan(isPro: $0.isPro, keptCardID: keptCardID) }
    }

    /// Whether a Pro-only screen or action is open; when not, shows the paywall saying why.
    func requirePro(_ reason: String) -> Bool {
        if isPro { return true }
        paywall = reason
        return false
    }

    /// A write the plan refused opens the paywall; anything else is an ordinary error message.
    func report(_ error: Error) {
        if let plan = error as? PlanError, plan.opensPaywall { paywall = plan.localizedDescription }
        else { self.error = error.localizedDescription }
    }
}

// MARK: - Onboarding

extension AppModel {
    /// First launch: no real card yet. A restored backup with real cards skips the rest.
    var needsOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: "onboarded") && !cards.contains { $0.kind == .real }
    }

    /// The workspace currency on a fresh install, without exchange rates: only the Sample card's made-up
    /// entries and budget exist, so they are scaled to look plausible rather than converted.
    func setUpCurrency(_ new: String) throws {
        guard let expenseService, Money.isCurrencyCode(new), new != reportingCurrency else { return }
        guard !cards.contains(where: { $0.kind == .real }) else { throw EntryError.corruptStore }
        let factor = Money.roughRate(from: reportingCurrency, to: new)
        func scale(_ minor: Int64) throws -> Int64 { try Money.minor(fromMajor: Decimal(minor) / 100 * factor, code: new) }
        let sample = Card.demo.id
        let expenses = try expenseService.expenses(for: sample).map { expense -> Expense in
            var value = expense
            value.amount = try scale(expense.amount)
            value.splits = try Self.rescale(expense.splits, from: expense.amount, to: value.amount)
            return value
        }
        let budgets = try expenseService.budgets(for: sample).map { version -> BudgetVersion in
            var value = version
            value.overallLimit = try scale(version.overallLimit)
            value.categoryLimits = try version.categoryLimits.map { .init(categoryID: $0.categoryID, limit: try scale($0.limit)) }
            return value
        }
        var proposed = workspacePreferences
        proposed.reportingCurrency = new
        var proposedSettings = settings
        proposedSettings.budget = try scale(settings.budget)
        try performWorkspaceCommand {
            try expenseService.saveExpenses(expenses, in: sample)
            for version in budgets { try expenseService.save(version, in: sample) }
            try requireState().saveWorkspacePreferences(proposed)
            try requireState().saveSettings(proposedSettings)
        }
        publishPreferences(proposed)
        settings = proposedSettings
        invalidateExpenseCaches()
    }

    /// Onboarding's last step: the user's real card, opened, and whether the Sample card stays on Home.
    func finishOnboarding(cardName: String, keepSample: Bool) throws {
        let trimmed = cardName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "My card" : String(trimmed.prefix(40))
        // Onboarding shown again (e.g. after an interruption) reuses the card it made instead of hitting the Free limit.
        let card: Card
        if let existing = cards.first(where: { $0.kind == .real }) {
            if existing.name != name { try renameCard(id: existing.id, to: name) }
            card = existing
        } else {
            card = try createCard(named: name)
        }
        _ = selectCard(card.id)
        if !keepSample {
            hiddenCardIDs.insert(Card.demo.id)
            persistWorkspacePreferences()
        }
        UserDefaults.standard.set(true, forKey: "onboarded")
    }
}
