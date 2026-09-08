# Backup and restore — format 1

Updated: 2026-09-08. Implementation: BookBackup, BackupService, ExpenseRepository.replace, BackupView.

## User flow

Settings → Backup & restore → Export full backup opens the system Files destination picker. Choose backup to restore opens Files, validates the document and presents its export time, book, expense/category counts, total, and number of current expenses being replaced. Replace current book requires explicit confirmation. Cancel review does not mutate the current store.

Before activation, monocle retains a local safety backup. Export last safety backup makes it portable. One local safety backup is kept; export it before a subsequent restore to retain an older version. Files are unencrypted JSON with a `.monoclebackup` extension and registered type `com.farchan.monocle.backup` conforming to `public.json`. File access uses the picker-granted security scope.

## Scope and format

The format preserves all currently implemented durable application data:

- `formatVersion` (1), `exportedAt` (Foundation JSON Date encoding: seconds since 2001-01-01).
- `bookID`, `bookName`, `bookKind` (`sample`), `currency` (`IDR`), `minorUnitScale` (2), `sampleSeeded` (true).
- Categories with stable IDs, names and icons.
- Expenses with IDs, exact Int64 amounts, reporting date strings, notes, allocations, source and creation timestamp.
- Draft including input mode, unfinished text, category reference, expense identity and editing status.
- Prototype settings: budget amount, cycle start day, bill recording mode and reminder preference, plus the optional app-lock timeout. The backup retains the preference, never a biometric credential or passcode.

Transient navigation, toast and Undo state are cleared after restore and are not exported. There are no persisted production bill occurrences, budget history, custom parsing rules or cloud identities yet. Format 1 only accepts the current sample book identity; a future real-book format requires an explicit versioned change.

## Validation

Maximum 10 MB, 10,000 expenses, 500 categories. Reject unsupported versions/book identities/currency scale, duplicate IDs, invalid category names/icons, broken category references, invalid dates or money, incorrect allocation totals, aggregate Int64 overflow, and invalid settings. Editing drafts must reference a recorded expense; unfinished draft text and amount may remain invalid so recovery does not lose work in progress.

The imported snapshot is first materialized into an independent in-memory Core Data candidate. Compare canonical complete expense values (including IDs and sorted allocations) and categories against the decoded snapshot. No active writes occur during preview. Activation validates the candidate again so a mutated value cannot bypass the gate.

Amounts remain exact integers. The human preview formats totals with the device locale; locale does not affect stored values. JSON encoding is sorted and readable. This is structural consistency checking, not a cryptographic authenticity mechanism.

## Replacement and restart protocol

All local expense commands and restore activation are main-actor isolated without suspension points, so same-process commands cannot interleave with the snapshot/replacement. Bulk graph creation uses a category-ID map and one context save, avoiding per-expense database fetches. This is a bounded local implementation; sustained 10,000-record performance and device storage-pressure behaviour still require profiling.

1. Snapshot the original repository plus current draft/settings.
2. Atomically write `last-safety-backup.monoclebackup`.
3. Atomically write the same original snapshot to `restore-journal.json`. No active data changes before both writes succeed.
4. Replace all managed records in one Core Data context transaction. Validation precedes mutation; save failures roll back the context.
5. Atomically replace draft.json and settings.json; write the sample seed marker.
6. Reload the shared expense service. Remove the journal as the completion point. Keep the safety backup.
7. Publish restored draft/settings and clear transient state.

If any activation stage fails, replay the journal to restore database, draft, settings and marker. If rollback fails, block UI/expense commands and retain recovery artifacts. On startup, open the repository and recover a retained journal before reading local state or sample seeding. A corrupt journal fails closed; it is never deleted as an error recovery shortcut.

The journal is idempotent: a restart during recovery repeats restoration of the same original snapshot. An interruption before journal removal may roll back even if the candidate had been written; this conservative rule prevents a mixed book. Atomic writes and SQLite transactions cover process interruption; sudden hardware/storage failure is not claimed to be eliminated.

## Compatibility and verification

Existing bundle ID, SQLite filename/model, draft/settings encoding, and sample folder stay unchanged. No model migration or store reset is introduced. The existing disk-reopen regression remains applicable.

Tests cover portable round-trip with exact IDs/splits/draft/settings, invalid candidates, failures at every activation stage, failed safety-file creation, disk close/reopen recovery, malformed journal retention, and empty-book seed prevention. UI checks cover reaching backup settings and presenting the system export picker. Actual Files save/import and successful/failed replacement should also be exercised on the user's signed iPhone installation before daily-use readiness.

## Next milestone

M2d: optional app lock and remaining capture features. First collect phone backup/restore/update evidence using sample data. Full daily-use gate remains in roadmap.md; backup implementation alone does not satisfy it.
