import Foundation

enum WidgetSnapshotUpdater {
    @discardableResult
    static func update(
        activeBook: BookProfile,
        activeStack: CardStack? = nil,
        allBooks: [BookProfile] = [],
        expenses: [Expense],
        stackExpenses: [Expense] = [],
        categories: [ExpenseCategory],
        captureCategories: [ExpenseCategory]? = nil,
        budget: BudgetVersion?,
        cycle: BudgetCycle?,
        revision: UInt64? = nil
    ) -> WidgetSnapshot {
        let budgetSummary: WidgetBudgetSummary? = {
            guard let budget, let cycle else { return nil }
            let cycleExpenses = expenses.filter { cycle.contains($0) }
            let spent = Money.sum(cycleExpenses.map(\.amount))
            let remaining = budget.overallLimit - spent
            let percentage = min(1.0, max(0.0, Double(spent) / Double(max(1, budget.overallLimit))))
            let nowDay = Day.calendar.startOfDay(for: .now)
            let endDay = Day.calendar.startOfDay(for: cycle.end)
            let days = max(0, Day.calendar.dateComponents([.day], from: nowDay, to: endDay).day ?? 0)
            let dailyPace = days > 0 ? max(0, remaining / Int64(days)) : 0

            return WidgetBudgetSummary(
                limit: budget.overallLimit,
                spent: spent,
                remaining: remaining,
                percentage: percentage,
                daysRemaining: days,
                dailyPaceRemaining: dailyPace,
                cycleStartDate: cycle.start,
                cycleEndDate: cycle.end,
                cycleLabel: cycle.label
            )
        }()

        let stackSummary: WidgetStackSummary? = {
            guard let activeStack else { return nil }
            let cardNames = allBooks.filter { activeStack.cardIDs.contains($0.id) }.map(\.name)
            let total = Money.sum(stackExpenses.map(\.amount))
            return WidgetStackSummary(
                id: activeStack.id,
                name: activeStack.name,
                icon: activeStack.icon,
                cardCount: activeStack.cardIDs.count,
                totalSpent: total,
                cardNames: cardNames
            )
        }()

        let todayStr = Day.string(.now)
        let todayExpenses = expenses.filter { $0.day == todayStr }
        let todaySpent = Money.sum(todayExpenses.map(\.amount))

        let recentItems: [WidgetTransactionItem] = expenses.prefix(3).map { exp in
            let cat = categories.first(where: { $0.id == exp.allocations.first?.categoryID })
            let note = exp.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (!note.isEmpty) ? note : (cat?.name ?? "Expense")
            return WidgetTransactionItem(
                id: exp.id,
                bookID: exp.bookID,
                title: title,
                amount: exp.amount,
                categoryName: cat?.name ?? "General",
                categorySymbol: cat?.symbol ?? "tag.fill",
                day: Day.title(exp.day),
                timeFormatted: exp.createdAt.formatted(date: .omitted, time: .shortened)
            )
        }

        let quickCategories: [WidgetCategoryItem] = (captureCategories ?? categories).prefix(3).map { cat in
            WidgetCategoryItem(id: cat.id, name: cat.name, symbol: cat.symbol)
        }

        let snapshot = WidgetSnapshot(
            updatedAt: .now,
            reportingDay: todayStr,
            revision: revision,
            activeBook: WidgetBookSummary(id: activeBook.id, name: activeBook.name),
            activeStack: stackSummary,
            cycleBudget: budgetSummary,
            todaySpending: WidgetTodaySummary(
                totalSpent: todaySpent,
                transactionCount: todayExpenses.count,
                recentTransactions: Array(recentItems)
            ),
            quickCategories: quickCategories
        )

        do { try WidgetSnapshotStore.writeSnapshot(snapshot) }
        catch { BackendDiagnostics.widgetPublicationFailed() }
        return snapshot
    }
}
