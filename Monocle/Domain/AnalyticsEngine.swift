import Foundation

// MARK: - Enums & Data Types

enum AnalyticsTimeHorizon: String, CaseIterable, Identifiable, Sendable {
    case thisCycle = "This cycle"
    case thisMonth = "This month"
    case lastMonth = "Last month"
    case last30Days = "Last 30 days"
    case last90Days = "Last 90 days"
    case yearToDate = "Year to date"

    var id: String { rawValue }
}

enum AnalyticsScope: String, CaseIterable, Identifiable, Sendable {
    case activeCard = "Current card"
    case allCards = "All cards"

    var id: String { rawValue }
}

enum AnalyticsFilterScope: Equatable, Hashable, Sendable, Codable {
    case stack(id: UUID, name: String)
    case card(id: UUID, name: String)
    case allCards

    var title: String {
        switch self {
        case .stack(_, let name): return name
        case .card(_, let name): return name
        case .allCards: return "All cards"
        }
    }

    var subtitle: String {
        switch self {
        case .stack: return "Stack"
        case .card: return "Card"
        case .allCards: return "All cards"
        }
    }

    var icon: String {
        switch self {
        case .stack: return "square.stack.3d.up.fill"
        case .card: return "creditcard.fill"
        case .allCards: return "rectangle.stack"
        }
    }

    var isStack: Bool {
        if case .stack = self { return true }
        return false
    }

    var isCard: Bool {
        if case .card = self { return true }
        return false
    }

    var isAllCards: Bool {
        if case .allCards = self { return true }
        return false
    }
}

enum SpendingPaceStatus: Equatable, Sendable {
    case underPace(percentage: Int)
    case onTrack
    case accelerated(percentage: Int)
    case beyondRange

    var label: String {
        switch self {
        case .underPace(let pct): return "\(pct)% under budget pace"
        case .onTrack: return "On track with budget"
        case .accelerated(let pct): return "\(pct)% above budget pace"
        case .beyondRange: return "Above supported budget pace"
        }
    }
}

struct DailySpendPoint: Identifiable, Equatable, Sendable {
    var id: String { day }
    let day: String // YYYY-MM-DD
    let date: Date
    let amount: Int64
    let cumulativeAmount: Int64?
    let targetCumulativeAmount: Int64?
    let transactionCount: Int
    let isFuture: Bool

    init(
        day: String,
        date: Date,
        amount: Int64,
        cumulativeAmount: Int64?,
        targetCumulativeAmount: Int64? = nil,
        transactionCount: Int = 0,
        isFuture: Bool = false
    ) {
        self.day = day
        self.date = date
        self.amount = amount
        self.cumulativeAmount = cumulativeAmount
        self.targetCumulativeAmount = targetCumulativeAmount
        self.transactionCount = transactionCount
        self.isFuture = isFuture
    }
}

struct CategorySpendPoint: Identifiable, Equatable, Sendable, Codable {
    var id: UUID { categoryID }
    let categoryID: UUID
    let categoryName: String
    let categorySymbol: String
    let amount: Int64
    let percentage: Double // 0.0 .. 1.0
    let transactionCount: Int
    let budgetLimit: Int64?
}

struct ComparativePeriodPoint: Identifiable, Equatable, Sendable {
    var id: Int { dayIndex }
    let dayIndex: Int // 1..31
    let currentPeriodCumulative: Int64?
    let previousPeriodCumulative: Int64?
    let currentDate: Date?
    let previousDate: Date?
}

struct CardSpendPoint: Identifiable, Equatable, Sendable {
    var id: UUID { cardID }
    let cardID: UUID
    let cardName: String
    let colorIndex: Int
    let amount: Int64
    let percentage: Double
    let transactionCount: Int
}

struct AnalyticsMetrics: Equatable, Sendable {
    let totalSpend: Int64
    let dailyAverage: Int64
    let projectedPeriodTotal: Int64?
    let highestSpendDay: (day: String, amount: Int64)?
    let topCategory: (name: String, amount: Int64)?
    let transactionCount: Int
    let daysElapsed: Int
    let totalDaysInPeriod: Int
    let paceStatus: SpendingPaceStatus?

    static func == (lhs: AnalyticsMetrics, rhs: AnalyticsMetrics) -> Bool {
        lhs.totalSpend == rhs.totalSpend &&
        lhs.dailyAverage == rhs.dailyAverage &&
        lhs.projectedPeriodTotal == rhs.projectedPeriodTotal &&
        lhs.highestSpendDay?.day == rhs.highestSpendDay?.day &&
        lhs.highestSpendDay?.amount == rhs.highestSpendDay?.amount &&
        lhs.topCategory?.name == rhs.topCategory?.name &&
        lhs.topCategory?.amount == rhs.topCategory?.amount &&
        lhs.transactionCount == rhs.transactionCount &&
        lhs.daysElapsed == rhs.daysElapsed &&
        lhs.totalDaysInPeriod == rhs.totalDaysInPeriod &&
        lhs.paceStatus == rhs.paceStatus
    }
}

// MARK: - Analytics Engine

enum AnalyticsEngine {

    /// Computes the exact date boundaries (start inclusive, end exclusive/inclusive) and string days for a given horizon.
    static func dateRange(
        for horizon: AnalyticsTimeHorizon,
        currentCycle: Cycle? = nil,
        calendar: Calendar = Day.calendar,
        now: Date = .now
    ) -> (startDate: Date, endDate: Date, startDay: String, endDay: String) {
        let calendar = Day.reportingCalendar(calendar)
        let startOfToday = calendar.startOfDay(for: now)

        switch horizon {
        case .thisCycle:
            if let cycle = currentCycle {
                let end = calendar.date(byAdding: .day, value: -1, to: cycle.end) ?? cycle.start
                let sDay = Day.string(cycle.start, calendar: calendar)
                let eDay = Day.string(end, calendar: calendar)
                return (cycle.start, end, sDay, eDay)
            } else {
                // Fallback to current calendar month
                return dateRange(for: .thisMonth, currentCycle: nil, calendar: calendar, now: now)
            }

        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: startOfToday)
            let start = calendar.date(from: comps) ?? startOfToday
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? startOfToday
            let end = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? startOfToday
            return (start, end, Day.string(start, calendar: calendar), Day.string(end, calendar: calendar))

        case .lastMonth:
            let comps = calendar.dateComponents([.year, .month], from: startOfToday)
            let thisMonthStart = calendar.date(from: comps) ?? startOfToday
            let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? startOfToday
            let lastMonthEnd = calendar.date(byAdding: .day, value: -1, to: thisMonthStart) ?? startOfToday
            return (lastMonthStart, lastMonthEnd, Day.string(lastMonthStart, calendar: calendar), Day.string(lastMonthEnd, calendar: calendar))

        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: startOfToday) ?? startOfToday
            return (start, startOfToday, Day.string(start, calendar: calendar), Day.string(startOfToday, calendar: calendar))

        case .last90Days:
            let start = calendar.date(byAdding: .day, value: -89, to: startOfToday) ?? startOfToday
            return (start, startOfToday, Day.string(start, calendar: calendar), Day.string(startOfToday, calendar: calendar))

        case .yearToDate:
            let comps = calendar.dateComponents([.year], from: startOfToday)
            let start = calendar.date(from: comps) ?? startOfToday
            return (start, startOfToday, Day.string(start, calendar: calendar), Day.string(startOfToday, calendar: calendar))
        }
    }

    /// Filters a list of expenses to those falling within the specified day range [startDay, endDay].
    static func filterExpenses(
        _ expenses: [Expense],
        startDay: String,
        endDay: String
    ) -> [Expense] {
        expenses.filter { $0.day >= startDay && $0.day <= endDay }
    }

    /// Special category IDs for reconciliation
    static let uncategorizedCategoryID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    static let otherCategoryID = UUID(uuidString: "ffffffff-ffff-ffff-ffff-ffffffffffff")!

    /// Computes daily spending points with zero-gap continuity across the entire date span.
    /// Days with zero spending are included with amount 0 to preserve curve continuity.
    /// In future days within the period, target budget pace continues while actual spend is nil.
    static func calculateDailySpendPoints(
        expenses: [Expense],
        startDate: Date,
        endDate: Date,
        overallBudgetLimit: Int64? = nil,
        calendar: Calendar = Day.calendar,
        now: Date = .now
    ) -> [DailySpendPoint] {
        let calendar = Day.reportingCalendar(calendar)
        let startOfToday = calendar.startOfDay(for: now)
        guard (try? Money.checkedSum(expenses.map(\.amount))) != nil else { return [] }
        // Validated Gregorian civil strings sort chronologically; parse only the latest day.
        let latestExpenseDate = expenses.lazy.map(\.day).max().flatMap { Day.date($0, calendar: calendar) }
        let lastActualDate = max(startOfToday, latestExpenseDate ?? startOfToday)
        let endOfPeriod = calendar.startOfDay(for: endDate)

        // Group expenses by day
        var spendByDay: [String: (amount: Int64, count: Int)] = [:]
        for exp in expenses {
            let current = spendByDay[exp.day, default: (amount: 0, count: 0)]
            spendByDay[exp.day] = (amount: current.0 + exp.amount, count: current.1 + 1)
        }

        // Calculate total days in the full period for target budget line
        let fullPeriodDays = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: endOfPeriod).day ?? 0) + 1)

        var points: [DailySpendPoint] = []
        var runningTotal: Int64 = 0
        var iterDate = calendar.startOfDay(for: startDate)
        var dayIndex = 1

        while iterDate <= endOfPeriod {
            let isFutureDay = iterDate > lastActualDate
            let dayString = Day.string(iterDate, calendar: calendar)
            let dayData = isFutureDay ? (0, 0) : (spendByDay[dayString] ?? (0, 0))

            if !isFutureDay {
                runningTotal += dayData.0
            }

            var targetCumulative: Int64? = nil
            if let budgetLimit = overallBudgetLimit, budgetLimit > 0 {
                targetCumulative = try? Money.checkedScale(budgetLimit, numerator: dayIndex, denominator: fullPeriodDays)
            }

            points.append(DailySpendPoint(
                day: dayString,
                date: iterDate,
                amount: dayData.0,
                cumulativeAmount: isFutureDay ? nil : runningTotal,
                targetCumulativeAmount: targetCumulative,
                transactionCount: dayData.1,
                isFuture: isFutureDay
            ))

            guard let next = calendar.date(byAdding: .day, value: 1, to: iterDate) else { break }
            iterDate = next
            dayIndex += 1
        }

        return points
    }

    /// Computes Month-over-Month Day 1..31 cumulative spending comparison with high-performance string matching.
    static func calculateMonthOverMonthComparison(
        expenses: [Expense],
        calendar: Calendar = Day.calendar,
        now: Date = .now
    ) -> [ComparativePeriodPoint] {
        let calendar = Day.reportingCalendar(calendar)
        let startOfToday = calendar.startOfDay(for: now)
        guard (try? Money.checkedSum(expenses.map(\.amount))) != nil else { return [] }
        let thisMonthComps = calendar.dateComponents([.year, .month], from: startOfToday)
        guard let thisYear = thisMonthComps.year,
              let thisMonth = thisMonthComps.month,
              let thisMonthStart = calendar.date(from: thisMonthComps),
              let lastMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) else {
            return []
        }

        let lastMonthComps = calendar.dateComponents([.year, .month], from: lastMonthStart)
        guard let lastYear = lastMonthComps.year,
              let lastMonth = lastMonthComps.month else {
            return []
        }

        let thisMonthPrefix = String(format: "%04d-%02d-", thisYear, thisMonth)
        let lastMonthPrefix = String(format: "%04d-%02d-", lastYear, lastMonth)

        let thisMonthRange = calendar.range(of: .day, in: .month, for: thisMonthStart) ?? 1..<31
        let lastMonthRange = calendar.range(of: .day, in: .month, for: lastMonthStart) ?? 1..<31
        let maxDays = max(thisMonthRange.count, lastMonthRange.count)

        // Today's day of month
        let todayDayNumber = calendar.component(.day, from: startOfToday)

        // Group expenses by day number (1..31) using fast string prefix checks
        var currentMonthSpend: [Int: Int64] = [:]
        var previousMonthSpend: [Int: Int64] = [:]

        for exp in expenses {
            if exp.day.hasPrefix(thisMonthPrefix) {
                if let day = Int(exp.day.suffix(2)) {
                    currentMonthSpend[day, default: 0] += exp.amount
                }
            } else if exp.day.hasPrefix(lastMonthPrefix) {
                if let day = Int(exp.day.suffix(2)) {
                    previousMonthSpend[day, default: 0] += exp.amount
                }
            }
        }

        var points: [ComparativePeriodPoint] = []
        var curRunning: Int64 = 0
        var prevRunning: Int64 = 0

        for dayIndex in 1...maxDays {
            // Previous month: hold flat across full 31-day domain for shorter months
            var prevAmount: Int64? = nil
            var prevDate: Date? = nil
            if dayIndex <= lastMonthRange.count {
                prevRunning += previousMonthSpend[dayIndex] ?? 0
                prevAmount = prevRunning
                var c = lastMonthComps
                c.day = dayIndex
                prevDate = calendar.date(from: c)
            } else {
                prevAmount = prevRunning
            }

            // Current month (only plot up to today)
            var curAmount: Int64? = nil
            var curDate: Date? = nil
            if dayIndex <= thisMonthRange.count && dayIndex <= todayDayNumber {
                curRunning += currentMonthSpend[dayIndex] ?? 0
                curAmount = curRunning
                var c = thisMonthComps
                c.day = dayIndex
                curDate = calendar.date(from: c)
            }

            points.append(ComparativePeriodPoint(
                dayIndex: dayIndex,
                currentPeriodCumulative: curAmount,
                previousPeriodCumulative: prevAmount,
                currentDate: curDate,
                previousDate: prevDate
            ))
        }

        return points
    }

    /// Computes category distribution, percentage shares, transaction counts, and budget limits.
    /// Captures unallocated amounts in Uncategorized and groups unresolvable categories into Other.
    static func calculateCategoryDistribution(
        expenses: [Expense],
        categories: [ExpenseCategory],
        budgetLimits: [UUID: Int64] = [:]
    ) -> [CategorySpendPoint] {
        guard let totalSpend = try? Money.checkedSum(expenses.map(\.amount)), totalSpend > 0,
              expenses.allSatisfy({ expense in
                  guard let allocated = try? Money.checkedSum(expense.splits.map(\.amount)) else { return false }
                  return allocated <= expense.amount && expense.splits.allSatisfy { $0.amount >= 0 }
              }) else { return [] }

        let catMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var spendByCat: [UUID: (amount: Int64, count: Int)] = [:]

        for exp in expenses {
            let allocatedSum = exp.splits.reduce(0) { $0 + $1.amount }
            for alloc in exp.splits {
                let targetID = catMap[alloc.categoryID] != nil ? alloc.categoryID : otherCategoryID
                let current = spendByCat[targetID, default: (amount: 0, count: 0)]
                spendByCat[targetID] = (amount: current.0 + alloc.amount, count: current.1 + 1)
            }
            let unallocated = exp.amount - allocatedSum
            if unallocated > 0 {
                let current = spendByCat[uncategorizedCategoryID, default: (amount: 0, count: 0)]
                spendByCat[uncategorizedCategoryID] = (amount: current.0 + unallocated, count: current.1 + 1)
            }
        }

        var points: [CategorySpendPoint] = []
        for (catID, data) in spendByCat where data.0 > 0 {
            let name: String
            let symbol: String
            if catID == uncategorizedCategoryID {
                name = "Uncategorized"
                symbol = "questionmark.circle"
            } else if catID == otherCategoryID {
                name = "Other"
                symbol = "tag"
            } else {
                let cat = catMap[catID]
                name = cat?.name ?? "Other"
                symbol = cat?.symbol ?? "tag"
            }
            let pct = Double(data.0) / Double(totalSpend)
            let limit = budgetLimits[catID]

            points.append(CategorySpendPoint(
                categoryID: catID,
                categoryName: name,
                categorySymbol: symbol,
                amount: data.0,
                percentage: pct,
                transactionCount: data.1,
                budgetLimit: limit
            ))
        }

        return points.sorted { $0.amount > $1.amount }
    }

    /// Computes cross-card spending distribution.
    static func calculateCardDistribution(
        expensesByCard: [UUID: [Expense]],
        cards: [Card]
    ) -> [CardSpendPoint] {
        guard (try? Money.checkedSum(expensesByCard.values.flatMap { $0.map(\.amount) })) != nil else { return [] }
        var cardTotals: [UUID: (amount: Int64, count: Int)] = [:]
        var grandTotal: Int64 = 0

        for (bID, exps) in expensesByCard {
            let sum = exps.reduce(0) { $0 + $1.amount }
            cardTotals[bID] = (sum, exps.count)
            grandTotal += sum
        }

        guard grandTotal > 0 else { return [] }
        let cardMap = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })

        var points: [CardSpendPoint] = []
        for (bID, data) in cardTotals where data.0 > 0 {
            let card = cardMap[bID]
            let name = card?.name ?? "Card"
            let colorIdx = card?.colorIndex ?? 0
            let pct = Double(data.0) / Double(grandTotal)

            points.append(CardSpendPoint(
                cardID: bID,
                cardName: name,
                colorIndex: colorIdx,
                amount: data.0,
                percentage: pct,
                transactionCount: data.1
            ))
        }

        return points.sorted { $0.amount > $1.amount }
    }

    /// Computes high-level KPI spending metrics.
    static func calculateMetrics(
        dailyPoints: [DailySpendPoint],
        categoryPoints: [CategorySpendPoint],
        startDate: Date,
        endDate: Date,
        overallBudgetLimit: Int64? = nil,
        calendar: Calendar = Day.calendar,
        now: Date = .now
    ) -> AnalyticsMetrics {
        let calendar = Day.reportingCalendar(calendar)
        let elapsedPoints = dailyPoints.filter { !$0.isFuture }
        let totalSpend = elapsedPoints.last?.cumulativeAmount ?? 0
        let txCount = elapsedPoints.reduce(0) { $0 + $1.transactionCount }

        let fullPeriodDays = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: calendar.startOfDay(for: endDate)).day ?? 1) + 1)
        let daysElapsed = max(1, elapsedPoints.count)

        let dailyAvg: Int64 = daysElapsed > 0 ? (totalSpend / Int64(daysElapsed)) : 0
        let projectedTotal = try? Money.checkedScale(totalSpend, numerator: fullPeriodDays, denominator: daysElapsed)

        // Highest spend day
        let highestDay = elapsedPoints.max { $0.amount < $1.amount }
        let highest: (day: String, amount: Int64)? = (highestDay != nil && (highestDay?.amount ?? 0) > 0)
            ? (highestDay!.day, highestDay!.amount)
            : nil

        // Top category
        let topCat = categoryPoints.first.map { ($0.categoryName, $0.amount) }

        // Pace calculation
        var paceStatus: SpendingPaceStatus? = nil
        if let budget = overallBudgetLimit, budget > 0 {
            // Pace is an approximate percentage, not a ledger amount. Retain the
            // fractional expected pace so even a one-minor-unit budget has a result.
            let expectedPaceSpend = Double(budget) * (Double(daysElapsed) / Double(fullPeriodDays))
            if expectedPaceSpend > 0 {
                let diff = Double(totalSpend) - expectedPaceSpend
                let percentage = (abs(diff) / expectedPaceSpend * 100.0).rounded()
                if percentage >= Double(Int.max) {
                    paceStatus = .beyondRange
                } else if percentage <= 5 {
                    paceStatus = .onTrack
                } else if diff > 0 {
                    paceStatus = .accelerated(percentage: Int(percentage))
                } else {
                    paceStatus = .underPace(percentage: Int(percentage))
                }
            }
        }

        return AnalyticsMetrics(
            totalSpend: totalSpend,
            dailyAverage: dailyAvg,
            projectedPeriodTotal: projectedTotal,
            highestSpendDay: highest,
            topCategory: topCat,
            transactionCount: txCount,
            daysElapsed: daysElapsed,
            totalDaysInPeriod: fullPeriodDays,
            paceStatus: paceStatus
        )
    }
}


extension AnalyticsEngine {
    /// Totals per Paid with label, biggest first, with expenses that have none under "Not set".
    /// Empty when no expense in view has a label, so the breakdown can stay hidden.
    static func paidWithTotals(_ expenses: [Expense], methods: [PaymentMethod]) -> [(name: String, amount: Int64)] {
        guard expenses.contains(where: { $0.paidWithID != nil }) else { return [] }
        let names = Dictionary(uniqueKeysWithValues: methods.map { ($0.id, $0.name) })
        let totals = Dictionary(expenses.map { (($0.paidWithID.flatMap { names[$0] }) ?? "Not set", $0.amount) }, uniquingKeysWith: { Money.sum([$0, $1]) })
        return totals.map { (name: $0.key, amount: $0.value) }.sorted { $0.amount != $1.amount ? $0.amount > $1.amount : $0.name < $1.name }
    }
}

/// Immutable scoped inputs. Budgets are supplied only for a single-card scope; aggregate
/// scopes use Gregorian calendar-month boundaries and show no combined budget/pace.
struct AnalyticsReportingData {
    var expenses: [Expense] = []
    var categories: [ExpenseCategory] = []
    var budgets: [BudgetVersion] = []
    var cards: [Card] = []
    var expensesByCard: [UUID: [Expense]] = [:]
    var bills: [Bill] = []
    var billOccurrences: [BillOccurrence] = []
    var errorMessage: String? = nil
}

/// One computation feeds every chart and label in a rendered report.
struct AnalyticsReport {
    let data: AnalyticsReportingData
    let range: (startDate: Date, endDate: Date, startDay: String, endDay: String)
    let period: BudgetPeriod?
    let dailyPoints: [DailySpendPoint]
    let categoryPoints: [CategorySpendPoint]
    let cardPoints: [CardSpendPoint]
    let monthPoints: [ComparativePeriodPoint]
    let metrics: AnalyticsMetrics
    let errorMessage: String?

    static func build(data: AnalyticsReportingData, horizon: AnalyticsTimeHorizon, calendar: Calendar = Day.calendar, now: Date = .now) -> Self {
        let period = BudgetHistory.period(containing: now, budgets: data.budgets, calendar: calendar)
        let range = AnalyticsEngine.dateRange(for: horizon, currentCycle: period?.cycle, calendar: calendar, now: now)
        let budget = horizon == .thisCycle ? period?.budget : nil
        let filtered = AnalyticsEngine.filterExpenses(data.expenses, startDay: range.startDay, endDay: range.endDay)
        let overflow = (try? Money.checkedSum(data.expenses.map(\.amount))) == nil
        let error = data.errorMessage ?? (overflow ? EntryError.aggregateOverflow.localizedDescription : nil)
        let daily = error == nil ? AnalyticsEngine.calculateDailySpendPoints(expenses: filtered, startDate: range.startDate, endDate: range.endDate, overallBudgetLimit: budget?.overallLimit, calendar: calendar, now: now) : []
        let limits = Dictionary((budget?.categoryLimits ?? []).map { ($0.categoryID, $0.limit) }) { first, _ in first }
        let category = error == nil ? AnalyticsEngine.calculateCategoryDistribution(expenses: filtered, categories: data.categories, budgetLimits: limits) : []
        let cards = error == nil ? AnalyticsEngine.calculateCardDistribution(expensesByCard: data.expensesByCard.mapValues { AnalyticsEngine.filterExpenses($0, startDay: range.startDay, endDay: range.endDay) }, cards: data.cards) : []
        let months = error == nil ? AnalyticsEngine.calculateMonthOverMonthComparison(expenses: data.expenses, calendar: calendar, now: now) : []
        let metrics = AnalyticsEngine.calculateMetrics(dailyPoints: daily, categoryPoints: category, startDate: range.startDate, endDate: range.endDate, overallBudgetLimit: budget?.overallLimit, calendar: calendar, now: now)
        return .init(data: data, range: range, period: period, dailyPoints: daily, categoryPoints: category, cardPoints: cards, monthPoints: months, metrics: metrics, errorMessage: error)
    }
}
