import Foundation
import Observation

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

    var cycle: BudgetCycle { BudgetCycle.containing(.now, startDay: settings.startDay) }
    var cycleExpenses: [Expense] { expenses.filter { cycle.contains($0) } }
    var spent: Int64 { cycleExpenses.reduce(0) { $0 + $1.amount } }
    var remaining: Int64 { settings.budget - spent }

    init(expenses: ExpenseService, state: any LocalStateStore, draft: ExpenseDraft = ExpenseDraft(), settings: PrototypeSettings = PrototypeSettings(), appLock: AppLockController? = nil) {
        self.expenseService = expenses
        self.state = state
        self.draft = draft
        self.settings = settings
        self.appLock = appLock ?? AppLockController(timeout: settings.appLockTimeout)
    }

    init(startupFailure: String) {
        expenseService = nil
        state = nil
        appLock = AppLockController(timeout: nil)
        startupError = startupFailure
    }

    func reload() throws {
        guard let expenseService else { throw EntryError.corruptStore }
        try expenseService.reload()
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
    func openEntry() { showEntry = true }
    func edit(_ expense: Expense) {
        if draftNeedsConfirmation { pendingRepeat = false; pendingEntry = expense; return }
        draft = ExpenseDraft(expense: expense); showEntry = true
    }
    func persistDraft() {
        guard startupError == nil else { return }
        do { try requireState().saveDraft(draft) } catch { self.error = "Your draft could not be saved: \(error.localizedDescription)" }
    }
    @discardableResult
    func discardDraft() -> Bool {
        let cleared = ExpenseDraft()
        do { try requireState().saveDraft(cleared); draft = cleared; return true }
        catch { self.error = "Your draft could not be discarded: \(error.localizedDescription)"; return false }
    }
    func discardAndOpenPendingEntry() {
        guard let pendingEntry, discardDraft() else { return }
        self.pendingEntry = nil
        if pendingRepeat { repeatExpense(pendingEntry) } else { edit(pendingEntry) }
    }
    private func showToast(_ text: String) { toast = text; toastID = UUID() }
    func saveDraft() {
        do {
            let expense = try draft.expense()
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
    }
    func delete(_ expense: Expense) {
        do {
            guard let expenseService else { throw EntryError.corruptStore }
            try expenseService.delete(expense.id)
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
        draft.createdAt = .now; draft.date = .now; draft.source = "repeat"; showEntry = true
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
    func saveSettings(_ proposed: PrototypeSettings) throws {
        guard proposed.budget > 0, (1...31).contains(proposed.startDay) else { throw EntryError.invalidAmount }
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
