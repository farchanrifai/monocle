# Backend reliability and performance implementation plan

Prepared 2026-10-04 for Monocle 0.7.20/build 83 at `b7621cc`. This is the execution plan for [the backend audit](../audit/2026-10-04-backend.md). No fixes have been applied on the audit branch.

Execution update, 2026-10-05: see the [implementation report](../audit/2026-10-05-backend-implementation.md) for source changes, fixture evidence and verification. The plan below preserves the original acceptance gates. Background persistence/streaming memory work and signed-phone profiling/integration gates remain outstanding; simulator results do not satisfy those gates.

The sequence protects durable data first, then establishes consistent command/publication contracts, repairs integrations/reporting, and measures performance before changing concurrency or indexing. Each change should remain independently reviewable and keep existing user data recoverable.

## Start on the Mac

From your existing repository, fetch the pushed audit branch and create a separate worktree. Use a different destination if that directory already exists.

```sh
git fetch origin
git worktree add -b fix/backend-reliability ../monocle-backend-fixes origin/audit/backend-2026-10-04
cd ../monocle-backend-fixes
cat HANDOFF.md
xcodebuild -version
xcrun simctl list devices available
scripts/test.sh <available-simulator-UDID>
```

The checkout contains only audit documentation changes. Read the root `AGENTS.md` before implementation. Keep one root `HANDOFF.md` current after every major checkpoint. Retain the initial result bundle as the baseline; the September result counts are not a substitute for this run.

Use generated synthetic stores and copied fixtures for the failure/migration tests. Preserve the original user store and make a separately verified export before any real-device migration. Audit F05 means the current exporter may fail for large stores; prove recovery on a copy before assuming export succeeded.

## Decisions required during implementation

These decisions need concrete fixture checks and a documented contract; they do not block starting the existing-workflow regressions.

1. **Money precision and aggregate range (F11/F12).** Whole-IDR capture remains a product policy, but accepted historical minor units must survive edits/exports. Prefer preserving exact existing data and rejecting unsupported new input explicitly. Choose checked `Int64` aggregates with a defined admission policy or a wider exact aggregate representation; forecasts may use a separate overflow state. Never silently clamp or round ledger values.
2. **Destructive deletion and undo (F01/F02).** Deactivation should retain historical categories. Deleted bill expenses must not be auto-recreated; specify skipped/detached/restored occurrence behavior for undo. Do not rewrite historical budget limits silently.
3. **Recurring edits (F09).** Default edits should take effect prospectively. Explicit retroactive changes need a separate reviewed action. Preserve handled occurrence history.
4. **Workspace portability (F05/F06/F27).** Define a new scalable backup format with a manifest and separately bounded assets, complete graph validation, version migration, and a recoverable activation protocol. Older formats 1–6 must remain readable under explicit compatibility rules.
5. **Reporting/calendar scope (F20–F22).** Use a defined Gregorian civil date for storage. Document reporting time zone and aggregate-cycle/budget behavior when cards have different cycle starts. Avoid a hidden active-card fallback for scoped reports.

## Work packages and acceptance gates

### 0. Establish the baseline and failing regression fixtures

**Covers:** All findings; migration/observability coverage gaps. **Depends on:** Mac/Xcode availability.

- Run the unchanged unit suite and relevant UI tests; record Xcode/iOS runtime, result bundle, and any existing failures.
- Add disk-backed multi-card fixtures containing historical category budgets, recorded/pending bills, distinct drafts, hidden cards, custom artwork, and global-category migration input.
- Add injectable read/write/failure and OS-integration clients only where needed for the following behavioral tests. Keep test fakes faithful to scoped draft filenames and commit semantics.
- Add fixture builders at 1,000, 10,000, and 50,000 expenses across 1/10 cards, plus 101-card and large-artwork cases. They are benchmarks/synthetic fixtures, not production migrations.
- Preserve the existing rollback/card-isolation/idempotency regression suite. Add each failing regression with its corresponding fix rather than replacing the existing tests.

**Gate:** Baseline is recorded, fixtures reopen without mutation, and the first confirmed failure cases can be demonstrated on the current code.

### 1. Repair ordinary deletion and draft integrity

**Covers:** F01–F03. **Depends on:** 0. **Suggested split:** one commit per command family.

- Centralize category dependency checks over every historical budget, expense, and bill. Retain historical rows on deactivation; reject incompatible hard deletion with a useful result.
- Centralize expense deletion/promotion and linked occurrence updates in one repository transaction. Specify undo linkage/status and automatic-recreation suppression.
- Retain the target book ID when clearing a committed draft; write the exact per-card file. Preserve other cards' drafts, and expose cleanup failure without misreporting the already committed expense.
- Verify existing data before introducing any repair migration. An invalid reference should be preserved and reported, not silently replaced with a guessed category.

**Gate:** Budget-only category operations cannot produce unreadable stores; bill deletion/undo/promotion round-trip through full backup; two independent durable drafts survive save and restart correctly.

### 2. Make recovery admission and snapshot capacity safe

**Covers:** F04/F05. **Depends on:** 0/1. **Suggested split:** journal admission guard first; scalable format second.

- Use one recovery-state/admission check for clear/reset/start/rename/restore and all future destructive commands.
- Preserve existing journal/safety artifacts and block ordinary mutation after rollback failure. Publish recovery-required state consistently to the root model.
- Separate external import admission from internal lossless export/safety snapshots. Avoid an internal recovery path constrained to the current 10,000/100/10 MiB import limits.
- Stage a versioned manifest/assets snapshot with bounded I/O, completeness metadata, validation, atomic promotion, and a documented crash protocol. Retain enough state to recover after interruption at every database/file/asset stage.
- Ensure storage-full/read-only failures preserve the prior recovery artifacts and report a recoverable outcome.

**Gate:** Every destructive retry preserves the original journal byte-for-byte after a double failure. A workspace beyond current ceilings can export, restore, clear/reset with a safety snapshot, and roll back completely. Process interruption tests reopen to a complete old or complete new workspace.

### 3. Unify graph validation and category migration

**Covers:** F06–F08/F15/F27. **Depends on:** 1/2.

- Implement shared validators for workspace/settings/preferences, budgets, rules, occurrences, draft references, assets, and identity scope. Incomplete draft input is allowed; dangling identity references and invalid edit targets are not.
- Validate one occurrence per `(bookID, ruleID, dueDay)` and status/expense linkage; preserve any explicit deletion-detachment policy from package 1.
- Make bill/occurrence reads fail closed on malformed persisted records; remove unknown-recurrence coercion and silent skipping.
- Preview must compare complete canonical materialized data, including defaults added during legacy migration. Validate assets before touching the active database and inject the artwork store for fixtures.
- Scope category migration by book/old ID and migrate budget/bill scalars, per-card drafts, rules/archive/inactive references together. A completed catalog must not serve as a premature migration-completion marker.
- Load workspace preferences at the composition root and distinguish missing from malformed state. Preserve malformed file bytes and avoid startup initialization writes on failure.
- Add on-disk V1/V2/current migration fixtures with populated graphs and storage-failure preservation. Do not add global category-UUID uniqueness constraints.

**Gate:** Crafted duplicate budgets/occurrences, dangling rules, malformed preferences, invalid assets, and invalid palette indices fail before active mutation. Legacy formats still import deterministically. Scoped category migration survives interruption/retry/reopen with all references preserved.

### 4. Define committed outcomes and publish one consistent workspace state

**Covers:** F13/F14/F19/F23/F24. **Depends on:** 1–3.

- Have commands return durable results/identities separately from projection-refresh errors. Prevent retrying a committed creation/import as an uncommitted operation.
- Put compound category/card/budget/reset operations behind explicit workspace commands. Stage proposed changes; commit SQLite together, and coordinate JSON/assets through the recovery protocol where needed.
- Reduce duplicated financial settings or make their authoritative source explicit. Do not use a silent preference-write helper as the durable completion signal.
- Add a committed revision/event or immutable snapshot shared by manual entry, Shortcuts, CSV, bills, backup, and reset. Derive caches and widget snapshots from that revision. Production widgets need explicit unavailable/stale states, App Group error diagnostics, and reporting-day freshness checks rather than sample financial data.
- Restore/reset all derived presentation state together, including permanent hidden IDs and service rule/archive configuration.
- Make startup seeding target only the explicit sample identity and run atomically; a missing seed marker with a real book must never inject samples.
- Surface failed bill/category/customization actions currently using `try?`, based on the real command outcome.

**Gate:** Post-commit fetch failures cannot create duplicate books/imports; injected mid-step failures yield consistent disk/memory state across restart; warmed caches and widget files reflect all entry paths; restore/reset visibility and category availability are correct.

### 5. Repair recurrence and notifications across the workspace

**Covers:** F09/F17/F18. **Depends on:** 3/4.

- Introduce prospective schedule revisions/effective dates and retire obsolete pending occurrences atomically. Keep recorded/skipped history.
- Reconcile eligible bills for all relevant cards independent of selection, using bounded catch-up and the shared command/publication path.
- Inject a notification client. Request authorization when reminders are enabled, show permission/failure state, and derive a bounded desired OS schedule from persisted state.
- Diff/cancel/rebuild requests after launch, restore, reset, card/rule deletion, and schedule edits. Respect system pending-request limits and device clock/time-zone changes.

**Gate:** Edited schedules add no unrequested historical/obsolete charges; two-card repeated reconciliation is idempotent; notification client fixtures prove complete rebuild/cancellation; a signed phone proves permission denial/grant, real delivery, and restoration.

### 6. Make money, dates, and scoped reporting consistent

**Covers:** F11/F12/F16/F20–F22. **Depends on:** 3/4; can proceed alongside 5 once shared contracts settle.

- Implement the chosen exact-money/aggregate policy once and use it in all totals, projections, CSV previews, and widgets.
- Preserve accepted historical precision through edit/export; define the CSV representation of splits and fractions explicitly rather than treating a display string as a reversible format.
- Replace the permissive tokenizer with a strict error-returning parser; preserve valid multiline/escaped fields and include record locations in review errors.
- Separate durable Gregorian civil dates from localized display. Persist an edit/new draft's intended reporting day independently of absolute DatePicker instants so travel cannot change it. Normalize period boundaries to start of day and use one inclusive-start/exclusive-end policy.
- Add a scoped reporting snapshot builder that resolves the selected card's categories/budget history/bills. Implement the documented stack/all-card policy rather than using active-card limits.

**Gate:** Boundary addition/projection tests do not crash; note-only edits do not change accepted money; malformed CSV writes nothing; calendar/time-zone changes preserve civil dates; all views/widgets agree for transition periods and differing card budgets.

### 7. Synchronize app lock and ActivityKit lifecycle

**Covers:** F10/F25; widget/reminder privacy follow-up. **Depends on:** 4.

- Apply the restoration lock policy to both settings and the controller, requiring authentication before exposing content when appropriate.
- Capture immutable activity handles/session generations in asynchronous updates/end calls; prevent prior tasks from clearing a replacement session.
- Add `NSSupportsLiveActivities` to both project-generation inputs and committed build configuration. Preserve configuration parity after XcodeGen regeneration.
- Define interruption/session-recovery behavior and display ActivityKit authorization/start failures appropriately.
- Verify signed app-group access, widget freshness, app-switcher privacy, protected-data behavior, and the intended information displayed in widgets/reminders while the app is locked.

**Gate:** Imported lock state behaves immediately and after restart; delayed tasks cannot end/update the wrong activity; actual widgets/Shortcuts/Live Activities function on the signed phone.

### 8. Profile and optimize bounded backend work

**Covers:** F26 plus migration/query/observability controls. **Depends on:** 1–7 for correctness; baseline profiling starts in 0.

- Add redacted OSLog/signposts around startup, fetch/validation/save, CSV stages, backup preview/activation, reconciliation, analytics, and widget publication. Record duration, count, scope/revision, and outcome; exclude user notes and financial values.
- Measure Release builds on a physical device with Time Profiler, Core Data instruments, Allocations, and hangs tracking. Measure simulator runs separately.
- Move heavy I/O/validation/materialization to background work and serialized Core Data contexts. Pass only immutable values/IDs between contexts; publish on the main actor once per committed operation.
- Add predicate-based range/ID queries and pagination/batching. Preload category references for batch writes; avoid whole-relationship realization for previews/pages. Use SQL-debug evidence/query plans to select scoped identity/date indexes and test their migrations.
- Compute scoped analytics once per input revision/range and read that result in every chart row/label; precompute category-budget totals in one pass. Preserve the month-over-month engine's existing one-pass grouping. Remove data-cache/widget rebuilds from appearance-only preference changes.
- Make imports/backup/catch-up bounded, cancellable before commit, and progress-reporting where work is long. Cancellation must preserve the same atomicity/recovery guarantees as failure.

**Gate:** Correctness/failure tests still pass; before/after profiling shows measured improvement and the agreed budgets below are met. Background contexts must not weaken transaction serialization or occurrence uniqueness.

## Proposed performance budgets and fixture matrix

These are initial acceptance targets to confirm against the baseline and chosen phone. They are **not measurements from this audit**. Record device, iOS, Release configuration, fixture shape, cold/warm conditions, repeated samples, p50/p95, and peak memory. Adjust deliberately if baseline/device constraints require it.

| Operation | Fixture | Initial acceptance target |
| --- | --- | --- |
| Ordinary committed save/delete | 10,000 expenses, 10 cards | p95 user-visible completion ≤150 ms; avoid main-thread blocks >50 ms |
| Warm card switch/current-cycle report | Same, differing budgets | p95 ≤200 ms; calculations use scoped data |
| Cold open including due-bill catch-up | 10,000 expenses + multi-year rules | First usable screen ≤2 s on chosen phone; bounded work/progress beyond that |
| CSV import | 10,000 rows with splits/categories/duplicate hints | No UI stall >100 ms; cancellation/progress before commit; record end-to-end time and peak memory |
| Backup export/preview/activation | 10,001/50,000 expenses and >10 MiB assets | Complete/recoverable output; UI responsive; memory scales with bounded batches rather than decoded duplicate graphs |
| Analytics | 1,000/10,000/50,000 entries; 1/10 cards | One aggregate computation per revision/range; p95 warm 10k report ≤200 ms |
| Migration | Populated V1/V2/current SQLite fixtures | Lossless reopen; recorded duration/memory; preserves original on failure |

For 50,000-record and large-asset cases, use results to set a supported envelope rather than inventing one. Admission and recovery capacity must agree, and every admitted workspace must remain exportable/recoverable.

## Release and continuation gate

- All 27 findings have a linked implementation/test result or an explicit accepted decision with scope/limitations.
- Full unit suite and relevant UI flows pass on the recorded Xcode/runtime; new fixtures cover failure/reopen behavior, not just in-memory state.
- Mac CI builds/tests backend changes and retains results; periodic jobs run migration/performance fixtures. No workflow currently exists in this checkout.
- A signed phone validates permission prompts, notification delivery, Shortcuts/app-group widgets, Live Activities, app lock, file protection, and update persistence.
- Current/legacy backups round-trip and interruption recovery works for large stores and artwork. The original user data remains recoverable.
- Update `docs/planning/architecture.md`, `backup-format.md`, README, and the single root `HANDOFF.md` to reflect the completed contracts and outstanding device limits.

Do not turn the planned CloudKit direction into a synchronization implementation during these repairs. Any future sync work needs its own scoped identity/conflict/convergence design and tests; main-actor serialization currently establishes only in-process behavior.
