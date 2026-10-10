# Backup and restore — formats 1–8

Updated: 2026-10-05, 0.7.21/build 84. Implementation: WorkspaceBackup, BookBackup, BackupService, ExpenseRepository.replace, CardArtworkStore and BackupView.

## User flow and portable scope

Settings → Backup & restore exports to Files. Import validates/materializes a separate candidate, then shows its scope/counts/total before replacement confirmation. Cancel writes no active state. Files are unencrypted financial documents.

New exports use .monoclebackup, registered com.farchan.monocle.backup conforming to public.data. The picker also accepts legacy JSON/generic data and validates contents. Picker-granted security scope controls file access. Export last safety backup preserves the old workspace; export older safety copies before another admitted mutation replaces them.

Backups retain all card profiles/color, categories, exact expenses/allocations/sources/timestamps, effective-dated budgets, recurring rules/occurrences/schedule revisions, owner-scoped drafts with civil day/exact unchanged values, settings/rules/archive IDs, global categories, stacks/order/visibility/appearance and every referenced artwork byte. App-lock preferences are retained; biometric/passcode credentials, navigation, toast and Undo are not.

## Format 7 stream

The ASCII magic is `MONOCLE-BACKUP-7\n`. Every following frame has an unsigned 64-bit big-endian byte length followed by exactly that many bytes:

1. JSON header: export date, currency/scale, settings/preferences, book/asset counts.
2. For each book: JSON profile/draft/counts header, then one JSON frame per category, expense, budget, bill and occurrence in that order.
3. For each artwork: JSON filename frame, then raw binary asset frame.

Foundation JSON dates encode seconds since 2001-01-01. UUIDs and exact minor units remain stable. Lengths/counts check remaining input; truncated/trailing frames fail. Individual JSON frames are bounded; artwork is at most 8 MiB per file and must decode at no more than 1,200 × 1,200 pixels. Filenames cannot escape storage. Every referenced asset must be present; missing artwork explicitly fails export.

## Format 8 (model B, 2026-10-11)

Same stream as format 7 with magic `MONOCLE-BACKUP-8\n`; new exports always write 8. The header `currency` is the workspace reporting currency and must equal `preferences.reportingCurrency` (formats ≤ 7 must be IDR). Added optional fields: card `currency`, `spendingCurrency`, `defaultPaidWithID`; expense `paidWithID`, `originalAmount`, `originalCurrency`, `rate`, `rateSource` (all four foreign fields or none); budget `totalUntilDay`; preferences `paymentMethods`, `hiddenEntryFields`, `reportingCurrency`; stack `capLimit`, `capStartDay`. Every Paid with reference must name an existing payment method. The version bump makes an older app refuse the file instead of silently dropping these fields. Amounts stay minor units at scale 2 for every currency.

Version 7 removes the former whole-workspace 100-card/10,000-expense/10 MiB ceilings and base64 expansion. It still holds the complete graph/output Data in memory; bounded-memory file streaming and a physically profiled supported envelope remain outstanding.

## Legacy compatibility and validation

Formats 1–3 are single-book JSON; 4–6 are workspace JSON. Historical external-input limits remain (10 MiB document, 100 workspace books, 10,000 expenses per book and bounded record/category counts). Magic selects format 7 or 8; otherwise decoding routes legacy JSON.

Missing legacy budgets/drafts materialize deterministically from exported settings/date/card identity. Formats 4–6 accept exact sample settings beside real cards or stale metadata for an existing same-kind identity; normalization adopts the authoritative exported card metadata. Absent real identities or malformed records fail. Version 7 requires exact settings-profile metadata. No damaged financial identity is silently guessed.

Validators cover currency/scale/version, identities, references, allocation totals, bounded positive amounts/workspace aggregate, Gregorian dates, unique budgets/effective days, recurrence/occurrence uniqueness and same-card status/expense linkage. Draft text may remain unfinished, but category/edit references must exist. Preferences/settings validate global catalog, rules/archive, stacks/order/visibility, palette/color and artwork completeness.

Preview materializes an independent Core Data store plus temporary state/artwork stores and compares full canonical readback: profiles, categories, expenses, budgets, rules, occurrences, drafts, settings/preferences and raw assets, including legacy defaults. Activation repeats this gate.

## Crash and mutation protocol

1. Reject a retained/unresolved journal or blocked service before replacing safety artifacts.
2. Encode the old workspace and atomically write last-safety-backup.monoclebackup, then identical bytes to restore-journal.json. The journal filename stays compatible; new contents are format 7.
3. Stage validated artwork, execute SQLite changes in one transaction and atomically write affected owner drafts/settings/preferences.
4. Stage a validated committed service snapshot without exposing it or scheduling candidate notifications, and load committed service configuration.
5. Remove the journal as completion; publish revision/snapshot and root projections. Keep the safety copy.

Failure replays old database/artwork/state and verifies complete canonical readback before journal removal. Double failure preserves original journal/safety bytes, blocks further mutation and exposes recovery-required state. Startup replays retained journals before ordinary initialization or seeding.

An interruption before removal conservatively restores old data even if candidate files were written. After removal startup opens committed new data. Atomic files/SQLite protect process interruption, not every hardware/storage loss. Orphaned unreferenced files are not workspace identities.

## Verification limits

Fixtures cover model migration, malformed graphs, exact fractions/splits, activation fault stages, byte-preserved retry journals, reopen/replay, 101 cards/10,001 expenses, raw artwork above 10 MiB, incomplete assets and partial artwork rollback. See [implementation evidence](../audit/2026-10-05-backend-implementation.md).

SQLite/full materialization remains synchronous on the main actor. Recovery capacity is improved; large-store responsiveness, bounded peak memory, cancellation during persistence, storage pressure and signed Files/SideStore update behavior remain follow-up gates. Synthetic tests did not open or mutate the original user store.
