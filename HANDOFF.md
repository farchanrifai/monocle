## 1. Immediate Next Step

Fixed both known AI Chat bugs (Apple on-device backend); merged into `feat/apple-intelligence-chat` (commit `3657720`, pushed). Do NOT merge to main until the user says so.

- "updated"/"saved" before confirm: `AppleChatAgent.claimsDone` drops the reply text when the turn shows a proposal/change/bill card and the text uses a done verb (EN + ID word list).
- "what categories?" echoing the list: Apple's app_context no longer lists categories (`ChatAgent.context(listCategories: false)`); instead `category` in the propose_* tool schemas is an enum of the target card's categories (session rebuilt when they change). Claude backend unchanged.
- On-device probe (`AppleChatTests.testGoldenPromptsOnDevice`): 9/11 → 10/11. Remaining ✗: the 3-turn follow-up "what categories?" answers this month instead of keeping last month (period carry-over, separate issue). Netflix bill picked category Wellbeing and record automatic (valid but odd).
- Verified: Mac unit tests 20 pass (1 skipped), iOS sim build OK. Mac UI tests not run; Claude golden prompts not rerun (Claude path only lost nothing; context default unchanged); no IPA built.

Still open (AI Chat): live check of Quick Chat, charts, @ picker (Mac + iOS on device); keep/remove Apple backend decision; follow-up period carry-over; proxy before sharing; chat v2 streaming + localized strings. Mac Analytics live feedback (previous checkpoint) still pending.

Mac toolbar (commit `a88a4e3`, pushed): window title hidden (`.windowToolbarStyle(.unified(showsTitle: false))` in MonocleMacApp; each page draws its own large title) and toolbar background hidden so every page matches. `.toolbar` sits on the detail column in MacRootView (on the split view, macOS 26 ignored `ToolbarSpacer`); layout (Search) (Commands | Inspector) (+), inspector icon `pointer.arrow.click`. Verified by window capture.
- Screen checks without focus: `screencapture -x -o -l <windowID>` works (window id via CGWindowListCopyWindowInfo, owner "Monocle"); the window must be on screen, not in the Stage Manager strip. A post-launch capture showed an empty sidebar Cards section and 0 bills in the demo; likely still loading, unconfirmed.

## 2. Last Completed Checkpoint


User is live-checking the Mac Analytics page in the demo workspace (branch `feat/apple-intelligence-chat`, pushed, last commit `974fae4`). Ask for feedback; do NOT merge to main until the user says so. Launch: `open --env MONOCLE_DEMO=1 ~/Library/Developer/Xcode/DerivedData/Monocle-euhlpsgynpyfmfajgbppbaiqkptd/Build/Products/Debug/Monocle.app` (kill the running app first).

Mac Analytics (`MonocleMac/Features/MacPlanningViews.swift`, `MacAnalyticsView`):
- Row: scope pill (All cards / stack / card; follows last sidebar card or stack via `MacAppState.analyticsScope`) | period pills (This month hidden when it equals the cycle) | Custom | start and end date pills (open `MonthCalendar`, a SwiftUI grid; clicking switches to Custom).
- Tiles: Total, Average per active day, vs previous (same length), Biggest day.
- Equal-height card pairs (`cardRow`, `ChartCard` with click info popover): Spending over time | By category (`BarList` rows; Charts overlapped labels), Cumulative | By weekday, By card (hidden for single card) | Largest transactions. Hover tooltips (`HoverOverlay`, `ChartTooltip`) on the three Charts.
- Single card uses its own budget cycle; stacks/all cards use the calendar month (as iOS).
- New app icon cherry-picked from `worktree-app-icon-grid-cross` (0.7.29 build 94).
- Not seen by me on screen: cmux Computer Use helper was down. Mac unit tests 19 pass (1 skipped); Mac UI tests not run; no IPA built.

Earlier open items (from previous checkpoint) still apply: Quick Chat live check, chat backend decision (Apple on-device keep or remove), iOS side of charts/@ picker unchecked on device, older Mac backlog.

