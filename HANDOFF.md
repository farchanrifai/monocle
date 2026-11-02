## 1. Immediate Next Step

Checks after the U2/U7/D7 decisions done (2026-11-02 noon, `release/app-store`, not pushed). Details: `docs/audit/2026-11-02-v1-launch.md` ▸ "Checks after the decisions".

- iOS UI tests (iPhone 17): 48 passed, 9 skipped (screenshots), 1 failed (known `testTransactionPageLiquidGlassAddButtonAndPlatter`).
- Phone: 1.0.0 (114) real Pro build from `build/phone-fast` installed and launched 2026-11-02 (free team, expires 2026-11-09). Owner runs: Control Center control, App Lock (Immediately: Control Center, banner, app switcher, an open sheet survives, Face ID asks once), Delete Card on a throwaway card, bill reminder tap (reminders fire 9:00 on the lead day). The paywall from the customizer/stack/CSV sheets needs a build without `ANKKA_FORCE_PRO`; a purchase while locked needs TestFlight.
- Store screenshots: the Oct 31 set (`build/app-store-screenshots/`) predates the Analytics tab, calendar-month budgets, the Budgets page, dotted card letters and the Add pills, so 02–07 need a retake (01-intro is still right). Demo data follows the real date, so shoot in the last ~10 days of a month (on Nov 2 the month is nearly empty: 1 expense, "Projected $26,542"). Recipe: iPhone 17 Pro Max simulator, `simctl status_bar <sim> override --time 9:41 …`, `TEST_RUNNER_ANKKA_SCREENSHOTS=1 xcodebuild test … -only-testing:AnkkaUITests/AppStoreScreenshots`, `xcresulttool export attachments`, then `python3 scripts/compose-store-screenshots.py <raw> <out>`.
- Fixed: "1 expense" (card faces and five other labels said "1 EXPENSES") `4e570d8`; screenshot runs no longer show the What's New sheet `539e26a`.
- iPad: runs as a scaled 375×667 iPhone. No app bug found (see the audit doc); nit: on small phones the keyboard covers the card designs after typing a new card's name. Simulator "Ankka SE" (iPhone SE 3rd gen, `3958A10D`) was created for this.
- Then: the App Store account (B7, prices D2, EU trader status D3) and the App Store Connect items. U16 Dynamic Type: recommended to skip for 1.0 (don't declare Larger Text).

Open outside the plan: on macOS 27.2 beta 26B5091g the Mac Debug build crashes at `Date <=` in `AnalyticsEngine` (so `AppleChatTests.testGoldenPromptsOnDevice` fails); iOS unaffected.

## 2. Last Completed Checkpoint

Second fix pass from the v1 audit done (2026-11-02 morning, `release/app-store`, commits `a29ffac`..HEAD, not pushed). Status and what's still open: `docs/audit/2026-11-02-v1-launch.md` ▸ "Status after the second fix pass".

Changed: App Lock (timer on background only, app-switcher cover in its own window so sheets and purchases survive, Face ID asks on its own), locked cards show a lock and a banner and Add opens the paywall first, card totals without a cached rate ("≈ rate unavailable"), free-week copy only when eligible, System appearance by default and one Appearance picker, Restore feedback, budget editor cents, privacy-sensitive widget amounts, bill reminder tap opens Bills, CSV credits unticked, Backup mentions iCloud Backup and Settings shows the last export, no compiler warnings, dead code removed, card back Analytics without its stale Pro gate, CSV formula neutralizing, CI on `release/**`. Verified: iOS unit 283/0 failed, iOS UI 46 passed + the 2 known failures, Mac unit 20 passed + 1 OS-beta crash (below).

Next: phone checks (Control Center control, App Lock flows incl. a purchase while locked, paywall from the customizer/stack/CSV sheets, Delete Card, bill reminder tap), then the App Store Connect items. U2, U7 and D7 are decided and done (audit doc ▸ "Owner decisions after the second pass"). Dollar intro assets: `build/marketing/intro-dollar/` (44 s website clip in the site clips' format, a 29.9 s App Preview cut at 886×1920 with a silent stereo track, and settled stills for steps 2–5); the Claude Design canvas "Ankka Onboarding" has a "Dollar version · steps 2–5" board. The store's intro screenshot (`09-intro` → `01-intro.png`) is step 1, which shows no amounts, so it needs no retake.

Open outside the plan: on macOS 27.2 beta 26B5091g the Mac Debug build crashes at `Date <=` in `AnalyticsEngine` (so `AppleChatTests.testGoldenPromptsOnDevice` fails); same before this pass, iOS unaffected.
