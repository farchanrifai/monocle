import Foundation

/// Runs Claude's tool calls on-device (CHAT_SPEC §4). Every amount and total in a result is computed
/// here by app code; Claude only relays it. Tools speak whole rupiah; the store keeps minor units.
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
        var bill: BillRule? = nil
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

    enum GroupBy: String, Decodable { case category, day, card }

    struct SplitPart: Decodable { let category: String; let amount: Int64 }
    struct ProposeInput: Decodable {
        let amount: Int64; var category: String?; var split: [SplitPart]?; var note: String?; var day: String?; var card: String?
        var paid_with: String?
    }
    struct EditInput: Decodable { let id: String; var amount: Int64?; var category: String?; var split: [SplitPart]?; var note: String?; var day: String? }
    struct DeleteInput: Decodable { let id: String }
    enum Frequency: String, Decodable { case monthly, weekly, yearly }
    enum RecordMode: String, Decodable { case automatic, confirm }
    struct BillInput: Decodable {
        let name: String; let amount: Int64; let category: String; let frequency: Frequency
        var day: Int?; var weekday: Int?; var month: Int?; var record: RecordMode?; var reminder: Bool?; var card: String?
    }
    struct ListBillsInput: Decodable { var scope: String? }
    struct QueryInput: Decodable {
        var period: Period?; var start: String?; var end: String?
        var category: String?; var text: String?; var scope: String?; var limit: Int?; var offset: Int?
    }
    struct SummaryInput: Decodable { let period: Period; var groupBy: GroupBy?; var scope: String? }
    struct CompareInput: Decodable { let periodA: Period; let periodB: Period; var scope: String? }
    struct BudgetInput: Decodable { var card: String? }

    // MARK: - Outputs

    struct Amount: Encodable, Equatable {
        let rupiah: Int64
        let display: String
        init(_ minor: Int64) {
            // ponytail: whole rupiah for Claude; `display` keeps the exact value for CSV-imported cents.
            rupiah = minor / 100
            display = Money.format(minor)
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
    struct StackInfo: Encodable { let name: String; let cards: [String] }
    struct CardList: Encodable { let scope: String; let defaultCard: String?; let cards: [String]; let stacks: [StackInfo] }

    // MARK: - Tools

    private func proposeExpense(_ input: ProposeInput) throws -> Outcome {
        guard input.amount > 0, input.amount <= Money.maximum / 100 else {
            throw ToolError(message: "Amount must be whole rupiah above 0, for example 28000.")
        }
        let book = try input.card.map { try card(named: $0) } ?? targetCard()
        let day = input.day ?? Day.string(now)
        guard Day.date(day) != nil else { throw ToolError(message: "Day must be a valid yyyy-MM-dd date.") }
        let categories = try model.activeCategories(in: book.id)
        let minor = input.amount * 100
        guard let allocations = try allocations(total: minor, category: input.category, split: input.split, in: categories) else {
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
        } else { paidWithID = book.defaultPaidWithID }
        let expense = Expense(amount: minor, day: day, note: note, allocations: allocations, source: "chat", bookID: book.id, paidWithID: paidWithID)
        try expense.validate(categories: categories)
        let result = ProposalResult(status: "shown_to_user", card: book.name, category: try summary(of: expense, in: book).category,
                                    amount: Amount(minor), day: day, note: note)
        return Outcome(json: try Self.encode(result), proposal: expense)
    }

    private func proposeEdit(_ input: EditInput) throws -> Outcome {
        let (original, book) = try savedExpense(input.id)
        var updated = original
        if let amount = input.amount {
            guard amount > 0, amount <= Money.maximum / 100 else {
                throw ToolError(message: "Amount must be whole rupiah above 0, for example 28000.")
            }
            updated.amount = amount * 100
        }
        let categories = try model.activeCategories(in: book.id)
        if let allocations = try allocations(total: updated.amount, category: input.category, split: input.split, in: categories) {
            updated.allocations = allocations
        } else if input.amount != nil {
            guard original.allocations.count == 1 else {
                throw ToolError(message: "This expense is split. Give the new split with the new amount.")
            }
            updated.allocations[0].amount = updated.amount
        }
        if let note = input.note { updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let day = input.day {
            guard Day.date(day) != nil else { throw ToolError(message: "Day must be a valid yyyy-MM-dd date.") }
            updated.day = day
        }
        guard updated != original else { throw ToolError(message: "Nothing to change. Give a new amount, category, note or day.") }
        // Same catalog the store validates against, so a kept archived category still passes.
        guard let service = model.expenseService else { throw EntryError.corruptStore }
        try updated.validate(categories: try service.categories(for: book.id))
        let result = ChangeResult(status: "shown_to_user", card: book.name,
                                  before: try summary(of: original, in: book), after: try summary(of: updated, in: book))
        return Outcome(json: try Self.encode(result), change: ExpenseChange(original: original, updated: updated))
    }

    private func proposeDelete(_ input: DeleteInput) throws -> Outcome {
        let (expense, book) = try savedExpense(input.id)
        let result = ChangeResult(status: "shown_to_user", card: book.name, before: try summary(of: expense, in: book))
        return Outcome(json: try Self.encode(result), change: ExpenseChange(original: expense, updated: nil))
    }

    /// One category, or a split whose parts add up to `total` (minor units). nil when neither was given.
    private func allocations(total: Int64, category name: String?, split: [SplitPart]?, in categories: [ExpenseCategory]) throws -> [Allocation]? {
        if let split, !split.isEmpty {
            guard name == nil else { throw ToolError(message: "Give either category or split, not both.") }
            guard split.count >= 2 else { throw ToolError(message: "A split needs two or more categories; use category for one.") }
            let parts = try split.map { part -> Allocation in
                guard part.amount > 0, part.amount <= Money.maximum / 100 else { throw ToolError(message: "Each split amount must be whole rupiah above 0.") }
                return Allocation(categoryID: try category(named: part.category, in: categories).id, amount: part.amount * 100)
            }
            guard Set(parts.map(\.categoryID)).count == parts.count else { throw ToolError(message: "Each category can appear once in a split.") }
            let sum = try Money.checkedSum(parts.map(\.amount))
            guard sum == total else {
                throw ToolError(message: "Split parts add up to \(Money.format(sum)) but the amount is \(Money.format(total)). Make them match.")
            }
            return parts
        }
        return try name.map { [Allocation(categoryID: try category(named: $0, in: categories).id, amount: total)] }
    }

    private func proposeBill(_ input: BillInput) throws -> Outcome {
        guard input.amount > 0, input.amount <= Money.maximum / 100 else {
            throw ToolError(message: "Amount must be whole rupiah above 0, for example 186000.")
        }
        let book = try input.card.map { try card(named: $0) } ?? targetCard()
        let categories = try model.activeCategories(in: book.id)
        let category = try category(named: input.category, in: categories)
        let today = Day.calendar.dateComponents([.day, .weekday, .month], from: now)
        // Missing day/weekday/month default to today's, so "netflix 186rb monthly" starts from today's date.
        let recurrence: BillRecurrence = switch input.frequency {
        case .monthly: .monthly(day: input.day ?? today.day ?? 1)
        case .weekly: .weekly(weekday: input.weekday ?? today.weekday ?? 1)
        case .yearly: .yearly(month: input.month ?? today.month ?? 1, day: input.day ?? today.day ?? 1)
        }
        let rule = BillRule(bookID: book.id, name: input.name.trimmingCharacters(in: .whitespacesAndNewlines), amount: input.amount * 100,
                            categoryID: category.id, recurrence: recurrence,
                            recordingMode: input.record == .automatic ? .automatic : .pending, hasReminder: input.reminder ?? true)
        do { try rule.validate(categories: categories) } catch {
            throw ToolError(message: "Bill rejected: name 1-40 characters, day 1-31, weekday 1-7 (1 = Sunday), month 1-12.")
        }
        let result = BillResult(status: "shown_to_user", card: book.name, name: rule.name, amount: Amount(rule.amount),
                                schedule: recurrence.title, category: category.name, record: rule.recordingMode.title, reminder: rule.hasReminder)
        return Outcome(json: try Self.encode(result), bill: rule)
    }

    private func listBills(_ input: ListBillsInput) throws -> Outcome {
        let target = try resolveScope(input.scope)
        guard let service = model.expenseService else { throw EntryError.corruptStore }
        var rows: [BillRow] = []
        for book in model.books(in: target) {
            let names = Dictionary(try service.categories(for: book.id).map { ($0.id, $0.name) }) { first, _ in first }
            rows += try service.bills(for: book.id).map {
                BillRow(name: $0.name, amount: Amount($0.amount), schedule: $0.recurrence.title,
                        category: names[$0.categoryID] ?? "Unknown", card: book.name, paused: !$0.isActive)
            }
        }
        return Outcome(json: try Self.encode(BillList(scope: Self.label(target), bills: rows)))
    }

    private func savedExpense(_ id: String) throws -> (Expense, BookProfile) {
        if let uuid = UUID(uuidString: id) {
            for book in model.books {
                if let expense = model.expenses(for: book.id).first(where: { $0.id == uuid }) { return (expense, book) }
            }
        }
        throw ToolError(message: "No expense with id \(id). Find it with query_expenses first.")
    }

    private func summary(of expense: Expense, in book: BookProfile) throws -> ExpenseSummary {
        guard let service = model.expenseService else { throw EntryError.corruptStore }
        let names = Dictionary(try service.categories(for: book.id).map { ($0.id, $0.name) }) { first, _ in first }
        return ExpenseSummary(amount: Amount(expense.amount), category: expense.allocations.compactMap { names[$0.categoryID] }.joined(separator: ", "),
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
        for book in model.books(in: target) {
            guard let service = model.expenseService else { throw EntryError.corruptStore }
            let names = Dictionary(try service.categories(for: book.id).map { ($0.id, $0.name) }) { first, _ in first }
            // Date-bounded read (audit F26); refuse rather than return a silently truncated total.
            let rows = try service.expenses(for: book.id, from: start, to: Day.string(after), limit: fetchCap)
            guard rows.count < fetchCap else { throw ToolError(message: "Too many expenses in this range. Use a shorter period.") }
            for expense in rows {
                var allocations = expense.allocations
                if let wanted {
                    allocations = allocations.filter { names[$0.categoryID].map(Self.key) == wanted }
                    if !allocations.isEmpty { categoryFound = true } else { continue }
                }
                if let text, !Self.key(expense.note).contains(text) { continue }
                let amount = try Money.checkedSum(allocations.map(\.amount))
                let label = allocations.compactMap { names[$0.categoryID] }.joined(separator: ", ")
                matches.append((expense, amount, label, book.name))
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
            groups = report.bookPoints.map { Group(name: $0.bookName, amount: Amount($0.amount), share: Self.percent($0.percentage), count: $0.transactionCount) }
        case .day:
            groups = report.dailyPoints.filter { $0.amount > 0 }.map { Group(name: $0.day, amount: Amount($0.amount), share: nil, count: $0.transactionCount) }
        }
        let result = SummaryResult(period: input.period.horizon.rawValue, start: report.range.startDay, end: report.range.endDay,
                                   scope: Self.label(target), total: Amount(report.metrics.totalSpend),
                                   count: report.metrics.transactionCount, groups: groups)
        let title = "\(input.period.horizon.rawValue) · \(target.title)"
        let chart: ChatChart = switch input.groupBy ?? .category {
        case .category: ChatChart(categories: report.categoryPoints, title: title)
        case .card: ChatChart(style: .bars, title: title, items: report.bookPoints.map { .init(label: $0.bookName, value: $0.amount) })
        case .day: ChatChart(style: .trend, title: title, items: report.dailyPoints.filter { !$0.isFuture }.map { .init(label: $0.day, value: $0.amount) })
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
        let chart = ChatChart(style: .comparison, title: "\(periodA.horizon.rawValue) vs \(periodB.horizon.rawValue) · \(target.title)",
                              items: [.init(label: "Total", value: b.metrics.totalSpend, reference: a.metrics.totalSpend)] + rows,
                              series: [periodA.horizon.rawValue, periodB.horizon.rawValue])
        return Outcome(json: try Self.encode(result), chart: chart)
    }

    private func budgetStatus(_ input: BudgetInput) throws -> Outcome {
        let book = try input.card.map { try card(named: $0) } ?? targetCard()
        guard let service = model.expenseService else { throw EntryError.corruptStore }
        let budgets = try service.budgets(for: book.id)
        guard let period = BudgetHistory.period(containing: now, budgets: budgets) else {
            return Outcome(json: try Self.encode(BudgetResult(card: book.name, hasBudget: false)))
        }
        let report = try report(.thisCycle, scope: .card(id: book.id, name: book.name))
        let spent = report.metrics.totalSpend
        let lastDay = Day.calendar.date(byAdding: .day, value: -1, to: period.cycle.end) ?? period.cycle.start
        var result = BudgetResult(card: book.name, hasBudget: true,
                                  cycleStart: Day.string(period.cycle.start), cycleEnd: Day.string(lastDay),
                                  limit: Amount(period.budget.overallLimit), spent: Amount(spent),
                                  remaining: Amount(period.budget.overallLimit - spent))
        let spentByCategory = Dictionary(report.categoryPoints.map { ($0.categoryID, $0.amount) }) { $0 + $1 }
        let names = Dictionary(try service.categories(for: book.id).map { ($0.id, $0.name) }) { first, _ in first }
        result.categories = period.budget.categoryLimits.map { limit in
            let used = spentByCategory[limit.categoryID] ?? 0
            return CategoryBudgetStatus(category: names[limit.categoryID] ?? "Unknown", limit: Amount(limit.limit),
                                        spent: Amount(used), remaining: Amount(limit.limit - used))
        }
        let items = [ChatChart.Item(label: "Overall", value: spent, reference: period.budget.overallLimit)]
            + period.budget.categoryLimits.map { .init(label: names[$0.categoryID] ?? "Unknown", value: spentByCategory[$0.categoryID] ?? 0, reference: $0.limit) }
        return Outcome(json: try Self.encode(result), chart: ChatChart(style: .budget, title: "Budget this cycle · \(book.name)", items: items))
    }

    private func cardList() -> CardList {
        let cards = model.unhiddenBooks
        let stacks = model.stacks.map { stack in
            StackInfo(name: stack.name, cards: model.books(in: .stack(id: stack.id, name: stack.name)).map(\.name))
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
        let book = kinds.contains("card") ? model.unhiddenBooks.first { Self.key($0.name) == key } : nil
        switch (stack, book) {
        case (let stack?, nil): return .stack(id: stack.id, name: stack.name)
        case (nil, let book?): return .card(id: book.id, name: book.name)
        case (_?, _?): throw ToolError(message: "\"\(name)\" is both a stack and a card. Use \"stack:\(name)\" or \"card:\(name)\".")
        case (nil, nil):
            let valid = ["all_cards"] + model.stacks.map { "stack:\($0.name)" } + model.unhiddenBooks.map { "card:\($0.name)" }
            throw ToolError(message: "No stack or card named \"\(name)\". Valid scopes: \(valid.joined(separator: ", ")).")
        }
    }

    private func card(named name: String) throws -> BookProfile {
        if let book = model.unhiddenBooks.first(where: { Self.key($0.name) == Self.key(name) }) { return book }
        throw ToolError(message: "No card named \"\(name)\". Cards: \(model.unhiddenBooks.map(\.name).joined(separator: ", ")).")
    }

    /// Open or active card when it is in scope, else the scope's first card (CHAT_SPEC §2).
    func targetCard() throws -> BookProfile {
        let inScope = model.books(in: scope)
        let preferred = model.selectedBookID ?? model.activeBookID
        if let book = inScope.first(where: { $0.id == preferred }) ?? inScope.first { return book }
        throw ToolError(message: "There are no cards in \(Self.label(scope)). Ask which card to use.")
    }

    private func category(named name: String, in categories: [ExpenseCategory]) throws -> ExpenseCategory {
        if let match = categories.first(where: { Self.key($0.name) == Self.key(name) }) { return match }
        throw ToolError(message: "No category named \"\(name)\" on this card. Valid categories: \(categories.map(\.name).joined(separator: ", ")).")
    }

    private func scopeCategoryNames(_ target: AnalyticsFilterScope) throws -> [String] {
        guard let service = model.expenseService else { throw EntryError.corruptStore }
        var seen = Set<String>()
        return try model.books(in: target).flatMap { try service.categories(for: $0.id) }.map(\.name).filter { seen.insert(Self.key($0)).inserted }
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
    private func cycle(for target: AnalyticsFilterScope) -> BudgetCycle? {
        guard case .card(let id, _) = target, let budgets = try? model.expenseService?.budgets(for: id) else { return nil }
        return BudgetHistory.period(containing: now, budgets: budgets)?.cycle
    }

    private func report(_ period: Period, scope target: AnalyticsFilterScope) throws -> AnalyticsReport {
        let report = AnalyticsReport.build(data: model.reportingData(for: target), horizon: period.horizon, now: now)
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
