## 1. Immediate Next Step

2026-10-10: iOS UI suite green again. Full run had 2 failing tests (chat opt-in already passed). Both were stale tests, not app bugs: `testSettingsAppearanceModeAndAutoSwitch` — appearance picker sits below the fold on iPhone 17 Pro Max and the lazy Form never loaded it; test now swipes up until the picker is hittable. `testTransactionPageLiquidGlassAddButtonAndPlatter` — still compared the tab island to the filter bubble, which moved to the Home header; now aligns with `chatButton`. All 3 previously-failing tests pass in a targeted rerun. Mac UI tests not run.

Next: commit the UI test fixes. Then pick from roadmap (M3 bills catch-up/reminders polish, M3b multi-book home, M4 CSV) or golden-prompt script. Live chat still blocked on Anthropic credit top-up.

Other pending: proxy (Cloudflare Worker; user deploys); when billing works: live golden prompts + verify cache reads.

## 2. Last Completed Checkpoint

2026-10-10: Bill pause. `BillRule.isActive` already existed (Mac editor had an Active toggle) but pause was broken. `ExpenseService.saveBill` now: pausing deletes the bill's pending occurrences due after today (already-due ones stay pending for the user); resuming sets `scheduleEffectiveDay` = today so reconciliation never backfills the paused gap (automatic bills used to record expenses for every missed date). iOS `BillsView`: paused bills stay in Scheduled Bills (sorted last, orange "Paused" badge) instead of vanishing; editor has a "Pause bill" toggle (`billPauseToggle`); save no longer forces `isActive: true`. Test `testPauseDropsLookaheadAndResumeDoesNotBackfill`. iOS 200 unit + Mac 9 unit pass. UI tests not run. Committed 843c150.

Next: user reviews/commits bill pause. Then: fix the 3 pre-existing iOS UI failures (chat opt-in, appearance picker, tab island). Live chat still blocked on Anthropic credit top-up.

Other pending: proxy (Cloudflare Worker; user deploys), golden-prompt script; when billing works: live golden prompts + verify cache reads.
