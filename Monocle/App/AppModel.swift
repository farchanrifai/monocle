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
    var activeCategories: [ExpenseCategory] { categories.filter { !settings.archivedCategoryIDs.contains($0.id) } }
    var draft = ExpenseDraft()
    var settings = PrototypeSettings()
    var showEntry = false
    var showSettings = false
    var showStackCustomizer = false
    var stackCustomizerMode: StackCustomizerMode = .manage
    var selectedTab = 0
    var error: String?
    var startupError: String?
    var backups: BackupService?
    let appLock: AppLockController
    var toast: String?
    var toastID = UUID()
    var saveFeedback = 0
    var pendingEntry: Expense?
    var pendingRepeat = false
    var undoExpense: Expense?
    private let expenseService: ExpenseService?
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
    var cycleExpenses: [Expense] { expenses.filter { cycle.contains($0) } }
    var spent: Int64 { cycleExpenses.reduce(0) { $0 + $1.amount } }
    var remaining: Int64 { activeBudget.overallLimit - spent }

    init(expenses: ExpenseService, state: any LocalStateStore, draft: ExpenseDraft = ExpenseDraft(), settings: PrototypeSettings = PrototypeSettings(), appLock: AppLockController? = nil) {
        self.expenseService = expenses
        self.state = state
        self.draft = draft
        self.settings = settings
        self.appLock = appLock ?? AppLockController(timeout: settings.appLockTimeout)
        if let prefs = try? state.loadWorkspacePreferences() {
            self.workspacePreferences = prefs
            self.hiddenBookIDs = Set(prefs.visibleBookIDs.isEmpty ? [] : expenses.books.map(\.id).filter { !prefs.visibleBookIDs.contains($0) })
            self.alwaysHiddenBookIDs = Set(prefs.alwaysHiddenBookIDs)
        }
        ensureDefaultStack()
    }

    init(startupFailure: String) {
        expenseService = nil
        state = nil
        appLock = AppLockController(timeout: nil)
        startupError = startupFailure
    }

    func ensureDefaultStack() {
        if workspacePreferences.bookOrder.isEmpty {
            workspacePreferences.bookOrder = books.map(\.id)
            persistWorkspacePreferences()
        }
        if workspacePreferences.stacks.isEmpty {
            let initialCardIDs = orderedBooks.map(\.id).filter { !alwaysHiddenBookIDs.contains($0) }
            let defaultStack = CardStack(id: UUID(), name: "Daily", icon: "rectangle.stack", cardIDs: initialCardIDs)
            workspacePreferences.stacks = [defaultStack]
            workspacePreferences.activeStackID = defaultStack.id
            persistWorkspacePreferences()
        } else if workspacePreferences.activeStackID == nil || !workspacePreferences.stacks.contains(where: { $0.id == workspacePreferences.activeStackID }) {
            workspacePreferences.activeStackID = workspacePreferences.stacks.first?.id
            persistWorkspacePreferences()
        }
    }

    func reload() throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.reload()
        ensureDefaultStack()
    }
    func category(_ id: UUID?) -> ExpenseCategory? { categories.first { $0.id == id } }
    func title(_ expense: Expense) -> String { expense.note.isEmpty ? category(expense.allocations.first?.categoryID)?.name ?? "Expense" : expense.note }
    func spent(in category: ExpenseCategory) -> Int64 {
        cycleExpenses.flatMap(\.allocations).filter { $0.categoryID == category.id }.reduce(0) { $0 + $1.amount }
    }
    var draftNeedsConfirmation: Bool {
        guard draft.editing else { return draft.hasContent }
        guard let saved = expenses.first(where: { $0.id == draft.id }) else { return draft.hasContent }
        return (try? draft.expense()) != saved
    }
    func openEntry(for bookID: UUID? = nil) {
        if let bookID {
            draft.bookID = bookID
        } else if draft.bookID == nil {
            draft.bookID = selectedBookID ?? activeBookID
        }
        showEntry = true
    }
    func edit(_ expense: Expense) {
        if draftNeedsConfirmation { pendingRepeat = false; pendingEntry = expense; return }
        draft = ExpenseDraft(expense: expense)
        if draft.bookID == nil {
            draft.bookID = expense.bookID ?? activeBookID
        }
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
        let cleared = ExpenseDraft()
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

    func selectBook(_ id: UUID) {
        selectedBookID = id
        if let expenseService {
            try? expenseService.selectBook(id)
        }
    }

    func createBook(named name: String) throws -> BookProfile {
        guard let expenseService else { throw EntryError.corruptStore }
        let book = try expenseService.createBook(named: name)
        workspacePreferences.bookOrder.append(book.id)
        if let activeID = workspacePreferences.activeStackID,
           let index = workspacePreferences.stacks.firstIndex(where: { $0.id == activeID }) {
            if !workspacePreferences.stacks[index].cardIDs.contains(book.id) {
                workspacePreferences.stacks[index].cardIDs.append(book.id)
            }
        }
        persistWorkspacePreferences()
        showToast("Book created")
        return book
    }

    func renameBook(id: UUID, to name: String) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.renameBook(id: id, to: name)
        showToast("Book renamed")
    }

    func deleteBook(id: UUID) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.deleteBook(id: id)
        if let custom = workspacePreferences.cardCustomizations[id],
           case .customPhoto(let filename) = custom.style {
            CardArtworkStore.shared.deleteArtwork(filename: filename)
        }
        workspacePreferences.cardCustomizations.removeValue(forKey: id)
        workspacePreferences.bookOrder.removeAll { $0 == id }
        workspacePreferences.visibleBookIDs.removeAll { $0 == id }
        hiddenBookIDs.remove(id)
        alwaysHiddenBookIDs.remove(id)
        for i in workspacePreferences.stacks.indices {
            workspacePreferences.stacks[i].cardIDs.removeAll { $0 == id }
        }
        if selectedBookID == id { selectedBookID = nil }
        persistWorkspacePreferences()
        showToast("Book deleted")
    }

    func customization(for bookID: UUID) -> BookCardCustomization {
        if let custom = workspacePreferences.cardCustomizations[bookID] {
            return custom
        }
        let colorIdx = books.first { $0.id == bookID }?.colorIndex ?? 0
        return BookCardCustomization.defaultFor(colorIndex: colorIdx)
    }

    func updateCustomization(_ customization: BookCardCustomization, for bookID: UUID) {
        workspacePreferences.cardCustomizations[bookID] = customization
        persistWorkspacePreferences()
    }

    func setBookHidden(id: UUID, isHidden: Bool) {
        if isHidden {
            hiddenBookIDs.insert(id)
        } else {
            hiddenBookIDs.remove(id)
        }
        persistWorkspacePreferences()
    }

    func setCardAlwaysHidden(id: UUID, isHidden: Bool) {
        if isHidden {
            alwaysHiddenBookIDs.insert(id)
            hiddenBookIDs.insert(id)
            var updatedStacks = stacks
            for i in updatedStacks.indices {
                updatedStacks[i].cardIDs.removeAll { $0 == id }
            }
            stacks = updatedStacks
            if selectedBookID == id { selectedBookID = nil }
            showToast("Card archived")
        } else {
            alwaysHiddenBookIDs.remove(id)
            hiddenBookIDs.remove(id)
            if let activeID = activeStackID, let index = stacks.firstIndex(where: { $0.id == activeID }) {
                if !stacks[index].cardIDs.contains(id) {
                    var updatedStacks = stacks
                    updatedStacks[index].cardIDs.append(id)
                    stacks = updatedStacks
                }
            }
            showToast("Card unarchived")
        }
        workspacePreferences.alwaysHiddenBookIDs = Array(alwaysHiddenBookIDs)
        persistWorkspacePreferences()
    }

    func toggleFilterScope() {
        switch filterScope {
        case .activeStack:
            filterScope = .allCards
        case .allCards:
            filterScope = .activeStack
        }
    }

    func setActiveStack(id: UUID) {
        guard stacks.contains(where: { $0.id == id }) else { return }
        activeStackID = id
        filterScope = .activeStack
    }

    @discardableResult
    func createStack(name: String, icon: String = "rectangle.stack", cardIDs: [UUID] = []) -> CardStack {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmed.isEmpty ? "New Stack" : String(trimmed.prefix(40))
        let newStack = CardStack(id: UUID(), name: finalName, icon: icon, cardIDs: cardIDs)
        var updated = stacks
        updated.append(newStack)
        stacks = updated
        activeStackID = newStack.id
        filterScope = .activeStack
        showToast("Stack '\(finalName)' created")
        return newStack
    }

    func updateStack(_ stack: CardStack) {
        if let index = stacks.firstIndex(where: { $0.id == stack.id }) {
            var updated = stacks
            updated[index] = stack
            stacks = updated
        }
    }

    func deleteStack(id: UUID) {
        guard stacks.count > 1 else {
            showToast("Cannot delete the only stack")
            return
        }
        var updated = stacks
        updated.removeAll { $0.id == id }
        stacks = updated
        if activeStackID == id {
            activeStackID = updated.first?.id
        }
        showToast("Stack deleted")
    }

    func reorderBooks(fromOffsets: IndexSet, toOffset: Int) {
        var currentOrder = orderedBooks.map(\.id)
        currentOrder.move(fromOffsets: fromOffsets, toOffset: toOffset)
        workspacePreferences.bookOrder = currentOrder
        persistWorkspacePreferences()
    }

    func persistWorkspacePreferences() {
        workspacePreferences.visibleBookIDs = visibleBooks.map(\.id)
        workspacePreferences.alwaysHiddenBookIDs = Array(alwaysHiddenBookIDs)
        try? state?.saveWorkspacePreferences(workspacePreferences)
    }

    private var expensesCache: [UUID: [Expense]] = [:]
    private var spentCache: [UUID: Int64] = [:]
    private var memoizedActivities: [Expense]? = nil
    private var memoizedActivitiesKey: String = ""

    func invalidateExpenseCaches() {
        expensesCache.removeAll()
        spentCache.removeAll()
        memoizedActivities = nil
        memoizedActivitiesKey = ""
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
        let total = expenses(for: bookID).reduce(0) { $0 + $1.amount }
        spentCache[bookID] = total
        return total
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
        let settings = try backups.startEmptyRealBook(named: name, currentDraft: draft, settings: settings)
        self.settings = settings
        draft = ExpenseDraft()
        undoExpense = nil; pendingEntry = nil
        invalidateExpenseCaches()
        showToast("Your real book is ready")
    }
    func renameRealBook(to name: String) throws {
        guard let backups else { throw BackupError.unsupported }
        settings = try backups.renameRealBook(to: name, currentDraft: draft, settings: settings)
        invalidateExpenseCaches()
        showToast("Book renamed")
    }
    private func showToast(_ text: String) { toast = text; toastID = UUID() }
    func saveDraft() {
        do {
            var expense = try draft.expense()
            let targetID = draft.bookID ?? selectedBookID ?? activeBookID
            expense.bookID = targetID
            try save(expense)
            let editing = draft.editing
            draft = ExpenseDraft(); persistDraft(); showEntry = false
            undoExpense = nil
            saveFeedback += 1
            showToast(editing ? "Expense updated" : "Expense recorded")
        } catch { self.error = error.localizedDescription }
    }
    func save(_ expense: Expense) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.save(expense)
        invalidateExpenseCaches()
    }
    func delete(_ expense: Expense) {
        do {
            guard let expenseService else { throw EntryError.corruptStore }
            try expenseService.delete(expense.id)
            invalidateExpenseCaches()
            undoExpense = expense; showToast("Expense deleted")
        } catch { self.error = error.localizedDescription }
    }
    func undoDelete() {
        guard let undoExpense else { return }
        do { try save(undoExpense); self.undoExpense = nil; showToast("Expense restored") }
        catch { self.error = error.localizedDescription }
    }
    func repeatExpense(_ expense: Expense) {
        if draftNeedsConfirmation { pendingRepeat = true; pendingEntry = expense; return }
        draft = ExpenseDraft(expense: expense); draft.id = UUID(); draft.editing = false
        draft.createdAt = .now; draft.date = .now; draft.source = "repeat"
        draft.bookID = expense.bookID ?? activeBookID
        showEntry = true
    }
    func saveCategory(_ category: ExpenseCategory) throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.saveCategory(category)
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
        draft.splitAllocations = [.init(categoryID: categoryID, amount: draft.amount)]
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
        guard draft.categoryID != category.id, undoExpense?.allocations.contains(where: { $0.categoryID == category.id }) != true,
              !settings.categoryRules.contains(where: { $0.categoryID == category.id }) else { throw CategoryError.inUse }
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.deleteCategory(category.id)
    }
    func restoreBackup(_ backup: BookBackup) throws {
        guard let backups else { throw BackupError.unsupported }
        do {
            try backups.restore(backup, currentDraft: draft, settings: settings)
            draft = backup.draft; settings = backup.settings
            expenseService?.configure(categoryRules: settings.categoryRules, archivedCategoryIDs: settings.archivedCategoryIDs)
            undoExpense = nil; pendingEntry = nil; toast = nil
        } catch {
            if backups.requiresRecovery { startupError = error.localizedDescription }
            throw error
        }
    }

    func restoreWorkspaceBackup(_ backup: WorkspaceBackup) throws {
        guard let backups else { throw BackupError.unsupported }
        do {
            try backups.restoreWorkspace(backup, currentDraft: draft, settings: settings)
            if let first = backup.books.first {
                draft = first.draft ?? ExpenseDraft()
            }
            settings = backup.settings
            workspacePreferences = backup.preferences
            hiddenBookIDs = Set(books.map(\.id).filter { !backup.preferences.visibleBookIDs.contains($0) })
            expenseService?.configure(categoryRules: settings.categoryRules, archivedCategoryIDs: settings.archivedCategoryIDs)
            undoExpense = nil; pendingEntry = nil; toast = nil
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
        try expenseService.save(budget)
        var proposed = settings
        proposed.budget = overallLimit
        proposed.startDay = startDay
        do {
            try requireState().saveSettings(proposed)
        } catch {
            settings = proposed
            throw error
        }
        settings = proposed
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
