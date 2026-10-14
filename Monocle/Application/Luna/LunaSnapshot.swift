import Foundation

/// What Monocle tells the owner's Luna server (schema 1, `luna/docs/PLAN.md` §8): cards, bills with nearby occurrences,
/// budget status and monthly totals. Never individual expenses or notes. Amounts are Monocle's minor units (scale 100).
/// Encode with `LunaSnapshot.encoder`; keys come out snake_case.
struct LunaSnapshot: Encodable, Equatable {
    enum Part: String, CaseIterable, Sendable { case bills, budgets, summary }

    let schema = 1
    var storeID: String
    /// Milliseconds since 1970: grows across launches (`ExpenseService.committedRevision` restarts at 0 every launch).
    var revision: Int64
    var generatedAt: String
    /// Which parts the owner chose to share; a part not listed is absent, not empty.
    var categories: [String]
    var cards: [CardInfo]
    var bills: [BillInfo]?
    var budgets: [BudgetInfo]?
    var summary: [MonthSummary]?

    struct CardInfo: Encodable, Equatable {
        var id: String, name: String, currency: String
        let minorUnitScale = 100
    }

    struct BillInfo: Encodable, Equatable {
        struct Recurrence: Encodable, Equatable { var type: String; var day: Int?; var weekday: Int?; var month: Int? }
        struct Occurrence: Encodable, Equatable { var id: String, dueDay: String, status: String }
        var id: String, cardID: String, name: String
        var amountMinor: Int64
        var recurrence: Recurrence
        var mode: String
        var active: Bool
        var occurrences: [Occurrence]

        /// Occurrences from 30 days back to 60 days ahead of `now`.
        init(_ bill: Bill, occurrences all: [BillOccurrence], now: Date, calendar: Calendar = Day.calendar) {
            let from = Day.string(calendar.date(byAdding: .day, value: -30, to: now)!, calendar: calendar)
            let to = Day.string(calendar.date(byAdding: .day, value: 60, to: now)!, calendar: calendar)
            id = bill.id.uuidString; cardID = bill.cardID.uuidString; name = bill.name; amountMinor = bill.amount
            mode = bill.recordingMode.rawValue; active = bill.isActive
            switch bill.recurrence {
            case .monthly(let day): recurrence = .init(type: "monthly", day: day)
            case .weekly(let weekday): recurrence = .init(type: "weekly", weekday: weekday)
            case .yearly(let month, let day): recurrence = .init(type: "yearly", day: day, month: month)
            }
            occurrences = all.filter { $0.billRuleID == bill.id && $0.dueDay >= from && $0.dueDay <= to }
                .sorted { $0.dueDay < $1.dueDay }
                .map { .init(id: $0.id.uuidString, dueDay: $0.dueDay, status: $0.status.rawValue) }
        }
    }

    struct BudgetInfo: Encodable, Equatable {
        struct Pace: Encodable, Equatable { var state: String; var percent: Int? }
        struct Line: Encodable, Equatable { var name: String; var limitMinor: Int64?; var spentMinor: Int64 }
        var subject: String, id: String, name: String, currency: String
        /// `cycleEnd` is exclusive.
        var cycleStart: String, cycleEnd: String
        var limitMinor: Int64, spentMinor: Int64, remainingMinor: Int64
        var isGoal: Bool, approximate: Bool
        var projectedMinor: Int64?
        var pace: Pace?
        var lines: [Line]

        init(name: String, status: BudgetStatus, calendar: Calendar = Day.calendar) {
            switch status.subject {
            case .card(let id): subject = "card"; self.id = id.uuidString
            case .stack(let id): subject = "stack"; self.id = id.uuidString
            }
            self.name = name; currency = status.currency
            cycleStart = Day.string(status.cycle.start, calendar: calendar); cycleEnd = Day.string(status.cycle.end, calendar: calendar)
            limitMinor = status.limit; spentMinor = status.spent; remainingMinor = status.remaining
            isGoal = status.isGoal; approximate = status.approximate; projectedMinor = status.projected
            switch status.pace {
            case .underPace(let pct): pace = .init(state: "under", percent: pct)
            case .onTrack: pace = .init(state: "on_track")
            case .accelerated(let pct): pace = .init(state: "above", percent: pct)
            case .beyondRange: pace = .init(state: "beyond")
            case nil: pace = nil
            }
            lines = status.lines.map { .init(name: $0.name, limitMinor: $0.limit, spentMinor: $0.spent) }
        }
    }

    struct MonthSummary: Encodable, Equatable {
        struct CategoryTotal: Encodable, Equatable { var category: String; var totalMinor: Int64 }
        var cardID: String, currency: String
        /// `YYYY-MM`.
        var month: String
        var totalMinor: Int64
        var transactionCount: Int
        var byCategory: [CategoryTotal]

        /// One card's month in the card's currency. `amount` is the expense in that currency; split amounts are scaled to match,
        // ponytail: so category totals can differ from `totalMinor` by rounding when the card isn't in the reporting currency.
        init(card: UUID, currency: String, month: String, expenses: [Expense], categoryNames: [UUID: String], amount: (Expense) -> Int64) {
            cardID = card.uuidString; self.currency = currency; self.month = month
            let inMonth = expenses.filter { $0.day.hasPrefix(month) }
            transactionCount = inMonth.count
            var total: Int64 = 0
            var perCategory: [String: Int64] = [:]
            for expense in inMonth {
                let value = amount(expense)
                total += value
                if expense.splits.isEmpty { perCategory["Uncategorized", default: 0] += value; continue }
                for split in expense.splits {
                    let scaled = value == expense.amount || expense.amount == 0
                        ? split.amount : Int64((Double(split.amount) * Double(value) / Double(expense.amount)).rounded())
                    perCategory[categoryNames[split.categoryID] ?? "Other", default: 0] += scaled
                }
            }
            totalMinor = total
            byCategory = perCategory.map { .init(category: $0.key, totalMinor: $0.value) }
                .sorted { ($0.totalMinor, $1.category) > ($1.totalMinor, $0.category) }
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static func isoString(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
