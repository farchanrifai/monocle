import Foundation

/// Runs the assistant's tool calls on-device (CHAT_SPEC §4). Every amount and total in a result is computed
/// here by app code; the model only relays it. Tools speak major units of the card's currency; the store keeps minor units.
@MainActor
struct ToolExecutor {
    struct Outcome {
        var json: String
        var isError = false
        /// Shown as a confirm card; nothing is saved until the user taps Save.
        var proposal: Expense? = nil
        /// An edit or delete of a saved expense, applied only when the user confirms.
        var change: ExpenseChange? = nil
        /// A new recurring bill, saved only when the user confirms.
        var bill: Bill? = nil
        var chart: ChatChart? = nil
    }

    struct ToolError: Error { let message: String }

    let model: AppModel
    /// Chat-local default scope (CHAT_SPEC §2).
    let scope: AnalyticsFilterScope
    var now: Date = .now

    func run(_ name: String, input: Data) -> Outcome {
        do {
            switch name {
            case "propose_expense": return try proposeExpense(decode(input))
            case "propose_edit": return try proposeEdit(decode(input))
            case "propose_delete": return try proposeDelete(decode(input))
            case "propose_bill": return try proposeBill(decode(input))
            case "list_bills": return try listBills(decode(input))
            case "query_expenses": return try queryExpenses(decode(input))
            case "get_summary": return try summary(decode(input))
            case "compare_periods": return try compare(decode(input))
            case "get_budget_status": return try budgetStatus(decode(input))
            case "get_insights": return try insights(decode(input))
            case "list_cards": return try Outcome(json: Self.encode(cardList()))
            default: throw ToolError(message: "Unknown tool \(name).")
            }
        } catch let error as ToolError {
            return Self.failure(error.message)
        } catch is DecodingError {
            return Self.failure("Invalid arguments for \(name). Check required fields, types and allowed values.")
        } catch {
            return Self.failure(error.localizedDescription)
        }
    }

    // MARK: - Inputs

    enum Period: String, Decodable {
        case thisCycle = "this_cycle", thisMonth = "this_month", lastMonth = "last_month"
        case last30Days = "last_30_days", last90Days = "last_90_days", yearToDate = "year_to_date"

        var horizon: AnalyticsTimeHorizon {
            switch self {
            case .thisCycle: .thisCycle
            case .thisMonth: .thisMonth
            case .lastMonth: .lastMonth
            case .last30Days: .last30Days
            case .last90Days: .last90Days
            case .yearToDate: .yearToDate
            }
        }
    }

    enum GroupBy: String, Decodable { case category, day, card, paidWith = "paid_with", weekday }
    enum InsightKind: String, Decodable {
        case overview, pace, monthOverMonth = "month_over_month", budgetHistory = "budget_history", topExpenses = "top_expenses"
    }

    struct SplitPart: Decodable { let category: String; let amount: Decimal }
    struct ProposeInput: Decodable {
        let amount: Decimal; var category: String?; var split: [SplitPart]?; var note: String?; var day: String?; var card: String?
        var paid_with: String?
    }
    struct EditInput: Decodable { let id: String; var amount: Decimal?; var category: String?; var split: [SplitPart]?; var note: String?; var day: String? }
    struct DeleteInput: Decodable { let id: String }
    enum Frequency: String, Decodable { case monthly, weekly, yearly }
    enum RecordMode: String, Decodable { case automatic, confirm }
    struct BillInput: Decodable {
        let name: String; let amount: Decimal; let category: String; let frequency: Frequency
        var day: Int?; var weekday: Int?; var month: Int?; var record: RecordMode?; var reminder: Bool?; var card: String?
    }
    struct ListBillsInput: Decodable { var scope: String? }
    struct QueryInput: Decodable {
        var period: Period?; var start: String?; var end: String?
        var category: String?; var text: String?; var scope: String?; var limit: Int?; var offset: Int?
    }
    struct SummaryInput: Decodable { let period: Period; var groupBy: GroupBy?; var scope: String? }
    struct CompareInput: Decodable { let periodA: Period; let periodB: Period; var scope: String? }
    struct BudgetInput: Decodable { var card: String?; var cycle: String? }
    struct InsightsInput: Decodable { let kind: InsightKind; var period: Period?; var scope: String? }

    // MARK: - Outputs

    struct Amount: Encodable, Equatable {
        /// Major units, exact (28000, 4.5).
        let value: Decimal
        let display: String
        init(_ minor: Int64) {
            value = Decimal(minor) / 100
            display = Money.format(minor)
        }
    }

    /// The model's major-unit amount in minor units of `card`'s currency.
    private func minor(_ major: Decimal, on card: Card, what: String = "Amount") throws -> Int64 {
        let code = model.currency(ofCard: card.id)
        do { return try Money.minor(fromMajor: major, code: code) } catch {
            throw ToolError(message: "\(what) must be above 0 in \(code), for example \(Money.fractionDigits(code) > 0 ? "4.50" : "28000").")
        }
    }

    struct ProposalResult: Encodable { let status: String; let card: String; let category: String; let amount: Amount; let day: String; let note: String }
    struct ExpenseSummary: Encodable { let amount: Amount; let category: String; let day: String; let note: String }
    struct ChangeResult: Encodable { let status: String; let card: String; let before: ExpenseSummary; var after: ExpenseSummary? }
    struct BillResult: Encodable { let status: String; let card: String; let name: String; let amount: Amount; let schedule: String; let category: String; let record: String; let reminder: Bool }
    struct BillRow: Encodable { let name: String; let amount: Amount; let schedule: String; let category: String; let card: String; let paused: Bool }
    struct BillList: Encodable { let scope: String; let bills: [BillRow] }
    struct Row: Encodable { let id: String; let day: String; let amount: Amount; let category: String; let note: String; let card: String }
    struct QueryResult: Encodable { let start: String; let end: String; let scope: String; let count: Int; let total: Amount; let rows: [Row]; let hasMore: Bool }
    struct Group: Encodable { let name: String; let amount: Amount; let share: Int?; let count: Int }
    struct SummaryResult: Encodable { let period: String; let start: String; let end: String; let scope: String; let total: Amount; let count: Int; let groups: [Group] }
    struct Delta: Encodable { let category: String; let a: Amount; let b: Amount; let change: Amount }
    struct CompareResult: Encodable { let periodA: String; let periodB: String; let scope: String; let totalA: Amount; let totalB: Amount; let change: Amount; let summary: String; let categories: [Delta] }
    struct CategoryBudgetStatus: Encodable { let category: String; let limit: Amount; let spent: Amount; let remaining: Amount }
    struct BudgetResult: Encodable {
        let card: String; let hasBudget: Bool; var cycleStart: String?; var cycleEnd: String?
        var limit: Amount?; var spent: Amount?; var remaining: Amount?; var categories: [CategoryBudgetStatus] = []
    }
    struct OverviewResult: Encodable {
        let period: String; let start: String; let end: String; let scope: String; let total: Amount; let count: Int
        let dailyAverage: Amount; var projected: Amount?; var peakDay: String?; var peakDayAmount: Amount?
        var topCategory: String?; var topCategoryAmount: Amount?; var pace: String?
    }
    struct PaceResult: Encodable { let start: String; let end: String; let scope: String; let spent: Amount; var budget: Amount?; var projected: Amount?; var pace: String?; let summary: String }
    struct MonthResult: Encodable { let scope: String; let thisMonthSoFar: Amount; let lastMonthSameDay: Amount; let lastMonthTotal: Amount; let summary: String }
    struct CycleRow: Encodable { let cycle: String; let limit: Amount; let spent: Amount; let over: Bool }
    struct HistoryResult: Encodable { let scope: String; let hasBudget: Bool; let cycles: [CycleRow] }
    struct TopResult: Encodable { let period: String; let start: String; let end: String; let scope: String; let rows: [Row] }
    struct StackInfo: Encodable { let name: String; let cards: [String] }
    struct CardList: Encodable { let scope: String; let defaultCard: String?; let cards: [String]; let stacks: [StackInfo] }

    // MARK: - Tools

    private func proposeExpense(_ input: ProposeInput) throws -> Outcome {
        let card = try input.card.map { try card(named: $0) } ?? targetCard()
        let minor = try minor(input.amount, on: card)
        let day = input.day ?? Day.string(now)
        guard Day.date(day) != nil else { throw ToolError(message: "Day must be a valid yyyy-MM-dd date.") }
        let categories = try model.activeCategories(in: card.id)
        guard let splits = try splits(total: minor, category: input.category, split: input.split, on: card, in: categories) else {
            throw ToolError(message: "Give a category, or a split of two or more categories.")
        }
        let note = (input.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // Paid with: a named label, otherwise the card's default.
        let paidWithID: UUID?
        if let name = input.paid_with?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            guard let method = model.paymentMethods.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                throw ToolError(message: "Paid with must be one of: \(model.paymentMethods.map(\.name).joined(separator: ", ")). Omit it if unsure.")
            }
            paidWithID = method.id
        } else { paidWithID = card.defaultPaidWithID }
        let expense = Expense(amount: minor, day: day, note: note, splits: splits, source: "chat", cardID: card.id, paidWithID: paidWithID)
        try expense.validate(categories: categories)
        let result = ProposalResult(status: "shown_to_user", card: card.name, category: try summary(of: expense, in: card).category,
                                    amount: Amount(minor), day: day, note: note)
        return Outcome(json: try Self.encode(result), proposal: expense)
    }

    private func proposeEdit(_ input: EditInput) throws -> Outcome {
        let (original, card) = try savedExpense(input.id)
        var updated = original
        if let amount = input.amount { updated.amount = try minor(amount, on: card) }
        let categories = try model.activeCategories(in: card.id)
        if let splits = try splits(total: updated.amount, category: input.category, split: input.split, on: card, in: categories) {
            updated.splits = splits
        } else if input.amount != nil {
            guard original.splits.count == 1 else {
                throw ToolError(message: "This expense is split. Give the new split with the new amount.")
            }
            updated.splits[0].amount = updated.amount
        }
        if let note = input.note { updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let day = input.day {
            guard Day.date(day) != nil else { throw ToolError(message: "Day must be a valid yyyy-MM-dd date.") }
            updated.day = day
        }
        guard updated != original else { throw ToolError(message: "Nothing to change. Give a new amount, category, note or day.") }
        // Same catalog the store validates against, so a kept archived category still passes.
        guard let service = model.expenseService else { throw EntryError.corruptStore }
        try updated.validate(categories: try service.categories(for: card.id))
        let result = ChangeResult(status: "shown_to_user", card: card.name,
                                  before: try summary(of: original, in: card), after: try summary(of: updated, in: card))
        return Outcome(json: try Self.encode(result), change: ExpenseChange(original: original, updated: updated))
    }

    private func proposeDelete(_ input: DeleteInput) throws -> Outcome {
        let (expense, card) = try savedExpense(input.id)
        let result = ChangeResult(status: "shown_to_user", card: card.name, before: try summary(of: expense, in: card))
        return Outcome(json: try Self.encode(result), change: ExpenseChange(original: expense, updated: nil))
    }

    /// One category, or a split whose parts add up to `total` (minor units). nil when neither was given.
    private func splits(total: Int64, category name: String?, split: [SplitPart]?, on card: Card, in categories: [ExpenseCategory]) throws -> [Split]? {
        if let split, !split.isEmpty {
            guard name == nil else { throw ToolError(message: "Give either category or split, not both.") }
            guard split.count >= 2 else { throw ToolError(message: "A split needs two or more categories; use category for one.") }
            let parts = try split.map { part -> Split in
                Split(categoryID: try category(named: part.category, in: categories).id, amount: try minor(part.amount, on: card, what: "Each split amount"))
            }
            guard Set(parts.map(\.categoryID)).count == parts.count else { throw ToolError(message: "Each category can appear once in a split.") }
            let sum = try Money.checkedSum(parts.map(\.amount))
            guard sum == total else {
                throw ToolError(message: "Split parts add up to \(Money.format(sum)) but the amount is \(Money.format(total)). Make them match.")
            }
            return parts
        }
        return try name.map { [Split(categoryID: try category(named: $0, in: categories).id, amount: total)] }
    }

    private func proposeBill(_ input: BillInput) throws -> Outcome {
        let card = try input.card.map { try card(named: $0) } ?? targetCard()
        let amount = try minor(input.amount, on: card)
        let categories = try model.activeCategories(in: card.id)
        let category = try category(named: input.category, in: categories)
        let today = Day.calendar.dateComponents([.day, .weekday, .month], from: now)
        // Missing day/weekday/month default to today's, so "netflix 186rb monthly" starts from today's date.
        let recurrence: BillRecurrence = switch input.frequency {
        case .monthly: .monthly(day: input.day ?? today.day ?? 1)
        case .weekly: .weekly(weekday: input.weekday ?? today.weekday ?? 1)
        case .yearly: .yearly(month: input.month ?? today.month ?? 1, day: input.day ?? today.day ?? 1)
        }
        let rule = Bill(cardID: card.id, name: input.name.trimmingCharacters(in: .whitespacesAndNewlines), amount: amount,
                            categoryID: category.id, recurrence: recurrence,
                            recordingMode: input.record == .automatic ? .automatic : .pending, hasReminder: input.reminder ?? true)
        do { try rule.validate(categories: categories) } catch {
            throw ToolError(message: "Bill rejected: name 1-40 characters, day 1-31, weekday 1-7 (1 = Sunday), month 1-12.")
        }
        let result = BillResult(status: "shown_to_user", card: card.name, name: rule.name, amount: Amount(rule.amount),
                                schedule: recurrence.title, category: category.name, record: rule.recordingMode.title, reminder: rule.hasReminder)
        return Outcome(json: try Self.encode(result), bill: rule)
    }

    private func listBills(_ input: ListBillsInput) throws -> Outcome {
        let target = try resolveScope(input.scope)
        guard let service = model.expenseService else { throw EntryError.corruptStore }
        var rows: [BillRow] = []
        for card in model.cards(in: target) {
            let names = Dictionary(try service.categories(for: card.id).map { ($0.id, $0.name) }) { first, _ in first }
            rows += try service.bills(for: card.id).map {
                BillRow(name: $0.name, amount: Amount($0.amount), schedule: $0.recurrence.title,
                        category: names[$0.categoryID] ?? "Unknown", card: card.name, paused: !$0.isActive)
            }
        }
        return Outcome(json: try Self.encode(BillList(scope: Self.label(target), bills: rows)))
    }

    private func savedExpense(_ id: String) throws -> (Expense, Card) {
        if let uuid = UUID(uuidString: id) {
            for card in model.cards {
                if let expense = model.expenses(for: card.id).first(where: { $0.id == uuid }) { return (expense, card) }
            }
        }
        throw ToolError(message: "No expense with id \(id). Find it with query_expenses first.")
    }

    private func summary(of expense: Expense, in card: Card) throws -> ExpenseSummary {
        guard let service = model.expenseService else { throw EntryError.corruptStore }
        let names = Dictionary(try service.categories(for: card.id).map { ($0.id, $0.name) }) { first, _ in first }
        return ExpenseSummary(amount: Amount(expense.amount), category: expense.splits.compactMap { names[$0.categoryID] }.joined(separator: ", "),
                              day: expense.day, note: expense.note)
    }

    private func queryExpenses(_ input: QueryInput) throws -> Outcome {
        let target = try resolveScope(input.scope)
        let (start, end) = try dayRange(input, scope: target)
        guard let endDate = Day.date(end), let after = Day.calendar.date(byAdding: .day, value: 1, to: endDate) else {
            throw ToolError(message: "End must be a valid yyyy-MM-dd date.")
        }
        let limit = min(max(input.limit ?? 20, 1), 50)
        let offset = max(input.offset ?? 0, 0)
        let text = input.text.map(Self.key).flatMap { $0.isEmpty ? nil : $0 }
        let wanted = input.category.map(Self.key)
        let fetchCap = 1_000

        var matches: [(expense: Expense, amount: Int64, categories: String, card: String)] = []
        var categoryFound = wanted == nil
        for card in model.cards(in: target) {
            guard let service = model.expenseService else { throw EntryError.corruptStore }
            let names = Dictionary(try service.categories(for: card.id).map { ($0.id, $0.name) }) { first, _ in first }
            // Date-bounded read (audit F26); refuse rather than return a silently truncated total.
            let rows = try service.expenses(for: card.id, from: start, to: Day.string(after), limit: fetchCap)
            guard rows.count < fetchCap else { throw ToolError(message: "Too many expenses in this range. Use a shorter period.") }
            for expense in rows {
                var splits = expense.splits
                if let wanted {
                    splits = splits.filter { names[$0.categoryID].map(Self.key) == wanted }
                    if !splits.isEmpty { categoryFound = true } else { continue }
                }
                if let text, !Self.key(expense.note).contains(text) { continue }
                let amount = try Money.checkedSum(splits.map(\.amount))
                let label = splits.compactMap { names[$0.categoryID] }.joined(separator: ", ")
                matches.append((expense, amount, label, card.name))
            }
        }
        if !categoryFound, let name = input.category {
            let valid = try scopeCategoryNames(target)
            throw ToolError(message: "No category named \"\(name)\". Valid categories: \(valid.joined(separator: ", ")).")
        }
        matches.sort { ($0.expense.day, $0.expense.createdAt) > ($1.expense.day, $1.expense.createdAt) }
        let total = try Money.checkedSum(matches.map(\.amount))
        let page = matches.dropFirst(offset).prefix(limit).map {
            Row(id: $0.expense.id.uuidString, day: $0.expense.day, amount: Amount($0.amount), category: $0.categories, note: $0.expense.note, card: $0.card)
        }
        let result = QueryResult(start: start, end: end, scope: Self.label(target), count: matches.count,
                                 total: Amount(total), rows: page, hasMore: offset + page.count < matches.count)
        return Outcome(json: try Self.encode(result))
    }

    private func summary(_ input: SummaryInput) throws -> Outcome {
        let target = try resolveScope(input.scope)
        let report = try report(input.period, scope: target)
        let groups: [Group]
        switch input.groupBy ?? .category {
        case .category:
            groups = report.categoryPoints.map { Group(name: $0.categoryName, amount: Amount($0.amount), share: Self.percent($0.percentage), count: $0.transactionCount) }
        case .card:
            groups = report.cardPoints.map { Group(name: $0.cardName, amount: Amount($0.amount), share: Self.percent($0.percentage), count: $0.transactionCount) }
        case .day:
            groups = report.dailyPoints.filter { $0.amount > 0 }.map { Group(name: $0.day, amount: Amount($0.amount), share: nil, count: $0.transactionCount) }
        case .paidWith, .weekday:
            let total = max(report.metrics.totalSpend, 1)
            groups = buckets(report, by: input.groupBy ?? .category).map {
                Group(name: $0.name, amount: Amount($0.amount), share: Self.percent(Double($0.amount) / Double(total)), count: $0.count)
            }
        }
        let result = SummaryResult(period: input.period.horizon.rawValue, start: report.range.startDay, end: report.range.endDay,
                                   scope: Self.label(target), total: Amount(report.metrics.totalSpend),
                                   count: report.metrics.transactionCount, groups: groups)
        let title = "\(Self.rangeLabel(report.range.startDay, report.range.endDay)) · \(target.title)"
        let chart: ChatChart = switch input.groupBy ?? .category {
        case .category: ChatChart(categories: report.categoryPoints, title: title)
        case .card: ChatChart(style: .bars, title: title, items: report.cardPoints.map { .init(label: $0.cardName, value: $0.amount) })
        case .day: ChatChart(style: .trend, title: title, items: report.dailyPoints.filter { !$0.isFuture }.map { .init(label: $0.day, value: $0.amount) },
                             average: report.metrics.dailyAverage)
        case .paidWith, .weekday: ChatChart(style: .bars, title: title, items: buckets(report, by: input.groupBy ?? .category).map { .init(label: $0.name, value: $0.amount) })
        }
        return Outcome(json: try Self.encode(result), chart: report.metrics.totalSpend > 0 ? chart : nil)
    }

    private func compare(_ input: CompareInput) throws -> Outcome {
        let target = try resolveScope(input.scope)
        var (periodA, periodB) = (input.periodA, input.periodB)
        var a = try report(periodA, scope: target)
        var b = try report(periodB, scope: target)
        // Always earlier → later, so `change` and every delta read forward in time whichever order the model asked in.
        if b.range.startDay < a.range.startDay { swap(&a, &b); swap(&periodA, &periodB) }
        let spentA = Dictionary(a.categoryPoints.map { ($0.categoryName, $0.amount) }) { $0 + $1 }
        let spentB = Dictionary(b.categoryPoints.map { ($0.categoryName, $0.amount) }) { $0 + $1 }
        let names = Set(spentA.keys).union(spentB.keys).sorted()
        let deltas = names.map { name in
            let x = spentA[name] ?? 0, y = spentB[name] ?? 0
            return Delta(category: name, a: Amount(x), b: Amount(y), change: Amount(y - x))
        }
        let change = b.metrics.totalSpend - a.metrics.totalSpend
        // Spelled out so a small model never has to read the sign of `change` itself.
        let summary = "Spending \(change == 0 ? "stayed the same" : "went \(change > 0 ? "up" : "down") by \(Money.format(abs(change)))"): "
            + "\(periodA.rawValue) \(Money.format(a.metrics.totalSpend)), \(periodB.rawValue) \(Money.format(b.metrics.totalSpend))."
        let result = CompareResult(periodA: periodA.horizon.rawValue, periodB: periodB.horizon.rawValue,
                                   scope: Self.label(target), totalA: Amount(a.metrics.totalSpend), totalB: Amount(b.metrics.totalSpend),
                                   change: Amount(change), summary: summary, categories: deltas)
        let rows = names.map { ChatChart.Item(label: $0, value: spentB[$0] ?? 0, reference: spentA[$0] ?? 0) }.sorted { max($0.value, $0.reference ?? 0) > max($1.value, $1.reference ?? 0) }
        let chart = ChatChart(style: .comparison, title: "\(Self.rangeLabel(a.range.startDay, a.range.endDay)) vs \(Self.rangeLabel(b.range.startDay, b.range.endDay)) · \(target.title)",
                              items: [.init(label: "Total", value: b.metrics.totalSpend, reference: a.metrics.totalSpend)] + rows,
                              series: [periodA.horizon.rawValue, periodB.horizon.rawValue])
        return Outcome(json: try Self.encode(result), chart: chart)
    }

    private func budgetStatus(_ input: BudgetInput) throws -> Outcome {
        let card = try input.card.map { try card(named: $0) } ?? targetCard()
        guard let service = model.expenseService else { throw EntryError.corruptStore }
        let budgets = try service.budgets(for: card.id)
        var day = now
        if input.cycle == "previous", let current = BudgetHistory.period(containing: now, budgets: budgets) {
            day = Day.calendar.date(byAdding: .day, value: -1, to: current.cycle.start) ?? now
        }
        guard input.cycle != "previous" || day != now, let period = BudgetHistory.period(containing: day, budgets: budgets) else {
            return Outcome(json: try Self.encode(BudgetResult(card: card.name, hasBudget: false)))
        }
        // The previous cycle is "this cycle" as seen from its last day.
        let report = try report(.thisCycle, scope: .card(id: card.id, name: card.name), at: day)
        let spent = report.metrics.totalSpend
        let lastDay = Day.calendar.date(byAdding: .day, value: -1, to: period.cycle.end) ?? period.cycle.start
        var result = BudgetResult(card: card.name, hasBudget: true,
                                  cycleStart: Day.string(period.cycle.start), cycleEnd: Day.string(lastDay),
                                  limit: Amount(period.budget.overallLimit), spent: Amount(spent),
                                  remaining: Amount(period.budget.overallLimit - spent))
        let spentByCategory = Dictionary(report.categoryPoints.map { ($0.categoryID, $0.amount) }) { $0 + $1 }
        let names = Dictionary(try service.categories(for: card.id).map { ($0.id, $0.name) }) { first, _ in first }
        result.categories = period.budget.categoryLimits.map { limit in
            let used = spentByCategory[limit.categoryID] ?? 0
            return CategoryBudgetStatus(category: names[limit.categoryID] ?? "Unknown", limit: Amount(limit.limit),
                                        spent: Amount(used), remaining: Amount(limit.limit - used))
        }
        let items = [ChatChart.Item(label: "Overall", value: spent, reference: period.budget.overallLimit)]
            + period.budget.categoryLimits.map { .init(label: names[$0.categoryID] ?? "Unknown", value: spentByCategory[$0.categoryID] ?? 0, reference: $0.limit) }
        return Outcome(json: try Self.encode(result), chart: ChatChart(style: .budget, title: "Budget \(Self.rangeLabel(Day.string(period.cycle.start), Day.string(lastDay))) · \(card.name)", items: items))
    }

    /// Expenses in the report's range, grouped by how they were paid or by weekday (in calendar order, empty days kept).
    private func buckets(_ report: AnalyticsReport, by group: GroupBy) -> [(name: String, amount: Int64, count: Int)] {
        let expenses = AnalyticsEngine.filterExpenses(report.data.expenses, startDay: report.range.startDay, endDay: report.range.endDay)
        if group == .weekday {
            let calendar = Day.calendar
            let symbols = calendar.shortWeekdaySymbols
            let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }
            var sums = Array(repeating: (amount: Int64(0), count: 0), count: 7)
            for expense in expenses {
                guard let date = Day.date(expense.day) else { continue }
                let index = calendar.component(.weekday, from: date) - 1
                sums[index].amount += expense.amount; sums[index].count += 1
            }
            return order.map { (symbols[$0], sums[$0].amount, sums[$0].count) }
        }
        var sums: [String: (amount: Int64, count: Int)] = [:]
        for expense in expenses {
            let name = model.paymentMethod(expense.paidWithID)?.name ?? "Not set"
            sums[name, default: (0, 0)].amount += expense.amount
            sums[name, default: (0, 0)].count += 1
        }
        return sums.map { ($0.key, $0.value.amount, $0.value.count) }.sorted { $0.amount > $1.amount }
    }

    private func insights(_ input: InsightsInput) throws -> Outcome {
        let target = try resolveScope(input.scope)
        switch input.kind {
        case .overview:
            let period = input.period ?? .thisMonth
            let report = try report(period, scope: target)
            let m = report.metrics
            var result = OverviewResult(period: period.horizon.rawValue, start: report.range.startDay, end: report.range.endDay,
                                        scope: Self.label(target), total: Amount(m.totalSpend), count: m.transactionCount,
                                        dailyAverage: Amount(m.dailyAverage), pace: m.paceStatus?.label)
            var stats = [ChatChart.Stat(label: "Spent", value: Money.format(m.totalSpend)),
                         .init(label: "Expenses", value: "\(m.transactionCount)"),
                         .init(label: "Daily average", value: Money.format(m.dailyAverage))]
            if let projected = m.projectedPeriodTotal, m.daysElapsed < m.totalDaysInPeriod {
                result.projected = Amount(projected)
                stats.append(.init(label: "Projected", value: Money.format(projected)))
            }
            if let peak = m.highestSpendDay, peak.amount > 0 {
                result.peakDay = peak.day; result.peakDayAmount = Amount(peak.amount)
                stats.append(.init(label: "Peak day · \(Day.title(peak.day))", value: Money.format(peak.amount)))
            }
            if let top = m.topCategory {
                result.topCategory = top.name; result.topCategoryAmount = Amount(top.amount)
                stats.append(.init(label: "Top · \(top.name)", value: Money.format(top.amount)))
            }
            let chart = ChatChart(style: .stats, title: "\(Self.rangeLabel(report.range.startDay, report.range.endDay)) · \(target.title)",
                                  items: [], stats: stats, caption: m.paceStatus?.label)
            return Outcome(json: try Self.encode(result), chart: m.transactionCount > 0 ? chart : nil)

        case .pace:
            let report = try report(.thisCycle, scope: target)
            let m = report.metrics
            let budget = report.dailyPoints.last?.targetCumulativeAmount
            let summary = budget.map { "Spent \(Money.format(m.totalSpend)) of \(Money.format($0)) so far; \(m.paceStatus?.label ?? "no pace yet")." }
                ?? "Spent \(Money.format(m.totalSpend)) so far. This scope has no budget for the cycle, so there is no pace line."
            let result = PaceResult(start: report.range.startDay, end: report.range.endDay, scope: Self.label(target), spent: Amount(m.totalSpend),
                                    budget: budget.map(Amount.init), projected: m.projectedPeriodTotal.map(Amount.init), pace: m.paceStatus?.label, summary: summary)
            let items = report.dailyPoints.map {
                ChatChart.Item(label: $0.day, value: $0.cumulativeAmount ?? 0, reference: $0.targetCumulativeAmount, isFuture: $0.isFuture ? true : nil)
            }
            let chart = ChatChart(style: .pace, title: "\(Self.rangeLabel(report.range.startDay, report.range.endDay)) · \(target.title)",
                                  items: items, series: budget == nil ? ["Spent"] : ["Spent", "Budget"], caption: m.paceStatus?.label)
            return Outcome(json: try Self.encode(result), chart: items.isEmpty ? nil : chart)

        case .monthOverMonth:
            let report = try report(.thisMonth, scope: target)
            let points = report.monthPoints
            let today = points.last { $0.currentPeriodCumulative != nil }
            let soFar = today?.currentPeriodCumulative ?? 0
            let sameDay = today?.previousPeriodCumulative ?? 0
            let lastTotal = points.last { $0.previousPeriodCumulative != nil }?.previousPeriodCumulative ?? 0
            let change = soFar - sameDay
            let summary = "This month so far \(Money.format(soFar)), \(change == 0 ? "the same as" : "\(Money.format(abs(change))) \(change > 0 ? "more than" : "less than")") last month by the same day (\(Money.format(sameDay))). Last month ended at \(Money.format(lastTotal))."
            let result = MonthResult(scope: Self.label(target), thisMonthSoFar: Amount(soFar), lastMonthSameDay: Amount(sameDay),
                                     lastMonthTotal: Amount(lastTotal), summary: summary)
            let items = points.map {
                ChatChart.Item(label: "\($0.dayIndex)", value: $0.currentPeriodCumulative ?? 0, reference: $0.previousPeriodCumulative,
                               isFuture: $0.currentPeriodCumulative == nil ? true : nil)
            }
            let chart = ChatChart(style: .cumulative, title: "This month vs last · \(target.title)", items: items, series: ["Last month", "This month"])
            return Outcome(json: try Self.encode(result), chart: soFar > 0 || lastTotal > 0 ? chart : nil)

        case .budgetHistory:
            let subject: BudgetSubject
            switch target {
            case .card(let id, _): subject = .card(id)
            case .stack(let id, _): subject = .stack(id)
            case .allCards:
                let card = try targetCard()
                subject = .card(card.id)
            }
            let cycles = model.budgetCycles(subject, now: now)
            let result = HistoryResult(scope: Self.label(target), hasBudget: !cycles.isEmpty,
                                       cycles: cycles.map { CycleRow(cycle: $0.cycle.label, limit: Amount($0.limit), spent: Amount($0.spent), over: $0.isOver) })
            let chart = ChatChart(style: .budget, title: "Budget, cycle by cycle · \(target.isAllCards ? (try? targetCard().name) ?? "" : target.title)",
                                  items: cycles.reversed().map { .init(label: $0.cycle.label + ($0.isCurrent ? " · now" : ""), value: $0.spent, reference: $0.limit) })
            return Outcome(json: try Self.encode(result), chart: cycles.isEmpty ? nil : chart)

        case .topExpenses:
            let period = input.period ?? .thisMonth
            let report = try report(period, scope: target)
            guard let service = model.expenseService else { throw EntryError.corruptStore }
            var names: [UUID: String] = [:], cardNames: [UUID: String] = [:]
            for card in model.cards(in: target) {
                cardNames[card.id] = card.name
                for category in try service.categories(for: card.id) { names[category.id] = category.name }
            }
            let top = AnalyticsEngine.filterExpenses(report.data.expenses, startDay: report.range.startDay, endDay: report.range.endDay)
                .sorted { $0.amount > $1.amount }.prefix(5)
            let rows = top.map { expense in
                Row(id: expense.id.uuidString, day: expense.day, amount: Amount(expense.amount),
                    category: expense.splits.compactMap { names[$0.categoryID] }.joined(separator: ", "),
                    note: expense.note, card: expense.cardID.flatMap { cardNames[$0] } ?? "")
            }
            let result = TopResult(period: period.horizon.rawValue, start: report.range.startDay, end: report.range.endDay, scope: Self.label(target), rows: rows)
            let items = zip(top, rows).map { expense, row in
                ChatChart.Item(label: row.note.isEmpty ? row.category : row.note, value: expense.amount, detail: "\(Day.title(row.day)) · \(row.category)")
            }
            let chart = ChatChart(style: .ranking, title: "Biggest expenses · \(Self.rangeLabel(report.range.startDay, report.range.endDay))", items: items)
            return Outcome(json: try Self.encode(result), chart: items.isEmpty ? nil : chart)
        }
    }

    /// "1–31 Oct 2026", "1 Sep – 12 Oct 2026" or a span across years: what a chart title shows instead of a period keyword.
    static func rangeLabel(_ start: String, _ end: String) -> String {
        guard let from = Day.date(start), let to = Day.date(end) else { return "\(start) – \(end)" }
        let calendar = Day.calendar
        let sameYear = calendar.component(.year, from: from) == calendar.component(.year, from: to)
        if sameYear, calendar.component(.month, from: from) == calendar.component(.month, from: to), from != to {
            return "\(calendar.component(.day, from: from))–\(to.formatted(.dateTime.day().month(.abbreviated).year()))"
        }
        if from == to { return to.formatted(.dateTime.day().month(.abbreviated).year()) }
        return "\(from.formatted(sameYear ? .dateTime.day().month(.abbreviated) : .dateTime.day().month(.abbreviated).year())) – \(to.formatted(.dateTime.day().month(.abbreviated).year()))"
    }

    private func cardList() -> CardList {
        let cards = model.unhiddenCards
        let stacks = model.stacks.map { stack in
            StackInfo(name: stack.name, cards: model.cards(in: .stack(id: stack.id, name: stack.name)).map(\.name))
        }
        return CardList(scope: Self.label(scope), defaultCard: try? targetCard().name, cards: cards.map(\.name), stacks: stacks)
    }

    // MARK: - Resolution

    /// nil/"default" → chat scope; "all_cards"; a stack or card name, optionally prefixed "stack:" / "card:".
    private func resolveScope(_ name: String?) throws -> AnalyticsFilterScope {
        guard let name, Self.key(name) != "default" else { return scope }
        var key = Self.key(name)
        if key == "all_cards" || key == "all cards" { return .allCards }
        var kinds: Set<String> = ["stack", "card"]
        for prefix in ["stack:", "card:"] where key.hasPrefix(prefix) {
            kinds = [String(prefix.dropLast())]
            key = Self.key(String(key.dropFirst(prefix.count)))
        }
        let stack = kinds.contains("stack") ? model.stacks.first { Self.key($0.name) == key } : nil
        let card = kinds.contains("card") ? model.unhiddenCards.first { Self.key($0.name) == key } : nil
        switch (stack, card) {
        case (let stack?, nil): return .stack(id: stack.id, name: stack.name)
        case (nil, let card?): return .card(id: card.id, name: card.name)
        case (_?, _?): throw ToolError(message: "\"\(name)\" is both a stack and a card. Use \"stack:\(name)\" or \"card:\(name)\".")
        case (nil, nil):
            let valid = ["all_cards"] + model.stacks.map { "stack:\($0.name)" } + model.unhiddenCards.map { "card:\($0.name)" }
            throw ToolError(message: "No stack or card named \"\(name)\". Valid scopes: \(valid.joined(separator: ", ")).")
        }
    }

    private func card(named name: String) throws -> Card {
        if let card = model.unhiddenCards.first(where: { Self.key($0.name) == Self.key(name) }) { return card }
        throw ToolError(message: "No card named \"\(name)\". Cards: \(model.unhiddenCards.map(\.name).joined(separator: ", ")).")
    }

    /// Open or active card when it is in scope, else the scope's first card (CHAT_SPEC §2).
    func targetCard() throws -> Card {
        let inScope = model.cards(in: scope)
        let preferred = model.selectedCardID ?? model.activeCardID
        if let card = inScope.first(where: { $0.id == preferred }) ?? inScope.first { return card }
        throw ToolError(message: "There are no cards in \(Self.label(scope)). Ask which card to use.")
    }

    private func category(named name: String, in categories: [ExpenseCategory]) throws -> ExpenseCategory {
        if let match = categories.first(where: { Self.key($0.name) == Self.key(name) }) { return match }
        throw ToolError(message: "No category named \"\(name)\" on this card. Valid categories: \(categories.map(\.name).joined(separator: ", ")).")
    }

    private func scopeCategoryNames(_ target: AnalyticsFilterScope) throws -> [String] {
        guard let service = model.expenseService else { throw EntryError.corruptStore }
        var seen = Set<String>()
        return try model.cards(in: target).flatMap { try service.categories(for: $0.id) }.map(\.name).filter { seen.insert(Self.key($0)).inserted }
    }

    private func dayRange(_ input: QueryInput, scope target: AnalyticsFilterScope) throws -> (String, String) {
        if let period = input.period {
            let range = AnalyticsEngine.dateRange(for: period.horizon, currentCycle: cycle(for: target), now: now)
            return (range.startDay, range.endDay)
        }
        if let start = input.start, let end = input.end {
            guard Day.date(start) != nil, Day.date(end) != nil, start <= end else {
                throw ToolError(message: "start and end must be valid yyyy-MM-dd dates with start on or before end.")
            }
            return (start, end)
        }
        if input.start != nil || input.end != nil { throw ToolError(message: "Give both start and end, or a period.") }
        let range = AnalyticsEngine.dateRange(for: .thisMonth, now: now)
        return (range.startDay, range.endDay)
    }

    /// A budget cycle exists per card only; multi-card scopes fall back to the calendar month, as Analytics does.
    private func cycle(for target: AnalyticsFilterScope) -> Cycle? {
        guard case .card(let id, _) = target, let budgets = try? model.expenseService?.budgets(for: id) else { return nil }
        return BudgetHistory.period(containing: now, budgets: budgets)?.cycle
    }

    private func report(_ period: Period, scope target: AnalyticsFilterScope, at date: Date? = nil) throws -> AnalyticsReport {
        let report = AnalyticsReport.build(data: model.reportingData(for: target), horizon: period.horizon, now: date ?? now)
        if let error = report.errorMessage { throw ToolError(message: error) }
        return report
    }

    // MARK: - Helpers

    private static func key(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func label(_ scope: AnalyticsFilterScope) -> String {
        scope.isAllCards ? "All cards" : "\(scope.subtitle): \(scope.title)"
    }

    private static func percent(_ fraction: Double) -> Int { Int((fraction * 100).rounded()) }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data.isEmpty ? Data("{}".utf8) : data)
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private static func failure(_ message: String) -> Outcome {
        Outcome(json: (try? encode(["error": message])) ?? #"{"error":"Tool failed."}"#, isError: true)
    }
}
