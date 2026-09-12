import Foundation

enum BillRecurrence: Codable, Equatable, Hashable, Sendable {
    case monthly(day: Int)
    case weekly(weekday: Int)
    case yearly(month: Int, day: Int)

    var title: String {
        switch self {
        case .monthly(let day):
            return "Monthly on day \(day)"
        case .weekly(let weekday):
            let symbols = Calendar.current.weekdaySymbols
            let idx = max(0, min(symbols.count - 1, weekday - 1))
            return "Weekly on \(symbols[idx])"
        case .yearly(let month, let day):
            let symbols = Calendar.current.monthSymbols
            let idx = max(0, min(symbols.count - 1, month - 1))
            return "Yearly on \(symbols[idx]) \(day)"
        }
    }

    var shortTitle: String {
        switch self {
        case .monthly(let day):
            return "Day \(day)"
        case .weekly(let weekday):
            let symbols = Calendar.current.shortWeekdaySymbols
            let idx = max(0, min(symbols.count - 1, weekday - 1))
            return symbols[idx]
        case .yearly(let month, let day):
            let symbols = Calendar.current.shortMonthSymbols
            let idx = max(0, min(symbols.count - 1, month - 1))
            return "\(symbols[idx]) \(day)"
        }
    }
}

enum BillRecordingMode: String, Codable, CaseIterable, Sendable {
    case automatic = "automatic"
    case pending = "pending"

    var title: String {
        switch self {
        case .automatic: return "Record automatically"
        case .pending: return "Confirm before recording"
        }
    }

    var subtitle: String {
        switch self {
        case .automatic: return "Automatically records an expense on the due date."
        case .pending: return "Requires your confirmation before recording an expense."
        }
    }
}

enum BillOccurrenceStatus: String, Codable, CaseIterable, Sendable {
    case pending = "pending"
    case recorded = "recorded"
    case skipped = "skipped"
}

struct BillRule: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var bookID: UUID
    var name: String
    var amount: Int64
    var categoryID: UUID
    var recurrence: BillRecurrence
    var recordingMode: BillRecordingMode
    var hasReminder: Bool
    var reminderLeadDays: Int
    var createdAt: Date
    var isActive: Bool

    init(
        id: UUID = UUID(),
        bookID: UUID,
        name: String,
        amount: Int64,
        categoryID: UUID,
        recurrence: BillRecurrence,
        recordingMode: BillRecordingMode = .pending,
        hasReminder: Bool = true,
        reminderLeadDays: Int = 0,
        createdAt: Date = .now,
        isActive: Bool = true
    ) {
        self.id = id
        self.bookID = bookID
        self.name = name
        self.amount = amount
        self.categoryID = categoryID
        self.recurrence = recurrence
        self.recordingMode = recordingMode
        self.hasReminder = hasReminder
        self.reminderLeadDays = reminderLeadDays
        self.createdAt = createdAt
        self.isActive = isActive
    }

    func validate(categories: [ExpenseCategory]) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 40 else { throw BillError.invalidName }
        guard amount > 0, amount <= Money.maximum else { throw BillError.invalidAmount }
        guard categories.contains(where: { $0.id == categoryID }) else { throw BillError.missingCategory }
        switch recurrence {
        case .monthly(let day):
            guard (1...31).contains(day) else { throw BillError.invalidRecurrence }
        case .weekly(let weekday):
            guard (1...7).contains(weekday) else { throw BillError.invalidRecurrence }
        case .yearly(let month, let day):
            guard (1...12).contains(month), (1...31).contains(day) else { throw BillError.invalidRecurrence }
        }
        guard reminderLeadDays >= 0 && reminderLeadDays <= 30 else { throw BillError.invalidReminder }
    }
}

struct BillOccurrence: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var billRuleID: UUID
    var bookID: UUID
    var dueDay: String // YYYY-MM-DD
    var status: BillOccurrenceStatus
    var expenseID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        billRuleID: UUID,
        bookID: UUID,
        dueDay: String,
        status: BillOccurrenceStatus = .pending,
        expenseID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.billRuleID = billRuleID
        self.bookID = bookID
        self.dueDay = dueDay
        self.status = status
        self.expenseID = expenseID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

enum BillError: LocalizedError {
    case alreadyResolved
    case invalidName, invalidAmount, missingCategory, invalidRecurrence, invalidReminder, ruleNotFound, occurrenceNotFound

    var errorDescription: String? {
        switch self {
        case .alreadyResolved: return "This bill occurrence has already been recorded or skipped."
        case .invalidName: return "Enter a bill name up to 40 characters."
        case .invalidAmount: return "Enter a valid bill amount greater than zero."
        case .missingCategory: return "Choose a category for this bill."
        case .invalidRecurrence: return "Choose a valid bill recurrence schedule."
        case .invalidReminder: return "Reminder lead days must be between 0 and 30."
        case .ruleNotFound: return "The requested bill could not be found."
        case .occurrenceNotFound: return "The bill occurrence could not be found."
        }
    }
}
