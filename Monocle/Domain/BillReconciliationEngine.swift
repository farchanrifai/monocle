import Foundation

struct ReconciliationResult: Equatable {
    var newOccurrences: [BillOccurrence]
    var autoExpenses: [Expense]

    init(newOccurrences: [BillOccurrence] = [], autoExpenses: [Expense] = []) {
        self.newOccurrences = newOccurrences
        self.autoExpenses = autoExpenses
    }
}

enum BillReconciliationEngine {
    /// Generates due day strings for a bill rule within a given date window.
    static func dueDays(
        for rule: BillRule,
        from startDate: Date,
        to endDate: Date,
        calendar: Calendar = .current
    ) -> [String] {
        guard startDate <= endDate else { return [] }
        let startDayString = Day.string(startDate, calendar: calendar)
        let endDayString = Day.string(endDate, calendar: calendar)
        var result: [String] = []

        switch rule.recurrence {
        case .monthly(let targetDay):
            let startComponents = calendar.dateComponents([.year, .month], from: startDate)
            let endComponents = calendar.dateComponents([.year, .month], from: endDate)

            guard let startYear = startComponents.year, let startMonth = startComponents.month,
                  let endYear = endComponents.year, let endMonth = endComponents.month else {
                return []
            }

            var year = startYear
            var month = startMonth

            while (year < endYear) || (year == endYear && month <= endMonth) {
                if let monthDate = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                   let range = calendar.range(of: .day, in: .month, for: monthDate) {
                    let clampedDay = min(max(1, targetDay), range.count)
                    let dayString = String(format: "%04d-%02d-%02d", year, month, clampedDay)
                    if dayString >= startDayString && dayString <= endDayString {
                        result.append(dayString)
                    }
                }

                month += 1
                if month > 12 {
                    month = 1
                    year += 1
                }
            }

        case .weekly(let targetWeekday):
            var current = calendar.startOfDay(for: startDate)
            let end = calendar.startOfDay(for: endDate)

            while current <= end {
                let weekday = calendar.component(.weekday, from: current)
                if weekday == targetWeekday {
                    let dayString = Day.string(current, calendar: calendar)
                    if dayString >= startDayString && dayString <= endDayString {
                        result.append(dayString)
                    }
                }
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }

        case .yearly(let targetMonth, let targetDay):
            let startYear = calendar.component(.year, from: startDate)
            let endYear = calendar.component(.year, from: endDate)

            for year in startYear...endYear {
                if let monthDate = calendar.date(from: DateComponents(year: year, month: targetMonth, day: 1)),
                   let range = calendar.range(of: .day, in: .month, for: monthDate) {
                    let clampedDay = min(max(1, targetDay), range.count)
                    let dayString = String(format: "%04d-%02d-%02d", year, targetMonth, clampedDay)
                    if dayString >= startDayString && dayString <= endDayString {
                        result.append(dayString)
                    }
                }
            }
        }

        return result
    }

    /// Reconciles missed and upcoming bill occurrences against existing records.
    /// Idempotent: existing occurrences (recorded, skipped, or pending) are never duplicated.
    static func reconcile(
        rule: BillRule,
        existingOccurrences: [BillOccurrence],
        asOf date: Date = .now,
        lookaheadDays: Int = 30,
        calendar: Calendar = .current
    ) -> ReconciliationResult {
        guard rule.isActive else { return ReconciliationResult() }

        let todayString = Day.string(date, calendar: calendar)
        let startDate = calendar.startOfDay(for: rule.createdAt)
        let endDate = calendar.date(byAdding: .day, value: max(0, lookaheadDays), to: date) ?? date

        let allDueDays = dueDays(for: rule, from: startDate, to: endDate, calendar: calendar)
        let existingDueDays = Set(existingOccurrences.filter { $0.billRuleID == rule.id }.map(\.dueDay))

        var newOccurrences: [BillOccurrence] = []
        var autoExpenses: [Expense] = []

        for dueDay in allDueDays {
            guard !existingDueDays.contains(dueDay) else { continue }

            let isDueOrPast = (dueDay <= todayString)

            if isDueOrPast && rule.recordingMode == .automatic {
                let expenseID = UUID()
                let occurrenceID = UUID()
                let occurrenceDate = Day.date(dueDay, calendar: calendar) ?? date

                let expense = Expense(
                    id: expenseID,
                    amount: rule.amount,
                    day: dueDay,
                    note: rule.name,
                    allocations: [.init(categoryID: rule.categoryID, amount: rule.amount)],
                    source: "bill-automatic",
                    createdAt: occurrenceDate,
                    bookID: rule.bookID
                )

                let occurrence = BillOccurrence(
                    id: occurrenceID,
                    billRuleID: rule.id,
                    bookID: rule.bookID,
                    dueDay: dueDay,
                    status: .recorded,
                    expenseID: expenseID,
                    createdAt: occurrenceDate,
                    updatedAt: date
                )

                autoExpenses.append(expense)
                newOccurrences.append(occurrence)
            } else {
                let occurrenceID = UUID()
                let occurrenceDate = Day.date(dueDay, calendar: calendar) ?? date

                let occurrence = BillOccurrence(
                    id: occurrenceID,
                    billRuleID: rule.id,
                    bookID: rule.bookID,
                    dueDay: dueDay,
                    status: .pending,
                    expenseID: nil,
                    createdAt: occurrenceDate,
                    updatedAt: date
                )

                newOccurrences.append(occurrence)
            }
        }

        return ReconciliationResult(newOccurrences: newOccurrences, autoExpenses: autoExpenses)
    }
}
