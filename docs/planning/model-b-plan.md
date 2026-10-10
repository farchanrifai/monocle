# Model B implementation plan

Branch `feat/model-b` (from `feat/apple-intelligence-chat` at `23e8586`). Decisions: Monocle Data Model page, https://claude.ai/artifact/8vedGpoUBw6J97NBgRZqPg (decided 11 Oct 2026).

## What Model B is

- Monocle tracks spending by purpose. A card is a purpose (Daily, Japan Trip, Side Business), never a bank account. No balances anywhere.
- Spending only. No income, savings pots, refund entries or business revenue. A refund = lower the amount or delete the expense.
- A goal is a card budget of kind "Total until <date>".
- A card is in zero or one stack ("Not in a Stack" otherwise). Stack budget = sum of its cards, with an optional cap.
- "Paid with" is an optional label per expense, with a default per card. Never a balance.
- Categories are shared across the workspace.
- Currency: workspace reporting currency, optional card currency, optional card spending currency. Each expense keeps its original amount, currency and rate. The rate is fetched with a manual override. Expenses use the rate of their own day; budgets use today's rate.
- Add Expense form: Amount, Card and Category always shown. Date, Note, Split, Paid with and Currency can be hidden (Paid with and Currency start hidden). A hidden field that has a value still shows when editing.

## What the code already does (no work needed)

- **Shared categories.** Names and symbols live in `GlobalCategory`. `updateGlobalCategoryMetadata` renames every card's copy by shared UUID. Per card, only archive and delete exist. The per-card `CategoryRecord` copies stay (`ponytail:` collapsing them into one row is cleanup with no user-visible effect; do it only if it blocks something).
- **Stacks in the preferences file.** `CardStack` in `WorkspacePreferences` JSON. They stay there; a Core Data move isn't needed for ≤1 stack per card.
- **No sync.** Nothing uses iCloud. Workspace settings live in a local JSON file and in backups, so "synced" means "saved with the workspace and in backups".

## Storage changes (one Core Data V5, one backup format 8)

Core Data `MonocleV5` adds only optional attributes, so lightweight migration works (the store already uses `NSInferMappingModelAutomaticallyOption`):

| Entity | New attributes |
|---|---|
| `Book` | `currency` String?, `spendingCurrency` String?, `defaultPaidWithID` UUID? |
| `ExpenseRecord` | `paidWithID` UUID?, `originalAmount` Int64 (0 = same as amount), `originalCurrency` String?, `rate` String?, `rateSource` String? |
| `BudgetRecord` | `kind` String (default "monthly"), `endDay` String? |

Referencing by UUID matches how `BillRuleRecord.categoryID` and `BillOccurrenceRecord.expenseID` already work. No new relationships.

`WorkspacePreferences` (JSON, decoded with defaults): `paymentMethods: [PaymentMethod]`, `hiddenEntryFields: [EntryField]`, `reportingCurrency: String = "IDR"`. `CardStack` gains `capLimit: Int64?` and `capStartDay: Int?`.

Backup format 8: header `currency` becomes the reporting currency; new fields as above. Format 4–7 files still read and are upgraded on import. `ponytail:` Core Data entity names (`Book`, `ExpenseRecord`…) stay as they are. They're storage-only and invisible to users; renaming entities adds migration risk for no gain.

All amounts stay `Int64` at scale 100 for every currency (¥12,000 is stored as 1_200_000). Display uses each currency's own number of decimal places. This keeps every `checkedSum`, split and analytics path unchanged.

## Phases

Each phase is its own commit (or set of commits), builds, and passes `MonocleTests` + `MonocleMacTests` before the next one. Mac UI tests aren't run unless the user is away.

### Phase 0: Copy and names in the UI (no data change)

- One noun: Expense. Replace "Transaction", "Transactions", "Record" (noun) and "Spending" (noun) in UI strings (`TransactionDetailView` title → "Expense Details", "N TRANSACTIONS" → "N EXPENSES", etc.).
- One verb: Add. "Record" → "Add", "Quick Record" → "Quick Add", "Record automatically" → "Add automatically", "Recording mode" → "When due".
- Remove balance wording: `ResetDataView.swift:78`, `:136`.
- Chat prompts and tool descriptions use the same words (`ChatAgent`, `AppleChatAgent`, `ToolExecutor`).
- Tests: update string assertions; run the on-device chat golden prompts once (`AppleChatTests`) because the wording changed.

### Phase 1: Storage foundation

- Add `MonocleV5` (attributes above), set as current. Repository read/write for the new fields, defaulting to today's behavior.
- `WorkspacePreferences` and `CardStack` fields above, with `decodeIfPresent` defaults.
- Backup format 8 writer + reader; format 7 import still works.
- Tests: migrate a V4 store fixture to V5 with data intact; backup round trip v8; import v7 into v8.

### Phase 2: Stacks

- Enforce ≤1 stack per card in `saveStackConfiguration`, `createStack` and the hide/unhide paths (`AppModel.swift:565`, `:640`, `:710`).
- One-time cleanup at launch: a card in several stacks keeps the first one (in stack order) and is removed from the others. Show a toast once.
- "Not in a Stack" group in the stack picker, iOS home and the Mac sidebar.
- Optional stack cap: editor in `StackCustomizerView` and Mac; stack budget = sum of card budgets (converted to reporting currency in phase 5), shown against the cap when one is set.
- Tests: the invariant, the cleanup, totals with and without a cap.

### Phase 3: Budget kinds (goals)

- `BudgetVersion.kind` = monthly | total, `endDay` for total. For a total budget, the cycle runs from the budget's `effectiveDay` to `endDay`; spending pace uses that range.
- Budget editor: "Monthly" / "Total until <date>" segmented control (iOS `BudgetsView`, Mac planning).
- Card back, widgets and analytics use the right range for total budgets.
- Tests: cycle math for a total budget across months; pace; widget snapshot.

### Phase 4: Paid with and form customization

- Settings list to manage Paid with labels (name + kind icon). Card default in the card editor.
- Entry: Paid with picker (pre-filled from the card's default). Expense details show it. Filter and "By Paid with" chart in analytics (iOS + Mac).
- CSV: optional "Paid with" column, export and import. Chat: optional `paid_with` on propose tools.
- Form customization: Settings → "Add Expense Form" toggle list, also in the sheet's ⋯ menu. Applies to iOS `EntryView` and Mac `MacExpenseForm`. A hidden field with a value is still shown. Hidden Date means today; Split hidden means one category.
- Tests: hidden-field rules; CSV round trip with Paid with; filter totals add up to the grand total.

### Phase 5: Currency (largest)

1. **Money is currency-aware.** `Money.format(_:currency:)` with the reporting currency as the default; `Money.parse(_:currency:)` accepts decimals only for currencies that have them (USD yes, JPY/IDR no). About 95 `Money.format` call sites. Pass a currency explicitly only where a card or expense currency applies; the rest keep the default.
2. **Rates.** `ExchangeRateService`: fetch daily rates (candidate: Frankfurter, ECB data, has IDR/JPY/USD; verify coverage and terms before choosing), cache by day in a local JSON file, nearest earlier day when missing (marked ≈ and refetched later). This is the app's first network call for data: update the privacy policy and the App Store privacy label. Manual override per expense.
3. **Entry.** Currency field (hidden by default), defaulting to expense → card spending currency → card currency → reporting currency. Shows the converted amount live. Saving stores original amount, currency, rate, rateSource and `amount` in reporting currency.
4. **Card display.** Totals and budget in card currency; ≈ line in spending currency, otherwise the reporting currency. Expense rows show the original amount, with the card-currency value beside it when different.
5. **Stacks, analytics, widgets** in reporting currency.
6. **Reporting currency change.** Settings, with a warning. Re-convert every expense from its original amount at its own day's rate (manual overrides carried over: override × old→new on that day). Budgets convert at today's rate. Runs as one background save. A backup is created first, as Reset already does.
7. **Card currency change.** Budget converts at today's rate; card totals recompute from originals.
8. **Prompt.** After the first expense on a card in a currency other than the card's, offer "Use JPY as this card's spending currency?"
9. **CSV, backup, chat.** CSV gains Currency, Original amount and Rate columns. Chat accepts "¥1200 ramen".
- Tests: format/parse per currency; conversion with fixed rates (no network in tests; inject the rate source); reporting-currency change round trip; manual override survives; missing-rate fallback; card totals in card currency.

### Phase 6: Code names

Mechanical renames, one commit per type, no behavior change: `BookProfile`/`Book` → `Card`, `bookID` → `cardID` (≈680 references including tests), `CardStack` → `Stack`, `Allocation` → `Split`, `BudgetCycle` + `BudgetPeriod` → `Cycle`, `BillRule` → `Bill`, `BookKind.sample` → `.demo`. Backup JSON keys stay readable: decode old keys, write new ones in format 8. This phase comes last so it doesn't create merge conflicts in phases 0–5.

## Release

- After each phase: Mac unit tests, iOS simulator tests and builds. Build an IPA to the SideStore folder for phases the user wants to try on a phone.
- Merge to main only when the user says so; `feat/apple-intelligence-chat` has to be merged first.
- Rollback: V5 is additive, so an older build can't open a V5 store. Ship phase 1 only together with a phase that users can see, and keep a backup prompt before the first V5 launch.

## Open questions for the user

1. Phase 6 renames ~680 `bookID` references. Do it, or rename only the types and leave property names?
2. Exchange rate source: Frankfurter (free, ECB, no key) unless you prefer another.
