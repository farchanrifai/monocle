# monocle — planning overview

Updated: 2026-09-08

## Purpose

Make recording everyday purchases fast enough to become a habit. Help the user understand spending and stay within budgets. Cash-flow projections come later.

Initially a personal app. A public subscription release is a possible later stage. The user has no coding experience; explain trade-offs plainly and handle technical implementation.

## Foundation

| Area | Direction |
| --- | --- |
| Platforms | iOS 26+ first; native macOS later; Apple only |
| Interface | SwiftUI, using UIKit for specific needs |
| Storage | Local Core Data; explicit saves and versioned migrations |
| Future sync and sharing | CloudKit/iCloud; user accepts the iCloud requirement |
| Initial accounts and network | No monocle account or app backend required for local use |
| Recovery | Manual full backup/export and tested restoration |
| Entry | One Add Expense screen, keypad and text modes, one shared draft |
| App lock | Optional Face ID with device-passcode fallback and configurable timeout |
| Visual identity | Black, off-white, deliberate red accents; precise typography and native interaction |

Storage and UI choices are implementation recommendations for the agreed requirements. Real-device validation remains necessary; the planning direction does not imply working sync, signing, or Shortcuts.

## Read next

- [Milestones and Terra continuation roadmap](roadmap.md): status, completion gates and exact next-session sequence.
- [Product specification](product-spec.md): behaviour and v1 scope.
- [Decision log](decisions.md): confirmed choices, proposed defaults, and deferred questions.
- [Architecture](architecture.md): data boundaries, future sharing, and recovery.
- [Implementation plan](implementation-plan.md): prototype, device validation, and daily-use readiness.
- [Original handoff](original-handoff.md): preserved starting context; later decisions in these documents take precedence.

## Current evidence

- Project folder was empty before planning; a local Git repository and native app now exist.
- Local Xcode reports version 26.6, build 17F113.
- Test phone from the handoff: iPhone 15 Pro. The user reports a successful original SideStore installation and snappy navigation. Updated-build preservation, signed Shortcuts and refresh still require phone validation.
- The user wants to start daily use once UI/UX and reliable recording work, ideally after a few Codex sessions. This is an aspiration, not a delivery guarantee.

## Next deliverable

The native interaction prototype now exists: Recents → Add Expense → Record, both entry modes, budget-cycle preview, and bill settings. See [prototype status and review](../prototype/README.md). Next: evaluate the signed build on the actual iPhone and finish recovery before daily use.
