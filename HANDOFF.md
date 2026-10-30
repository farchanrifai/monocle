## 1. Immediate Next Step

Release polish (2026-10-30, `release/app-store`, pushed at `22ee805`). `5923d97` soft scroll-edge on every screen and sheet (iOS 27 defaults to hard). `3a6c6d4` registers `anka://` (CFBundleURLTypes in project.yml). `8abcebf` Settings > About "Contact support" mails anka@pakaryan.com (`AppLinks.support`). `f87e173` Mac chat composer is a `safeAreaBar` with the soft edge; `ProgressiveBlur` deleted (file now only holds chat colours); Mac tool-count test bumped to 11. `22ee805` Analytics' own header/isPushed/showsDismissButton removed (always pushed).

Open: owner to check on phone: #4 chat, Settings support row, sheets blur. Mac chat blur not yet seen by owner. Sim note: a stale "Open in anka" prompt from `simctl openurl` survives reboot; the sim is not Pro, so ANKA_SCREEN=analytics shows the paywall.

## 2. Last Completed Checkpoint

Native iOS 26 blur everywhere (2026-10-30, `release/app-store`). Committed `1ae82bf`: Home wraps its whole ZStack (card plane included) in a still outer ScrollView that owns the top bar via `safeAreaBar`, parked 1 pt down (the soft edge effect only draws once content is under the bar; re-pinned in `onScrollGeometryChange`). Chat: nav bar's edge effect, composer is a bottom `safeAreaBar`. Grey material headers removed; `ProgressiveBlur` is Mac chat only. Card close: other cards land critically damped (0.74 spring overshot them ~16 pt over the title strip above). `a2a2a55` adds `ANKA_SCREEN=budgets|analytics`.

Audit: Budgets, Analytics, Bills, Transaction detail, kept-card picker and onboarding Forms already scroll under standard nav bars, so they get the native effect with no change (Budgets and Analytics checked in the sim, scrolled). Sheets (Add, Settings, editors) are not full-screen and were left alone.

Open: owner to confirm the close fix and card animations on the phone; Mac chat still uses the old material fade; earlier items still open (#4 chat recheck, support email, `anka://` not in Info.plist). Phone builds: build with `-destination 'generic/platform=iOS'` (device destination times out over Wi-Fi), install with devicectl; saved builds in `build/saved/`.
