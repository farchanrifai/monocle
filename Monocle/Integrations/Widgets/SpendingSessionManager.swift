@preconcurrency import ActivityKit
import Foundation
import Observation

@MainActor @Observable
public final class SpendingSessionManager {
    public static let shared = SpendingSessionManager()

    public private(set) var isSessionActive: Bool = false
    public private(set) var sessionName: String = ""
    public private(set) var sessionBudgetLimit: Int64? = nil
    public private(set) var sessionSpent: Int64 = 0
    public private(set) var sessionItemCount: Int = 0
    public private(set) var sessionStartTime: Date? = nil
    public private(set) var latestItemNote: String? = nil
    public private(set) var latestItemCategorySymbol: String? = nil

    private var currentActivity: Activity<SpendingActivityAttributes>?

    private init() {
        // Reconnect to active running Live Activity on app launch
        if ActivityAuthorizationInfo().areActivitiesEnabled {
            if let existing = Activity<SpendingActivityAttributes>.activities.first {
                self.currentActivity = existing
                self.isSessionActive = true
                self.sessionName = existing.attributes.sessionName
                self.sessionStartTime = existing.attributes.startTime
                self.sessionSpent = existing.content.state.currentSpent
                self.sessionItemCount = existing.content.state.itemCount
                self.sessionBudgetLimit = existing.content.state.sessionBudgetLimit
                self.latestItemNote = existing.content.state.latestItemNote
                self.latestItemCategorySymbol = existing.content.state.latestItemCategorySymbol
            }
        }
    }

    public func startSession(name: String, bookName: String, budgetLimit: Int64? = nil) {
        if isSessionActive {
            endSession()
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "Spending Session" : trimmedName
        self.sessionName = finalName
        self.sessionBudgetLimit = budgetLimit
        self.sessionSpent = 0
        self.sessionItemCount = 0
        let start = Date.now
        self.sessionStartTime = start
        self.latestItemNote = nil
        self.latestItemCategorySymbol = nil
        self.isSessionActive = true

        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = SpendingActivityAttributes(sessionName: finalName, bookName: bookName, startTime: start)
        let state = SpendingActivityAttributes.ContentState(
            currentSpent: 0,
            itemCount: 0,
            latestItemNote: nil,
            latestItemCategorySymbol: nil,
            sessionBudgetLimit: budgetLimit,
            isPaused: false
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
            self.currentActivity = activity
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    public func recordExpense(amount: Int64, note: String?, categorySymbol: String?) {
        guard isSessionActive else { return }
        sessionSpent += amount
        sessionItemCount += 1
        latestItemNote = note
        latestItemCategorySymbol = categorySymbol

        let state = SpendingActivityAttributes.ContentState(
            currentSpent: sessionSpent,
            itemCount: sessionItemCount,
            latestItemNote: note,
            latestItemCategorySymbol: categorySymbol,
            sessionBudgetLimit: sessionBudgetLimit,
            isPaused: false
        )
        let content = ActivityContent(state: state, staleDate: nil)
        Task { @MainActor [weak self] in
            await self?.currentActivity?.update(content)
        }
    }

    public func endSession() {
        guard isSessionActive else { return }
        isSessionActive = false
        Task { @MainActor [weak self] in
            await self?.currentActivity?.end(dismissalPolicy: .immediate)
            self?.currentActivity = nil
        }
        sessionStartTime = nil
    }
}
