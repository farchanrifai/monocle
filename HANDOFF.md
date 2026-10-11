## 1. Immediate Next Step

Nothing is half-done. Start by installing 0.8.3 (98) from SideStore and looking at the iOS screens, which nobody has seen on a device yet, then decide what to keep. Everything is committed and pushed; the working tree was clean after the 0.8.3 commit.

**Branches (stacked, each is a fast-forward of the one before):** `feat/model-b` (`fd5aaa7`, budget model/UI + Mac budget polish) -> `feat/mac-activity-filters` (`d1cdb0c`, Mac filter + card stats, 0.8.1) -> `fix/ios-nav-polish` (HEAD, iOS navigation, Budgets tab, 0.8.3). Worktree `.claude/worktrees/model-b` is on `fix/ios-nav-polish`. The user has not approved any merge; do not merge to main (`feat/apple-intelligence-chat` must merge first). The user said they will review the Mac filter work before keeping it, so merge or drop `feat/mac-activity-filters` only on their word (it sits under the iOS work, so dropping it means rebasing `fix/ios-nav-polish`).

**Things to check on the phone (0.8.3 (98)):**
- Home / Budgets are the two tabs; Analytics is the chart button in the Budgets top bar (pushed on the Budgets stack) and also opens from the card back's Analytics button (pushed on Home).
- Budgets, Bills, Analytics and Expense Details are pushed (system back + edge swipe). The floating bottom bar hides on pushed screens (`AppModel.pushedDepth`, `.hidesBottomNavigation(model)`).
- The stack/card switcher is the "Daily · 1" pill next to "Recent Expenses" (a Menu); the old toolbar layers button is gone. The pill only exists on the Home list, not on an open card.
- Budgets picker (cards, stacks), per-card edit pencil in a stack's "By card" list, Analytics "Budget vs actual" card.

**Known gaps / ideas, none blocking:**
- Options menu "Tools & Insights" no longer has Budgets (it is a tab); widget deep link `monocle://budgets` selects the tab, `monocle://analytics` opens Analytics from Home. Not tested on a device.
- `UINavigationController` is globally extended (`BottomNavigation.swift`) so the edge swipe survives hidden nav bars; if a pushed screen misbehaves, look there first.
- Stack cap is current-only (past stack cycles use today's cap); versioning it needs `BudgetVersion.stackID` and backup format 9.
- Stack and all-cards totals convert foreign-currency cards at today's rate (marked ≈), so past cycles re-value.
- Saving a "Total until" goal replaces the cycle budget stored on the same `effectiveDay`.
- Mac: no Mac UI tests were run this session (they take over the screen; run only when the user is away). None cover the new budget picker, filter popover or card stats. The Mac Release app in `~/Applications` is old (`MONOCLE_SIGNING_IDENTITY="Clipboard Dev" scripts/build-macos.sh --install`).
- Mac screens seen via screenshots only for the card page, Budgets, Bills; the filter popover was reviewed by the user from a screenshot.
- Older open items: `docs/planning/roadmap.md` is stale (2026-09-09); privacy policy / App Store label must mention the Frankfurter (ECB) rate request; demo card still named "Sample book".

**Workflow notes for this repo:**
- After every Mac rebuild, launch the demo: `open -n --env MONOCLE_DEMO=1 build/macos/DebugDerived/Build/Products/Debug/Monocle.app` (run `pkill -f "Debug/Monocle.app/Contents/MacOS/Monocle"` first).
- Publishing an IPA: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, `xcodegen generate`, then `scripts/build-ipa.sh "notes"` (builds, copies to iCloud `Monocle-codex/`, publishes to `farchanrifai/monocle-releases`). Report filename + SHA-256. Run `xcodegen generate` whenever a Swift file is added or `project.yml` changes.
- iOS simulator for tests: iPhone 17, id `3671E817-3295-439C-9A7D-ABE326ACF481`. The first run after a long idle can hang ("test runner hung before establishing connection"): `xcrun simctl shutdown all`, boot it again, rerun with `test-without-building`.
- The shell blocks compound commands in this worktree (heredocs with git-like text, loops with computed sed args): write scripts to `$CLAUDE_JOB_DIR/tmp` with the Write tool and run them as one plain command.

## 2. Last Completed Checkpoint

Budget redesign, Mac polish and iOS navigation rework, shipped as SideStore **0.8.3 (98)**: `monocle-0.8.3-build-98-unsigned.ipa`, SHA-256 `a69836a9cbac6d01be9c2030b53df3260afb6a317bb081d0f25f827930e0ba68` (also in iCloud `Monocle-codex/`, earlier IPAs 0.8.0 (95), 0.8.1 (96), 0.8.2 (97) kept). Verified: iOS unit 233 pass (4 skipped); iOS UI tests that touch these screens pass on the simulator (budget/bills, edge swipe, analytics navigation, options menu, card flip, stack filter, transaction detail); Mac unit 22 pass (run before the iOS-only changes); Mac and iOS builds succeed. Not verified: any iOS screen on a device.

**Budget model and UI** (`Monocle/Domain/BudgetStatus.swift`, no storage or backup change): `BudgetStatus` / `BudgetCycleResult` are computed from the existing effective-dated `BudgetVersion`s. Stack budget = its cap, else the sum of the cards' non-goal budgets as of that cycle (stack cycle = calendar month or `capStartDay`). Expired "Total until" goals end (`BudgetHistory.active`); projection scales total spend. Any card's budget is editable (`AppModel.saveBudget(..., cardID:)`, leaves the active card's settings alone). Shared views `BudgetLineRows`, `BudgetCyclesChart` (`Monocle/Features/BudgetStatusViews.swift`, also compiled into the Mac target). iOS `BudgetsView` and Mac `MacBudgetsView` have a card/stack picker, lines, cycle-by-cycle chart; Analytics has "Budget vs actual" plus the cycle chart on both platforms.

**Mac (branch `feat/mac-activity-filters`):** toolbar Filter beside Search (collapsible Category/Date/Card, counts, multi-select, Clear, hidden on pages without a full table; state in `MacAppState.activityFilter` / `filterOptions`), wider search (note, card, Paid with, amount), quick stats beside the card on a card page (`MacCardStats.swift`), Budgets and Bills as natural-height grids.

**iOS (branch `fix/ios-nav-polish`):** pushed navigation instead of sheets, edge-swipe back, stack switcher in the Recent Expenses pill, Budgets as a main tab with an Analytics button in its top bar, `Expense`/`Split` made Hashable (Expense hashes by id).

Earlier: model B phases 0-6 (preview 0.8.0 (95), upgrades data to Core Data V5 / backup format 8; back up first, older builds can't open it), Mac UI polish; plan and deviations in `docs/planning/model-b-plan.md`.
