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
            let symbols = Day.calendar.weekdaySymbols
            let idx = max(0, min(symbols.count - 1, weekday - 1))
            return "Weekly on \(symbols[idx])"
        case .yearly(let month, let day):
            let symbols = Day.calendar.monthSymbols
            let idx = max(0, min(symbols.count - 1, month - 1))
            return "Yearly on \(symbols[idx]) \(day)"
        }
    }

    var shortTitle: String {
        switch self {
        case .monthly(let day):
            return "Day \(day)"
        case .weekly(let weekday):
            let symbols = Day.calendar.shortWeekdaySymbols
            let idx = max(0, min(symbols.count - 1, weekday - 1))
            return symbols[idx]
        case .yearly(let month, let day):
            let symbols = Day.calendar.shortMonthSymbols
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
    /// The current schedule starts on this civil day; handled occurrences retain their history.
    var scheduleEffectiveDay: String?
    var scheduleRevision: Int

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
        isActive: Bool = true,
        scheduleEffectiveDay: String? = nil,
        scheduleRevision: Int = 0
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
        self.scheduleEffectiveDay = scheduleEffectiveDay
        self.scheduleRevision = scheduleRevision
    }

    private enum CodingKeys: String, CodingKey {
        case id, bookID, name, amount, categoryID, recurrence, recordingMode, hasReminder
        case reminderLeadDays, createdAt, isActive, scheduleEffectiveDay, scheduleRevision
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        bookID = try values.decode(UUID.self, forKey: .bookID)
        name = try values.decode(String.self, forKey: .name)
        amount = try values.decode(Int64.self, forKey: .amount)
        categoryID = try values.decode(UUID.self, forKey: .categoryID)
        recurrence = try values.decode(BillRecurrence.self, forKey: .recurrence)
        recordingMode = try values.decode(BillRecordingMode.self, forKey: .recordingMode)
        hasReminder = try values.decode(Bool.self, forKey: .hasReminder)
        reminderLeadDays = try values.decode(Int.self, forKey: .reminderLeadDays)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        isActive = try values.decode(Bool.self, forKey: .isActive)
        scheduleEffectiveDay = try values.decodeIfPresent(String.self, forKey: .scheduleEffectiveDay)
        scheduleRevision = try values.decodeIfPresent(Int.self, forKey: .scheduleRevision) ?? 0
    }

    func validate(categories: [ExpenseCategory]) throws {
        guard createdAt.timeIntervalSince1970.isFinite else { throw EntryError.corruptStore }
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
        guard scheduleRevision >= 0,
              scheduleEffectiveDay.map({ Day.date($0) != nil }) ?? true else { throw BillError.invalidRecurrence }
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

    func validate(rules: [BillRule], expenses: [Expense], bookID: UUID? = nil) throws {
        let owner = bookID ?? self.bookID
        guard self.bookID == owner, Day.date(dueDay) != nil,
              createdAt.timeIntervalSince1970.isFinite, updatedAt.timeIntervalSince1970.isFinite,
              rules.contains(where: { $0.id == billRuleID && $0.bookID == owner }) else {
            throw EntryError.corruptStore
        }
        switch status {
        case .recorded:
            guard let expenseID,
                  expenses.contains(where: { $0.id == expenseID && ($0.bookID == nil || $0.bookID == owner) }) else {
                throw EntryError.corruptStore
            }
        case .pending, .skipped:
            guard expenseID == nil else { throw EntryError.corruptStore }
        }
    }

    static func validate(_ occurrences: [BillOccurrence], rules: [BillRule], expenses: [Expense], bookID: UUID) throws {
        guard Set(occurrences.map(\.id)).count == occurrences.count else { throw EntryError.corruptStore }
        var dueKeys = Set<String>()
        var linkedExpenses = Set<UUID>()
        for occurrence in occurrences {
            try occurrence.validate(rules: rules, expenses: expenses, bookID: bookID)
            guard dueKeys.insert("\(occurrence.billRuleID.uuidString)/\(occurrence.dueDay)").inserted else {
                throw EntryError.corruptStore
            }
            if let expenseID = occurrence.expenseID, !linkedExpenses.insert(expenseID).inserted {
                throw EntryError.corruptStore
            }
        }
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
