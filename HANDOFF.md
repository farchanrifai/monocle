## 1. Immediate Next Step

Budget deep dive, step 1 done (fixes 1 and 2 below). Discuss the rest with the user, then pick one:
- Past-cycle history: spent vs limit per past cycle, hit/miss record (no such view exists).
- Stack budgets are a stub: synthetic `BudgetVersion` at `AppModel.swift:~1305`, ignores member cards' start days, transitions, goals; no category roll-up.
- Currency drift: analytics/widgets/stack caps convert a foreign-currency card budget at today's rate, so past cycles re-value.
- Mac `MacBudgetsView` shows only the active card.
- Known gap: saving a goal replaces the cycle budget stored at the same `effectiveDay`, so a goal started on a fresh card leaves no earlier cycle version; after it ends, the fallback is `settings.budget`/`startDay` (goals no longer overwrite those).
- Open items from the earlier checkpoint still stand (stale roadmap, privacy label for Frankfurter, Mac Release rebuild, Mac UI tests not rerun, no merge to main).

## 2. Last Completed Checkpoint

Budget fixes on `feat/model-b`. Verified: iOS unit 225 pass (4 skipped); Mac tests and UI tests not run.

- Expired "Total until" goals: `BudgetHistory.active` skips a goal whose `totalUntilDay` is before the date, so the earlier cycle budget (or the settings fallback) applies again. `saveBudget` no longer overwrites `settings.budget`/`startDay` when saving a goal.
- Projection: `calculateMetrics` scales total spend (`spend × days / elapsed`) instead of the truncated daily average; card back target-per-day uses `checkedScale` too.
- Tests: updated `testTotalUntilBudgetIsOnePeriodAndSwitchingBackReplacesIt`, added `testProjectionScalesTotalNotRoundedDailyAverage`.
- Earlier: Mac UI polish (Settings, Add Expense, navigation history, chart padding), model B phases 0-6 (preview 0.8.0 (95)); details in `docs/planning/model-b-plan.md`.
