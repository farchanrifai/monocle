import Foundation

/// What a budget screen or chart is about. A stack budget is derived: its cap, or the sum of its cards' budgets.
enum BudgetSubject: Equatable, Hashable, Sendable {
    case card(UUID)
    case stack(UUID)
}

/// One row under a budget: a category (card budget) or a member card (stack budget).
struct BudgetLine: Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let limit: Int64?
    let spent: Int64
}

/// Computed, never stored. Budget screens and analytics both read this so they cannot disagree.
struct BudgetStatus: Equatable, Sendable {
    let subject: BudgetSubject
    let currency: String
    let cycle: Cycle
    let limit: Int64
    let spent: Int64
    let isGoal: Bool
    let isTransition: Bool
    let pace: SpendingPaceStatus?
    let projected: Int64?
    let lines: [BudgetLine]
    /// A stack total that mixes currencies, converted at today's cached rate.
    let approximate: Bool

    var remaining: Int64 { limit - spent }
    var fraction: Double { Double(spent) / Double(max(1, limit)) }
}

/// One finished (or the running) cycle of a budget: what was allowed against what was spent.
struct BudgetCycleResult: Identifiable, Equatable, Sendable {
    let cycle: Cycle
    let limit: Int64
    let spent: Int64
    let isCurrent: Bool
    let isGoal: Bool
    var id: Date { cycle.start }
    var isOver: Bool { spent > limit }
}

struct BudgetCardInput {
    var card: Card
    var budgets: [BudgetVersion]
    var expenses: [Expense]
    var categories: [ExpenseCategory]
    var currency: String
    /// An expense in the card's currency (display only).
    var amount: (Expense) -> Int64
}

struct BudgetStackInput {
    var stack: Stack
    var cards: [BudgetCardInput]
    var reportingCurrency: String
    /// Converts `amount` between currencies with the newest cached rate; nil when no rate is cached.
    var convert: (Int64, String, String) -> Int64?
}

enum BudgetReport {
    // MARK: Card

    static func card(_ input: BudgetCardInput, now: Date = .now, calendar: Calendar = Day.calendar) -> BudgetStatus? {
        guard let period = BudgetHistory.period(containing: now, budgets: input.budgets, calendar: calendar) else { return nil }
        let inCycle = input.expenses.filter { period.cycle.contains($0) }
        let spent = Money.sum(inCycle.map(input.amount))
        let (elapsed, total) = days(in: period.cycle, now: now)
        return BudgetStatus(
            subject: .card(input.card.id), currency: input.currency, cycle: period.cycle,
            limit: period.budget.overallLimit, spent: spent,
            isGoal: period.budget.totalUntilDay != nil, isTransition: period.isTransition,
            pace: AnalyticsEngine.paceStatus(spent: spent, budget: period.budget.overallLimit, daysElapsed: elapsed, totalDays: total),
            projected: try? Money.checkedScale(spent, numerator: total, denominator: elapsed),
            lines: categoryLines(input, budget: period.budget, expenses: inCycle), approximate: false)
    }

    /// The running cycle and the ones before it (oldest first), as far back as the budget history goes.
    static func cardHistory(_ input: BudgetCardInput, count: Int, now: Date = .now, calendar: Calendar = Day.calendar) -> [BudgetCycleResult] {
        var results: [BudgetCycleResult] = []
        var date = now
        while results.count < count, let period = BudgetHistory.period(containing: date, budgets: input.budgets, calendar: calendar) {
            let spent = Money.sum(input.expenses.filter { period.cycle.contains($0) }.map(input.amount))
            results.append(BudgetCycleResult(cycle: period.cycle, limit: period.budget.overallLimit, spent: spent,
                                             isCurrent: results.isEmpty, isGoal: period.budget.totalUntilDay != nil))
            guard let previous = period.cycle.calendar.date(byAdding: .day, value: -1, to: period.cycle.start) else { break }
            date = previous
        }
        return results.reversed()
    }

    // MARK: Stack

    static func stack(_ input: BudgetStackInput, now: Date = .now, calendar: Calendar = Day.calendar) -> BudgetStatus? {
        let cycle = Cycle.containing(now, startDay: input.stack.capStartDay ?? 1, calendar: calendar)
        guard let value = stackCycle(input, cycle: cycle, now: now, calendar: calendar) else { return nil }
        let (elapsed, total) = days(in: cycle, now: now)
        return BudgetStatus(
            subject: .stack(input.stack.id), currency: input.reportingCurrency, cycle: cycle,
            limit: value.limit, spent: value.spent, isGoal: false, isTransition: false,
            pace: AnalyticsEngine.paceStatus(spent: value.spent, budget: value.limit, daysElapsed: elapsed, totalDays: total),
            projected: try? Money.checkedScale(value.spent, numerator: total, denominator: elapsed),
            lines: value.lines, approximate: value.approximate)
    }

    /// Past stack cycles sum the cards' budgets that applied then; the cap, if set, is today's cap.
    static func stackHistory(_ input: BudgetStackInput, count: Int, now: Date = .now, calendar: Calendar = Day.calendar) -> [BudgetCycleResult] {
        var results: [BudgetCycleResult] = []
        var date = now
        while results.count < count {
            let cycle = Cycle.containing(date, startDay: input.stack.capStartDay ?? 1, calendar: calendar)
            guard let value = stackCycle(input, cycle: cycle, now: now, calendar: calendar) else { break }
            results.append(BudgetCycleResult(cycle: cycle, limit: value.limit, spent: value.spent, isCurrent: results.isEmpty, isGoal: false))
            guard let previous = cycle.calendar.date(byAdding: .day, value: -1, to: cycle.start) else { break }
            date = previous
        }
        return results.reversed()
    }

    // MARK: Helpers

    private static func stackCycle(_ input: BudgetStackInput, cycle: Cycle, now: Date, calendar: Calendar)
        -> (limit: Int64, spent: Int64, lines: [BudgetLine], approximate: Bool)? {
        // Budgets as of the cycle's last day, or today inside the running cycle.
        let lastDay = cycle.calendar.date(byAdding: .day, value: -1, to: cycle.end) ?? cycle.end
        let asOf = min(now, lastDay)
        var spent: Int64 = 0, approximate = false
        var limits: [Int64] = [], lines: [BudgetLine] = []
        for card in input.cards {
            let inCycle = card.expenses.filter { cycle.contains($0) }
            spent += Money.sum(inCycle.map(\.amount))
            var cardLimit: Int64?
            if let version = BudgetHistory.active(on: asOf, budgets: card.budgets, calendar: calendar), version.totalUntilDay == nil {
                cardLimit = version.overallLimit
                if card.currency == input.reportingCurrency {
                    limits.append(version.overallLimit)
                } else {
                    approximate = true
                    limits.append(input.convert(version.overallLimit, card.currency, input.reportingCurrency) ?? version.overallLimit)
                }
            }
            lines.append(BudgetLine(id: card.card.id, name: card.card.name, limit: cardLimit, spent: Money.sum(inCycle.map(card.amount))))
        }
        guard let limit = input.stack.budgetLimit(cardLimits: limits) else { return nil }
        return (limit, spent, lines, approximate)
    }

    /// Categories with a limit or any spend, limited ones first, then by spend.
    private static func categoryLines(_ input: BudgetCardInput, budget: BudgetVersion, expenses: [Expense]) -> [BudgetLine] {
        var spentBy: [UUID: Int64] = [:]
        for expense in expenses {
            let total = input.amount(expense)
            for part in expense.splits {
                let share = (try? Money.checkedScale(total, numerator: Int(truncatingIfNeeded: part.amount),
                                                     denominator: Int(truncatingIfNeeded: max(1, expense.amount)))) ?? 0
                spentBy[part.categoryID, default: 0] += share
            }
        }
        return input.categories.compactMap { category -> BudgetLine? in
            let limit = budget.limit(for: category.id), spent = spentBy[category.id] ?? 0
            guard limit != nil || spent > 0 else { return nil }
            return BudgetLine(id: category.id, name: category.name, limit: limit, spent: spent)
        }.sorted {
            ($0.limit != nil) != ($1.limit != nil) ? $0.limit != nil : $0.spent > $1.spent
        }
    }

    /// Days elapsed (today included, at least 1) and total days of a cycle.
    static func days(in cycle: Cycle, now: Date) -> (elapsed: Int, total: Int) {
        let calendar = cycle.calendar
        let total = max(1, calendar.dateComponents([.day], from: cycle.start, to: cycle.end).day ?? 1)
        let passed = calendar.dateComponents([.day], from: cycle.start, to: calendar.startOfDay(for: now)).day ?? 0
        return (min(total, max(1, passed + 1)), total)
    }
}
