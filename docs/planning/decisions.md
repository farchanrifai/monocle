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
