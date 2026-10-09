## 1. Immediate Next Step

2026-10-10: Bill pause. `BillRule.isActive` already existed (Mac editor had an Active toggle) but pause was broken. `ExpenseService.saveBill` now: pausing deletes the bill's pending occurrences due after today (already-due ones stay pending for the user); resuming sets `scheduleEffectiveDay` = today so reconciliation never backfills the paused gap (automatic bills used to record expenses for every missed date). iOS `BillsView`: paused bills stay in Scheduled Bills (sorted last, orange "Paused" badge) instead of vanishing; editor has a "Pause bill" toggle (`billPauseToggle`); save no longer forces `isActive: true`. Test `testPauseDropsLookaheadAndResumeDoesNotBackfill`. iOS 200 unit + Mac 9 unit pass. UI tests not run. Uncommitted.

Next: user reviews/commits bill pause. Then: fix the 3 pre-existing iOS UI failures (chat opt-in, appearance picker, tab island). Live chat still blocked on Anthropic credit top-up.

Other pending: proxy (Cloudflare Worker; user deploys), golden-prompt script; when billing works: live golden prompts + verify cache reads.

## 2. Last Completed Checkpoint

2026-10-10: Mac multi-select + chat inspector. Inspector column hidden (and its toolbar toggle disabled) on Chat. Expense tables now select many (⌘/⇧-click): `MacInspectorSelection.expenses(Set<UUID>)` + `expenseIDs` / `init?(expenseIDs:)`; table binds a `Set` through the same single inspector selection. `MacAppState.delete([Expense], undoManager:)` (single delete now routes through it) and `recategorize(_:to:undoManager:)` — each one undo/redo step; recategorize skips split expenses; `sharedCategories(for:)` = categories active on every selected card. Context menu: single row adds "Change Category"; several rows get "Change Category" + "Delete N Expenses"; Delete key deletes all selected; double-click edit only for one row. `MultiExpenseInspector`: count, date range, total, by-category totals, split count, Change Category + Delete N actions. Tests: `testBulkDeleteAndRecategorizeUndoAsOneStep` (unit), `testMultiSelectShowsSummaryAndDeletesWithOneUndo` (UI). Mac 9 unit + 10 UI pass; iOS builds.

Next: user reviews multi-select (rebuild: `MONOCLE_SIGNING_IDENTITY="Clipboard Dev" scripts/build-macos.sh --install`). Then: bill pause, or fix the 3 pre-existing iOS UI failures (chat opt-in, appearance picker, tab island). Live chat still blocked on Anthropic credit top-up.

Other pending: proxy (Cloudflare Worker; user deploys), golden-prompt script; when billing works: live golden prompts + verify cache reads.
