## 1. Immediate Next Step

0.9.9 (113) is the latest: `monocle-0.9.9-build-113-unsigned.ipa`, SHA-256 `e59c6d0533cac6a6fbdabb0fe0c74e45dcc3d33c3e0275ac53c2e5895c09a067`, iCloud `Monocle-codex/`, tag `v0.9.9-build.113`. Adds `get_budget_status` `cycle: current|previous` (ask about last cycle in chat). `main` is pushed.

**Next:** phone checks on 0.9.9: last-cycle budget question in chat, Luna bridge with a real invite, streaming, composer clear, Shortcuts incl. Remove Last Expense, widget deep links. Stack cap versioning still needs owner approval (`BudgetVersion.stackID`, backup format 9). Left: `docs/privacy.md` contact line + hosting; chat width creep; Shortcuts payment-method parameter, Spotlight `IndexedEntity`, Control Center action; `requestConfirmation(result:…)` deprecation warning in `ExpenseIntents.swift:580`.

## 2. Last Completed Checkpoint

0.9.8 (112) is the latest: `monocle-0.9.8-build-112-unsigned.ipa`, SHA-256 `b1896d3146dfa4de14ed2d1b36faa6ef7192fc8760e46b512fc94b73075f4217`, iCloud `Monocle-codex/`, published to `farchanrifai/monocle-releases` (tag `v0.9.8-build.112`). It adds the Remove Last Expense Shortcut, the Luna `register` fix (offline only when offline, real device label), "Sample card", and `Monocle/Resources/PrivacyInfo.xcprivacy` (iOS + Mac targets; no tracking, no collected data, UserDefaults `CA92.1`).

Unreleased on `main`: `get_budget_status` takes `cycle: current|previous` (`ToolExecutor.budgetStatus`; `testBudgetStatusForThePreviousCycle`). 260 iOS unit tests and 22 Mac unit tests pass; Mac UI tests not run.

**Next:** phone checks on 0.9.8 (Luna bridge with a real invite, streaming, composer clear, Shortcuts incl. Remove Last Expense, widget deep links). Stack cap versioning still needs owner approval (`BudgetVersion.stackID`, backup format 9). Left: `docs/privacy.md` contact line + hosting; chat width creep; Shortcuts payment-method parameter, Spotlight `IndexedEntity`, Control Center action.
