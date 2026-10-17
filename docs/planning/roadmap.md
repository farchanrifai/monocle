# monocle — roadmap

Updated: 2026-10-17 (0.9.7). Product requirements are in `product-spec.md`, data decisions in `architecture.md`, chat in `CHAT_SPEC.md`. The root `HANDOFF.md` has the live checkpoint; `CHANGELOG.md` has what shipped in each build.

## Product goal

Make recording and understanding personal spending pleasant enough to use every day: spend-only (no balances, income or accounts), local first, on iPhone and Mac. Wording follows the glossary: Card, Stack, Expense, Add, Budget (Monthly / Total until), Paid with.

## Where things stand

| Area | Status |
| --- | --- |
| Cards and Stacks (model B, backup format 8) | Shipped 0.8.0; multi-card home, stack budgets (sum of cards or a monthly cap) |
| Budgets and Bills | Shipped; Monthly and Total-until budgets, recurring bills with occurrences and reminders |
| Currency | Shipped; reporting currency per workspace, card and spending currency, ECB rates with manual override |
| Backup, CSV, reset | Shipped; formats 1–8 import, safety backup before restore/reset |
| Shortcuts and Siri | Add Expense, record text, Quick entry, How Much Did I Spend, Budget Left, Ask Monocle, Remove Last Expense, spending sessions (iOS) |
| AI chat | Shipped; Claude (own key or Luna invite) or Apple on-device, streaming replies, `@`/`#` scope, charts, proposals confirmed in-app |
| Luna bridge | 0.9.7; opt-in snapshot push and `monocle://chat?q=` |
| Mac app | Shipped alongside iOS; Quick Chat panel, Analytics |

## Open work

- **Phone checks:** Luna bridge with a real invite, chat streaming and composer clearing (0.9.3–0.9.5), Shortcuts, widget deep links, 0.8.x screens.
- **Stack cap versioning:** caps are current-only; needs `BudgetVersion.stackID` and backup format 9 with golden fixtures. Needs owner approval.
- **Chat:** budget tool covers the current cycle only; width creep on the first streamed line; Apple on-device probe at 9/11.
- **Shortcuts:** Add Expense takes whole rupiah only (changing the `Int` parameter can break saved shortcuts); no payment-method parameter; no Spotlight `IndexedEntity`; Control Center button only opens the app.
- **Localization:** the app has none; Indonesian would be a whole-app String Catalog project.
- **Release:** `PrivacyInfo.xcprivacy` missing; `docs/privacy.md` needs a contact line and hosting.

## Deferred

iCloud sync and shared cards: needs roles, ownership, conflict resolution and multi-device bill deduplication designed first. App Store distribution and pricing are separate decisions.

## Working conventions

Swift 6 / SwiftUI / Core Data. `AppModel` is presentation; every write goes through `ExpenseService`; managed objects stay in the repository. Golden fixtures must round-trip byte for byte. Record what passed and what still needs the owner's phone; a prototype is not evidence.
