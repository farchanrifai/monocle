## 1. Immediate Next Step

Continue backend fixes on the Mac from branch `audit/backend-2026-10-04`, based on `b7621cc0e2133336a4f4faa9961447dbde6a9b16` (0.7.20/build 83).

Read `AGENTS.md`, `docs/audit/2026-10-04-backend.md`, and `docs/planning/backend-improvement-plan.md`. Fetch the audit branch and create `fix/backend-reliability` in a new local worktree using the commands in the plan. Establish the unchanged Xcode/unit/UI baseline before implementing fixes.

Start with work packages 0 and 1: disk-backed regressions, budget-only category deletion, bill-expense deletion/undo links, and correct per-card draft cleanup. Then protect recovery journals and remove the live-data/backup-capacity mismatch before concurrency/performance refactoring.

No application fixes are included in this branch. Runtime verification is outstanding: this cloud executor is Linux without Swift/Xcode. Preserve real user data and test migrations/recovery on fixtures/copies. Keep this as the single root handoff file and update it after each major checkpoint.

## 2. Last Completed Checkpoint

Completed the full local-backend source audit on 2026-10-04 in `/workspace/monocle-backend-audit`, isolated from the original `/workspace/monocle` checkout. Reviewed persistence, financial/date logic, backup/import/artwork, startup/recovery, recurring bills/notifications, Shortcuts/widgets/Live Activities, lock behavior, performance work placement, migrations, and test coverage.

The report records 27 prioritized findings with file/line evidence, triggers, fixes, and regression requirements. The plan sequences baseline/regressions, integrity/recovery, validation/migration, committed publication, recurrence/integrations, reporting/precision, device lifecycle, and measured optimization.

Verified model/relationship inverses, plist/entitlement/scheme/asset syntax, four shell scripts, exact arithmetic boundaries, and documentation consistency. Inventoried 118 unit and 42 UI test methods; did not compile or execute them. No source fixes, data changes, release builds, or IPA publication were performed. The delivery branch for this audit checkpoint is `audit/backend-2026-10-04`; use the plan's fetch/worktree commands to continue on the Mac.
