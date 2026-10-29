## 1. Immediate Next Step

iOS polish list (owner, 2026-10-29) is done through #7 on `release/app-store`: Home stack lag and swipe-to-back, 120 Hz key, Add sheet, split sheet redesign, thousands grouping in every amount field, Settings reorganized (`SettingsView.swift`; per-card Paid with and Currency moved to the customizer's Details pane), customizer redesign (pinned carousel and name, Look | Details panes, carousel width/centering fixed). Debug launch hook `ANKA_SCREEN=entry|settings|chat|customize`. A dedicated simulator `anka-polish` avoids another project's `nc.Anka` that also claims `anka://` on the shared one.

Open: #4 chat not yet re-checked by the owner; no support email for Settings > About; `anka://` scheme is handled but not registered in Info.plist (widgets work without it); Analytics still has its own custom top bar like Home's.

Commits that add a file need a clean `project.pbxproj`: move the untracked Demo files aside, `xcodegen generate --spec <HEAD project.yml>`, stage the project file, restore the Demo files and regenerate. Demo variant files stay uncommitted.

## 2. Last Completed Checkpoint

iOS UI polish before release on `release/app-store`, from the owner's 7-point list (2026-10-29). Committed so far: Home lag fixes (expense list and card face/artwork are separate views that skip re-rendering while the stack moves), card drags measured in screen space with an axis lock (fan vertical, carry horizontal 1:1 with lift, tilt and a velocity spring; release past 45 pt sends the card to the back), "Move to Back" naming (was "Bring to Front"), 44 pt glass `…` button, bottom bar 23 pt from the screen edge like the system tab bar, customizer carousel pinned above the form, plus last night's sessions' chat, Add sheet, live preview and 9 new stock styles. Owner rejected a large-title Home header; the wordmark stays in the inline row.

Next, in order: #5 Add expense sheet (center a bolder hero amount, no divider, fix the Add button riding up behind the keyboard's Done, fade the category strip edge), check #4 chat on the phone, #6 Settings (move `SettingsView` out of `BillsView.swift`, iOS-Settings-style rows, order Pro, Card, Add sheet, Appearance, Privacy & Security, Data incl. Reset, About), #7 customizer redesign (custom scroll layout, pinned live card, stock style grid). Phone installs: optimized Debug with demo data, recipe in memory `phone-install-free-team`. Instruments over Wi-Fi fails ("Device is offline"); profile with a cable.

Demo variant files stay uncommitted (owner's call): `project.yml`, `project.pbxproj`, `AppEnvironment.swift`, `ProStore.swift`, `WidgetSnapshotStore.swift`, `MacRootView.swift`, `DemoData.swift`, both Demo entitlements.
