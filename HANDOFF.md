## 1. Immediate Next Step

Branch `release/app-store` (from `main` @ `ba4f078`) prepares the App Store release; `main` stays the SideStore line. Plan, decisions and Free/Pro split: `docs/planning/app-store-release.md`. Never publish this branch to the SideStore feed.

**Next (no paid account needed):** phase 1 strip Luna + Claude; phase 1b worldwide currency fixes; phase 2 StoreKit 2 with a local `.storekit` file, paywall, gates in `ExpenseService`; phase 2b onboarding, Settings → Subscription/About; phase 3 compliance bits; phase 4 privacy policy rewrite. Open: prices, EU trader status. Owner: enroll (Individual), Paid Apps Agreement, Small Business Program.

## 2. Last Completed Checkpoint

0.9.9 (113) is the latest: `monocle-0.9.9-build-113-unsigned.ipa`, SHA-256 `e59c6d0533cac6a6fbdabb0fe0c74e45dcc3d33c3e0275ac53c2e5895c09a067`, iCloud `Monocle-codex/`, tag `v0.9.9-build.113`. Adds `get_budget_status` `cycle: current|previous` (ask about last cycle in chat). `main` is pushed.

**Next:** phone checks on 0.9.9: last-cycle budget question in chat, Luna bridge with a real invite, streaming, composer clear, Shortcuts incl. Remove Last Expense, widget deep links. Stack cap versioning still needs owner approval (`BudgetVersion.stackID`, backup format 9). Left: `docs/privacy.md` contact line + hosting; chat width creep; Shortcuts payment-method parameter, Spotlight `IndexedEntity`, Control Center action; `requestConfirmation(result:…)` deprecation warning in `ExpenseIntents.swift:580`.
