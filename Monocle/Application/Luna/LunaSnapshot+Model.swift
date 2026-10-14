import Foundation

extension LunaSnapshot {
    /// Reads the live workspace. Hidden cards and anything the owner did not opt into stay out.
    @MainActor
    static func build(model: AppModel, storeID: String, share: Set<Part>, now: Date = .now) -> LunaSnapshot {
        let cards = model.unhiddenCards
        var snapshot = LunaSnapshot(
            storeID: storeID, revision: Int64(now.timeIntervalSince1970 * 1000), generatedAt: isoString(now),
            categories: Part.allCases.filter(share.contains).map(\.rawValue),
            cards: cards.map { .init(id: $0.id.uuidString, name: $0.name, currency: model.currency(of: $0)) })

        if share.contains(.bills) {
            let hidden = Set(model.cards.map(\.id)).subtracting(cards.map(\.id))
            snapshot.bills = cards.flatMap { card -> [BillInfo] in
                let occurrences = (try? model.expenseService?.billOccurrences(for: card.id)) ?? []
                return ((try? model.expenseService?.bills(for: card.id)) ?? [])
                    .filter { !hidden.contains($0.cardID) }
                    .map { BillInfo($0, occurrences: occurrences, now: now) }
            }
        }
        if share.contains(.budgets) {
            let cardBudgets = cards.compactMap { card in model.budgetStatus(.card(card.id)).map { BudgetInfo(name: card.name, status: $0) } }
            let stackBudgets = model.stacks.compactMap { stack in model.budgetStatus(.stack(stack.id)).map { BudgetInfo(name: stack.name, status: $0) } }
            snapshot.budgets = cardBudgets + stackBudgets
        }
        if share.contains(.summary) {
            let calendar = Day.calendar
            let months = [now, calendar.date(byAdding: .month, value: -1, to: now)!].map { String(Day.string($0, calendar: calendar).prefix(7)) }
            snapshot.summary = cards.flatMap { card -> [MonthSummary] in
                let expenses = model.expenses(for: card.id)
                let names = Dictionary(((try? model.expenseService?.categories(for: card.id)) ?? []).map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
                return months.map { month in
                    MonthSummary(card: card.id, currency: model.currency(of: card), month: month, expenses: expenses,
                                 categoryNames: names, amount: { model.cardAmount($0, in: card) })
                }
            }
        }
        return snapshot
    }
}
