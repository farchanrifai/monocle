## 1. Immediate Next Step

Model B phase 1 (storage foundation) is done on `feat/model-b` (commit `e8b6180`, pushed). Next: phase 2, stacks (≤1 stack per card, one-time cleanup, "Not in a Stack", optional stack cap). Plan: `docs/planning/model-b-plan.md`.

- Core Data `MonocleV5` (optional fields only): card `currency`, `spendingCurrency`, `defaultPaidWithID`; expense `paidWithID`, `originalAmount`, `originalCurrency`, `rate`, `rateSource`; budget `totalUntilDay` (replaces the planned kind + endDay). Preferences: `paymentMethods`, `hiddenEntryFields`, `reportingCurrency`; `CardStack.capLimit`/`capStartDay`. Backup format 8 (`MONOCLE-BACKUP-8`), format 7 still imports; doc in `docs/planning/backup-format.md`. CSV export column Book → Card. Edit draft keeps Paid with; foreign amount kept only while amount unchanged.
- Verified: iOS unit tests 216 pass (4 skipped; new: V4→V5 migration, format 8 round trip, edit draft). Mac unit tests 20 pass (1 skipped). The simulator test runner sometimes hangs on the first run after a rebuild ("hung before establishing connection"); a rerun passes, and the app launches fine on migrated data. UI tests not run; no IPA built.
- Don't ship phase 1 alone: an older build can't open a V5 store.
- Follow-up: the demo card is still named "Sample book" (`BookProfile.sample.name`, stored data); rename in phase 6.
- Don't merge to main; `feat/apple-intelligence-chat` is still unmerged.

## 2. Last Completed Checkpoint

Model B phase 0 (UI wording) is done on `feat/model-b` (commit `e49a4ee`, pushed). Next: phase 1, storage foundation (Core Data V5 optional fields, `WorkspacePreferences` fields, backup format 8, CSV "Book" column → "Card" with "Book" still accepted on import). Plan: `docs/planning/model-b-plan.md`.

- Phase 0: Expense instead of Transaction/Record, Add instead of Record (Quick Add, Add automatically, "When due"), Card/Workspace instead of Book, no "card balances" text. Accessibility IDs (`recordExpense`), storage keys (`quickRecord`) and the CSV Book column unchanged.
- Verified: iOS unit tests 213 pass (4 skipped), Mac unit tests 20 pass (1 skipped). Not run: Mac/iOS UI tests (strings updated only), on-device chat golden prompts (tool wording changed slightly), no IPA built.
- User decisions: rename everything in phase 6 (incl. ~680 `bookID`); Frankfurter for exchange rates.
- Don't merge to main; `feat/apple-intelligence-chat` is still unmerged.
