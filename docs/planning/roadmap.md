# monocle — goals, milestones, and continuation roadmap

Updated: 2026-09-09. This is the implementation roadmap. Product requirements remain in `product-spec.md`; dependency and data decisions are in `architecture.md`. Read the root `HANDOFF.md` for the latest local checkpoint and `docs/prototype/README.md` for build evidence.

## Product goal

Make recording and understanding personal spending pleasant enough to use every day. The first real use is a local workspace of user-defined IDR books on iPhone. A native Mac app follows. iCloud sync and shared books come near public release. Preserve the user's records across every update once real-data use begins.

The user values a quick coffee entry (`+ → amount → category → optional note → Record`), an alternative `Coffee 28k` text flow, clear amounts, native-feeling motion, and subtle haptics. The interface should remain responsive without requiring cloud or AI services.

## Status vocabulary

- **Implemented:** code exists and its recorded checks pass. This does not mean every phone integration is verified.
- **Prototype:** interactive preview; do not imply production scheduling, history, or security.
- **Pending:** required work with explicit exit criteria below.
- **Deferred:** deliberately later work; preserve design boundaries without adding speculative implementations.

## Milestone map

| Milestone | Status | Outcome / exit gate |
| --- | --- | --- |
| M0 — product and architecture decisions | Completed baseline | Apple-only scope, local Core Data, exact money, future sharing, entry modes, bill preferences, and planning location recorded |
| M1 — native interaction and installation | Implemented prototype; phone integration checks pending | User installed 0.1.0 on iPhone 15 Pro and reported working functions/snappy navigation. Updated UI, signed Shortcuts, refresh and update preservation need phone review |
| M2a — local dependency structure | Implemented | Shared expense service, injected value-only store boundary, atomic local state adapter, isolated sample seeder; failed-write and reopen tests |
| M2b — capture polish and category editor | Implemented; phone validation pending | System separators; separate glass navigation/+ islands; stationary category selection; category grid; create/rename/icon selection and protected deletion. Verify locale parsing and category persistence/history |
| M2c — reliable backup and restoration | Implemented; phone validation pending | Full portable export, validated preview, safety backup, recoverable restore, old-store/update fixtures and failure tests |
| M2d — remaining reliable capture and lock | Implemented locally; signed-phone validation pending | Optional Face ID/device-passcode lock, split editing, structured Shortcuts, category archive/rules and explicit empty real-book onboarding are implemented; signed-phone validation remains |
| M3 — production budgets and bills | Budget first slice implemented; bills pending | Effective-dated budget history and cycle transitions are persisted locally. Remaining gate: persisted schedules/occurrences, pending/automatic reconciliation, catch-up/skip handling and optional reminders |
| M3b — multi-book workspace and Wallet-style home | Design accepted; implementation pending | User-defined local books, customizable visible book stack, per-book history, visible/all activity scope, all-books menu, hero images, and book-scoped entry/Shortcuts/backups |
| M4 — CSV and v1 completion | Pending | Reviewed mapping/import with reconciliation, CSV export, complete accessibility and recovery audit |
| M5 — native Mac, iCloud, sharing, public release | Deferred | Reuse domain/data code, validate multi-device conflict/ownership behaviour, production cloud schema and distribution checks |

## Immediate sequence for the next coding session

1. Read HANDOFF, confirm branch/status and latest test evidence. Preserve the store identity and user edits.
2. Review [backup format and recovery protocol](backup-format.md). The automated round-trip/failure tests are implemented; collect signed-phone Files export/import and update-preservation evidence using sample records when the user is available.
3. Validate M2d app lock on a signed phone: optional device authentication, Face ID/system passcode fallback and timeout choices immediately/1 minute/5 minutes, including both Shortcuts. Never infer a lock from an authentication-policy declaration alone.
4. Validate both structured and text Add Expense Shortcuts on a signed phone, including custom/renamed category resolution, device authentication, failure messages and repeated actions. Split editing is implemented locally and still needs signed-phone validation.
5. Validate real-book onboarding on a signed phone: it must retain categories/settings, clear only the explicitly selected sample entries and draft, create a safety backup, and export/restore a format-2 backup. Do not silently reset or replace the sample book.
6. Continue M3 with persisted bill rules and occurrences, then add pending/automatic reconciliation, reminders, catch-up and skip handling behind the same local write boundary.
7. In parallel, explore M3b's book-stack home as a bounded UI prototype. Compare category/book/budget representations without changing production navigation yet; use the selected direction to guide implementation.
8. Before implementing multi-book UI, audit every expense/category/budget/bill/draft/Shortcut path for explicit book scope and extend backup/restore to all books and book images.
9. Re-evaluate every daily-use gate below; build an incremented IPA and update docs/HANDOFF with actual evidence. Keep previous artifacts.

## Daily-use gate — not yet met

All of these must pass before inviting real financial records:

- Manual/text/edit/repeat/split entry persists correctly, rejects invalid values and remains safe on repeated actions. Split editing is implemented; signed-phone evidence is still required.
- Draft interruption recovery and intentional discard work; failures retain the user's input.
- Full backup restores into a fresh installation with matching IDs and totals; failed restore never destroys the active book.
- Update the actual SideStore installation over the existing app and verify records and Shortcuts remain. Do not uninstall to update.
- Optional app lock: Face ID, system passcode fallback, timeout choices and locked/unlocked entry paths are tested on device. The implementation exists; signed-phone evidence is still required.
- User approves the current phone layout, reachability, haptic strength and familiar-entry speed.
- Real-book onboarding removes reliance on sample data without resetting the existing sample store implicitly.

## M3 specifics and open decisions

Budgets: overall and category limits are independent; no carry-forward initially. Persist effective dates and period history. Start days clamp at month end. An amount change with the same start day applies at the current cycle start or next cycle start; a start-day change applies at the old cycle end and creates a transition period through the next boundary under the new start day. The transition uses the new budget amount, with inclusive starts and exclusive ends. This budget slice is implemented locally and covered by domain, persistence, backup and migration checks.

Bills: persist rule and occurrence identities, recording mode, reminder preference and pending/recorded/skipped states. Reconcile missed background runs on app execution without duplicates. Pending items do not count as spending. Decide recurrence frequencies and edit/skip semantics before implementation. Notification refusal must not prevent manual recording.

### M3b — Multi-book workspace and book-stack home

Books are generic local containers, not bank accounts, cards, or fixed-purpose types. A book may represent daily expenses, travel, bills, projects, or any other expense-tracking context. Do not add a `BookType` until it changes behavior.

The home screen uses an Apple Wallet-inspired stacked-card interaction with Monocle's own Apple-plus-Teenage-Engineering visual language: Apple supplies clarity, accessibility, progressive disclosure and responsive motion; Teenage Engineering supplies modular layouts, bold book colors, oversized typography, compact metadata and tactile personality. This is an interaction and visual reference, not a pixel-for-pixel Wallet clone.

The visible stack is user-customizable by book and order. All books remain reachable through the options menu. Tapping a book focuses its hero card and shows that book's transaction list. All Activities has two initial scopes: visible books or all books. A book hero image is app-owned, downsampled, backed up and allowed to fall back to a generated color treatment.

The existing `Book` foundation should be extended rather than replaced. Do not persist a separate WalletCard entity; derive cards from book data and presentation preferences. Every transaction, category, budget, bill, occurrence, draft and Shortcut write must have an explicit target book. Multi-book local storage is distinct from future shared iCloud books.

## M4 specifics

CSV import requires mapping, preview, row validation and suspected-duplicate review; identical real purchases may be legitimate. Report accepted/rejected/skipped counts and amounts. Decide refunds, zero values and fractional rupiah before accepting them. Export CSV for interchange; it is not a substitute for full backup.

Audit large Dynamic Type, VoiceOver, Reduce Motion, reduced transparency, light/dark appearance and real device responsiveness. Confirm all persisted entities are included in backup whenever the model expands.

## M5 boundaries

No cloud entitlement, app server, account system or speculative package is needed now. Core Data relationships leave room for CloudKit, but sharing is not a switch. Define roles, ownership, conflict resolution, leaving a share and restore interactions; test private/shared stores, offline edits, deletions and multi-device bill deduplication. Public subscription, distribution and launch policies are separate decisions.

## Known constraints at this checkpoint

- The current build still exposes one local book in the UI. Multi-book local workspace is the next planned extension; there is no bank/card/account model and no multi-book implementation yet.
- Money remains IDR with exact Int64 minor units. Display and text separators follow the system locale. Entry accepts whole rupiah only; a localized decimal with `k` may yield whole rupiah. No silent fractional rounding or currency conversion.
- Starter text keywords map to stable starter category IDs. Renaming does not change mappings. Custom keyword/rule editing is pending; custom categories can be chosen manually.
- Category editor supports create/rename/curated icon selection and deletion only when unused. Recorded references, the current draft and Undo are protected. Archive/reorder and book-specific keyword rules remain pending.
- All categories now uses a full-height searchable grid. This is a monocle picker, not an exact recreation of Messages.
- The custom bottom navigation retains TabView screen state, hides its visible native bar, and supplies accessible destination buttons plus a separate dark glass add button. At accessibility text sizes destination icons retain full accessibility labels.
- Backup/restore is implemented with a safety document and restart rollback journal. Signed-phone validation remains pending. App lock now has an optional Face ID/device-passcode flow with immediate/1-minute/5-minute timeout, split editing has a two-or-more-category allocation editor with exact-total validation, and structured Shortcuts accept an amount, live category, optional note and optional date through the shared service; signed-phone validation remains pending. Budget history and V1-to-V2 migration are implemented locally; real bill schedules, CSV, sync and multi-book UI remain unimplemented.

## Working conventions for GPT-5.6 Terra continuation

Use existing Swift 6/SwiftUI/Core Data boundaries. Keep AppModel focused on presentation; UI and text Shortcuts share ExpenseService. Managed objects stay inside the repository. Inject dependencies for failure tests; do not add broad architecture frameworks or placeholder services.

The root HANDOFF has only Immediate Next Step and Last Completed Checkpoint sections. Rotate it at completed milestones; it is local and ignored by Git. Keep this roadmap and the architecture/status documents committed so another machine also has context. Record precisely what passed and what still requires the user's phone. Do not treat a previous prototype promise as test evidence.
