# Book home exploration — 2026-09-09

User authorized exploration/rebuild with no real app data. This is a bounded native SwiftUI prototype, ahead of multi-book persistence. A local device-review IPA was subsequently delivered; see below.

Open Settings → Design exploration → Explore book home. Simulator launch argument: `-book-home-prototype`. Select Instrument, Ledger or Signal through Book options. Existing navigation remains available on normal launch.

Initial exploration compared Instrument (numbered dark modules), Ledger (paper/serif/ruled cards), and Signal (oversized heading/vivid cards). The subsequent Wallet interaction pass unified the compact header and card layout; current style differences are mainly canvas and amount typography. No final style was selected.

All share six sample books and 120 transactions, including an empty book and long title/history. Tap cards or use Book options to focus a hero and its transaction list. All book cards returns to the stack. Native scrolling browses cards. Manage stack controls visibility/order; Move to top is also available as a context-menu and accessibility action. Visible/all activity scope applies to the stack view. Add Expense chooses an explicit sample book and records only in this screen's memory.

Sample data and stack preferences reset when the screen is recreated. This is deliberate isolation, not completed multi-book persistence. Hero-image customization/backup is not implemented. Add Expense uses a small sample form because existing EntryView is coupled to the production single-book AppModel; connecting it here would write to the wrong store. No production Shortcut changes.

## Evidence

- Native iOS Simulator build passed with Xcode 26.5 SDK.
- Simulator service works outside the sandbox; prior unavailable-runtime conclusions do not apply to this execution context.
- Foundation assertion check passed: selected-book isolation, visible/all filtering, empty selection and date ordering. Run `swiftc -module-cache-path /tmp/monocle-prototype-module-cache Monocle/Features/PrototypeBookSamples.swift scripts/check-book-prototype.swift -o /tmp/check-book-prototype && /tmp/check-book-prototype`.
- XCTest UI check `testBookPrototypeFocusAndSampleEntry` passed on iPhone 17 Pro / iOS 26.5: open empty book, record a sample expense, confirm it appears, switch to Everyday, confirm absence.
- Simulator screenshot inspected for native card/menu layout. Dynamic Type uses semantic fonts/wrapping, the final stack scales card/strip dimensions with Dynamic Type, VoiceOver exposes native controls, and Reduce Motion disables focus animation. Full accessibility/three-direction visual review remains pending; these code provisions are not a usability certification.
- No signed-device evidence, migration validation or workspace recovery validation. IPA delivery is documented below.

## Next

Review the three directions in Simulator and choose/remix a direction. Then implement explicit production book scope and the workspace backup/recovery protocol from `docs/planning/book-scope-audit.md` before wiring this prototype to durable books. Add hero storage and portable images there. Bills remain after scope/persistence. Do not reset or amend 31b88e9.

## Wallet motion reference — 2026-09-09

User supplied an 18.81-second, 60 fps Wallet recording and requested its stack/overscroll/open-close behavior. Inspected 2 fps full-recording contact sheet plus 12 fps opening (7–8 s) and closing (10.5–11.5 s) sequences. Reference media remains outside the repository.

Replaced the tall-card VStack and screen replacement with overlapping 44-point exposed headers and a 224-point card (both Dynamic Type scaled). The last card is fully exposed. A native SwiftUI ScrollView supplies tracking, momentum and rubber-banding. During top overscroll, compensate 90% of the first-card travel and add 22% of the native overscroll per card gap; this matches the observed nearly stationary top card and increasingly spread lower cards. This is calibrated approximation, not access to Wallet's private animation parameters.

Opening/closing uses the same matched card geometry with a 0.48 response / 0.86 damping spring, other cards receding and a fading detail background. Keep the underlying stack scroll view mounted and disabled during detail so X returns to the original slot and scroll position. Detail has its own native scrolling/bounce. Reduce Motion removes animation and fanning. Book menu and close button remain alternatives to gestures. The full book name remains available in the menu and detail heading when its exposed card strip truncates.

Visual direction and stack management now live in Book options so the stack starts directly under the header. Existing sample-only data/write isolation remains. A native UI regression checks overlapping frames, tapping an exposed strip, opening the correct book, returning to the same Y position, and a downward drag; book-specific entry regression remains included. Exact velocity/overscroll equivalence and signed-device feel are not claimed.

## Device review artifact

User explicitly requested a review IPA on 2026-09-09. Version 0.1.4 (14) built successfully for arm64 and ZIP validation passed. Delivered `monocle-0.1.4-build-14-unsigned.ipa` to the Monocle-codex iCloud Drive folder, preserving prior artifacts. SHA-256: `d4cbafdc86e79c3684d0876e4dc67d0b893c819bb5e5e08978ef4ec067d9f737`. Local review only (`SKIP_SIDESTORE_PUBLISH=1`); signed-phone review pending. Open Settings → Design exploration → Explore book home after SideStore installation.
