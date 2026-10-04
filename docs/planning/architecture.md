# Monocle — implemented local architecture

Updated: 2026-10-05, 0.7.21/build 84. See the [implementation report](../audit/2026-10-05-backend-implementation.md) for evidence and remaining gates.

## Composition and persistence

AppEnvironment opens the existing SQLite store and replays a retained recovery journal before reading preferences, settings or drafts. Workspace/settings semantics validate before initialization writes. Missing files receive defaults; malformed files remain intact and startup blocks. Legacy settings metadata resolves by stable card identity; unknown real identities are rejected.

ExpenseRepository implements the value-only ExpenseStore boundary. The V4 Core Data model adds prospective bill schedule metadata and persisted card color, with inferred migration from older models. Managed objects remain in one main-actor context. Nested transactions share one commit; a caught inner failure still prevents the outer commit. Failed writes roll back. This is serialization inside this process; CloudKit sync is not implemented.

ExpenseService is the shared command boundary for UI, CSV, bills and App Intents. Durable commits advance committedRevision, publish immutable card values and invoke onCommit. Failed post-commit reads populate projectionRefreshError without turning a successful save into a failed command. Simple saves/deletes publish known deltas; compound commands stage complete readback.

AppModel holds drafts, navigation and presentation preferences. It invalidates financial caches/widgets from committed events; appearance-only changes avoid financial cache rebuilds. Production compound card/category/budget commands use BackupService.withRecovery to coordinate SQLite and atomic JSON files. Presentation-only commands save one proposed preference value before publishing success.

## Workspace identity and integrity

Cards are generic expense containers with stable UUIDs. Expenses, category rows, budgets, bills, occurrences and drafts retain explicit card scope. Global categories live in workspace preferences; book-local rows retain historical dependencies. Migration maps (bookID, oldCategoryID) to global IDs and updates budgets, bills, drafts, inactive flags, rules and archive state together. Completion follows the recoverable command.

Deactivation retains categories used by historical budgets, expenses or bills. Hard deletion rejects dependencies including drafts/Undo. Deleting a bill expense marks its occurrence skipped and detaches its expense ID; Undo restores both atomically. Sample promotion detaches removed sample links.

FileLocalStateStore stores settings/workspace JSON and one atomic draft per card. Committed cleanup explicitly targets its owner and reports a separate cleanup error when the expense already saved. Reset republishes service configuration, hidden state and owner-scoped drafts.

Shared graph validators reject duplicate identities/budget boundaries, dangling references, invalid rule recurrence/status/linkage, invalid customization values and incomplete artwork. Malformed persisted financial records fail closed; reconciliation does not guess damaged state. Settings rules/archive IDs resolve against both persisted categories and the global catalog, so deleting their last active card preserves user configuration.

## Money, dates and reporting

Money is exact Int64 minor units, currency IDR, scale two. Individual values retain the existing range; the nonnegative workspace total must fit Int64.max. Admission and reads enforce this policy. Forecasts/percentages expose unavailable or beyond-range state when projected arithmetic cannot fit.

New manual input remains whole-IDR. Accepted historical fractions survive unchanged fields/note-only edits. Canonical CSV preserves fractions and allocations through a reversible Splits column. Strict tokenization rejects malformed quotes with record locations and preserves valid escaped/multiline fields.

Stored days use Gregorian yyyy-MM-dd civil dates. Draft civilDay is independent of DatePicker instants and changes only on deliberate date selection. Legacy drafts without that field resolve their old instant in the current timezone once; the original timezone cannot be inferred. Reporting uses current timezone and civil-midnight inclusive start/exclusive end.

Scoped reports resolve the selected card's categories, budgets and bills. Stack/all-card reports use calendar months and omit a combined budget/pace because card cycles differ. Permanently hidden cards are excluded from aggregate scopes, including restored preferences. One immutable report supplies a rendered chart and its labels.

## Recovery and integrations

Format 7 uses length-framed records and raw artwork; legacy formats 1–6 remain readable. See [backup/crash protocol](backup-format.md). Destructive commands reject existing journals before overwriting safety artifacts. After database/files commit, candidate values stage without notifications/publication; journal removal establishes completion. Failed rollback retains original bytes and blocks mutation. Startup seeding is atomic and only targets the explicit sample identity.

App Intents use the same service publication path. Widget snapshots carry day/revision and reject missing, malformed, future or stale data. Production widgets show unavailable state, with App Group diagnostics. Capture categories are active categories; historical labels retain historical ones.

Notifications derive a bounded complete workspace schedule, request authorization when reminders are enabled and expose permission/add failures. Restore/reset/card/rule changes rebuild/cancel. Bill schedule edits are prospective, retire old pending entries and preserve handled history. Launch/reload reconcile all cards idempotently.

Restored app lock immediately synchronizes the controller and requires authentication when enabled. Configuration revisions reject stale authentication results. Credentials are not backed up. Live Activity tasks capture immutable handles; old tasks cannot update/end a replacement. Startup reconnects an available activity, errors reach the app, and NSSupportsLiveActivities is present in both generated/source configuration.

## Performance and verification limits

CSV read/tokenization/value parsing runs in a cancellable worker task with generation checks. Batch persistence preloads categories/candidate IDs and commits once. Predicate/date paging is bounded and deterministic. Redacted signposts instrument commands/commits/import/preview; logs omit user notes and amounts.

Full snapshot reads, SQLite writes and backup materialization/activation remain on the main actor. Format 7 removes legacy capacity ceilings/base64 expansion but still holds whole graph/output Data. Serialized background contexts, bounded-memory streaming, feature page consumption and indexes selected from SQL/device profiling remain follow-up work. Simulator timings do not establish physical latency/memory targets.

Mac CI runs unit, migration, failure/recovery and fixture checks plus unsigned device Release builds, retains evidence, and enables the optional 50k fixture weekly. Signed-phone checks remain necessary for SideStore update preservation, App Groups/Shortcuts, notifications, authentication, Live Activities and physical performance.
