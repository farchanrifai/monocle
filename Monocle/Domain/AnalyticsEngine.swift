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
    case activeBook = "Current card"
    case allBooks = "All cards"

    var id: String { rawValue }
}

enum SpendingPaceStatus: Equatable, Sendable {
    case underPace(percentage: Int)
    case onTrack
    case accelerated(percentage: Int)

    var label: String {
        switch self {
        case .underPace(let pct): return "\(pct)% under budget pace"
        case .onTrack: return "On track with budget"
        case .accelerated(let pct): return "\(pct)% above budget pace"
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

struct CategorySpendPoint: Identifiable, Equatable, Sendable {
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

struct BookSpendPoint: Identifiable, Equatable, Sendable {
    var id: UUID { bookID }
    let bookID: UUID
    let bookName: String
    let colorIndex: Int
    let amount: Int64
    let percentage: Double
    let transactionCount: Int
}

struct AnalyticsMetrics: Equatable, Sendable {
    let totalSpend: Int64
    let dailyAverage: Int64
    let projectedPeriodTotal: Int64
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
        currentCycle: BudgetCycle? = nil,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> (startDate: Date, endDate: Date, startDay: String, endDay: String) {
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
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [DailySpendPoint] {
        let startOfToday = calendar.startOfDay(for: now)
        let latestExpenseDate = expenses.compactMap { Day.date($0.day, calendar: calendar) }.max()
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
                targetCumulative = Int64(Double(budgetLimit) * (Double(dayIndex) / Double(fullPeriodDays)))
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
        calendar: Calendar = .current,
        now: Date = .now
    ) -> [ComparativePeriodPoint] {
        let startOfToday = calendar.startOfDay(for: now)
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
        let totalSpend = expenses.reduce(0) { $0 + $1.amount }
        guard totalSpend > 0 else { return [] }

        let catMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var spendByCat: [UUID: (amount: Int64, count: Int)] = [:]

        for exp in expenses {
            let allocatedSum = exp.allocations.reduce(0) { $0 + $1.amount }
            for alloc in exp.allocations {
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

    /// Computes cross-book spending distribution.
    static func calculateBookDistribution(
        expensesByBook: [UUID: [Expense]],
        books: [BookProfile]
    ) -> [BookSpendPoint] {
        var bookTotals: [UUID: (amount: Int64, count: Int)] = [:]
        var grandTotal: Int64 = 0

        for (bID, exps) in expensesByBook {
            let sum = exps.reduce(0) { $0 + $1.amount }
            bookTotals[bID] = (sum, exps.count)
            grandTotal += sum
        }

        guard grandTotal > 0 else { return [] }
        let bookMap = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })

        var points: [BookSpendPoint] = []
        for (bID, data) in bookTotals where data.0 > 0 {
            let book = bookMap[bID]
            let name = book?.name ?? "Card"
            let colorIdx = book?.colorIndex ?? 0
            let pct = Double(data.0) / Double(grandTotal)

            points.append(BookSpendPoint(
                bookID: bID,
                bookName: name,
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
        calendar: Calendar = .current,
        now: Date = .now
    ) -> AnalyticsMetrics {
        let elapsedPoints = dailyPoints.filter { !$0.isFuture }
        let totalSpend = elapsedPoints.last?.cumulativeAmount ?? 0
        let txCount = elapsedPoints.reduce(0) { $0 + $1.transactionCount }

        let fullPeriodDays = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate), to: calendar.startOfDay(for: endDate)).day ?? 1) + 1)
        let daysElapsed = max(1, elapsedPoints.count)

        let dailyAvg: Int64 = daysElapsed > 0 ? (totalSpend / Int64(daysElapsed)) : 0
        let projectedTotal: Int64 = dailyAvg * Int64(fullPeriodDays)

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
            let expectedPaceSpend = Int64((Double(budget) * Double(daysElapsed)) / Double(fullPeriodDays))
            if expectedPaceSpend > 0 {
                let diff = totalSpend - expectedPaceSpend
                let pctDiff = Int(round(abs(Double(diff)) / Double(expectedPaceSpend) * 100.0))
                if pctDiff <= 5 {
                    paceStatus = .onTrack
                } else if diff > 0 {
                    paceStatus = .accelerated(percentage: pctDiff)
                } else {
                    paceStatus = .underPace(percentage: pctDiff)
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
