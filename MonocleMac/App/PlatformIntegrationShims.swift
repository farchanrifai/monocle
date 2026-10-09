import Foundation
import Observation

@MainActor @Observable
final class SpendingSessionManager {
    static let shared = SpendingSessionManager()

    private(set) var isSessionActive = false
    private(set) var sessionName = ""
    private(set) var sessionBookID: UUID?
    private(set) var sessionBudgetLimit: Int64?
    private(set) var sessionSpent: Int64 = 0
    private(set) var sessionItemCount = 0
    private(set) var sessionStartTime: Date?
    private(set) var latestItemNote: String?
    private(set) var latestItemCategorySymbol: String?

    private init() {}

    func startSession(name: String, bookName: String, bookID: UUID? = nil, budgetLimit: Int64? = nil) {
        sessionName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Spending Session" : name
        sessionBookID = bookID
        sessionBudgetLimit = budgetLimit
        sessionSpent = 0
        sessionItemCount = 0
        sessionStartTime = .now
        latestItemNote = nil
        latestItemCategorySymbol = nil
        isSessionActive = true
    }

    func recordExpense(amount: Int64, note: String?, categorySymbol: String?, bookID: UUID? = nil) {
        guard isSessionActive, amount > 0, sessionBookID == nil || sessionBookID == bookID else { return }
        let next = sessionSpent.addingReportingOverflow(amount)
        guard !next.overflow else { return }
        sessionSpent = next.partialValue
        sessionItemCount += 1
        latestItemNote = note
        latestItemCategorySymbol = categorySymbol
    }

    func endSession() {
        isSessionActive = false
        sessionBookID = nil
        sessionStartTime = nil
    }
}

enum WidgetSnapshotUpdater {
    static func update(
        activeBook: BookProfile,
        activeStack: CardStack? = nil,
        allBooks: [BookProfile] = [],
        expenses: [Expense],
        stackExpenses: [Expense] = [],
        categories: [ExpenseCategory],
        captureCategories: [ExpenseCategory]? = nil,
        budget: BudgetVersion?,
        cycle: BudgetCycle?,
        revision: UInt64? = nil
    ) {}
}

enum WidgetSnapshot { case unavailable(String) }

enum WidgetSnapshotStore {
    static func writeSnapshot(_ snapshot: WidgetSnapshot) throws {}
}
