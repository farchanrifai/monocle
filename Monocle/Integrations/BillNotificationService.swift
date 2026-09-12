import Foundation
import UserNotifications

@MainActor
final class BillNotificationService {
    static let shared = BillNotificationService()

    private let notificationCenter = UNUserNotificationCenter.current()

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var generations: [UUID: UUID] = [:]

    private init() {}

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func scheduleReminder(for occurrence: BillOccurrence, rule: BillRule) {
        let id = occurrence.id
        let previous = tasks[id]
        previous?.cancel()
        let generation = UUID()
        generations[id] = generation
        tasks[id] = Task {
            // Serialize replacement with a pending add so cancellation cannot resurrect a reminder.
            await previous?.value
            if !Task.isCancelled {
                await addReminder(for: occurrence, rule: rule)
                if Task.isCancelled {
                    notificationCenter.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier(for: id)])
                }
            }
            if generations[id] == generation {
                tasks[id] = nil
                generations[id] = nil
            }
        }
    }

    private func addReminder(for occurrence: BillOccurrence, rule: BillRule) async {
        guard rule.hasReminder, rule.isActive, occurrence.status == .pending else { return }
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
        tasks[occurrenceID]?.cancel()
        let identifier = notificationIdentifier(for: occurrenceID)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    func cancelAllReminders(for ruleID: UUID, occurrences: [BillOccurrence]) {
        for occurrence in occurrences where occurrence.billRuleID == ruleID {
            cancelReminder(for: occurrence.id)
        }
    }

    private func notificationIdentifier(for occurrenceID: UUID) -> String {
        "bill-reminder-\(occurrenceID.uuidString)"
    }
}
