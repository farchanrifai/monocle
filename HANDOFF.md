## 1. Immediate Next Step

Optional iCloud sync (Pro) built and committed (2026-11-02 evening, `release/app-store` @ `cc505f1`, not pushed). Design in the commit message and `Ankka/Persistence/CloudSync.swift`; decisions in `docs/planning/app-store-release.md`.

- Verified: iOS unit tests 295 run, 0 failed, 5 skipped (StoreKit); new `CloudSyncTests` (repair of two devices' Sample cards, duplicate recorded bill, lenient reads, settings files and photos, stable bill IDs). Mac unit tests 20 passed + the known macOS-beta crash (`testGoldenPromptsOnDevice`). iOS and Mac builds clean. UI tests not run (only a Settings toggle, its footer and one paywall row changed; the toggle is hidden in UI-test folders).
- Not verified, needs the paid account: anything against CloudKit. Free-team phone builds use an empty entitlements plist, so the toggle shows but sync can't start (the store falls back to local).
- When the account is active: register container `iCloud.com.farchan.ankka` and Push for `com.farchan.ankka`; run a team-signed Debug build with sync on so the development schema gets created; two-device test (iPhone + iPad or simulator signed in to iCloud): first sync on a second device, offline edits on both, a bill due while both are offline, card photo, Reset/Restore while synced, Pro lapse turning sync off. Then **deploy the CloudKit schema to Production** in the CloudKit Console before TestFlight.
- Known limits for 1.0: settings files are newest-wins as a whole (two devices editing Stacks at once keep one side); a deleted Sample card comes back if another device still has it; photo records stay in iCloud after a card's photo changes; chat history stays per device; turning sync off then on takes iCloud's settings over this device's.
- Site: `docs/privacy.md` gained an iCloud section; mirror it to `~/Xcode/pakaryan` `src/pages/ankka/privacy.astro` and deploy (owner's call).
- Still open from before: phone checks, store screenshots in the last ~10 days of November, App Store Connect items (B7, prices D2, EU trader D3).

## 2. Last Completed Checkpoint

**Next session: build optional iCloud sync (Pro), decided 2026-11-02 afternoon.** Owner wants it in 1.0; spec in `docs/planning/app-store-release.md` ▸ Decided and Free and Pro. Plan:
1. `ExpenseRepository` → `NSPersistentCloudKitContainer` (private DB, `iCloud.com.farchan.ankka`), persistent history tracking, remote-change refresh of `AppModel`; the merge policy is `.errorMergePolicyType` today and must change. Model V5 already meets CloudKit's rules (all optional, inverses, no unique constraints, no Deny), so no model or backup-format bump for the records.
2. `workspace.json` + syncable parts of `settings.json` (`LocalStateStore`) move into one synced record, newest copy wins. Local only: App Lock timeout, draft, `keptCardID`, onboarding/What's New/review flags.
3. Dedup after import: same `id` rows (the Sample card uses the fixed `Card.demo.id` on every device), same bill rule + `dueDay` occurrences (delete the duplicate expense too).
4. Settings toggle, Pro-gated, off by default; off keeps local data. Unit tests for dedup and the settings record (in-memory).
5. Privacy policy + review notes mention iCloud. Can't run on device or simulator until the paid account exists (free team can't sign iCloud).

Checks after the U2/U7/D7 decisions done (2026-11-02 noon, `release/app-store`, not pushed). Details: `docs/audit/2026-11-02-v1-launch.md` ▸ "Checks after the decisions".

- iOS UI tests (iPhone 17): 48 passed, 9 skipped (screenshots), 1 failed (known `testTransactionPageLiquidGlassAddButtonAndPlatter`).
- Phone: 1.0.0 (114) real Pro build from `build/phone-fast` installed and launched 2026-11-02 (free team, expires 2026-11-09). Owner runs: Control Center control, App Lock (Immediately: Control Center, banner, app switcher, an open sheet survives, Face ID asks once), Delete Card on a throwaway card, bill reminder tap (reminders fire 9:00 on the lead day). The paywall from the customizer/stack/CSV sheets needs a build without `ANKKA_FORCE_PRO`; a purchase while locked needs TestFlight.
- Store screenshots: the Oct 31 set (`build/app-store-screenshots/`) predates the Analytics tab, calendar-month budgets, the Budgets page, dotted card letters and the Add pills, so 02–07 need a retake (01-intro is still right). Demo data follows the real date, so shoot in the last ~10 days of a month (on Nov 2 the month is nearly empty: 1 expense, "Projected $26,542"). Recipe: iPhone 17 Pro Max simulator, `simctl status_bar <sim> override --time 9:41 …`, `TEST_RUNNER_ANKKA_SCREENSHOTS=1 xcodebuild test … -only-testing:AnkkaUITests/AppStoreScreenshots`, `xcresulttool export attachments`, then `python3 scripts/compose-store-screenshots.py <raw> <out>`.
- Fixed: "1 expense" (card faces and five other labels said "1 EXPENSES") `4e570d8`; screenshot runs no longer show the What's New sheet `539e26a`.
- iPad: runs as a scaled 375×667 iPhone. No app bug found (see the audit doc); nit: on small phones the keyboard covers the card designs after typing a new card's name. Simulator "Ankka SE" (iPhone SE 3rd gen, `3958A10D`) was created for this.
- Then: the App Store account (B7, prices D2, EU trader status D3) and the App Store Connect items. U16 Dynamic Type: recommended to skip for 1.0 (don't declare Larger Text).

Open outside the plan: on macOS 27.2 beta 26B5091g the Mac Debug build crashes at `Date <=` in `AnalyticsEngine` (so `AppleChatTests.testGoldenPromptsOnDevice` fails); iOS unaffected.
