## 1. Immediate Next Step

2026-10-10: Mac multi-select + chat inspector. Inspector column hidden (and its toolbar toggle disabled) on Chat. Expense tables now select many (⌘/⇧-click): `MacInspectorSelection.expenses(Set<UUID>)` + `expenseIDs` / `init?(expenseIDs:)`; table binds a `Set` through the same single inspector selection. `MacAppState.delete([Expense], undoManager:)` (single delete now routes through it) and `recategorize(_:to:undoManager:)` — each one undo/redo step; recategorize skips split expenses; `sharedCategories(for:)` = categories active on every selected card. Context menu: single row adds "Change Category"; several rows get "Change Category" + "Delete N Expenses"; Delete key deletes all selected; double-click edit only for one row. `MultiExpenseInspector`: count, date range, total, by-category totals, split count, Change Category + Delete N actions. Tests: `testBulkDeleteAndRecategorizeUndoAsOneStep` (unit), `testMultiSelectShowsSummaryAndDeletesWithOneUndo` (UI). Mac 9 unit + 10 UI pass; iOS builds.

Next: user reviews multi-select (rebuild: `MONOCLE_SIGNING_IDENTITY="Clipboard Dev" scripts/build-macos.sh --install`). Then: bill pause, or fix the 3 pre-existing iOS UI failures (chat opt-in, appearance picker, tab island). Live chat still blocked on Anthropic credit top-up.

Other pending: proxy (Cloudflare Worker; user deploys), golden-prompt script; when billing works: live golden prompts + verify cache reads.

## 2. Last Completed Checkpoint

2026-10-10: Mac Settings rebuilt as a sidebar window (`MacSettingsView`), Dia / System Settings layout: `NavigationSplitView` sidebar (General / Appearance / Shortcuts / Security / AI Chat / Data, 200pt), panes are centred `.formStyle(.columns)` forms (right-aligned "Label:" column, `SettingsNote` captions wrapped at 360pt) in a ScrollView with 40pt side / 28pt top padding. Settings scene now applies `preferredColorScheme` (it ignored the app's appearance before). Radio groups for entry mode + appearance; Shortcuts grouped (app / navigate / data) with fixed-width key buttons, explicit 14pt gaps (column forms ignore Section spacing). Mac-only `ChatSettingsPane` (checkbox + SecureField with `prompt:` + `labelsHidden`, else the placeholder renders as a label); shared iOS `ChatSettingsView` reverted to iOS-only. Gotcha: detail column didn't refresh on selection via `@AppStorage` binding — now `@State selection` + `.id(pane)`. `testSettingsUseSidebarPanes` clicks every pane, asserts title, attaches screenshots (+ main window). Mac 8 unit + 8 UI pass; iOS builds.

Then: DEBUG fake Claude (`MONOCLE_FAKE_CLAUDE` env → `ChatSession.fakeClaude`, scripted propose "Kopi 28rb" then confirm; Mac pane treats key as present). New `testChatProposesAndSavesWithFakeClaude`: send → proposal card → Save → "Saved" → expense in Activity. Mac 8 unit + 9 UI pass. Release build 0.7.26 (91) installed to ~/Applications (signed "Clipboard Dev").

Next: user can't top up Anthropic credit, so live API still untested. Next work: multi-select in tables (bulk delete/recategorize). Not done: multi-select (bulk actions), bill pause. iOS UI: 3 tests fail at HEAD too (chat opt-in, appearance picker, tab island) — pre-existing, uninvestigated.

Other pending: proxy (Cloudflare Worker; user deploys), golden-prompt script; when billing works: live golden prompts + verify cache reads.
