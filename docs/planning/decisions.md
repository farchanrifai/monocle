# monocle — decision log

Updated: 2026-09-07

## Confirmed by the user

| Decision | Consequence |
| --- | --- |
| iPhone and Mac only | No Android/web requirement |
| Shared books later | Preserve book boundaries in the data design now |
| iCloud acceptable for future sync/sharing | Participants need iCloud for those features |
| Manual export acceptable initially | Full export/restore required; automatic backup deferred |
| Sync near public release | Local first version; later sync requires its own implementation and validation |
| Daily use once working UI/UX is good | Preserve real data after daily-use readiness; no disposable store resets |
| Keypad and natural text entry | One Add Expense screen with two modes selected by assistant at user's request |
| Budget rules accepted | Independent overall/category limits; no carry-forward; effective-dated changes |
| Per-bill automatic or pending mode | Reminder toggle independent; pending excluded from recorded spending |
| Face ID/device-passcode fallback | No app-specific PIN recovery flow; configurable timeout |
| Planning documents in docs/planning | Keep specification and implementation decisions together |

All other confirmed v1 requirements and design direction in the handoff remain in scope.

## Phone review refinements — 2026-09-07

The user installed prototype 0.1.0 through SideStore on iPhone 15 Pro and reported working functions and snappy navigation. Their review sets these refinements for 0.1.1:

- Home's list should remain visible beneath floating bottom controls; Settings should match the small native Budget toolbar control.
- Entry must adapt to available height and keep all four keypad rows above Record.
- Categories should consume little vertical space with more than eight items. Chosen design: a horizontal shortcut row plus a searchable native sheet, inspired by the progressive disclosure and soft edges the user likes in Messages.
- Intentional closing asks to discard unsaved input. Interruption recovery remains, with a clear way to discard a recovered draft and edit another transaction.
- Brief press/amount animations and selection/success haptics should support the existing responsiveness. Honour Reduce Motion.

These refine prototype interaction; they do not change the agreed storage or sync architecture.

## Technical direction recommended for these requirements

- Swift + SwiftUI, with focused UIKit adapters if needed.
- Core Data local storage, replacing the handoff's initial SwiftData candidate because shared books are now a concrete future requirement.
- CloudKit for later Apple-device sync and shared books. Keep cloud capabilities inactive in the first local build.
- Small boundaries between UI, expense/budget logic, and persistence; no app server or third-party architecture framework initially.
- Exact integer money representation with explicit currency/scale; no floating-point financial calculations.
- Versioned store and portable backup format from the first persistent build.

These are architecture choices, not claims of implemented or tested capabilities. Sources and model constraints are in architecture.md.

## Proposed defaults, open to prototype refinement

- Keypad opens first; text mode shares the draft.
- Editable keyword rules with explicit mapping; unknown category requires clarification.
- Budget starts on day 1 until configured; nonexistent start days clamp to month end.
- Book calendar uses Gregorian dates and an explicit reporting timezone, initially device timezone; transaction dates do not shift when travelling.
- Archive categories referenced by history.
- Pending bill confirmation offers the due date, editable before recording.
- Lock timeout choices immediately, 1 minute, 5 minutes; lock initially optional.
- Full backup restoration initially replaces, with a safety backup and confirmation; no merging yet.

## Resolve when the relevant feature is implemented

| Question | Required before |
| --- | --- |
| Exact bundle identifier, signing route, final signed capabilities | First phone installation |
| Budget start-day transition length and transition budget amount | Shipping cycle-date changes |
| Accepted text formats, keyword precedence, correction-to-rule behaviour | Shipping parser |
| Refund handling and imported negative/zero amounts | Shipping CSV import; reject unsupported values explicitly until decided |
| Bill recurrence frequencies, reminder timing, and edit/skip semantics | Shipping bills |
| In-app notification detail and lock default | Daily-use settings review |
| Shared-book roles, edit conflicts, leaving a share, deletion propagation, multi-device scheduled deduplication | Enabling sync/sharing |
| Distribution from personal signing to paid membership/TestFlight/App Store | Moving to that channel |
| Subscription offering, name availability, and public-release policies | Public launch planning |

None of these prevent the entry prototype. Do not mistake unresolved implementation details for previously confirmed product choices.

## Capture refinement — 2026-09-08

- User requested system number separators. Display and strict text parsing now use the current locale; currency remains IDR and storage stays exact integer minor units.
- User requested side-by-side bottom islands: Recents/Budgets/Bills in a glass capsule, separated from a dark glass + circle. This replaces the vertically stacked Add Expense button and tab bar.
- Category taps preserve strip position and animate selection. All categories uses a searchable grid with a consistent page background.
- Custom category editor brought forward: create, rename, curated icon selection and protected deletion. Referenced categories keep history; archive and keyword editing remain future work.
- User will continue with GPT-5.6 Terra. Detailed committed roadmap and local two-section HANDOFF are the continuation contract; no new task/model change was requested.

## Backup milestone — 2026-09-08

Implemented format-1 portable JSON `.monoclebackup` files for the current sample book. Restore replaces rather than merges, requires an in-app review/confirmation and writes a local safety backup first. A rollback journal spans SQLite and draft/settings so restart recovers the original state until activation completes. Initial limits are 10 MB, 10,000 expenses and 500 categories. Files are unencrypted. See backup-format.md for validation, interruption semantics and phone checks still pending.
