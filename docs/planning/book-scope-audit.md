# Book-scope audit — 2026-09-09

Baseline: clean checkout at `31b88e9` (preserved). Read HANDOFF and all six requested planning sources before tracing production callers. Source inspection only; no store was opened or changed, no runtime tests or IPA build performed.

## Finding and stop gate

**Pause before persistence implementation, under the user's material migration/backup risk instruction.** Phase 1 inspection is complete; explicit-scope implementation is not complete. Phases 2–4 have not started.

The V2 schema already supports multiple Book rows and book relationships. The dangerous boundary is application-level recovery, not a demonstrated Core Data migration failure:

- `ExpenseRepository.replace(with:)` deletes every book and all financial records, then inserts one backup book.
- `BackupService.snapshot` gathers unfiltered records and labels them with the single settings profile. Its rollback journal cannot represent a multi-book workspace or hero files.
- Reusing this restore/recovery path after allowing a second book could collapse ownership into one book or fail validation; it cannot guarantee recovery of the original workspace.
- `startEmptyRealBook` deletes every expense and replaces the existing book UUID. It must not be used as multi-book migration or book creation.

These are risks when extending the existing single-book implementation, not evidence that the current user's data has been lost.

## Paths and required explicit identity

| Path | Current behavior | Required change before multiple books |
| --- | --- | --- |
| Core Data / ExpenseRepository | All category, expense and budget reads are unfiltered; currentBook requires exactly one row; ID lookup is global | Explicit bookID on reads/writes/deletes; validate ownership before update; resolve the requested Book rather than first/only Book |
| Expense / Allocation | Value omits bookID; allocation validation accepts any category in the supplied list | Carry expense bookID and validate against that book's categories at service and repository boundaries |
| Categories | Value omits bookID; global name validation and ID lookup; default IDs are fixed | Per-book name validation and ownership; retain existing IDs, generate new category IDs for new books |
| Budgets | Value omits bookID; same effective date replaces rows across the entire store; initial budget uses one fixed UUID | Per-book history, upsert and seed; preserve existing budget IDs/effective dates/transition ends; fresh IDs for new books |
| Drafts / edit / repeat / delete / Undo | One draft.json; AppModel holds one draft, pending edit and Undo without book identity | Draft per book with explicit owner; carry owner through deferred actions so a later selection cannot redirect a write |
| Parsing / archive / rules | One settings.json owns archive IDs and rules; starter keyword lookup hard-codes default category UUIDs | Per-book parsing context; initialize new-book starter mappings to its actual categories, retain legacy mappings |
| Add Expense / entry URL | BottomNavigation, quick-entry intent and monocle://entry call parameterless openEntry | Resolve and capture target book before editing; handle missing/invalid targets without silently choosing a different book |
| Structured Shortcut | Category entity is only category UUID; query reads current model categories; command uses singleton service | Explicit book parameter and book-bound category resolution, validated again at execution |
| Text Shortcut | Uses singleton service and its configured parser | Explicit book parameter; legacy missing target may resolve only an unambiguous sole book, otherwise request selection |
| Recents / budgets / categories | All views consume singleton service arrays through AppModel | Selected-book snapshots; activities rows retain owning book for tap/edit/repeat; visible/all filtering uses IDs |
| Bills / occurrences / reminders | BillsView is a fixed Home internet sample; only two settings flags persist; no rules, occurrences or notifications exist | Phase 4 rules and occurrences belong to explicit books; reconciliation and notification identity include owner/rule/scheduled date |
| Bootstrap / seeder | One profile, one draft, global seed marker; initial budget checks all budgets | Preserve existing graph and seed marker; never reseed an existing empty book; new book creation must be separate from sample promotion |
| Export / preview / restore / restart recovery | Formats 1–3 contain one book, draft and settings; all-graph replacement plus two JSON writes | Versioned workspace envelope, complete safety snapshot, candidate validation and restart recovery spanning all books/state/images |
| Hero / stack / activity preferences | No implementation | Separate visible IDs, order and activity scope from financial records; app-owned downsampled image files with safe fallback |

Relevant implementation files: `Monocle/Domain/Expense.swift`, `BookBackup.swift`; `Monocle/Persistence/ExpenseRepository.swift`, `LocalStateStore.swift`, `SampleBookSeeder.swift`; `Monocle/Application/ExpenseService.swift`, `BackupService.swift`; `Monocle/App/AppEnvironment.swift`, `AppModel.swift`, `MonocleApp.swift`; `Monocle/Integrations/ExpenseIntents.swift`; entry, recents, budget, bill, category and backup feature views.

`BookKind.sample/real` is existing legacy onboarding metadata, not a purpose taxonomy. Preserve legacy decoding; do not expand it into Daily/Travel/Bills or introduce BookType/WalletCard.

## Proposed minimum safe continuation

1. Keep the V2 model and existing SQLite identity if no new financial fields require a model version. Its relationships already express book ownership. Validate existing Book ID against local profile; reject ambiguity rather than remap records. Retain old draft/settings until a recoverable activation completes.
2. Make command and value ownership explicit throughout the table above while still permitting only the existing book. Reject cross-book references and attempts to reparent an existing record.
3. Add a versioned workspace backup envelope containing book-scoped snapshots, portable preferences and bounded image payloads. Decode formats 1–3 as one preserved book, not as a request to merge or reassign IDs. Keep restore as whole-workspace replacement with an accurate preview.
4. Extend the existing journal protocol before enabling book creation. Stage immutable image files; preserve original files until activation is committed. Journal the complete original workspace. Validate payload sizes, decoded image dimensions and safe generated filenames; never trust imported paths. Missing image references render a generated color fallback. Cleanup must not remove files needed by recovery.
5. Prove old V2 graph preservation and complete workspace rollback with disk fixtures and injected failures, then enable book creation and per-book state. No CloudKit or general-purpose architecture framework is needed.
6. Only then build the bounded native Instrument, Ledger and Signal prototypes. Keep production navigation until core selection and entry targeting work. Continue bills after these boundaries are stable.

This is a proposed implementation approach, not a validated migration or backup schema.

## Validation gates still required

- Open an existing V2 disk fixture and compare exact Book, expense, allocation, category and budget IDs/values before and after; include an existing real book, empty book and legacy draft/settings. Existing tests cover V1→V2, not this future workspace activation.
- Two books with overlapping dates/names: isolate read/save/edit/delete/repeat/Undo, budgets, categories, rules and drafts. Wrong-book IDs must fail without mutation.
- Workspace round trip and legacy formats 1–3: compare every book's values, draft, rules, preferences and images. Inject failure at each database/state/image stage and restart recovery twice; retain malformed journals and block writes.
- Hero replacement, missing-file fallback, invalid/oversized image rejection and failed image writes.
- Visible/all activities; order/visibility after relaunch; correct card/list and Add Expense/Shortcut targets, including a selection change while a draft is open.
- One/many/empty books, long names/history, large Dynamic Type, VoiceOver, Reduce Motion, native buttons and scroll alternatives.
- Full simulator testing remains reported blocked by unavailable CoreSimulatorService/runtime; not rechecked in this audit. No signed-device claims. No IPA until migration, backup and navigation are stable.
