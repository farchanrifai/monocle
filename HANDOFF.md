## 1. Immediate Next Step

Model B phase 0 (UI wording) is done on `feat/model-b` (commit `e49a4ee`, pushed). Next: phase 1, storage foundation (Core Data V5 optional fields, `WorkspacePreferences` fields, backup format 8, CSV "Book" column → "Card" with "Book" still accepted on import). Plan: `docs/planning/model-b-plan.md`.

- Phase 0: Expense instead of Transaction/Record, Add instead of Record (Quick Add, Add automatically, "When due"), Card/Workspace instead of Book, no "card balances" text. Accessibility IDs (`recordExpense`), storage keys (`quickRecord`) and the CSV Book column unchanged.
- Verified: iOS unit tests 213 pass (4 skipped), Mac unit tests 20 pass (1 skipped). Not run: Mac/iOS UI tests (strings updated only), on-device chat golden prompts (tool wording changed slightly), no IPA built.
- User decisions: rename everything in phase 6 (incl. ~680 `bookID`); Frankfurter for exchange rates.
- Don't merge to main; `feat/apple-intelligence-chat` is still unmerged.

## 2. Last Completed Checkpoint

Model B (purpose cards) is decided and planned; nothing is implemented yet. Branch `feat/model-b` (worktree `.claude/worktrees/model-b`, from `feat/apple-intelligence-chat` at `23e8586`).

- Plan: `docs/planning/model-b-plan.md` (phases 0–6: UI copy → V5 storage + backup 8 → stacks ≤1 per card + cap → budget kinds/goals → Paid with + form customization → currency + FX → code renames).
- Decisions and glossary: Monocle Data Model page https://claude.ai/artifact/8vedGpoUBw6J97NBgRZqPg (version 4).
- Waiting on the user: (1) rename all ~680 `bookID` references in phase 6, or only the types; (2) FX source (Frankfurter proposed). Then start phase 0.
- Don't merge to main; `feat/apple-intelligence-chat` (AI chat, Mac Analytics, Mac toolbar) is still unmerged and its open items still apply.
