# Backend fixes and verification — 2026-10-05

Implementation branch: `codex/backend-reliability`, based on audit commit `7937472` and application baseline `b7621cc` (0.7.20/build 83). Release version: 0.7.21/build 84.

This records the implementation of the [27-finding audit](2026-10-04-backend.md) against its [execution plan](../planning/backend-improvement-plan.md). Integrity/recovery and reporting/integration fixes are implemented. F26 is partially implemented: measured batching/report reuse and worker CSV parsing are in place; serialized background SQLite, fully bounded streaming memory and physical-device budgets are not established.

## Finding-to-implementation map

“Implemented” describes source behavior with local regression coverage. It does not assert signed OS integration or physical performance.

| Finding | Result | Implementation and regression evidence |
| --- | --- | --- |
| F01 Historical category dependencies | Implemented | Repository/model check all budget history as well as expenses/bills/drafts/Undo. Deactivation retains referenced rows; hard deletion rejects. BackendPersistenceTests budget-only reopen/export fixtures. |
| F02 Bill deletion/promotion links | Implemented | Delete atomically skips/detaches linked occurrences. Undo restores original links/status. Sample promotion detaches removed expense links. Persistence deletion, Undo, reconciliation/reopen tests. |
| F03 Scoped draft cleanup | Implemented | Save retains owner ID and clears only that owner's durable file. Cleanup failure preserves committed-save outcome. BackendModelTests real/sample draft and injected cleanup failure. |
| F04 Recovery retry admission | Implemented | One gate rejects retained journals/blocked recovery before safety writes. Double failure preserves original bytes and root blocks. BackendBackupTests retry matrix and reopen/replay. |
| F05 Recovery capacity | Implemented with memory limit | Format 7 framed records/raw assets remove old whole-workspace ceilings for internal snapshots. 101 cards/10,001 expenses export/restore/clear/reopen/reset and >10 MiB artwork fixtures. Whole graph/output Data remain resident; see F26. |
| F06 Graph validation/readback | Implemented | Shared workspace/settings/preferences/budget/draft/rule/occurrence validators plus full canonical materialized readback. Invalid graph fixtures fail before active writes. |
| F07 Scoped global migration | Implemented | Per-book category ID mappings update database scalars and scoped files under recovery. Catalog completion follows success. Persistence collision/migration tests and model file-failure rollback. |
| F08 Preserve malformed startup state | Implemented | Composition root validates preferences/settings before seeding/initialization; model fails closed. Malformed bytes and categories remain unchanged in BackendModelTests. |
| F09 Prospective recurrence | Implemented | V4 schedule effective day/revision; edits retire old pending occurrences and preserve handled history. Engine/persistence schedule edit regressions and V3 migration. |
| F10 Restored app lock | Implemented; phone pending | Restored controller configuration locks immediately; revision guards reject stale authentication completion. Model restore and existing lock tests. |
| F11 Aggregate/projection arithmetic | Implemented | Checked nonnegative workspace admission fits Int64.max; projection/pace overflow becomes explicit unavailable state. Boundary financial/persistence/import tests. |
| F12 Fractional historical precision | Implemented | Exact unchanged draft/split values and reversible CSV Amount/Splits. Manual new entry stays whole-IDR; bank imports accept two fractional digits. Financial/CSV round trips. |
| F13 Durable versus refresh outcome | Implemented | Committed revision/callback and separate projectionRefreshError. Failed follow-up reads cannot throw away committed identity. BackendCommandTests injected post-commit failures. |
| F14 Compound command integrity | Implemented | Staged card/category/budget/settings/preferences with one nested SQLite transaction and journal bridge. Presentation-only commands save a single proposed value. Model create/preferences failure and migration rollback tests. |
| F15 Fail-closed bill persistence | Implemented | No recurrence coercion/skipped unreadable occurrences. Shared rule/date/status/link/uniqueness validation on reads/writes. Malformed persisted-row fixtures preserve data and reject reconciliation. |
| F16 Strict CSV quotes | Implemented | Throwing tokenizer enforces EOF/transitions and row/field bounds; valid multiline/escaped fields remain valid. CSV tests cover malformed documents and split round trips. |
| F17 Complete reminders | Implemented; phone pending | Injected notification client, permission request/state, bounded whole-workspace desired schedules and cancellation/add errors. Command fake-client denial/failure/rebuild tests. |
| F18 Workspace reconciliation | Implemented | Unscoped reconciliation visits every card in one transaction/publication. Two-card repeated reconciliation tests verify isolation/idempotency. |
| F19 Shared cache/widget publication | Implemented; signed App Group pending | All service commits notify root; warmed inactive caches invalidate, snapshot carries revision/day. Widget files show unavailable on missing/stale/corrupt/group failure. Model and widget tests. |
| F20 Scoped reporting | Implemented | Selected-card snapshot supplies its own history/categories/bills. Stack/all scopes use calendar months without active-card budget; permanently hidden cards are excluded. Financial and model tests. |
| F21 Gregorian storage | Implemented | Day/reporting calendars consistently Gregorian while retaining timezone. Cycle bounds use civil midnight/inclusive start/exclusive end. Non-Gregorian/leap/boundary tests. Historical ambiguous dates are not guessed. |
| F22 Durable draft day | Implemented with legacy limit | civilDay survives timezone travel; DatePicker adapter updates on deliberate change. New/edit draft financial regressions. Old drafts lack original timezone, so retain documented one-time current-zone interpretation. |
| F23 Restored hidden state | Implemented | Publish hidden/permanently-hidden/preferences together; reporting/widgets filter archived IDs. Model restore and preference-save persistence tests. |
| F24 Reset configuration | Implemented | Fresh reset clears rule/archive state and republishes matching budgets/settings/service configuration and drafts. Backup/reset and multi-book tests. |
| F25 Activity lifecycle/configuration | Implemented; phone pending | Injected immutable activity handles, reconnect on launch, visible authorization/start error, configuration support in plist/project.yml. BackendSessionTests delayed end/update replacement. |
| F26 Work placement/query/report reuse | Partial | Worker CSV parsing/generation cancellation, preloaded batch upserts, bounded date/page predicates, one rendered report, single date lookup, appearance-only invalidation reduction and redacted signposts. 10k write/page and 10k/50k analytic fixtures. Background SQLite/backup materialization, fully streaming file I/O, query-plan-driven indexes and device budgets remain outstanding. |
| F27 Artwork completeness | Implemented; device memory pending | Injected asset store, safe names, required bytes, decode/pixel/per-file limits before activation; staged assets/full readback. Missing/corrupt/oversized/traversal/partial rollback/raw large-asset fixtures. |

Card rename/delete also update the settings profile within the coordinated command. Global rules/archive configuration can retain categories present only in the global catalog when their last active card is removed. Legacy same-identity stale metadata normalizes; v7 snapshots reject mismatched profile metadata.

## Recorded baseline

- Xcode 27.0 (`27A5194q`), iOS 26.5, iPhone simulator `D972CED0-283F-4ACC-A70E-457150023BA2`.
- Unchanged source extracted before application edits to `build/backend-audit/baseline-source`.
- Baseline: **118/118 unit tests passed**; **39/42 UI tests passed**.
- Existing UI failures: `testAppleWalletCardOpeningAndClosingAnimation`, `testCardContextMenuLongPressOnHomeScreen`, `testRapidCardOpenCloseAndMidwayCancellation`.
- Evidence: `build/backend-audit/baseline.log` and `baseline.xcresult`. Baseline UI runtime was approximately 831 seconds.
- Earlier corrected implementation run: **169/169 unit tests passed**, `fixes-unit-4.log/.xcresult`. Later review/performance regressions are subject to final verification below.

## Final verification and delivery

- Latest correctness run: 176 tests passed, one optional 50k test skipped, zero failures (177 executed). The unchanged 10k benchmark was excluded from this repeat after passing separately. Evidence: `fixes-unit-8.log/.xcresult`.
- 10k Debug simulator comparison: per-row writes in one transaction 204.431 s wall / 204.051 s CPU; batch writes 2.853 s wall / 2.843 s CPU; 100-row page 4.75–4.83 ms. This compares two paths in the same implementation, not a pristine Release/phone baseline. Evidence: `fixes-unit-7.log`; that run also exposed the subsequently fixed sample-card rename regression.
- Release arm64 device app/widget build succeeded (`fixes-release.log`). Compiled app version 0.7.21; Live Activity support is present. The package build will rebuild final source before delivery.

- Final complete unit run: **181/181 passed**, including both 10k and 50k fixtures, zero failures/skips. Evidence: `fixes-unit-final-2.log/.xcresult` (iPhone 17 Pro Max simulator `3321C59F-B6B1-4CC3-BA0D-27355A488689`).
- Complete implementation UI run: 38/42 passed, with the three baseline fixture failures and one introduced unfinished-split subtotal regression. The fixtures and split subtotal are corrected. Final targeted run: **18/18 passed**, including all four previous failures and affected card/category/budget/backup/CSV/reset/reporting flows. The full and follow-up runs cover all 42 unique flows; this is not a claim of a second single 42-test run. Evidence: `fixes-ui.log/.xcresult` and `fixes-ui-final.log/.xcresult`.
- The 50k fixture first measured 66.532 s wall / 66.490 s CPU. Caching card lookups for the lifetime of a transaction reduced the same batch path to 2.625 s wall / 2.613 s CPU in `fixes-unit-9`; final confirmation was 2.562 s / 2.543 s. 100-row pages were approximately 11 ms. Concurrent simulator UI work and Debug build conditions apply; physical budgets remain unverified.
- Final package rebuild succeeded (`ipa-build.log`); ZIP integrity, arm64 app/extension, stable bundle IDs, version 0.7.21/build 84, iPhone-only/minimum iOS 26, V4 model, ActivityKit support and backup UTI were verified. Debug three-card fixtures are excluded from the Release binary.
- IPA: `monocle-0.7.21-build-84-unsigned.ipa`, preserved in the mandated Monocle-codex iCloud folder. SHA-256: `b83a893235cec36a99bb6f54340795c5c160357c1e139e802897ca37d657b5d2`; delivery copy matches.

Published [Monocle 0.7.21/build 84](https://github.com/farchanrifai/monocle-releases/releases/tag/v0.7.21-build.84). GitHub reports the matching SHA-256 asset digest and size (2,939,800 bytes); SideStore source points to the new asset/version. All prior Monocle versions and the four other apps' complete feed entries are preserved. Release feed commit: `5d8efd7`; source implementation commit: `6ea3d04` on `codex/backend-reliability` (local, not pushed).

Final 10k confirmation: per-row writes 188.563 s wall / 188.408 s CPU versus batch 0.465 s / 0.464 s; 100-row page approximately 4.34–5.04 ms. These are synthetic Debug simulator measurements with concurrent UI work, not physical-device performance claims.

Result bundles/logs are local ignored build artifacts; they are not source-controlled or embedded in public releases.

Mac CI: `.github/workflows/backend.yml` builds/tests migration/recovery/large fixtures on macOS, retains results, builds the unsigned device app/widget extension and enables optional 50k fixtures weekly. YAML and shell syntax are checked locally; hosted execution is unverified until the branch is pushed.

## Remaining gates

- F26: move heavy snapshot/backup/SQLite materialization to serialized background work with immutable boundaries, pre-commit cancellation/progress and bounded file streaming. Adopt page consumption where features still read full ledgers. Select indexes only after SQL/query-plan evidence and migration tests.
- Profile Release on the user's phone with 1k/10k/50k multi-card fixtures. Record p50/p95, main-thread stalls, peak memory, allocations and storage-pressure behavior. Simulator CPU/wall samples do not prove the plan's proposed phone budgets.
- Install the new IPA over the existing SideStore installation with the same identity and verify preserved records/drafts, V4 migration, Files export/import, App Group widget/Shortcut refresh, notification grant/deny/delivery, app-lock/authentication and ActivityKit replacement/reconnect.
- The tests use synthetic temporary stores/assets. No original user database, credentials or private transaction data was read, altered or published.
- No CloudKit synchronization was introduced.
