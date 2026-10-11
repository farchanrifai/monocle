## 1. Immediate Next Step

Review on screen, then decide: `feat/mac-activity-filters` (Mac only: toolbar Filter with counts/collapsible sections, wider search, card-page quick stats; branched from `feat/model-b`, merge or delete) and the iOS budget screens (never viewed on a device yet: Budgets picker, Analytics "Budget vs actual"; shipped in 0.8.1 (96)).
- Still open: stack cap is current-only (versioning needs format 9); currency drift at today's rate; a goal replaces the cycle budget on the same `effectiveDay`; Mac UI tests not rerun (and none cover the new budget/filter UI); stale roadmap; privacy label for Frankfurter; Mac Release rebuild; no merge to main.
- Demo app: after every Mac rebuild, launch it (`open -n --env MONOCLE_DEMO=1 build/macos/DebugDerived/Build/Products/Debug/Monocle.app`).

## 2. Last Completed Checkpoint

Budget work plus Mac polish, published as SideStore 0.8.1 (96) (`monocle-0.8.1-build-96-unsigned.ipa`, SHA-256 `68109c4e053d2e2e88574f70cac849a405b756568b5294c5ad0224ea4a7be54b`, also in iCloud Monocle-codex). Verified: iOS unit 233 pass (4 skipped), Mac unit 22 pass; Mac screens seen via screenshots, iOS screens not.

- Budget model (`Monocle/Domain/BudgetStatus.swift`): `BudgetStatus`/`BudgetCycleResult` computed from existing versions, no storage change; expired "Total until" goals end; projection scales total spend; any card's budget is editable (`saveBudget(..., cardID:)`).
- UI: card/stack picker on Budgets (iOS + Mac), per-card Edit in a stack's "By card" list, Analytics "Budget vs actual" + cycle chart; Mac Budgets/Bills use natural-height grids.
- Mac (branch `feat/mac-activity-filters`): toolbar Filter, wider search (note, card, Paid with, amount), card-page stats. Details in the commits.
- Earlier: model B phases 0-6, Mac UI polish; see `docs/planning/model-b-plan.md`.
