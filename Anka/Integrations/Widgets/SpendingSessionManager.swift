@preconcurrency import ActivityKit
import Foundation
import Observation

@MainActor
protocol SessionActivityHandle: AnyObject {
    var attributes: SpendingActivityAttributes { get }
    var state: SpendingActivityAttributes.ContentState { get }
    func update(_ state: SpendingActivityAttributes.ContentState) async
    func end(_ state: SpendingActivityAttributes.ContentState) async
}

@MainActor
protocol SessionActivityClient {
    var isEnabled: Bool { get }
    var existing: [any SessionActivityHandle] { get }
    func request(attributes: SpendingActivityAttributes, state: SpendingActivityAttributes.ContentState) throws -> any SessionActivityHandle
}

@MainActor
private final class SystemSessionActivity: SessionActivityHandle {
    let activity: Activity<SpendingActivityAttributes>
    init(_ activity: Activity<SpendingActivityAttributes>) { self.activity = activity }
    var attributes: SpendingActivityAttributes { activity.attributes }
    var state: SpendingActivityAttributes.ContentState { activity.content.state }
    func update(_ state: SpendingActivityAttributes.ContentState) async { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    func end(_ state: SpendingActivityAttributes.ContentState) async { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate) }
}

@MainActor
private struct SystemSessionActivityClient: SessionActivityClient {
    var isEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    var existing: [any SessionActivityHandle] { Activity<SpendingActivityAttributes>.activities.map { SystemSessionActivity($0) } }
    func request(attributes: SpendingActivityAttributes, state: SpendingActivityAttributes.ContentState) throws -> any SessionActivityHandle {
        SystemSessionActivity(try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil)))
    }
}

@MainActor @Observable
public final class SpendingSessionManager {
    public static let shared = SpendingSessionManager()

    public private(set) var isSessionActive: Bool = false
    public private(set) var sessionName: String = ""
    public private(set) var sessionCardID: UUID? = nil
    public private(set) var sessionBudgetLimit: Int64? = nil
    public private(set) var sessionSpent: Int64 = 0
    public private(set) var sessionItemCount: Int = 0
    public private(set) var sessionStartTime: Date? = nil
    public private(set) var latestItemNote: String? = nil
    public private(set) var latestItemCategorySymbol: String? = nil

    public private(set) var activityError: String?
    private let activityClient: any SessionActivityClient
    private var currentActivity: (any SessionActivityHandle)?

    init(activityClient: (any SessionActivityClient)? = nil) {
        let client = activityClient ?? SystemSessionActivityClient()
        self.activityClient = client
        // Reconnect to active running Live Activity on app launch
        if client.isEnabled {
            if let existing = client.existing.first {
                self.currentActivity = existing
                self.isSessionActive = true
                self.sessionName = existing.attributes.sessionName
                self.sessionCardID = existing.attributes.cardID
                self.sessionStartTime = existing.attributes.startTime
                self.sessionSpent = existing.state.currentSpent
                self.sessionItemCount = existing.state.itemCount
                self.sessionBudgetLimit = existing.state.sessionBudgetLimit
                self.latestItemNote = existing.state.latestItemNote
                self.latestItemCategorySymbol = existing.state.latestItemCategorySymbol
            }
        }
    }

    public func startSession(name: String, cardName: String, cardID: UUID? = nil, budgetLimit: Int64? = nil) {
        if isSessionActive {
            endSession()
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? "Spending Session" : trimmedName
        self.sessionName = finalName
        self.sessionCardID = cardID
        self.sessionBudgetLimit = budgetLimit
        self.sessionSpent = 0
        self.sessionItemCount = 0
        let start = Date.now
        self.sessionStartTime = start
        self.latestItemNote = nil
        self.latestItemCategorySymbol = nil
        self.isSessionActive = true

        activityError = nil
        guard activityClient.isEnabled else {
            activityError = "Live Activities are disabled. The session remains available in Anka."
            return
        }

        let attributes = SpendingActivityAttributes(sessionName: finalName, cardName: cardName, startTime: start, cardID: cardID)
        let state = SpendingActivityAttributes.ContentState(
            currentSpent: 0,
            itemCount: 0,
            latestItemNote: nil,
            latestItemCategorySymbol: nil,
            sessionBudgetLimit: budgetLimit,
            isPaused: false
        )

        do {
            let activity = try activityClient.request(attributes: attributes, state: state)
            self.currentActivity = activity
        } catch {
            activityError = "The Live Activity could not start: \(error.localizedDescription)"
        }
    }

    public func recordExpense(amount: Int64, note: String?, categorySymbol: String?, cardID: UUID? = nil) {
        guard isSessionActive, amount > 0, sessionCardID == nil || cardID == sessionCardID else { return }
        let nextSpent = sessionSpent.addingReportingOverflow(amount)
        guard !nextSpent.overflow else { activityError = "The session total exceeds the supported amount range."; return }
        sessionSpent = nextSpent.partialValue
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
        let activity = currentActivity
        Task { await activity?.update(state) }
    }

    public func endSession() {
        guard isSessionActive else { return }
        isSessionActive = false
        let state = SpendingActivityAttributes.ContentState(
            currentSpent: sessionSpent,
            itemCount: sessionItemCount,
            latestItemNote: latestItemNote,
            latestItemCategorySymbol: latestItemCategorySymbol,
            sessionBudgetLimit: sessionBudgetLimit,
            isPaused: false
        )
        let activity = currentActivity
        currentActivity = nil
        Task { await activity?.end(state) }
        sessionStartTime = nil
        sessionCardID = nil
    }
}
