## 1. Immediate Next Step

2026-10-10: Mac cards/stacks/sidebar (committed). In MacRootView.swift + MacCommands.swift:
- Cards page: New Card/New Stack, cards grouped by stack, "Not in a Stack", "Hidden Cards" group. Shared `MacCardMenu` (Edit Card…, Stacks toggles, Hide/Unhide, Delete Card… with cascade warning). Card/stack sheets + delete confirm live on MacRootView via MacAppState (addingCard/editingCard/deletingCard/editingStack; deleteCard/deleteStack/setCardHidden).
- Card editor: live preview; Style = Color (palette) / Custom (ColorPicker → hex) / Template (9 stock designs) / Photo (fileImporter → CardArtworkStore.saveArtwork, unused picks deleted on close); Text tone. iOS `StockDesignViews.swift` added to Mac target (project.yml + xcodegen); MacCardView now draws real stock designs.
- Stack page: `MacDestination.stack(UUID)` and `.hiddenCards` (persisted). Header + Edit Stack…, card strip, cycle spending + transaction tiles, `MacExpenseTable(bookIDs:)` over the stack's cards. Viewing doesn't change the iOS active stack (createStack still does, model behaviour).
- Sidebar: collapsible Stacks / Cards / Planning (`@AppStorage`). Shows 5 items then "Show N More"/"Show Less"; a selected item past 5 stays visible. Hidden cards are left out of Cards and shown as a "Hidden Cards" row (setting: Stacks header right-click, or View ▸ Show Hidden Cards, default on). Hidden = existing `alwaysHiddenBookIDs`; iOS labels renamed Archived → Hidden (StackCustomizerView, toast).
- Command bar lists stacks.
Tests: Mac 12 unit pass (new: destination round-trip + sidebar limit; hide/unhide + stack page render). Renders checked: Cards page, stack page, hidden cards. NOT checked live: sidebar collapse/Show More, context menus, editor sheet (cmux Computer Use daemon down; offscreen render skips the sidebar and table rows). UI tests not run. iOS builds after the label rename; iOS unit tests not run.

Follow-ups done: fixed-height stack headers (symbols shifted the page); fixed-width card grid columns (cards slid during inspector animation); page action buttons use .glass / .glassProminent (New Card, New Stack, Edit Stack, Edit Budget, New Bill, Skip/Record).

Next: redesign the New Expense panel (in-app sheet MacExpenseForm + global Quick Record panel); proposal pending user approval. iOS unit tests still not run since the Archived→Hidden rename. Mac still lacks category management. Chat v2 remainder: streaming + localized UI strings.

Other pending: proxy (Cloudflare Worker; user deploys).

## 2. Last Completed Checkpoint

2026-10-10: Chat v2 tool set done. (1) Splits: `propose_expense`/`propose_edit` take `split` (2+ distinct categories summing to amount) instead of `category`; amount-only edit of a split refused (give new split); cards list each part. Committed da7a8c5. (2) Bills: `propose_bill` (name, amount, category, monthly/weekly/yearly, day/weekday/month default to today, record automatic|confirm default confirm, reminder default on, card) → `BillProposalCard` (in ExpenseProposalCard.swift) Save/Discard → `AppModel.saveBill`; `list_bills` (scope). 10 tools now. Golden prompts cover split + "netflix 186rb tiap bulan tanggal 5". iOS unit + Mac 9 unit pass. UI tests not run. IPAs published: 0.7.27 (92) edit/delete; 0.7.28 (93) splits + bills (SHA-256 2c2d2f2a…e2b762).

Next: remaining chat v2 is streaming + localized UI strings (bigger). Alternatives: F26 background persistence work, M4 accessibility audit, refresh stale docs/planning/roadmap.md. Golden prompts + cache check need Anthropic credits.

Other pending: proxy (Cloudflare Worker; user deploys).
