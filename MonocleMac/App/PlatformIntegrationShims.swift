import Foundation
import Observation

@MainActor @Observable
final class SpendingSessionManager {
    static let shared = SpendingSessionManager()

    private(set) var isSessionActive = false
    private(set) var sessionName = ""
    private(set) var sessionCardID: UUID?
    private(set) var sessionBudgetLimit: Int64?
    private(set) var sessionSpent: Int64 = 0
    private(set) var sessionItemCount = 0
    private(set) var sessionStartTime: Date?
    private(set) var latestItemNote: String?
    private(set) var latestItemCategorySymbol: String?

    private init() {}

    func startSession(name: String, cardName: String, cardID: UUID? = nil, budgetLimit: Int64? = nil) {
        sessionName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Spending Session" : name
        sessionCardID = cardID
        sessionBudgetLimit = budgetLimit
        sessionSpent = 0
        sessionItemCount = 0
        sessionStartTime = .now
        latestItemNote = nil
        latestItemCategorySymbol = nil
        isSessionActive = true
    }

    func recordExpense(amount: Int64, note: String?, categorySymbol: String?, cardID: UUID? = nil) {
        guard isSessionActive, amount > 0, sessionCardID == nil || sessionCardID == cardID else { return }
        let next = sessionSpent.addingReportingOverflow(amount)
        guard !next.overflow else { return }
        sessionSpent = next.partialValue
        sessionItemCount += 1
        latestItemNote = note
        latestItemCategorySymbol = categorySymbol
    }

    func endSession() {
        isSessionActive = false
        sessionCardID = nil
        sessionStartTime = nil
    }
}

enum WidgetSnapshotUpdater {
    static func update(
        activeCard: Card,
        activeStack: CardStack? = nil,
        allCards: [Card] = [],
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

import SwiftUI

/// The one iOS design token the shared chat views use; the rest of MonocleStyle is UIKit-bound.
enum MC {
    static let red = Color(red: 0.83, green: 0.16, blue: 0.12)
}
