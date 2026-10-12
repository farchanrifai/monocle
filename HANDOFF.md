## 1. Immediate Next Step

Nothing is half-done. Everything below is merged to `main` (pushed) and 0.8.4 (99) is published to SideStore. Start by installing 0.8.4 (99) and looking at the iOS screens on a device (nobody has seen the 0.8.x iOS work on a phone yet), then pick from the open list.

**Open items (none blocking):**
- Live checks still pending: Quick Chat, charts and the `@` picker (Mac + iOS on device); Mac Analytics feedback; iOS 0.8.x screens on a device (pushed navigation, Budgets tab, stack pill, the new amount/rate layout).
- Decisions: keep or remove the Apple on-device chat backend; chat follow-up period carry-over ("what categories?" answers this month instead of last); a proxy before sharing the app; chat streaming and localized strings.
- Release housekeeping: privacy policy / App Store label must mention the Frankfurter (ECB) rate request; Mac Release app in `~/Applications` is old (`MONOCLE_SIGNING_IDENTITY="Clipboard Dev" scripts/build-macos.sh --install`); `docs/planning/roadmap.md` is stale (2026-09-09); demo card still named "Sample book".
- Known gaps from model B: stack cap is current-only (versioning needs `BudgetVersion.stackID` and backup format 9); stack and all-cards totals convert foreign cards at today's rate (marked ≈); saving a "Total until" goal replaces the cycle budget on the same `effectiveDay`; widget deep links `monocle://budgets` / `monocle://analytics` untested on a device; `UINavigationController` is globally extended in `BottomNavigation.swift` so the edge swipe survives hidden nav bars.
- Mac UI tests were not run this session (they take over the screen; run only when the user is away).

**Workflow notes for this repo:**
- Two ways to record an expense: the manual form and AI chat. Text entry ("coffee 28k" field, Entry mode picker) is gone; `ExpenseParser` stays only for the Shortcuts "record text" action. Mac amount field accepts `28k` / `Rp28.000` and converts it to grouped digits when focus leaves the field; the iOS form is keypad only.
- Golden fixtures (`MonocleTests/Fixtures`) must round-trip byte for byte. `workspace-v8.monoclebackup` is gitignored and regenerated locally: build, delete it, run `GoldenFormatTests` with `test-without-building` (it writes the fixture and fails once), run again.
- After every Mac rebuild, launch the demo: `open -n --env MONOCLE_DEMO=1 build/macos/DebugDerived/Build/Products/Debug/Monocle.app` (`pkill -x Monocle` first).
- Publishing an IPA: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, `xcodegen generate`, then `scripts/build-ipa.sh "notes"` (builds, copies to iCloud `Monocle-codex/`, publishes to `farchanrifai/monocle-releases`). Report filename + SHA-256. Run `xcodegen generate` whenever a Swift file is added or `project.yml` changes.
- iOS simulator for tests: iPhone 17. The first run after a long idle can hang ("test runner hung before establishing connection"): `xcrun simctl shutdown all`, boot it again, rerun with `test-without-building`.
- The shell blocks compound commands in a worktree-isolated session (loops with `git`, chained git calls): run plain, separate commands.

## 2. Last Completed Checkpoint

Merged everything to `main` and shipped SideStore **0.8.4 (99)**: `monocle-0.8.4-build-99-unsigned.ipa`, SHA-256 `9c646796698686b51cf8d89932d99768ede93447b657423686b62a9656df9b15` (also in iCloud `Monocle-codex/`, earlier IPAs kept). `main` is the old chat line + model B + Mac filters + iOS navigation (0.8.3) + this session's work, fast-forwarded in one chain.

**This session:** Quick Chat panel closes (button, Esc) and no longer fronts the main window. Text entry removed on both platforms, with the dead code (`EntryMode`, draft `text`/`mode`, `entryModeRaw`, `EntryFormField.quick`); old backups and drafts still load (a stored hidden `quick` field is skipped), the two golden JSON fixtures were edited by hand. Expense form: the reporting-currency equivalent (`≈ Rp…`, `ExpenseDraft.reportingEquivalent`, needs only amount + rate) sits beside the editable rate on Mac and under the rate on iOS; Mac amount shows thousands separators while typing (`Money.groupedInput`, decimals only once typed and only where the currency has them); Mac date is one line (`Oct 11, 2026`).

**Verified:** iOS unit tests 234 (4 skipped) before the last two tests were added, `MonocleTests/MonocleTests` pass after; Mac unit tests pass; Mac and iOS builds succeed; IPA built and published. Not verified: Mac UI tests, any iOS screen on a device, the new Mac form layouts beyond the user's look at the demo app.
