import Foundation

struct ReconciliationResult: Equatable {
    var newOccurrences: [BillOccurrence]
    var autoExpenses: [Expense]
    var retiredOccurrenceIDs: [UUID]

    init(newOccurrences: [BillOccurrence] = [], autoExpenses: [Expense] = [], retiredOccurrenceIDs: [UUID] = []) {
        self.newOccurrences = newOccurrences
        self.autoExpenses = autoExpenses
        self.retiredOccurrenceIDs = retiredOccurrenceIDs
    }
}

enum BillReconciliationEngine {
    /// Generates due day strings for a bill rule within a given date window.
    static func dueDays(
        for rule: Bill,
        from startDate: Date,
        to endDate: Date,
        calendar: Calendar = Day.calendar
    ) -> [String] {
        let calendar = Day.reportingCalendar(calendar)
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
        rule: Bill,
        existingOccurrences: [BillOccurrence],
        asOf date: Date = .now,
        lookaheadDays: Int = 30,
        calendar: Calendar = Day.calendar
    ) -> ReconciliationResult {
        guard rule.isActive else { return ReconciliationResult() }
        let calendar = Day.reportingCalendar(calendar)

        let todayString = Day.string(date, calendar: calendar)
        let effectiveDate = rule.scheduleEffectiveDay.flatMap { Day.date($0, calendar: calendar) } ?? rule.createdAt
        let startDate = max(calendar.startOfDay(for: rule.createdAt), calendar.startOfDay(for: effectiveDate))
        let endDate = calendar.date(byAdding: .day, value: max(0, lookaheadDays), to: date) ?? date

        let allDueDays = dueDays(for: rule, from: startDate, to: endDate, calendar: calendar)
        let scheduledDays = Set(allDueDays)
        let existing = existingOccurrences.filter { $0.billRuleID == rule.id && $0.cardID == rule.cardID }
        let existingDueDays = Set(existing.map(\.dueDay))

        var newOccurrences: [BillOccurrence] = []
        var autoExpenses: [Expense] = []

        // Lookahead creates pending occurrences; promote them when their due day arrives.
        for var occurrence in existing where occurrence.status == .pending && scheduledDays.contains(occurrence.dueDay) && occurrence.dueDay <= todayString && rule.recordingMode == .automatic {
            let expenseID = UUID()
            let occurrenceDate = Day.date(occurrence.dueDay, calendar: calendar) ?? date
            autoExpenses.append(Expense(id: expenseID, amount: rule.amount, day: occurrence.dueDay,
                note: rule.name, splits: [.init(categoryID: rule.categoryID, amount: rule.amount)],
                source: "bill-automatic", createdAt: occurrenceDate, cardID: rule.cardID))
            occurrence.status = .recorded
            occurrence.expenseID = expenseID
            occurrence.updatedAt = date
            newOccurrences.append(occurrence)
        }

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
                    splits: [.init(categoryID: rule.categoryID, amount: rule.amount)],
                    source: "bill-automatic",
                    createdAt: occurrenceDate,
                    cardID: rule.cardID
                )

                let occurrence = BillOccurrence(
                    id: occurrenceID,
                    billRuleID: rule.id,
                    cardID: rule.cardID,
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
                    cardID: rule.cardID,
                    dueDay: dueDay,
                    status: .pending,
                    expenseID: nil,
                    createdAt: occurrenceDate,
                    updatedAt: date
                )

                newOccurrences.append(occurrence)
            }
        }

        let effectiveDay = Day.string(startDate, calendar: calendar)
        let retired = existing.filter {
            $0.status == .pending && $0.dueDay >= effectiveDay && $0.dueDay <= Day.string(endDate, calendar: calendar) && !scheduledDays.contains($0.dueDay)
        }.map(\.id)
        return ReconciliationResult(newOccurrences: newOccurrences, autoExpenses: autoExpenses, retiredOccurrenceIDs: retired)
    }
}
