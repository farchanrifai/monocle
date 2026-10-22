# Anka — App Spec (as built, v0.7.21 / build 84)

Personal IDR expense tracker for iPhone. Local-first. Describes the code on `codex/backend-reliability`.

## 1. Data models

**There is no SwiftData and no `@Model`.** Persistence is **Core Data** (`Anka.xcdatamodeld`, current version `AnkaV4`). Entities are untyped `NSManagedObject` (no generated classes). They are mapped by hand to `Sendable` value structs in `Persistence/ExpenseRepository.swift`.

The domain has no Account or Wallet entity. A **Book** is shown in the UI as a **"card"**. Users can hold multiple cards and group them into "stacks". Stacks and card appearance are stored in JSON (`workspace.json`), not in Core Data.

Core Data entities (V4, attribute → type):

```
Book                 id UUID, name String, colorIndex Int64
                     expenses →> ExpenseRecord (cascade), categories →> CategoryRecord (cascade),
                     budgets →> BudgetRecord (cascade), bills →> BillRuleRecord (cascade)
CategoryRecord       id UUID, name String, symbol String (SF Symbol)
                     book → Book, allocations →> AllocationRecord
ExpenseRecord        id UUID, amount Int64, day String ("yyyy-MM-dd"), note String,
                     source String ("manual", shortcut, CSV, bill…), createdAt Date
                     book → Book, allocations →> AllocationRecord (cascade)
AllocationRecord     amount Int64; expense → ExpenseRecord, category → CategoryRecord
BudgetRecord         id UUID, effectiveDay String, overallLimit Int64, startDay Int16,
                     transitionEndDay String?; book → Book, categoryLimits →> BudgetCategoryRecord
BudgetCategoryRecord categoryID UUID, limit Int64; budget → BudgetRecord
BillRuleRecord       id, name, amount Int64, categoryID UUID, recurrenceType String,
                     recurrenceDay/Month Int16, scheduleEffectiveDay String?, scheduleRevision Int64,
                     isAutomatic, hasReminder, isActive Bool, reminderLeadDays Int16, createdAt Date
                     book → Book, occurrences →> BillOccurrenceRecord
BillOccurrenceRecord id, dueDay String, status String, expenseID UUID?, createdAt, updatedAt Date
                     rule → BillRuleRecord
```

Domain structs (`Domain/Expense.swift`, `Domain/Bill.swift`, `Domain/BookBackup.swift`):

```swift
struct Expense { id: UUID; amount: Int64; day: String; note: String
                 allocations: [Allocation]; source: String; createdAt: Date; bookID: UUID? }
struct Allocation { categoryID: UUID; amount: Int64 }   // splits; sum must equal amount
struct ExpenseCategory { id: UUID; name: String; symbol: String }
struct GlobalCategory { id; name; symbol; defaultActiveForNewCards: Bool }
struct BookProfile { id: UUID; name: String; kind: BookKind (.sample/.real); colorIndex: Int }
struct BudgetVersion { id; effectiveDay: String; overallLimit: Int64; startDay: Int
                       categoryLimits: [CategoryBudget]; transitionEndDay: String?; bookID: UUID? }
struct BillRule { id; bookID; name; amount: Int64; categoryID; recurrence: BillRecurrence
                  recordingMode; hasReminder; reminderLeadDays; createdAt; isActive
                  scheduleEffectiveDay: String?; scheduleRevision: Int }
```

`Expense.validate` requires all of the following:
- `amount` > 0
- a valid day
- at least one allocation
- unique categories
- allocations that sum exactly to `amount`

## 2. Amounts

- Stored as `Int64` **minor units** at a fixed scale of 100: `Rp1 = 100` (see the `Expense.amount` comment).
- `Money.maximum` is 9e18. Sums use the overflow-checked `Money.checkedSum`.
- Currency is hard-coded to **IDR**. The backup header stores `currency: "IDR"` and `minorUnitScale`. No other currencies are supported.
- Manual entry accepts whole rupiah only. Inputs like `28k` and `Rp28.000` are parsed by `Money.parse`. CSV import accepts exact cents via `Money.parseExact`.
- Display uses `Money.format`, which prints `"Rp"` plus a number formatted for the current locale.

## 3. Categories

User-created, not an enum. Six defaults have fixed UUIDs: Food & Drink, Transport, Shopping, Home, Wellbeing, Leisure.

- A global catalog (`GlobalCategory`, stored in `workspace.json`) is activated per card as a `CategoryRecord`.
- Users can create, rename, archive and deactivate categories (`CategoryManager.swift`).
- `CategoryRule` keyword rules auto-categorise text entry (`ExpenseParser`).

## 4. Targets and shared code

Targets are generated from XcodeGen `project.yml`:
- **Anka**: iOS app, iPhone only, portrait.
- **AnkaWidgets**: WidgetKit and Live Activity extension.
- **AnkaTests** and **AnkaUITests**.

Other facts:
- **No macOS target.** A native Mac app is planned only (`docs/planning/roadmap.md`).
- **No Swift packages and no third-party dependencies.** The only shared code is two files compiled into both targets: `Integrations/Widgets/WidgetSnapshot.swift` and `WidgetSnapshotStore.swift`.
- App Group: `group.com.farchan.anka`, used for widget snapshots.

## 5. Sync and container setup

**CloudKit/iCloud is off.** There are no iCloud entitlements; the implementation report states "No CloudKit synchronization was introduced." iCloud sync is a roadmap item.

`App/AppEnvironment.swift` is the single composition root:
- **Store:** an `NSPersistentContainer` with a SQLite store at `Application Support/anka-prototype/Anka.sqlite`, opened with automatic lightweight migration.
- **Startup order:** backup recovery runs first, then sample seeding. Then it builds `ExpenseService` and `@MainActor @Observable AppModel` (a singleton).
- **Other state:** stored as JSON files next to the store (`FileLocalStateStore`): `settings.json`, `workspace.json` and per-card drafts.
- **Backups:** full-workspace export/restore (`.monoclebackup`, format 7) via `BackupService`.

## 6. Existing data layer for expenses

| Layer | File | Role |
|---|---|---|
| `ExpenseStore` protocol | `Application/ExpenseService.swift` | CRUD for books, expenses, budgets, bills and categories; paged `expenses(in:from:to:limit:offset:)` |
| `ExpenseRepository` | `Persistence/ExpenseRepository.swift` | Core Data implementation; `transaction {}` for atomic writes |
| `ExpenseService` | `Application/ExpenseService.swift` | Validated writes via `performTransaction`, snapshots, active card, commit callbacks (widget refresh, bill notifications) |
| `AppModel` | `App/AppModel.swift` | UI entry points: `save(_:)`, `saveDraft()`, `saveBudget`, `saveBill`, `saveCategory`, delete with undo |
| `ExpenseParser` | `Domain/Expense.swift` | Free text such as "Coffee 28k" → amount, note and category. **The closest existing hook for chat input.** |
| App Intents | `Integrations/ExpenseIntents.swift` | `AddExpenseIntent`, `AddExpenseFromTextIntent`, open quick entry, start/end spending session |
| CSV | `Domain/CSVEngine.swift` | Import/export |

## 7. Reports and charts

The Analytics screen uses **Swift Charts** (`Features/AnalyticsView.swift`): line, bar, area and sector (donut) marks. Data comes from the pure functions in `Domain/AnalyticsEngine.swift`:
- daily spend
- month-over-month comparison
- category distribution
- per-card distribution
- pace metrics

Filters:
- Time horizons: this cycle, this month, last month, last 30 days, last 90 days, year to date.
- Scopes: current card, a stack, a single card, or all cards.

Other surfaces:
- **Budgets:** `BudgetsView` shows budget progress.
- **Widgets:** Today spending, Budget, Stack, Quick capture, Spending session (Live Activity).

## 8. Navigation and where chat could go

`RootView` (`App/AnkaApp.swift`) is a `TabView` with **Home** (`BookHomeView`) and **Analytics** (`AnalyticsView`). The system tab bar is hidden and replaced by the custom `BottomNavigation`, which has a tab switcher, a stack filter menu and a central "+" add button.

Most other screens are `.sheet`s: entry, settings, budgets, bills, CSV, card customizer. Candidate places for chat:
1. **A third `Tab`.** This needs a matching item in `NativeTabSwitcher` (`BottomNavigation.swift`, which uses `UITabBarItem` tags 0 and 1).
2. **A sheet triggered from `BottomNavigation` or the Home toolbar**, the same pattern as `showAnalytics` and `showEntry`.
3. **A new `EntryMode`** in `EntryView`. (Historical: Text mode existed then; it was removed in 0.8.4, so recording is the form or chat. `ExpenseParser` remains for Shortcuts.)

There is no macOS app, so iOS is the only placement.

## 9. Platform and toolchain

| Item | Value |
|---|---|
| iOS deployment target | 26.0 (iPhone only) |
| Swift language mode | 6.0 |
| Xcode | Verified with Xcode 27.0. CI is moving to the `xcode-27` runner (26.6 timed out). |
| Project generation | XcodeGen 2.46.0 |
| Distribution | Unsigned IPA re-signed by SideStore. Not on the App Store. |

## 10. Networking, auth and secrets

- **No networking:** no `URLSession` and no server.
- **No user accounts or remote auth.** The app is fully offline.
- **App lock only:** `Application/AppLock.swift` uses LocalAuthentication (Face ID / passcode) with configurable timeouts.
- **No Keychain or secrets handling exists.** A chat feature that calls an LLM API would be the first network and first secret.

## 11. Localization

- **English only.** There are no `.xcstrings` or `.lproj` files. UI strings are hard-coded English literals, including error messages.
- **Currency** is always IDR, prefixed `"Rp"`, with digits formatted for the device locale (`Locale.autoupdatingCurrent`).
- **Amount input** follows the locale's decimal and grouping separators. CSV import auto-detects `id_ID` versus `en_US` style numbers.
- **Dates** are stored as Gregorian civil-day strings (`yyyy-MM-dd`) and reported in the local time zone. Display uses `Date.formatted` plus "Today" and "Yesterday".

## 12. Known TODOs and tech debt relevant to chat

- **No inline TODO/FIXME in the source.** Debt is tracked in `docs/audit/2026-10-05-backend-implementation.md`.
- **F26 is only partly done.** SQLite, snapshot and backup work still runs largely on the main actor, and some features read whole ledgers. A chat that queries history should use the paged/date-bounded APIs and avoid full scans.
- **Device gates are pending:** phone performance budgets (1k/10k/50k), and the IPA-over-install check (migration, widgets, notifications, app lock).
- **Writes have no background context.** They go through the `@MainActor` `ExpenseService` and `AppModel`. Chat-created expenses should reuse `AppModel.save` / `ExpenseService` so validation, undo, widget refresh and backups stay consistent.
- **IDR only, English only, iPhone only, no sync.** Each of these limits a chat feature's scope.
- **3 known flaky UI tests:** card animation and context menu.
