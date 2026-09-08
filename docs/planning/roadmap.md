# monocle — goals, milestones, and continuation roadmap

Updated: 2026-09-08. This is the implementation roadmap. Product requirements remain in `product-spec.md`; dependency and data decisions are in `architecture.md`. Read the root `HANDOFF.md` for the latest local checkpoint and `docs/prototype/README.md` for build evidence.

## Product goal

Make recording and understanding personal spending pleasant enough to use every day. The first real use is one person's IDR book on iPhone. A native Mac app follows. iCloud sync and shared books come near public release. Preserve the user's records across every update once real-data use begins.

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
| M2b — capture polish and category editor | Current checkpoint | System separators; separate glass navigation/+ islands; stationary category selection; category grid; create/rename/icon selection and protected deletion. Verify locale parsing and category persistence/history |
| M2c — reliable backup and restoration | Implemented; phone validation pending | Full portable export, validated preview, safety backup, recoverable restore, old-store/update fixtures and failure tests |
| M2d — remaining reliable capture and lock | Pending | Split UI, structured Shortcuts, optional Face ID/device-passcode lock with timeout, category archive/rules, real-book onboarding |
| M3 — production budgets and bills | Prototype screens only | Effective-dated budget history, cycle transitions, persisted schedules/occurrences, pending/automatic reconciliation, optional reminders |
| M4 — CSV and v1 completion | Pending | Reviewed mapping/import with reconciliation, CSV export, complete accessibility and recovery audit |
| M5 — native Mac, iCloud, sharing, public release | Deferred | Reuse domain/data code, validate multi-device conflict/ownership behaviour, production cloud schema and distribution checks |

## Immediate sequence for the next coding session

1. Read HANDOFF, confirm branch/status and latest test evidence. Preserve the store identity and user edits.
2. Review [backup format and recovery protocol](backup-format.md). The automated round-trip/failure tests are implemented; collect signed-phone Files export/import and update-preservation evidence using sample records when the user is available.
3. Implement M2d app lock: optional device authentication, Face ID/system passcode fallback and timeout choices immediately/1 minute/5 minutes. Define the interaction with foreground/background Shortcuts explicitly. Never infer a lock from an authentication-policy declaration alone.
4. Complete split editing and structured Add Expense Shortcut parameters through the shared expense commands; extend failure/repeated-action tests.
5. Add category archive/rules and real-book onboarding with explicit model/backup version changes. Do not silently reset or replace the sample book.
6. Re-evaluate every daily-use gate below; build an incremented IPA and update docs/HANDOFF with actual evidence. Keep previous artifacts.

## Daily-use gate — not yet met

All of these must pass before inviting real financial records:

- Manual/text/edit/repeat/split entry persists correctly, rejects invalid values and remains safe on repeated actions.
- Draft interruption recovery and intentional discard work; failures retain the user's input.
- Full backup restores into a fresh installation with matching IDs and totals; failed restore never destroys the active book.
- Update the actual SideStore installation over the existing app and verify records and Shortcuts remain. Do not uninstall to update.
- Optional app lock: Face ID, system passcode fallback, timeout choices and locked/unlocked entry paths are tested on device.
- User approves the current phone layout, reachability, haptic strength and familiar-entry speed.
- Real-book onboarding removes reliance on sample data without resetting the existing sample store implicitly.

## M3 specifics and open decisions

Budgets: overall and category limits are independent; no carry-forward initially. Persist effective dates and period history. Start days clamp at month end. Before production cycle changes, decide the transition period length and applicable limit; a visual preview is not a historical accounting implementation.

Bills: persist rule and occurrence identities, recording mode, reminder preference and pending/recorded/skipped states. Reconcile missed background runs on app execution without duplicates. Pending items do not count as spending. Decide recurrence frequencies and edit/skip semantics before implementation. Notification refusal must not prevent manual recording.

## M4 specifics

CSV import requires mapping, preview, row validation and suspected-duplicate review; identical real purchases may be legitimate. Report accepted/rejected/skipped counts and amounts. Decide refunds, zero values and fractional rupiah before accepting them. Export CSV for interchange; it is not a substitute for full backup.

Audit large Dynamic Type, VoiceOver, Reduce Motion, reduced transparency, light/dark appearance and real device responsiveness. Confirm all persisted entities are included in backup whenever the model expands.

## M5 boundaries

No cloud entitlement, app server, account system or speculative package is needed now. Core Data relationships leave room for CloudKit, but sharing is not a switch. Define roles, ownership, conflict resolution, leaving a share and restore interactions; test private/shared stores, offline edits, deletions and multi-device bill deduplication. Public subscription, distribution and launch policies are separate decisions.

## Known constraints at this checkpoint

- Storage is still one fixed sample book; no production multi-book UI.
- Money remains IDR with exact Int64 minor units. Display and text separators follow the system locale. Entry accepts whole rupiah only; a localized decimal with `k` may yield whole rupiah. No silent fractional rounding or currency conversion.
- Starter text keywords map to stable starter category IDs. Renaming does not change mappings. Custom keyword/rule editing is pending; custom categories can be chosen manually.
- Category editor supports create/rename/curated icon selection and deletion only when unused. Recorded references, the current draft and Undo are protected. Archive/reorder and book-specific keyword rules remain pending.
- All categories now uses a full-height searchable grid. This is a monocle picker, not an exact recreation of Messages.
- The custom bottom navigation retains TabView screen state, hides its visible native bar, and supplies accessible destination buttons plus a separate dark glass add button. At accessibility text sizes destination icons retain full accessibility labels.
- Backup/restore is implemented with a safety document and restart rollback journal. Signed-phone validation remains pending. App lock, production budget history, real schedules, CSV and sync remain unimplemented.

## Working conventions for GPT-5.6 Terra continuation

Use existing Swift 6/SwiftUI/Core Data boundaries. Keep AppModel focused on presentation; UI and text Shortcuts share ExpenseService. Managed objects stay inside the repository. Inject dependencies for failure tests; do not add broad architecture frameworks or placeholder services.

The root HANDOFF has only Immediate Next Step and Last Completed Checkpoint sections. Rotate it at completed milestones; it is local and ignored by Git. Keep this roadmap and the architecture/status documents committed so another machine also has context. Record precisely what passed and what still requires the user's phone. Do not treat a previous prototype promise as test evidence.
