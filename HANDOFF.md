## 1. Immediate Next Step

Native iOS 26 blur everywhere (2026-10-30, `release/app-store`). Committed `1ae82bf`: Home wraps its whole ZStack (card plane included) in a still outer ScrollView that owns the top bar via `safeAreaBar`, parked 1 pt down (the soft edge effect only draws once content is under the bar; re-pinned in `onScrollGeometryChange`). Chat: nav bar's edge effect, composer is a bottom `safeAreaBar`. Grey material headers removed; `ProgressiveBlur` is Mac chat only. Card close: other cards land critically damped (0.74 spring overshot them ~16 pt over the title strip above). `a2a2a55` adds `ANKA_SCREEN=budgets|analytics`.

Audit: Budgets, Analytics, Bills, Transaction detail, kept-card picker and onboarding Forms already scroll under standard nav bars, so they get the native effect with no change (Budgets and Analytics checked in the sim, scrolled). Sheets (Add, Settings, editors) are not full-screen and were left alone.

Open: owner to confirm the close fix and card animations on the phone; Mac chat still uses the old material fade; earlier items still open (#4 chat recheck, support email, `anka://` not in Info.plist). Phone builds: build with `-destination 'generic/platform=iOS'` (device destination times out over Wi-Fi), install with devicectl; saved builds in `build/saved/`.

## 2. Last Completed Checkpoint

iOS polish list (owner, 2026-10-29) is done through #7 on `release/app-store`: Home stack lag and swipe-to-back, 120 Hz key, Add sheet, split sheet redesign, thousands grouping in every amount field, Settings reorganized (`SettingsView.swift`; per-card Paid with and Currency moved to the customizer's Details pane), customizer redesign (pinned carousel and name, Look | Details panes, carousel width/centering fixed). Debug launch hook `ANKA_SCREEN=entry|settings|chat|customize`. A dedicated simulator `anka-polish` avoids another project's `nc.Anka` that also claims `anka://` on the shared one.

Open: #4 chat not yet re-checked by the owner; no support email for Settings > About; `anka://` scheme is handled but not registered in Info.plist (widgets work without it); Analytics still has its own custom top bar like Home's.

Commits that add a file need a clean `project.pbxproj`: move the untracked Demo files aside, `xcodegen generate --spec <HEAD project.yml>`, stage the project file, restore the Demo files and regenerate. Demo variant files stay uncommitted.
