import Foundation
import Observation
import UserNotifications

enum BillReminderAuthorization: Equatable, Sendable {
    case notDetermined, denied, authorized, unavailable
}

struct BillReminder: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
    let billRuleID: UUID
    let occurrenceID: UUID
    let bookID: UUID
}

@MainActor
protocol BillNotificationClient {
    func authorization() async -> BillReminderAuthorization
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func add(_ reminder: BillReminder) async throws
    func remove(_ identifiers: [String])
}

@MainActor
private final class SystemBillNotificationClient: BillNotificationClient {
    private let center = UNUserNotificationCenter.current()

    func authorization() async -> BillReminderAuthorization {
        switch await center.notificationSettings().authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .unavailable
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    func add(_ reminder: BillReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        content.userInfo = ["billRuleID": reminder.billRuleID.uuidString,
                            "occurrenceID": reminder.occurrenceID.uuidString,
                            "bookID": reminder.bookID.uuidString]
        var components = Day.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
        components.calendar = Day.calendar
        components.timeZone = .current
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content, trigger: trigger))
    }

    func remove(_ identifiers: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Rebuilds the complete workspace schedule from durable state. OS failures never undo a ledger commit.
@MainActor @Observable
final class BillNotificationService {
    static let shared = BillNotificationService(client: SystemBillNotificationClient())
    static let maximumPendingReminders = 64
    private static let prefix = "bill-reminder-"

    private let client: any BillNotificationClient
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private(set) var authorization: BillReminderAuthorization = .notDetermined
    private(set) var lastError: String?

    init(client: any BillNotificationClient) { self.client = client }

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await client.requestAuthorization()
            authorization = await client.authorization()
            lastError = granted ? nil : "Bill reminders are disabled in notification settings."
            return granted
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func reconcile(rules: [BillRule], occurrences: [BillOccurrence], asOf date: Date = .now,
                   requestAuthorization: Bool = false) {
        let desired = Self.desiredReminders(rules: rules, occurrences: occurrences, asOf: date)
        let previous = task
        previous?.cancel()
        let current = UUID()
        generation = current
        task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            if requestAuthorization, await client.authorization() == .notDetermined {
                _ = await self.requestAuthorization()
            }
            authorization = await client.authorization()
            let pending = await client.pendingIdentifiers()
            guard !Task.isCancelled else { return }
            let nonBillCount = pending.filter { !$0.hasPrefix(Self.prefix) }.count
            let capacity = max(0, Self.maximumPendingReminders - nonBillCount)
            let admitted = authorization == .authorized ? Array(desired.prefix(capacity)) : []
            let admittedIDs = Set(admitted.map(\.identifier))
            client.remove(pending.filter { $0.hasPrefix(Self.prefix) && !admittedIDs.contains($0) })
            if authorization == .authorized {
                lastError = nil
                for reminder in admitted {
                    guard !Task.isCancelled else { break }
                    do { try await client.add(reminder) }
                    catch { lastError = error.localizedDescription }
                    // A replacement reconciliation waits for this task before applying its desired state.
                }
            } else if authorization == .denied {
                lastError = "Bill reminders are disabled in notification settings."
            }
            if generation == current { task = nil }
        }
    }

    func waitForReconciliation() async { await task?.value }

    static func desiredReminders(rules: [BillRule], occurrences: [BillOccurrence], asOf date: Date) -> [BillReminder] {
        let byID = Dictionary(rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return occurrences.compactMap { occurrence in
            guard occurrence.status == .pending, let rule = byID[occurrence.billRuleID],
                  rule.bookID == occurrence.bookID, rule.hasReminder, rule.isActive,
                  let due = Day.date(occurrence.dueDay),
                  let leadDate = Day.calendar.date(byAdding: .day, value: -rule.reminderLeadDays, to: due),
                  let fireDate = Day.calendar.date(bySettingHour: 9, minute: 0, second: 0, of: leadDate),
                  fireDate > date else { return nil }
            return BillReminder(identifier: Self.prefix + occurrence.id.uuidString,
                title: "Bill Due: \(rule.name)",
                body: "\(Money.format(rule.amount)) is due on \(Day.title(occurrence.dueDay)).",
                fireDate: fireDate, billRuleID: rule.id, occurrenceID: occurrence.id, bookID: rule.bookID)
        }.sorted { $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate }
    }
}
