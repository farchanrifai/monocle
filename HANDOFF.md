## 1. Immediate Next Step

Budget UI + budget-vs-actual built (see checkpoint). Not yet seen on screen: ask the user to check the demo app (iOS Budgets tab picker, Mac Budgets picker, Analytics "Budget vs actual" card), then discuss what is left:
- Stack cap is current-only (past stack cycles use today's cap); versioned caps would need `BudgetVersion.stackID` and a format-9 change.
- Currency drift: stack/all-cards totals convert at today's rate (marked ≈), past cycles too.
- Saving a goal replaces the cycle budget stored on the same `effectiveDay`.
- Editing a budget is still active-card only (iOS and Mac); stack cap is edited under Stacks.
- No UI tests for the new pickers; Mac UI tests not rerun (skipped on purpose, they take over the screen).
- Open items from before still stand (stale roadmap, privacy label for Frankfurter, Mac Release rebuild, no merge to main).

## 2. Last Completed Checkpoint

Budget picker for cards and stacks, plus budget vs actual in analytics, on `feat/model-b`. Verified: iOS unit 232 pass (4 skipped), Mac unit 21 pass; no UI tests, no visual check.

- Domain `Monocle/Domain/BudgetStatus.swift`: `BudgetSubject` (.card/.stack), `BudgetStatus` (computed, never stored: limit, spent, pace, projected, lines, approximate), `BudgetCycleResult`, `BudgetReport` (card, cardHistory, stack, stackHistory). Stack limit = cap, else sum of the cards' non-goal budgets as of that cycle; stack cycle = calendar month or `capStartDay`. No storage or format change.
- `AnalyticsEngine.paceStatus` extracted; `AppModel.budgetStatus/budgetCycles/budgetCardInput/budgetStackInput/budgetLinesAcrossCards`.
- Shared views `Monocle/Features/BudgetStatusViews.swift` (`BudgetLineRows`, `BudgetCyclesChart`), added to the Mac target in `project.yml` (run `xcodegen generate` after adding files).
- iOS `BudgetsView` and Mac `MacBudgetsView`: subject menu (Cards, Stacks), status-driven tiles, per-category or per-card lines, cycle-by-cycle chart; Edit only for the active card. Analytics (iOS `budgetVsActualCard`, Mac `budgetVsActual`): this cycle's budget vs actual for the chosen scope (card, stack, or per card for All cards) plus last 6 cycles.
- Earlier: expired "Total until" goals end, projection scales total spend (`855d0b7`).
