# Monocle Flow Walkthrough

Date: 2026-09-19  
Branch: `gpt-review`  
Simulator: iPhone 15 Pro, iOS 26.5

## Static route map

- App root
  - Home tab: card stack, card detail, activity, quick expense entry
  - Analytics tab: horizons, filters, category distribution and trends
- Card detail
  - Add expense -> amount, category, note, date -> save/edit/delete
  - Card options -> Cards & Stacks, Budgets, Bills, Analytics, Spending Session, CSV, Settings
- Cards & Stacks
  - Open/switch card
  - Create, rename and customize card
  - Create and customize stacks
- Settings
  - Active-card rename and category management
  - Backup/restore and CSV import/export
  - Appearance, shortcut input order, app lock and destructive reset
- External entry points
  - Quick Capture widget -> target card/category -> expense entry
  - App Intent -> ordered card/category/note/amount prompts -> save
  - Live Activity spending session -> scoped expense aggregation

## Connection findings exercised

- Card switching now swaps and preserves per-card drafts instead of carrying draft state across cards.
- Widget deep links carry the target card, and category deep links are accepted only when active on that card.
- CSV export resolves categories from every exported card; import category selection follows the chosen target card.
- Structured shortcuts revalidate categories after card resolution, including custom prompt orders.
- Spending sessions are scoped to their starting card and receive saves from both the app and shortcuts.
- Full backup/restore includes cards, bills, drafts, preferences, stacks and artwork; safety backups use the same complete format.
- Clearing bill-created transactions marks their occurrence skipped so automatic reconciliation does not recreate them.

## Automated walkthrough

- Final unit suite: 118 tests passed, including the 750-write multi-card stress case.
- Focused UI regressions: 6 tests passed after one simulator launch-infrastructure retry.
- Full UI suite: 42 tests passed in 787.7 seconds.
- The full suite covers expense create/edit/delete, invalid saves, card and stack navigation, card creation/customization, budgets, bills, CSV, backup UI, settings, analytics and responsive layout variants.

## Human validation still required

- Real-device widget launch and Live Activity lifecycle.
- Face ID/app-lock prompts and notification delivery.
- VoiceOver reading order, larger Dynamic Type and Reduce Motion review.
- SideStore-installed persistence and cold-launch behavior.
- Subjective animation/gesture feel on 60 Hz and 120 Hz hardware.
