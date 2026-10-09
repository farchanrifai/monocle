import Foundation
import Observation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    var id: Self { self }
}

enum CustomizerTarget: Identifiable, Equatable {
    case existing(BookProfile)
    case newBook

    var id: String {
        switch self {
        case .existing(let book):
            return book.id.uuidString
        case .newBook:
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
    var bills: [BillRule] { expenseService?.bills ?? [] }
    var billOccurrences: [BillOccurrence] { expenseService?.billOccurrences ?? [] }
    var activeCategories: [ExpenseCategory] {
        let currentInactive = workspacePreferences.cardInactiveCategoryIDs[activeBookID] ?? []
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
    var showStackCustomizer = false
    var stackCustomizerMode: StackCustomizerMode = .manage
    var showCSVInterchange = false
    var csvInterchangeInitialTab = 0
    var showAnalytics = false
    var showChat = false
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
    var showStartSessionSheet = false
    var sessionSheetName: String = ""
    var sessionSheetBudget: String = ""
    var pendingRepeat = false
    var undoExpense: Expense?
    private var undoOccurrences: [BillOccurrence] = []
    @ObservationIgnored private var durablePreferences = WorkspacePreferences()
    let expenseService: ExpenseService?
    private let state: (any LocalStateStore)?

    var books: [BookProfile] { expenseService?.books ?? [settings.book] }
    var activeBookID: UUID { expenseService?.activeBookID ?? settings.book.id }
    var selectedBookID: UUID?
    var workspacePreferences = WorkspacePreferences()
    var hiddenBookIDs: Set<UUID> = []
    var alwaysHiddenBookIDs: Set<UUID> = []
    var customizerTarget: CustomizerTarget? = nil
    var customizingBook: BookProfile? {
        get {
            if case .existing(let book) = customizerTarget {
                return book
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

    var visualDirection: BookVisualDirection {
        get { workspacePreferences.direction }
        set {
            guard workspacePreferences.direction != newValue else { return }
            workspacePreferences.direction = newValue
            workspacePreferences.autoAppearance = false
            persistWorkspacePreferences()
        }
    }

    func effectiveDirection(for systemScheme: ColorScheme) -> BookVisualDirection {
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

    var stacks: [CardStack] {
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

    var currentStack: CardStack? {
        if let id = activeStackID, let stack = stacks.first(where: { $0.id == id }) {
            return stack
        }
        return stacks.first
    }

    var orderedBooks: [BookProfile] {
        let current = books
        var result: [BookProfile] = []
        for id in workspacePreferences.bookOrder {
            if let book = current.first(where: { $0.id == id }) {
                result.append(book)
            }
        }
        for book in current where !result.contains(where: { $0.id == book.id }) {
            result.append(book)
        }
        return result
    }

    var unhiddenBooks: [BookProfile] {
        orderedBooks.filter { !alwaysHiddenBookIDs.contains($0.id) }
    }

    var cardsInCurrentStack: [BookProfile] {
        guard let stack = currentStack else { return unhiddenBooks }
        let current = books
        var result: [BookProfile] = []
        for id in stack.cardIDs {
            if !alwaysHiddenBookIDs.contains(id), let book = current.first(where: { $0.id == id }) {
                result.append(book)
            }
        }
        return result
    }

    var homeDeckCards: [BookProfile] {
        switch filterScope {
        case .activeStack:
            return cardsInCurrentStack
        case .allCards:
            return unhiddenBooks
        }
    }

    var visibleBooks: [BookProfile] {
        homeDeckCards
    }

    var budgetHistory: [BudgetVersion] { expenseService?.budgets ?? [] }
    var activeBudget: BudgetVersion {
        BudgetHistory.active(on: .now, budgets: budgetHistory) ?? BudgetVersion.initial(overallLimit: settings.budget, startDay: settings.startDay)
    }
    var currentBudgetPeriod: BudgetPeriod {
        BudgetHistory.period(containing: .now, budgets: budgetHistory)
            ?? BudgetPeriod(budget: activeBudget, cycle: BudgetCycle.containing(.now, startDay: activeBudget.startDay))
    }
    var cycle: BudgetCycle { currentBudgetPeriod.cycle }
    var cycleExpenses: [Expense] {
        let currentCycle = cycle
        return expenses.filter { currentCycle.contains($0) }
    }
    var spent: Int64 { Money.sum(cycleExpenses.map(\.amount)) }
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
            for book in expenses.books { categoryMap[book.id] = try expenses.categories(for: book.id) }
            try prefs.validate(books: expenses.books, categoriesByBook: categoryMap)
            let settingsBooks = expenses.books.map { BookBackupItem(book: $0, categories: categoryMap[$0.id] ?? [], expenses: [], budgets: []) }
            try self.settings.validate(books: settingsBooks, globalCategories: prefs.globalCategories, allowLegacySampleProfile: true)
            if let stored = expenses.books.first(where: { $0.id == settings.book.id }) { self.settings.book = stored }
            else if settings.book == .sample, let active = expenses.books.first(where: { $0.id == expenses.activeBookID }) { self.settings.book = active }
            if self.settings.book != settings.book { try state.saveSettings(self.settings) }
            publishPreferences(prefs)
            try ensureGlobalCategories()
            try ensureDefaultStack()
            try expenses.reconcileBills()
            expenses.onCommit = { [weak self] in self?.committedWorkspaceChanged() }
            syncWidgetSnapshot()
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
        if proposed.bookOrder.isEmpty { proposed.bookOrder = books.map(\.id) }
        if proposed.stacks.isEmpty {
            let initial = CardStack(id: UUID(), name: "Daily", icon: "rectangle.stack", cardIDs: orderedBooks.map(\.id).filter { !alwaysHiddenBookIDs.contains($0) })
            proposed.stacks = [initial]; proposed.activeStackID = initial.id
        } else if !proposed.stacks.contains(where: { $0.id == proposed.activeStackID }) { proposed.activeStackID = proposed.stacks.first?.id }
        if proposed != workspacePreferences { try commitPresentationPreferences(proposed) }
    }

    private func commitPresentationPreferences(_ proposed: WorkspacePreferences) throws {
        guard startupError == nil, expenseService?.isBlocked != true else { throw BackupError.recoveryRequired }
        var categoriesByBook: [UUID: [ExpenseCategory]] = [:]
        for book in books { categoriesByBook[book.id] = try expenseService?.categories(for: book.id) }
        try proposed.validate(books: books, categoriesByBook: categoriesByBook)
        try requireState().saveWorkspacePreferences(proposed)
        publishPreferences(proposed); syncWidgetSnapshot()
    }

    func ensureGlobalCategories() throws {
        guard workspacePreferences.globalCategories.isEmpty, let expenseService else { return }
        var catalog: [GlobalCategory] = []
        var seenNames = Set<String>()
        var seenIDs = Set<UUID>()
        for book in books {
            for cat in try expenseService.categories(for: book.id) {
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
        for (bookID, ids) in preferences.cardInactiveCategoryIDs {
            preferences.cardInactiveCategoryIDs[bookID] = ids.map { mapping[bookID]?[$0] ?? $0 }
        }
        var updatedSettings = settings
        let settingsMap = mapping[settings.book.id] ?? [:]
        updatedSettings.archivedCategoryIDs = Set(settings.archivedCategoryIDs.map { settingsMap[$0] ?? $0 })
        updatedSettings.categoryRules = settings.categoryRules.map { rule in
            var value = rule; value.categoryID = settingsMap[rule.categoryID] ?? rule.categoryID; return value
        }
        var drafts: [UUID: ExpenseDraft] = [:]
        for book in books {
            var value = book.id == (draft.bookID ?? settings.book.id) ? draft : try requireState().loadDraft(for: book.id)
            value.bookID = book.id
            if let categoryID = value.categoryID { value.categoryID = mapping[book.id]?[categoryID] ?? categoryID }
            value.splitAllocations = value.splitAllocations.map { allocation in
                var result = allocation; result.categoryID = mapping[book.id]?[allocation.categoryID] ?? allocation.categoryID; return result
            }
            drafts[book.id] = value
        }
        try performWorkspaceCommand {
            try expenseService.unifyCategoriesToGlobalCatalog(catalog)
            for (bookID, value) in drafts { try requireState().saveDraft(value, for: bookID) }
            try requireState().saveSettings(updatedSettings)
            try requireState().saveWorkspacePreferences(preferences)
        }
        settings = updatedSettings
        expenseService.configure(categoryRules: settings.categoryRules, archivedCategoryIDs: settings.archivedCategoryIDs)
        if let value = drafts[draft.bookID ?? settings.book.id] { draft = value }
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
                for book in books { oldDrafts[book.id] = try local.loadDraft(for: book.id) }
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
        workspacePreferences = preferences
        durablePreferences = preferences
        hiddenBookIDs = Set(preferences.visibleBookIDs.isEmpty ? [] : books.map(\.id).filter { !preferences.visibleBookIDs.contains($0) })
        alwaysHiddenBookIDs = Set(preferences.alwaysHiddenBookIDs)
        memoizedActivities = nil
    }

    func reload() throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.reload()
        try expenseService.reconcileBills()
        invalidateExpenseCaches()
        try ensureDefaultStack()
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
    func title(_ expense: Expense) -> String { expense.note.isEmpty ? category(expense.allocations.first?.categoryID)?.name ?? "Expense" : expense.note }
    func spent(in category: ExpenseCategory) -> Int64 {
        Money.sum(cycleExpenses.flatMap(\.allocations).filter { $0.categoryID == category.id }.map(\.amount))
    }
    var draftNeedsConfirmation: Bool {
        if draft.editing {
            if let originalDraft {
                return draft != originalDraft
            }
            let saved = expenses.first(where: { $0.id == draft.id })
                ?? books.lazy.compactMap { self.expenses(for: $0.id).first(where: { $0.id == self.draft.id }) }.first
            guard let saved else { return false }
            return (try? draft.expense()) != saved
        }
        return draft.hasContent
    }
    var preferredEntryMode: EntryMode {
        get { workspacePreferences.entryMode }
        set {
            workspacePreferences.entryMode = newValue
            persistWorkspacePreferences()
        }
    }

    func openEntry(for bookID: UUID? = nil, categoryID: UUID? = nil) {
        originalDraft = nil
        let targetBookID = bookID ?? selectedBookID ?? activeBookID
        if targetBookID != activeBookID || draft.bookID != targetBookID {
            guard selectBook(targetBookID) else { return }
        }
        draft.bookID = targetBookID
        if let categoryID, let cat = activeCategories(for: targetBookID).first(where: { $0.id == categoryID }) {
            draft.categoryID = cat.id
        }
        if !draft.editing {
            draft.mode = preferredEntryMode
        }
        showEntry = true
    }
    func edit(_ expense: Expense) {
        if draftNeedsConfirmation { pendingRepeat = false; pendingEntry = expense; return }
        draft = ExpenseDraft(expense: expense)
        if draft.bookID == nil {
            draft.bookID = expense.bookID ?? activeBookID
        }
        originalDraft = draft
        showEntry = true
    }
    func persistDraft() {
        guard startupError == nil else { return }
        do {
            if let bookID = draft.bookID {
                try requireState().saveDraft(draft, for: bookID)
            } else {
                try requireState().saveDraft(draft)
            }
        } catch { self.error = "Your draft could not be saved: \(error.localizedDescription)" }
    }
    @discardableResult
    func discardDraft() -> Bool {
        originalDraft = nil
        var cleared = ExpenseDraft(); cleared.bookID = draft.bookID ?? activeBookID
        do {
            if let bookID = draft.bookID {
                try requireState().saveDraft(cleared, for: bookID)
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
        if !visibleBooks.contains(where: { $0.id == id }) {
            if let stack = stacks.first(where: { $0.cardIDs.contains(id) }) {
                setActiveStack(id: stack.id)
            } else {
                filterScope = .allCards
            }
        }
        selectBook(id)
    }

    func openStackInHome(id: UUID) {
        selectedTab = 0
        showEntry = false
        showSettings = false
        selectedBookID = nil
        setActiveStack(id: id)
    }

    @discardableResult
    func selectBook(_ id: UUID) -> Bool {
        guard let expenseService, books.contains(where: { $0.id == id }) else {
            error = "The selected card is no longer available."
            return false
        }
        do {
            if draft.bookID != id {
                try requireState().saveDraft(draft, for: draft.bookID ?? activeBookID)
            }
            let targetDraft = try requireState().loadDraft(for: id)
            try expenseService.selectBook(id)
            selectedBookID = id
            if draft.bookID != id {
                draft = targetDraft
                draft.bookID = id
                originalDraft = nil
            }
            invalidateExpenseCaches()
            return true
        } catch {
            self.error = "The selected card could not be opened: \(error.localizedDescription)"
            return false
        }
    }

    func createBook(named name: String, selectedCategoryIDs: Set<UUID>? = nil) throws -> BookProfile {
        guard let expenseService else { throw EntryError.corruptStore }
        let initialCategories = globalCategories.filter { selectedCategoryIDs?.contains($0.id) ?? $0.defaultActiveForNewCards }
        var created: BookProfile?
        var proposed = workspacePreferences
        try performWorkspaceCommand {
            let book = try expenseService.createBook(named: name, initialCategories: initialCategories)
            created = book
            proposed.bookOrder.append(book.id)
            if let index = proposed.stacks.firstIndex(where: { $0.id == proposed.activeStackID }) { proposed.stacks[index].cardIDs.append(book.id) }
            try requireState().saveWorkspacePreferences(proposed)
        }
        guard let created else { throw EntryError.corruptStore }
        publishPreferences(proposed); invalidateExpenseCaches(); showToast("Book created")
        return created
    }

    func renameBook(id: UUID, to name: String) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        guard let existing = books.first(where: { $0.id == id }) else { throw BackupError.invalid }
        var renamed = existing
        renamed.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try renamed.validate()
        var proposed = settings
        if proposed.book.id == id { proposed.book = renamed }
        try performWorkspaceCommand {
            try expenseService.renameBook(id: id, to: name)
            try requireState().saveSettings(proposed)
        }
        settings = proposed; invalidateExpenseCaches(); showToast("Book renamed")
    }

    func deleteBook(id: UUID) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        var proposed = workspacePreferences
        var updatedSettings = settings
        let remainingBooks = books.filter { $0.id != id }
        guard !remainingBooks.isEmpty else { throw BackupError.invalid }
        let ownsDeletedDraft = (draft.bookID ?? settings.book.id) == id
        let replacementDraftID = activeBookID == id ? remainingBooks[0].id : activeBookID
        let replacementDraft = ownsDeletedDraft ? try requireState().loadDraft(for: replacementDraftID) : nil
        if updatedSettings.book.id == id, let replacement = remainingBooks.first {
            updatedSettings.book = replacement
            if let budget = BudgetHistory.active(on: .now, budgets: try expenseService.budgets(for: replacement.id)) {
                updatedSettings.budget = budget.overallLimit; updatedSettings.startDay = budget.startDay
            }
        }
        let oldCustom = proposed.cardCustomizations.removeValue(forKey: id)
        proposed.cardInactiveCategoryIDs.removeValue(forKey: id)
        proposed.bookOrder.removeAll { $0 == id }
        proposed.visibleBookIDs.removeAll { $0 == id }
        proposed.alwaysHiddenBookIDs.removeAll { $0 == id }
        for index in proposed.stacks.indices { proposed.stacks[index].cardIDs.removeAll { $0 == id } }
        try performWorkspaceCommand {
            try expenseService.deleteBook(id: id)
            try requireState().saveSettings(updatedSettings)
            try requireState().saveWorkspacePreferences(proposed)
        }
        settings = updatedSettings
        expenseService.configure(categoryRules: settings.categoryRules, archivedCategoryIDs: settings.archivedCategoryIDs)
        publishPreferences(proposed)
        if selectedBookID == id { selectedBookID = nil }
        if var replacementDraft { replacementDraft.bookID = activeBookID; draft = replacementDraft; originalDraft = nil }
        if let oldCustom, case .customPhoto(let filename) = oldCustom.style,
           !proposed.cardCustomizations.values.contains(where: { $0.style == oldCustom.style }) {
            CardArtworkStore.shared.deleteArtwork(filename: filename)
        }
        invalidateExpenseCaches(); showToast("Book deleted")
    }

    func applyCardCustomizations(names: [UUID: String], customizations: [UUID: BookCardCustomization],
                                 newBookIDs: Set<UUID>, selections: [UUID: Set<UUID>]) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        var proposed = workspacePreferences
        var updatedSettings = settings
        var lastCreated: UUID?
        try performWorkspaceCommand {
            for placeholder in newBookIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                let raw = names[placeholder]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let selected = selections[placeholder]
                let initial = globalCategories.filter { selected?.contains($0.id) ?? $0.defaultActiveForNewCards }
                let book = try expenseService.createBook(named: raw.isEmpty ? "New Card" : String(raw.prefix(40)), initialCategories: initial)
                lastCreated = book.id
                proposed.bookOrder.append(book.id)
                if let index = proposed.stacks.firstIndex(where: { $0.id == proposed.activeStackID }) { proposed.stacks[index].cardIDs.append(book.id) }
                proposed.cardCustomizations[book.id] = customizations[placeholder]
            }
            for book in books where !newBookIDs.contains(book.id) {
                if let name = names[book.id]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty, name != book.name {
                    var renamed = book
                    renamed.name = String(name.prefix(40))
                    try renamed.validate()
                    try expenseService.renameBook(id: book.id, to: renamed.name)
                    if updatedSettings.book.id == book.id { updatedSettings.book = renamed }
                }
                if let customization = customizations[book.id] { proposed.cardCustomizations[book.id] = customization }
                if let selection = selections[book.id] {
                    for category in globalCategories {
                        var inactive = proposed.cardInactiveCategoryIDs[book.id] ?? []
                        if selection.contains(category.id) {
                            try expenseService.activateCategory(category, in: book.id)
                            inactive.removeAll { $0 == category.id }
                        } else {
                            try expenseService.deactivateCategory(category.id, in: book.id)
                            if !inactive.contains(category.id) { inactive.append(category.id) }
                        }
                        proposed.cardInactiveCategoryIDs[book.id] = inactive
                    }
                }
            }
            try requireState().saveSettings(updatedSettings)
            try requireState().saveWorkspacePreferences(proposed)
        }
        settings = updatedSettings
        publishPreferences(proposed); invalidateExpenseCaches()
        if let lastCreated { selectBook(lastCreated) }
        showToast("Cards saved")
    }

    func performUIAction(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }

    func customization(for bookID: UUID) -> BookCardCustomization {
        if let custom = workspacePreferences.cardCustomizations[bookID] {
            return custom
        }
        let colorIdx = books.first { $0.id == bookID }?.colorIndex ?? 0
        return BookCardCustomization.defaultFor(colorIndex: colorIdx)
    }

    func updateCustomization(_ customization: BookCardCustomization, for bookID: UUID) {
        var proposed = workspacePreferences
        proposed.cardCustomizations[bookID] = customization
        do { try commitPresentationPreferences(proposed) } catch { self.error = error.localizedDescription }
    }

    func setBookHidden(id: UUID, isHidden: Bool) {
        var hidden = hiddenBookIDs
        if isHidden { hidden.insert(id) } else { hidden.remove(id) }
        var proposed = workspacePreferences
        proposed.visibleBookIDs = books.map(\.id).filter { !hidden.contains($0) }
        do { try commitPresentationPreferences(proposed) } catch { self.error = error.localizedDescription }
    }

    func setCardAlwaysHidden(id: UUID, isHidden: Bool) {
        var proposed = workspacePreferences
        var hidden = Set(proposed.alwaysHiddenBookIDs)
        var ordinary = hiddenBookIDs
        if isHidden {
            hidden.insert(id); ordinary.insert(id)
            for index in proposed.stacks.indices { proposed.stacks[index].cardIDs.removeAll { $0 == id } }
        } else {
            hidden.remove(id); ordinary.remove(id)
            if let index = proposed.stacks.firstIndex(where: { $0.id == proposed.activeStackID }), !proposed.stacks[index].cardIDs.contains(id) { proposed.stacks[index].cardIDs.append(id) }
        }
        proposed.alwaysHiddenBookIDs = Array(hidden)
        proposed.visibleBookIDs = books.map(\.id).filter { !ordinary.contains($0) }
        do {
            try commitPresentationPreferences(proposed)
            if isHidden, selectedBookID == id { selectedBookID = nil }
            showToast(isHidden ? "Card archived" : "Card unarchived")
        } catch { self.error = error.localizedDescription }
    }

    func saveStackConfiguration(_ stacks: [CardStack], activeStackID: UUID?, alwaysHiddenIDs: Set<UUID>) throws {
        var proposed = workspacePreferences
        proposed.stacks = stacks; proposed.activeStackID = activeStackID
        proposed.alwaysHiddenBookIDs = Array(alwaysHiddenIDs)
        proposed.visibleBookIDs = books.map(\.id).filter { !alwaysHiddenIDs.contains($0) }
        proposed.filterScope = .activeStack
        try commitPresentationPreferences(proposed)
        if let selectedBookID, alwaysHiddenIDs.contains(selectedBookID) { self.selectedBookID = nil }
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
        do { try commitPresentationPreferences(proposed) } catch { self.error = error.localizedDescription }
    }

    func setActiveStack(id: UUID) {
        guard stacks.contains(where: { $0.id == id }) else { return }
        var proposed = workspacePreferences; proposed.activeStackID = id; proposed.filterScope = .activeStack
        do { try commitPresentationPreferences(proposed) } catch { self.error = error.localizedDescription }
    }

    @discardableResult
    func createStack(name: String, icon: String = "rectangle.stack", cardIDs: [UUID] = []) throws -> CardStack {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "New Stack" : String(trimmed.prefix(40))
        let stack = CardStack(id: UUID(), name: finalName, icon: icon, cardIDs: cardIDs)
        var proposed = workspacePreferences
        proposed.stacks.append(stack); proposed.activeStackID = stack.id; proposed.filterScope = .activeStack
        try commitPresentationPreferences(proposed)
        showToast("Stack '\(finalName)' created")
        return stack
    }

    func updateStack(_ stack: CardStack) throws {
        guard let index = stacks.firstIndex(where: { $0.id == stack.id }) else { throw BackupError.invalid }
        var proposed = workspacePreferences; proposed.stacks[index] = stack
        try commitPresentationPreferences(proposed)
    }

    func deleteStack(id: UUID) {
        guard stacks.count > 1 else { showToast("Cannot delete the only stack"); return }
        var proposed = workspacePreferences
        proposed.stacks.removeAll { $0.id == id }
        if proposed.activeStackID == id { proposed.activeStackID = proposed.stacks.first?.id }
        do { try commitPresentationPreferences(proposed); showToast("Stack deleted") }
        catch { self.error = error.localizedDescription }
    }

    func moveBookToFront(_ bookID: UUID) {
        var proposed = workspacePreferences
        if filterScope == .activeStack, let stackID = activeStackID, let idx = stacks.firstIndex(where: { $0.id == stackID }) {
            var cardIDs = stacks[idx].cardIDs.filter { $0 != bookID }
            cardIDs.insert(bookID, at: 0)
            proposed.stacks[idx].cardIDs = cardIDs
        } else {
            var currentOrder = orderedBooks.map(\.id).filter { $0 != bookID }
            currentOrder.insert(bookID, at: 0)
            proposed.bookOrder = currentOrder
        }
        do { try commitPresentationPreferences(proposed); showToast("Moved to front") }
        catch { self.error = error.localizedDescription }
    }

    func reorderCardsInCurrentStack(fromOffsets: IndexSet, toOffset: Int) {
        if filterScope == .activeStack, let stackID = activeStackID, let idx = stacks.firstIndex(where: { $0.id == stackID }) {
            var cardIDs = stacks[idx].cardIDs
            cardIDs.move(fromOffsets: fromOffsets, toOffset: toOffset)
            var proposed = workspacePreferences; proposed.stacks[idx].cardIDs = cardIDs
            do { try commitPresentationPreferences(proposed) } catch { self.error = error.localizedDescription }
        } else {
            reorderBooks(fromOffsets: fromOffsets, toOffset: toOffset)
        }
    }

    func reorderBooks(fromOffsets: IndexSet, toOffset: Int) {
        var currentOrder = orderedBooks.map(\.id)
        currentOrder.move(fromOffsets: fromOffsets, toOffset: toOffset)
        var proposed = workspacePreferences; proposed.bookOrder = currentOrder
        do { try commitPresentationPreferences(proposed) } catch { self.error = error.localizedDescription }
    }

    func persistWorkspacePreferences() {
        guard startupError == nil else { return }
        workspacePreferences.visibleBookIDs = books.map(\.id).filter { !hiddenBookIDs.contains($0) }
        workspacePreferences.alwaysHiddenBookIDs = Array(alwaysHiddenBookIDs)
        do {
            try requireState().saveWorkspacePreferences(workspacePreferences)
            let changedScope = durablePreferences.stacks != workspacePreferences.stacks ||
                durablePreferences.activeStackID != workspacePreferences.activeStackID ||
                durablePreferences.visibleBookIDs != workspacePreferences.visibleBookIDs ||
                durablePreferences.alwaysHiddenBookIDs != workspacePreferences.alwaysHiddenBookIDs ||
                durablePreferences.filterScopeRaw != workspacePreferences.filterScopeRaw
            durablePreferences = workspacePreferences
            if changedScope { memoizedActivities = nil; syncWidgetSnapshot() }
        } catch {
            publishPreferences(durablePreferences)
            self.error = error.localizedDescription
        }
    }

    @ObservationIgnored private var expensesCache: [UUID: [Expense]] = [:]
    @ObservationIgnored private var spentCache: [UUID: Int64] = [:]
    @ObservationIgnored private var memoizedActivities: [Expense]? = nil
    @ObservationIgnored private var memoizedActivitiesKey: String = ""

    var billReminderStatus: String? { expenseService?.notifications.lastError }

    private func committedWorkspaceChanged() {
        if let refreshError = expenseService?.projectionRefreshError {
            expensesCache.removeAll(); spentCache.removeAll(); memoizedActivities = nil
            error = "Your change was saved, but the display could not refresh: \(refreshError)"
            do { try WidgetSnapshotStore.writeSnapshot(.unavailable("Open Monocle to refresh")) }
            catch { BackendDiagnostics.widgetPublicationFailed() }
        } else { invalidateExpenseCaches() }
    }

    func invalidateExpenseCaches() {
        expensesCache.removeAll()
        spentCache.removeAll()
        memoizedActivities = nil
        memoizedActivitiesKey = ""
        syncWidgetSnapshot()
    }

    func syncWidgetSnapshot() {
        guard startupError == nil, expenseService?.projectionRefreshError == nil else { return }
        guard let activeBook = books.first(where: { $0.id == activeBookID }) ?? books.first else { return }
        var stack = currentStack
        stack?.cardIDs.removeAll { alwaysHiddenBookIDs.contains($0) }
        let stackExp: [Expense] = {
            if let stack {
                return books.filter { stack.cardIDs.contains($0.id) && !alwaysHiddenBookIDs.contains($0.id) }.flatMap { expenses(for: $0.id) }
            }
            return expenses
        }()
        WidgetSnapshotUpdater.update(
            activeBook: activeBook,
            activeStack: stack,
            allBooks: books,
            expenses: expenses,
            stackExpenses: stackExp,
            categories: categories,
            captureCategories: activeCategories(for: activeBookID),
            budget: activeBudget,
            cycle: cycle,
            revision: expenseService?.committedRevision
        )
    }

    func expenses(for bookID: UUID) -> [Expense] {
        if bookID == activeBookID {
            return expenses
        }
        if let cached = expensesCache[bookID] {
            return cached
        }
        let result = (try? expenseService?.expenses(for: bookID)) ?? []
        expensesCache[bookID] = result
        return result
    }

    func spent(for bookID: UUID) -> Int64 {
        if let cached = spentCache[bookID] {
            return cached
        }
        let total = Money.sum(expenses(for: bookID).map(\.amount))
        spentCache[bookID] = total
        return total
    }

    /// Cards a scope covers; stacks keep their own card order.
    func books(in scope: AnalyticsFilterScope) -> [BookProfile] {
        switch scope {
        case .card(let id, _): return books.filter { $0.id == id }
        case .stack(let id, _):
            let ids = stacks.first(where: { $0.id == id })?.cardIDs ?? []
            return ids.compactMap { id in books.first { $0.id == id } }.filter { !alwaysHiddenBookIDs.contains($0.id) }
        case .allCards: return unhiddenBooks
        }
    }

    /// Categories a new expense on this card may use: not archived, not deactivated for the card.
    func activeCategories(in bookID: UUID) throws -> [ExpenseCategory] {
        guard let expenseService else { throw EntryError.corruptStore }
        let inactive = workspacePreferences.cardInactiveCategoryIDs[bookID] ?? []
        return try expenseService.categories(for: bookID).filter { !settings.archivedCategoryIDs.contains($0.id) && !inactive.contains($0.id) }
    }

    func reportingData(for scope: AnalyticsFilterScope) -> AnalyticsReportingData {
        let selected = books(in: scope)
        var data = AnalyticsReportingData()
        data.books = selected
        do {
            guard let expenseService else { throw EntryError.corruptStore }
            var seen = Set<UUID>()
            for book in selected {
                let values = try expenseService.expenses(for: book.id)
                data.expensesByBook[book.id] = values
                data.expenses.append(contentsOf: values)
                data.categories += try expenseService.categories(for: book.id).filter { seen.insert($0.id).inserted }
                data.bills += try expenseService.bills(for: book.id)
                data.billOccurrences += try expenseService.billOccurrences(for: book.id)
            }
            if case .card(let id, _) = scope { data.budgets = try expenseService.budgets(for: id) }
        } catch { data.errorMessage = error.localizedDescription }
        return data
    }

    func allExpenses() -> [Expense] {
        var result: [Expense] = []
        for book in books {
            result.append(contentsOf: expenses(for: book.id))
        }
        return result
    }

    func allExpensesByBook() -> [UUID: [Expense]] {
        var map: [UUID: [Expense]] = [:]
        for book in books {
            map[book.id] = expenses(for: book.id)
        }
        return map
    }

    func activities(selectedBookID: UUID?, allBooks: Bool) -> [Expense] {
        if let selectedBookID {
            return expenses(for: selectedBookID)
        }
        let key = "\(allBooks)-\(filterScope.rawValue)-\(activeStackID?.uuidString ?? "nil")-\(unhiddenBooks.count)-\(homeDeckCards.count)"
        if memoizedActivitiesKey == key, let cached = memoizedActivities {
            return cached
        }

        var all: [Expense] = []
        let targetBooks = allBooks ? unhiddenBooks : homeDeckCards
        for b in targetBooks {
            all.append(contentsOf: expenses(for: b.id))
        }
        let sorted = all.sorted { $0.day == $1.day ? $0.createdAt > $1.createdAt : $0.day > $1.day }
        memoizedActivities = sorted
        memoizedActivitiesKey = key
        return sorted
    }

    func startEmptyRealBook(named name: String) throws {
        guard let backups else { throw BackupError.unsupported }
        let settings = try recoveryCommand { try backups.startEmptyRealBook(named: name, currentDraft: draft, settings: settings) }
        self.settings = settings
        draft = ExpenseDraft(); draft.bookID = settings.book.id
        undoExpense = nil; pendingEntry = nil
        invalidateExpenseCaches()
        showToast("Your real book is ready")
    }
    func renameRealBook(to name: String) throws {
        guard let backups else { throw BackupError.unsupported }
        try recoveryCommand { settings = try backups.renameRealBook(to: name, currentDraft: draft, settings: settings) }
        invalidateExpenseCaches()
        showToast("Book renamed")
    }

    func clearActiveCardExpenses() throws {
        guard let backups else { throw BackupError.unsupported }
        let targetID = selectedBookID ?? activeBookID
        try recoveryCommand { try backups.clearExpenses(in: targetID, currentDraft: draft, settings: settings) }
        draft = ExpenseDraft(); draft.bookID = activeBookID
        originalDraft = nil
        undoExpense = nil; pendingEntry = nil
        try reload()
        showToast("Transactions cleared")
    }

    func clearAllTransactions() throws {
        guard let backups else { throw BackupError.unsupported }
        try recoveryCommand { try backups.clearExpenses(in: nil, currentDraft: draft, settings: settings) }
        draft = ExpenseDraft(); draft.bookID = activeBookID
        originalDraft = nil
        undoExpense = nil; pendingEntry = nil
        try reload()
        showToast("All transactions cleared")
    }

    func resetAllData(cardName: String) throws {
        guard let backups else { throw BackupError.unsupported }
        let newSettings = try recoveryCommand { try backups.resetAllData(cardName: cardName, currentDraft: draft, settings: settings) }
        self.settings = newSettings
        publishPreferences(try requireState().loadWorkspacePreferences())
        expenseService?.configure(categoryRules: newSettings.categoryRules, archivedCategoryIDs: newSettings.archivedCategoryIDs)
        self.draft = ExpenseDraft(); self.draft.bookID = newSettings.book.id
        self.originalDraft = nil
        self.undoExpense = nil; pendingEntry = nil
        self.hiddenBookIDs = []
        self.alwaysHiddenBookIDs = []
        self.customizerTarget = nil
        self.selectedBookID = newSettings.book.id
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

    func importExpenses(_ batch: [Expense], to bookID: UUID) throws {
        try expenseService?.saveExpenses(batch, in: bookID)
        invalidateExpenseCaches()
        showToast("Imported \(batch.count) \(batch.count == 1 ? "expense" : "expenses")")
    }

    func csvExportText(
        for bookID: UUID?,
        dateRange: CSVDateRangeScope,
        customStartDate: Date = .now,
        customEndDate: Date = .now
    ) -> String {
        let calendar = Day.calendar
        var targetExpenses: [Expense]
        if let bookID {
            targetExpenses = expenses(for: bookID)
        } else {
            var all: [Expense] = []
            for b in books {
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
        if let bookID {
            rawCategories = (try? expenseService?.categories(for: bookID)) ?? categories
        } else {
            rawCategories = books.flatMap { (try? expenseService?.categories(for: $0.id)) ?? [] }
        }
        var seenCategoryIDs = Set<UUID>()
        let allCats = rawCategories.filter { seenCategoryIDs.insert($0.id).inserted }
        return CSVExportGenerator.generate(expenses: targetExpenses, categories: allCats, books: books)
    }

    @discardableResult
    func saveDraft() -> Bool {
        do {
            var expense = try draft.expense()
            let targetID = draft.bookID ?? selectedBookID ?? activeBookID
            expense.bookID = targetID
            try save(expense)
            let editing = draft.editing
            originalDraft = nil
            var cleared = ExpenseDraft(); cleared.bookID = targetID
            draft = cleared
            // The expense is already durable. Cleanup failure must never invite a second save.
            do { try requireState().saveDraft(cleared, for: targetID) }
            catch { self.error = "Expense saved, but its draft could not be cleared: \(error.localizedDescription)" }
            showEntry = false
            undoExpense = nil
            saveFeedback += 1
            if !editing, SpendingSessionManager.shared.isSessionActive {
                let cat = activeCategories(for: targetID).first(where: { $0.id == expense.allocations.first?.categoryID })
                SpendingSessionManager.shared.recordExpense(
                    amount: expense.amount,
                    note: expense.note,
                    categorySymbol: cat?.symbol,
                    bookID: targetID
                )
            }
            showToast(editing ? "Expense updated" : "Expense recorded")
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    func save(_ expense: Expense) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.save(expense)
        invalidateExpenseCaches()
    }
    func delete(_ expense: Expense) {
        do {
            guard let expenseService else { throw EntryError.corruptStore }
            let owner = expense.bookID ?? activeBookID
            let linked = try expenseService.billOccurrences(for: owner).filter { $0.expenseID == expense.id }
            try expenseService.delete(expense.id, in: owner)
            undoOccurrences = linked
            invalidateExpenseCaches()
            undoExpense = expense; showToast("Expense deleted")
        } catch { self.error = error.localizedDescription }
    }
    func undoDelete() {
        guard let undoExpense else { return }
        do {
            guard let expenseService else { throw EntryError.corruptStore }
            try expenseService.restoreExpense(undoExpense, occurrences: undoOccurrences, in: undoExpense.bookID ?? activeBookID)
            self.undoExpense = nil; undoOccurrences = []; invalidateExpenseCaches(); showToast("Expense restored")
        }
        catch { self.error = error.localizedDescription }
    }
    func saveBill(_ bill: BillRule, in bookID: UUID? = nil) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.saveBill(bill, in: bookID)
        invalidateExpenseCaches()
        showToast("Bill saved")
    }
    func deleteBill(_ id: UUID, in bookID: UUID? = nil) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.deleteBill(id, in: bookID)
        invalidateExpenseCaches()
        showToast("Bill deleted")
    }
    @discardableResult
    func confirmBillOccurrence(
        _ occurrenceID: UUID,
        customDate: Date? = nil,
        customAmount: Int64? = nil,
        customNote: String? = nil,
        in bookID: UUID? = nil
    ) throws -> Expense {
        guard let expenseService else { throw EntryError.corruptStore }
        let expense = try expenseService.confirmBillOccurrence(
            occurrenceID,
            customDate: customDate,
            customAmount: customAmount,
            customNote: customNote,
            in: bookID
        )
        invalidateExpenseCaches()
        showToast("Bill recorded")
        return expense
    }
    func skipBillOccurrence(_ occurrenceID: UUID, in bookID: UUID? = nil) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.skipBillOccurrence(occurrenceID, in: bookID)
        showToast("Bill skipped")
    }
    func reconcileBills(asOf date: Date = .now, in bookID: UUID? = nil) {
        guard let expenseService else { return }
        do { try expenseService.reconcileBills(asOf: date, in: bookID) }
        catch { self.error = error.localizedDescription }
        invalidateExpenseCaches()
    }
    func repeatExpense(_ expense: Expense) {
        if draftNeedsConfirmation { pendingRepeat = true; pendingEntry = expense; return }
        draft = ExpenseDraft(expense: expense); draft.id = UUID(); draft.editing = false
        draft.createdAt = .now; draft.date = .now; draft.source = "repeat"
        draft.bookID = expense.bookID ?? activeBookID
        showEntry = true
    }
    func saveCategory(_ category: ExpenseCategory) throws {
        let validated = try category.validated(against: categories)
        try saveGlobalCategory(GlobalCategory(category: validated, defaultActiveForNewCards: true), activeBookIDs: activeBookIDs(for: validated.id).union([activeBookID]))
    }

    func isCategoryActive(_ categoryID: UUID, on bookID: UUID) -> Bool {
        if let inactive = workspacePreferences.cardInactiveCategoryIDs[bookID], inactive.contains(categoryID) {
            return false
        }
        let bookCategories = (try? expenseService?.categories(for: bookID)) ?? []
        return bookCategories.contains(where: { $0.id == categoryID })
    }

    func activeBookIDs(for categoryID: UUID) -> Set<UUID> {
        Set(books.map(\.id).filter { isCategoryActive(categoryID, on: $0) })
    }

    func activeCategoryIDs(for bookID: UUID) -> Set<UUID> {
        let inactive = Set(workspacePreferences.cardInactiveCategoryIDs[bookID] ?? [])
        let bookCategories = (try? expenseService?.categories(for: bookID)) ?? []
        return Set(bookCategories.map(\.id).filter { !inactive.contains($0) })
    }

    func activeCategories(for bookID: UUID) -> [ExpenseCategory] {
        let inactive = Set(workspacePreferences.cardInactiveCategoryIDs[bookID] ?? [])
        let bookCategories = (try? expenseService?.categories(for: bookID)) ?? []
        return bookCategories.filter { !inactive.contains($0.id) && !settings.archivedCategoryIDs.contains($0.id) }
    }

    func setCategory(_ categoryID: UUID, active: Bool, for bookID: UUID) throws {
        guard let expenseService, let global = globalCategories.first(where: { $0.id == categoryID }) else { throw EntryError.missingCategory }
        var proposed = workspacePreferences
        var inactive = proposed.cardInactiveCategoryIDs[bookID] ?? []
        if active { inactive.removeAll { $0 == categoryID } }
        else if !inactive.contains(categoryID) { inactive.append(categoryID) }
        proposed.cardInactiveCategoryIDs[bookID] = inactive
        try performWorkspaceCommand {
            if active { try expenseService.activateCategory(global, in: bookID) }
            else { try expenseService.deactivateCategory(categoryID, in: bookID) }
            try requireState().saveWorkspacePreferences(proposed)
        }
        publishPreferences(proposed); invalidateExpenseCaches()
    }

    func saveGlobalCategory(_ category: GlobalCategory, activeBookIDs: Set<UUID>) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        let validated = try category.validated(against: globalCategories)
        var proposed = workspacePreferences
        proposed.globalCategories.removeAll { $0.id == validated.id }
        proposed.globalCategories.append(validated)
        try performWorkspaceCommand {
            try expenseService.updateGlobalCategoryMetadata(id: validated.id, name: validated.name, symbol: validated.symbol)
            for book in books {
                var inactive = proposed.cardInactiveCategoryIDs[book.id] ?? []
                if activeBookIDs.contains(book.id) {
                    try expenseService.activateCategory(validated, in: book.id)
                    inactive.removeAll { $0 == validated.id }
                } else {
                    try expenseService.deactivateCategory(validated.id, in: book.id)
                    if !inactive.contains(validated.id) { inactive.append(validated.id) }
                }
                proposed.cardInactiveCategoryIDs[book.id] = inactive
            }
            try requireState().saveWorkspacePreferences(proposed)
        }
        publishPreferences(proposed); invalidateExpenseCaches()
    }

    func deleteGlobalCategory(_ category: GlobalCategory) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        guard undoExpense?.allocations.contains(where: { $0.categoryID == category.id }) != true,
              !settings.categoryRules.contains(where: { $0.categoryID == category.id }) else { throw CategoryError.inUse }
        for book in books {
            let savedDraft = book.id == draft.bookID ? draft : try requireState().loadDraft(for: book.id)
            guard savedDraft.categoryID != category.id, !savedDraft.splitAllocations.contains(where: { $0.categoryID == category.id }),
                  !(try expenseService.expenses(for: book.id)).contains(where: { $0.allocations.contains(where: { $0.categoryID == category.id }) }),
                  !(try expenseService.bills(for: book.id)).contains(where: { $0.categoryID == category.id }),
                  !(try expenseService.budgets(for: book.id)).contains(where: { $0.categoryLimits.contains(where: { $0.categoryID == category.id }) }) else { throw CategoryError.inUse }
        }
        var proposed = workspacePreferences
        proposed.globalCategories.removeAll { $0.id == category.id }
        for book in books { proposed.cardInactiveCategoryIDs[book.id]?.removeAll { $0 == category.id } }
        try performWorkspaceCommand {
            for book in books { try expenseService.deactivateCategory(category.id, in: book.id) }
            try requireState().saveWorkspacePreferences(proposed)
        }
        publishPreferences(proposed); invalidateExpenseCaches()
    }

    func isArchived(_ category: ExpenseCategory) -> Bool { settings.archivedCategoryIDs.contains(category.id) }
    func archiveCategory(_ category: ExpenseCategory) throws {
        guard draft.categoryID != category.id, !draft.splitAllocations.contains(where: { $0.categoryID == category.id }),
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
        guard draft.splitAllocations.isEmpty else { return }
        guard let categoryID = draft.categoryID ?? activeCategories.first?.id else { error = EntryError.missingCategory.localizedDescription; return }
        draft.categoryID = categoryID
        let value = try? draft.resolvedAmount()
        draft.splitAllocations = [.init(categoryID: categoryID, amount: value.map(Money.exactDigits) ?? draft.amount, preservedAmount: value)]
    }
    func addSplitAllocation() {
        beginSplitting()
        let used = Set(draft.splitAllocations.map(\.categoryID))
        guard let category = activeCategories.first(where: { !used.contains($0.id) }) else {
            error = "Create another category before adding a further split."
            return
        }
        draft.splitAllocations.append(.init(categoryID: category.id, amount: ""))
    }
    func stopSplitting() {
        categoryIDFromSplit()
        draft.splitAllocations = []
    }
    private func categoryIDFromSplit() {
        if let categoryID = draft.splitAllocations.first?.categoryID { draft.categoryID = categoryID }
    }
    func deleteCategory(_ category: ExpenseCategory) throws {
        guard let global = globalCategories.first(where: { $0.id == category.id }) else { throw EntryError.missingCategory }
        try deleteGlobalCategory(global)
    }

    func restoreBackup(_ backup: BookBackup) throws {
        try restoreWorkspaceBackup(WorkspaceBackup(singleBook: backup))
    }

    func restoreWorkspaceBackup(_ source: WorkspaceBackup) throws {
        let backup = try source.normalized()
        guard let backups else { throw BackupError.unsupported }
        do {
            try backups.restoreWorkspace(backup, currentDraft: draft, settings: settings)
            let restoredBookID = expenseService?.activeBookID ?? backup.books[0].book.id
            if let active = backup.books.first(where: { $0.book.id == restoredBookID }) {
                draft = active.draft ?? ExpenseDraft()
            }
            draft.bookID = restoredBookID
            selectedBookID = restoredBookID
            settings = backup.settings
            appLock.applyPersistedConfiguration(settings.appLockTimeout, requireAuthentication: true)
            publishPreferences(backup.preferences)
            workspacePreferences = backup.preferences
            hiddenBookIDs = backup.preferences.visibleBookIDs.isEmpty
                ? []
                : Set(books.map(\.id).filter { !backup.preferences.visibleBookIDs.contains($0) })
            expenseService?.configure(categoryRules: settings.categoryRules, archivedCategoryIDs: settings.archivedCategoryIDs)
            undoExpense = nil; pendingEntry = nil; toast = nil
            invalidateExpenseCaches()
        } catch {
            if backups.requiresRecovery { startupError = error.localizedDescription }
            throw error
        }
    }

    func saveBudget(overallLimit: Int64, startDay: Int, categoryLimits: [CategoryBudget], applyToNextCycle: Bool,
                    date: Date = .now, calendar: Calendar = .current) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        let fallback = BudgetVersion.initial(overallLimit: settings.budget, startDay: settings.startDay, date: date, calendar: calendar)
        let current = BudgetHistory.period(containing: date, budgets: budgetHistory, calendar: calendar)
            ?? BudgetPeriod(budget: fallback, cycle: BudgetCycle.containing(date, startDay: fallback.startDay, calendar: calendar))
        let effectiveStart: Date
        let transitionEndDay: String?
        let isTransition = current.budget.transitionEndDay == Day.string(current.cycle.end, calendar: calendar)
        if startDay == current.budget.startDay {
            effectiveStart = applyToNextCycle ? current.cycle.end : current.cycle.start
            transitionEndDay = applyToNextCycle ? nil : (isTransition ? current.budget.transitionEndDay : nil)
        } else {
            effectiveStart = current.cycle.end
            transitionEndDay = Day.string(BudgetHistory.transitionEnd(after: effectiveStart, startDay: startDay, calendar: calendar), calendar: calendar)
        }
        let effectiveDay = Day.string(effectiveStart, calendar: calendar)
        let id = budgetHistory.first(where: { $0.effectiveDay == effectiveDay })?.id ?? UUID()
        let budget = BudgetVersion(id: id, effectiveDay: effectiveDay, overallLimit: overallLimit,
                                   startDay: startDay, categoryLimits: categoryLimits, transitionEndDay: transitionEndDay)
        var proposed = settings
        proposed.budget = overallLimit
        proposed.startDay = startDay
        try performWorkspaceCommand {
            try expenseService.save(budget)
            try requireState().saveSettings(proposed)
        }
        settings = proposed
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
