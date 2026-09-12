import Foundation

enum WidgetSnapshotUpdater {
    static func update(
        activeBook: BookProfile,
        expenses: [Expense],
        categories: [ExpenseCategory],
        budget: BudgetVersion?,
        cycle: BudgetCycle?
    ) {
        let budgetSummary: WidgetBudgetSummary? = {
            guard let budget, let cycle else { return nil }
            let cycleExpenses = expenses.filter { cycle.contains($0) }
            let spent = cycleExpenses.reduce(0) { $0 + $1.amount }
            let remaining = budget.overallLimit - spent
            let percentage = min(1.0, max(0.0, Double(spent) / Double(max(1, budget.overallLimit))))
            let nowDay = Calendar.current.startOfDay(for: .now)
            let endDay = Calendar.current.startOfDay(for: cycle.end)
            let days = max(0, Calendar.current.dateComponents([.day], from: nowDay, to: endDay).day ?? 0)
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

        let todayStr = Day.string(.now)
        let todayExpenses = expenses.filter { $0.day == todayStr }
        let todaySpent = todayExpenses.reduce(0) { $0 + $1.amount }

        let recentItems: [WidgetTransactionItem] = expenses.prefix(3).map { exp in
            let cat = categories.first(where: { $0.id == exp.allocations.first?.categoryID })
            let note = exp.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = (!note.isEmpty) ? note : (cat?.name ?? "Expense")
            return WidgetTransactionItem(
                id: exp.id,
                title: title,
                amount: exp.amount,
                categoryName: cat?.name ?? "General",
                categorySymbol: cat?.symbol ?? "tag.fill",
                day: Day.title(exp.day),
                timeFormatted: exp.createdAt.formatted(date: .omitted, time: .shortened)
            )
        }

        let quickCategories: [WidgetCategoryItem] = categories.prefix(3).map { cat in
            WidgetCategoryItem(id: cat.id, name: cat.name, symbol: cat.symbol)
        }

        let snapshot = WidgetSnapshot(
            updatedAt: .now,
            activeBook: WidgetBookSummary(id: activeBook.id, name: activeBook.name),
            cycleBudget: budgetSummary,
            todaySpending: WidgetTodaySummary(
                totalSpent: todaySpent,
                transactionCount: todayExpenses.count,
                recentTransactions: Array(recentItems)
            ),
            quickCategories: quickCategories
        )

        WidgetSnapshotStore.writeSnapshot(snapshot)
    }
}
