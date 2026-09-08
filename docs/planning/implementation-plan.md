# monocle — implementation plan

Updated: 2026-09-08

Detailed milestone statuses, exit gates and next-session instructions: [roadmap](roadmap.md).

## 0. Planning baseline — completed

Product scope, capture direction, privacy choice, budgets, bill modes, future shared books, and iCloud acceptance recorded. Xcode 26.6 is available. The planning baseline is committed in local Git.

## 1. Native interaction and delivery proof — prototype built and phone UX reviewed; integration checks pending

Build a SwiftUI prototype with sample data: Recents, compact summary, one Add Expense screen with keypad/text modes, category selection, optional note, Record feedback, and draft-preserving mode changes. Include budget-cycle and configurable-bill screens for review. Refine visual direction, one-handed reach, keyboard behaviour, animation, and haptics on the phone.

Validate installation early using a minimal build: choose a stable bundle identity, produce a device IPA, test SideStore signing/install/refresh, and verify a sample App Intent is discoverable and can write a test record. Record actual signed entitlements and authentication behaviour. Do not assume simulator success proves device signing or Shortcuts integration.

SideStore documents app refresh and installing updates over an existing app. Treat data preservation as a test requirement for this specific build and signing path, and do not uninstall a real-data installation to update it. Background refresh is not guaranteed. [SideStore FAQ](https://docs.sidestore.io/docs/faq)

Exit evidence: reviewable native flow, user feedback on phone, documented installation route, and a working minimal Shortcut in the installed build. User device interaction may be required; no credentials belong in project files.

Current evidence: native screens and local persistence implemented; capture tests and domain/storage tests pass; simulator and arm64 device builds succeed. See [prototype status](../prototype/README.md) for precise capabilities and pending checks. The user reports successful SideStore installation and responsive UI on iPhone 15 Pro; their requested layout and discard refinements are implemented. Signed Shortcut behaviour, refresh, and update preservation still require phone verification.

## 2. Reliable capture and recovery — dependency boundaries implemented

Implement the versioned local store and shared expense command; manual/text capture; categories and splits; draft recovery; edit, repeat, delete/Undo; complete manual backup and restoration; app-lock options; full Add Expense and Add Expense from Text Shortcuts. Preserve one store identity across builds. Clearly label remaining incomplete features.

Foundation checkpoint: production dependency assembly, a shared injectable expense service for UI/Shortcuts, a value-only repository boundary, atomic draft/settings storage, and isolated sample seeding are implemented. Backup/restore now covers current durable state with a validated candidate, safety backup and recoverable journal; restart/failure tests are implemented. Next: signed-phone backup/update verification, app locking and remaining capture features.

Daily-use readiness is a separate checkpoint, not a promise that the entire v1 is finished. Before inviting real entries:

- Record/edit/split/repeat through real UI and Shortcuts, including failed validation and rapid repeated actions.
- Force-close/relaunch and confirm drafts and recorded expenses persist.
- Export and restore to a fresh store; compare records, IDs, splits, and totals.
- Install a subsequent build over the first and confirm data and Shortcut behaviour survive.
- Check Face ID, fallback, timeout, and locked/unlocked capture.
- Review UI/UX with the user; measure familiar capture speed on their phone.

After daily use begins, do not reset the user's store or inject demonstration expenses. Migrate existing data in subsequent builds.

## 3. Budgeting and bills

Ship independent overall/category budgets, period history, custom start day, current/next-cycle amount changes, and a clear cycle-change transition preview. Resolve and test the transition's budget rule before enabling it.

Ship manual repeats, optional reminders, automatic/pending bill modes, catch-up, confirmation/correction, and skipped-occurrence handling. Define recurrence frequencies and scheduling edits as part of this milestone.

Exit evidence: boundary/leap-year cases, exact split category totals, pending exclusion, repeated reconciliation without duplicates, and notification-denied/background-missed paths. Extend backup/restore fixtures to all new entities before shipping.

## 4. CSV and complete v1

Ship mapping, preview, validation, suspected-duplicate review, controlled import, and CSV export. Define treatment of refunds, zero/negative values, dates, and fractional rupiah explicitly. Reconcile row counts and imported amounts to the reviewed source, including rejected/skipped rows.

Complete remaining accessibility, error, empty-state, and settings work. Verify the entire confirmed v1 scope and a full backup containing transactions, splits, budgets, categories, parsing rules, bills, and occurrence history.

## 5. Mac, sync, shared books, and public release — later

Plan native Mac UI and iCloud sync near public release. Test two devices and separate iCloud accounts for sharing, offline concurrent edits, deletion, incomplete imports, duplicate scheduled occurrences, restore interactions, and removal from a share. Determine roles and ownership before enabling shared books.

Verify developer membership, final app identity/entitlements, CloudKit production schema deployment, and distribution migration. Public subscription design and launch requirements are a distinct workstream.

## Delivery expectations

The user hopes to start daily use after a few Codex sessions. Prioritise the capture/recovery milestone and real-phone feel, but report actual progress and remaining checks rather than promise a session count. All four entry methods and all confirmed v1 features remain planned; staged delivery does not remove scope.
