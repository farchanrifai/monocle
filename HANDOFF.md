## 1. Immediate Next Step

Model B is fully implemented on `feat/model-b` (phases 0–6, pushed; last commit after `2ee9846`). Preview build 0.8.0 (95) is on the SideStore feed. Ask the user to try it (backup first: it upgrades data to Core Data V5 / backup format 8, older builds can't open it). Don't merge to main until the user says so; `feat/apple-intelligence-chat` must merge first.

- What shipped per phase: see commit messages and `docs/planning/model-b-plan.md` (status block lists deviations: `totalUntilDay`, display-only card-currency projection, `BudgetPeriod` kept, no ⋯ form menu, Paid with labels in use can't be deleted).
- Code names: Book → Card everywhere (files too), Allocation → Split, CardStack → Stack, BudgetCycle → Cycle, BillRule → Bill, demo card = `Card.demo`. Stored keys unchanged via CodingKeys; `GoldenFormatTests` + `MonocleTests/Fixtures` guard it.
- Verified: iOS unit 224 pass (4 skipped), Mac unit 20 pass (1 skipped), iOS UI 43/44 (`testChatOptInFromBottomBarAndCloses` fails the same on the parent commit, pre-existing). Mac UI tests could not start: macOS asked for authentication while the user was away. The simulator test runner often hangs on the first launch after a rebuild; rerun passes.
- Follow-ups: privacy policy / App Store label must mention the Frankfurter (ECB) rate request (sends only currency codes and dates, only when a non-reporting currency is used). Chat amounts stay in the reporting currency. Analytics/widgets for a card budgeted in another currency use today's cached rate. Demo card is still named "Sample book" (stored data). Data model page (artifact) could be marked "implemented".

## 2. Last Completed Checkpoint

Model B phase 1 (storage foundation) is done on `feat/model-b` (commit `e8b6180`, pushed). Next: phase 2, stacks (≤1 stack per card, one-time cleanup, "Not in a Stack", optional stack cap). Plan: `docs/planning/model-b-plan.md`.

- Core Data `MonocleV5` (optional fields only): card `currency`, `spendingCurrency`, `defaultPaidWithID`; expense `paidWithID`, `originalAmount`, `originalCurrency`, `rate`, `rateSource`; budget `totalUntilDay` (replaces the planned kind + endDay). Preferences: `paymentMethods`, `hiddenEntryFields`, `reportingCurrency`; `CardStack.capLimit`/`capStartDay`. Backup format 8 (`MONOCLE-BACKUP-8`), format 7 still imports; doc in `docs/planning/backup-format.md`. CSV export column Book → Card. Edit draft keeps Paid with; foreign amount kept only while amount unchanged.
- Verified: iOS unit tests 216 pass (4 skipped; new: V4→V5 migration, format 8 round trip, edit draft). Mac unit tests 20 pass (1 skipped). The simulator test runner sometimes hangs on the first run after a rebuild ("hung before establishing connection"); a rerun passes, and the app launches fine on migrated data. UI tests not run; no IPA built.
- Don't ship phase 1 alone: an older build can't open a V5 store.
- Follow-up: the demo card is still named "Sample book" (`BookProfile.sample.name`, stored data); rename in phase 6.
- Don't merge to main; `feat/apple-intelligence-chat` is still unmerged.
