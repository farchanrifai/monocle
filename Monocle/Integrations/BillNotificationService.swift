import Foundation
import UserNotifications

@MainActor
final class BillNotificationService {
    static let shared = BillNotificationService()

    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {}

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleReminder(for occurrence: BillOccurrence, rule: BillRule) async {
        guard rule.hasReminder else { return }
        guard let dueDate = Day.date(occurrence.dueDay) else { return }

        var calendar = Calendar.current
        calendar.timeZone = .current
        let reminderDate = calendar.date(byAdding: .day, value: -rule.reminderLeadDays, to: dueDate) ?? dueDate

        var dateComponents = calendar.dateComponents([.year, .month, .day], from: reminderDate)
        dateComponents.hour = 9
        dateComponents.minute = 0

        guard let fireDate = calendar.date(from: dateComponents), fireDate > Date.now else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Bill Due: \(rule.name)"
        content.body = "\(Money.format(rule.amount)) is due on \(Day.title(occurrence.dueDay))."
        content.sound = .default
        content.userInfo = [
            "billRuleID": rule.id.uuidString,
            "occurrenceID": occurrence.id.uuidString,
            "bookID": rule.bookID.uuidString
        ]

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let identifier = notificationIdentifier(for: occurrence.id)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        try? await notificationCenter.add(request)
    }

    func cancelReminder(for occurrenceID: UUID) {
        let identifier = notificationIdentifier(for: occurrenceID)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelAllReminders(for ruleID: UUID, occurrences: [BillOccurrence]) {
        let identifiers = occurrences.filter { $0.billRuleID == ruleID }.map { notificationIdentifier(for: $0.id) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func notificationIdentifier(for occurrenceID: UUID) -> String {
        "bill-reminder-\(occurrenceID.uuidString)"
    }
}
