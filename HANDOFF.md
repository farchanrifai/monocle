## 1. Immediate Next Step

User is live-checking the Mac Analytics page in the demo workspace (branch `feat/apple-intelligence-chat`, pushed, last commit `974fae4`). Ask for feedback; do NOT merge to main until the user says so. Launch: `open --env MONOCLE_DEMO=1 ~/Library/Developer/Xcode/DerivedData/Monocle-euhlpsgynpyfmfajgbppbaiqkptd/Build/Products/Debug/Monocle.app` (kill the running app first).

Mac Analytics (`MonocleMac/Features/MacPlanningViews.swift`, `MacAnalyticsView`):
- Row: scope pill (All cards / stack / card; follows last sidebar card or stack via `MacAppState.analyticsScope`) | period pills (This month hidden when it equals the cycle) | Custom | start and end date pills (open `MonthCalendar`, a SwiftUI grid; clicking switches to Custom).
- Tiles: Total, Average per active day, vs previous (same length), Biggest day.
- Equal-height card pairs (`cardRow`, `ChartCard` with click info popover): Spending over time | By category (`BarList` rows; Charts overlapped labels), Cumulative | By weekday, By card (hidden for single card) | Largest transactions. Hover tooltips (`HoverOverlay`, `ChartTooltip`) on the three Charts.
- Single card uses its own budget cycle; stacks/all cards use the calendar month (as iOS).
- New app icon cherry-picked from `worktree-app-icon-grid-cross` (0.7.29 build 94).
- Not seen by me on screen: cmux Computer Use helper was down. Mac unit tests 19 pass (1 skipped); Mac UI tests not run; no IPA built.

Earlier open items (from previous checkpoint) still apply: Quick Chat live check, chat backend decision (Apple on-device keep or remove), iOS side of charts/@ picker unchecked on device, older Mac backlog.

## 2. Last Completed Checkpoint

User is testing the demo app (Quick Chat, charts, @ picker, demo data). Start the next session by asking for their feedback and fixing what they found. Branch `feat/apple-intelligence-chat` (ahead of main; last feature commit `f5a0172`); do NOT merge to main until the user says it's ready.

Working mode (user, 2026-10-10): build and test in the demo workspace, not the user's real data.
- Launch: `open --env MONOCLE_DEMO=1 ~/Library/Developer/Xcode/DerivedData/Monocle-euhlpsgynpyfmfajgbppbaiqkptd/Build/Products/Debug/Monocle.app` (kill the running Debug app first; `open` alone just fronts an old instance).
- Folder `…/Containers/com.farchan.monocle.mac/Data/Library/Application Support/monocle-demo`, seeded once (marker `demo-seeded`) by `Monocle/Persistence/DemoWorkspace.swift` (DEBUG only) through `model.restoreWorkspaceBackup`: Daily, Household, Work, Tokyo Trip, Bali Trip in stacks Everyday/Travel/Work, ~1,555 expenses over a year, splits, budgets with category limits, bills. Delete the folder to reseed. Real data (`monocle-mac`) untouched.

Built this session, needs the user's live check:
- **Quick Chat** (Mac): global ⌃⌥⌘C (`MacCommandID.quickChat`, rebindable) opens `QuickChatPanelController` (MacChatView.swift): non-activating floating panel reusing `QuickRecordPanelController.makePanel`, `MacChatView(compact: true)`, same `model.chat` session as the Chat page. "Open in Monocle" → `state.openChatInApp()` (destination .chat, `bringMainWindowForward`, reopens via `openWindow(id: "main")`). Shortcut again or Esc hides; frame autosaved. `GlobalHotKeyController(id:)` now filters by hotkey id so two hotkeys coexist. Not opened by me (would need a synthetic keypress); crash risk = window sizing loop like Quick Record had, mitigated with `sizingOptions = []`.
- **Charts**: `ChatChart` (ChatSession.swift; styles donut, bars, trend, comparison, budget) built in ToolExecutor for get_summary (category/card/day), compare_periods, get_budget_status; drawn by `ChatChartView.swift` (donut via Charts, the rest plain SwiftUI rows). Old `.summary` rows still render. Prompt tells the model not to repeat charted numbers. `MonocleMacTests/ChatChartRenderTests` writes PNGs at 640 and 345 widths to `…/Data/tmp/chat-charts/`.
- **@ picker**: `ChatMentionList` (ChatTranscript.swift) overlays above the input on iOS and Mac; ↑/↓ + Return on Mac; picking sets scope via `ChatScopeMenuItems.select`.
- **Mac Open Settings** fixed via SwiftUI `openSettings` captured in `MacAppState`.

Chat backends (both behind `ChatBackend`; Settings ▸ AI Chat ▸ Model, `UserDefaults "chatBackend"`):
- Claude Haiku 5.5 is the user's preferred backend ("much better"). All golden prompts pass. Run: boot sim `D00AEC79-1687-4DA1-B1B6-D6EAB3E8CA47`, then `TEST_RUNNER_ANTHROPIC_API_KEY=$(cat ~/.monocle-anthropic-key) xcodebuild test -project Monocle.xcodeproj -scheme Monocle -destination 'id=D00AEC79-…' -only-testing:MonocleTests/ChatGoldenPromptTests` (key file is the user's; never print it). The key is also saved in the Mac app's Keychain.
- Apple Intelligence on-device (`AppleChatAgent.swift`) kept as an option; 9/11 on `AppleChatTests.testGoldenPromptsOnDevice` (wording-sensitive). PCC not available to the user. Open decision: keep or remove it.

Open items: user feedback on the above; model sometimes says "updated" before the user confirms; "what categories?" answered with the category list; iOS side of charts/@ not checked on a device (no IPA built this session); proxy only before chat is shared beyond the user. Older backlog: live-check Mac Tab order (incl. Date), sidebar collapse/Show More, card/stack menus, photo pick, Quick Record over full-screen apps; Quick Record UI tweaks; prominent glass buttons blue vs red (ask); Mac category management; chat v2 streaming + localized strings; F26 background persistence; M4 accessibility audit; stale docs/planning/roadmap.md.
