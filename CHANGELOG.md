# Changelog

All notable changes to Monocle are documented in this file.

## [0.6.11] - 2026-09-11
### Refined & Perfected
- **Apple Wallet Coordinate-Anchored Persistent Card Plane**: Adopted the exact architecture from the reference Apple Wallet repository (`farchanrifai/wallet`). Built a single persistent artwork view per card whose spatial destination is driven by coordinate anchors (`CardFrames` preference key), eliminating matched-geometry artifacts, coordinate mismatch, and mid-transition view resets.
- **Custom `WalletStackLayout` & Physical Kinematics**: Implemented custom `Layout` engine providing accordion fanning, progressive step expansion (`displacement * 0.28`), and scroll overscroll elasticity.
- **Authentic Apple Wallet Springs**: Opening spring tuned to `.spring(response: 0.48, dampingFraction: 0.66)`, settle spring to `.spring(response: 0.47, dampingFraction: 0.74)`, and release spring to an interpolating spring with natural angular frequency (`frequency = 2 * .pi / 0.47`) carrying finger release velocity directly back to the resting slot.
- **Interactive Pull-to-Dismiss Gesture**: Implemented `CardDismissPan` (`UIGestureRecognizerRepresentable`) coordinating vertical drag with 1:1 finger tracking (`dismissAmount`), threshold evaluation (`> 96pt` or velocity forward projection), and release momentum returning seamlessly into the deck slot.
- **Modular View Modifiers**: Extracted `CardSpringModifier`, `CardAccessibilityModifier`, and `CardGesturesModifier` for instant compilation, clean gesture separation, and zero type-checker overhead.

## [0.6.10] - 2026-09-11
### Refined & Perfected
- **Critically Damped Deck Shuffling (Zero Overshoot)**: Retuned lower cards' return spring behind the hero card to a critically damped curve (`dampingFraction: 0.98`), mathematically preventing any overshoot past the active card. Lower cards are recessed by 3.0pt below the hero card's top edge, guaranteeing they never peek above the active card during transitions.
- **Natural Symmetrical Hero Card Pop**: Selected card pop now scales organically from `.center` (`scale = 1.035`) with authentic elevation depth and soft lighting shadow, while keeping its top edge strictly top-aligned with the resting deck.
- **Zero List Jumping & Instant Clean Transition**: Removed implicit animation on the activity section so home transactions disappear instantly (0ms) upon card tap rather than lingering or bouncing with container frame oscillations. The transaction list smoothly fades and glides in only once all cards have settled.
- **Transition View Hierarchy Isolation**: Attached `.id(selectedID)` to the activity container to ensure clean, instant view replacement without ghost text cross-fading.

## [0.6.9] - 2026-09-11
### Refined & Perfected
- **Consistent Opened Card Placement**: Fixed ScrollView anchoring and eliminated content offset jitter across all cards. Every card (Card 01, 02, 03) now opens to the exact same top-aligned pixel coordinate matching the home deck's resting position.
- **Symmetrical Reverse Close Animation**: Dismissing a card now strictly and cleanly mirrors the opening sequence. Lower cards slide down behind the active card, hand z-index back below the bottom edge, and smoothly slide up in front into their resting fanned slots while the active card glides down and un-scales to 1.0.
- **Transition Scroll Locking**: Scroll interactions are securely locked during the 380ms transition window, preventing touch gestures from disrupting the physical kinematics.

## [0.6.8] - 2026-09-11
### Refined & Perfected
- **Full-Height Deck Shuffle Clearance**: Lower cards now slide down past the selected card in full height (`cardHeight + 20pt`) in front of the active card before surfacing it, creating an authentic physical deck cut with zero mid-flight popping.
- **Top-Aligned Hero Placement**: The selected card in the transaction view now top-aligns directly with `targetY = 0`, matching the resting deck's top edge exactly so the card feels like it slides right to the top of the deck.
- **Deferred Transaction Appearance**: Hidden the transaction list during card shuffling, gracefully fading it in only once the deck transition has settled, keeping the entire screen dedicated to fluid physical motion.
- **Symmetric Reversible Reassembly**: On dismiss, lower cards slide down from behind the active card to clear it, restore front z-order, and smoothly glide up into resting fanned slots.

## [0.6.7] - 2026-09-11
### Refined & Perfected
- **In-Place Deck Shuffle & Hero Zoom**: Replaced offscreen card ejection with an authentic in-place deck cut & shuffle. When opened, the selected card glides to the top-most position (`targetY = 10`) and zooms in (`scale = 1.04`), matching Apple Wallet's larger hero card layout in the transaction view.
- **Two-Phase Lower Card Cut & Gather**: Cards below the selected card dip down momentarily (`+45pt`) to open the deck, then smoothly slide back up into the stack directly behind the enlarged hero card.
- **Zero-Peek Hero Coverage**: Because the active card is larger (`scale = 1.04`) and elevated at `zIndex = 100`, it naturally covers the squared cards behind it with zero visible edge peek.
- **Fluid Reassembly**: Dismissing the card view smoothly un-squares the deck, zooms the active card back to standard size (`scale = 1.0`), and restores all cards into their resting fanned slots.

## [0.6.5] - 2026-09-11
### Refined & Perfected
- **Physical Card Stacking**: Opening any card now physically stacks the opened card directly on top of the cards above it (`targetY = 10`), covering them completely with authentic mechanical motion (no fade animation).
- **Lower Cards Ejection**: Cards below the selected card are thrown out of the screen towards the bottom (`targetY = 1200`) at full opacity (`opacity = 1.0`), and slide smoothly back up when dismissed.
- **Isolated 3D Card Flip**: Once fully covered, upper cards are hidden behind the active card so 3D rotation reveals clean empty space without background cards peeking through.
- **Seamless Reassembly on Dismiss**: When returning to the home page, covered cards are restored right before the closing spring begins, allowing all cards to un-stack and slide back down into their resting positions.

## [0.6.4] - 2026-09-11
### Refined & Perfected
- **Single-Card Transaction Page**: Opening any card now displays strictly that 1 opened card at the top, parting all other cards out of view. Cards above smoothly part upward and fade out; cards below smoothly part downward and fade out.
- **Consistent Top Clearance & Spacing**: Unified `focusedDeckHeight` across all cards, guaranteeing an identical top hero position and an exact 16pt gap to the transaction list regardless of card index.
- **Buttery Smooth Parting & Reassembly**: Tuned spring parameters to `.interactiveSpring(response: 0.48, dampingFraction: 0.88)` for crisp, natural opening and closing transitions without frame drops or jitter.
- **Frame-by-Frame Simulator Verified**: Recorded the transition on iPhone 17 Pro simulator and verified frame-by-frame that only 1 card is displayed during transaction review and that the deck seamlessly reassembles upon dismiss.

## [0.6.3] - 2026-09-11
### Refined & Redesigned
- **In-Line Scrollable Transaction List**: Replaced the detached modal sheet with an in-line scrollable transaction section styled identically to the home screen directly inside the main scroll view. Begins precisely 16pt beneath the active card with zero dead space or sheet disconnect.
- **Tactile Wallet Pocket Fanning & Stacking**: Upper cards above the selected card compress into a true physical wallet-pocket fan at `CGFloat(index) * 12pt` with depth perspective scaling (`0.98`, `0.96`...). Headers peek out neatly and remain fully interactive to switch active cards.
- **Offscreen Push with Smooth Fade**: Cards below the selected card glide smoothly offscreen past the viewport with a soft fade-out.
- **Zero Tap Flash**: Introduced `CardDeckButtonStyle` to eliminate the iOS touch-down white highlight overlay when tapping cards.
- **Unified Clean Modal Architecture**: Opening Trends & Analytics or the Artwork Customizer from the card's telemetry back face now presents cleanly as top-level sheets without competing modal presentations.
- **Seamless Dismiss Motion**: Tapping the top navigation bar `xmark` button smoothly collapses the entire deck back to its resting stacked slots.

## [0.6.2] - 2026-09-11
### Refined & Rebuilt
- **Apple Wallet Card Transition Physics**: Completely re-engineered card opening and closing animations adopting authentic Apple Wallet kinematics inspired by Kavsoft's SwiftUI 2026 reference architecture.
- **Viewport-Aware Geometry & Offscreen Push**: Powered by `.visualEffect`, selected cards smoothly glide to the top of the viewport with comfortable top breathing clearance (`14pt`), background cards above tuck behind at `0.95` scale, and lower cards smoothly slide down off the bottom of the screen.
- **Weighted `.interactiveSpring` Motion**: Tuned spring physics to `.interactiveSpring(response: 0.55, dampingFraction: 0.90)` for buttery smooth, natural gliding motion with zero jitter, stutter, or artificial bouncing.
- **Interactive Below-Card Presentation**: Adjusted bottom transactions sheet detents dynamically based on card geometry, allowing full touch interaction with the card at the top (3D drag tilt, flip to telemetry, quick actions) while transactions remain visible below.
- **One-Tap Close Transition**: Seamless dismissal via the top navigation bar `xmark` button or sheet dismiss, reversing the entire deck smoothly back into its resting stack slots.

## [0.6.1] - 2026-09-11
### Refined & Fixed
- **Direct In-Card Analytics & Artwork Presentation**: Tapping "Trends & Analytics" or "Artwork" on the flipped card now presents sheets directly on top of the active card without closing the card or kicking the user back to the home page. Dismissing either sheet returns directly to the flipped card.
- **Isolated Card Flip (Hidden Background Cards)**: All background stacked cards now smoothly cross-fade to 0 opacity when any card is opened, completely preventing background cards from showing or peeking through during 3D card flips.
- **Fluid 120 FPS Card Transitions**: Eliminated frame-querying layout feedback loops and offscreen compositing bottlenecks, replacing dynamic frame queries with deterministic stack slot math for buttery smooth opening and closing animations.
- **Header Bar Breathing Room**: Added `.scrollClipDisabled()` and increased resting top margin to 14pt, ensuring the card never collides with or tucks behind the header bar or `xmark` button during perspective tilt.

## [0.6.0] - 2026-09-11
### Added
- **Interactive 3D Card Flip**: Realistic 3D card rotation revealing a technical telemetry back-face with a single tap on the card's flip button or background tap-to-flip.
- **Teenage Engineering Telemetry Back-Face**: Industrial monospace card reverse view featuring technical serial stamp (`MONO-01 // #...`), real-time budget cycle & pace status indicator, daily burn average vs daily budget target, remaining cycle allowance, and next commitment banner for upcoming bills.
- **Back-Face Quick Actions**: Direct shortcuts to "Trends & Analytics" and "Artwork" card customization straight from the back of any focused card.
- **Specular Sheen & Perspective Drag Tilt**: Dynamic 3D tilt response ($\pm 12^\circ$) tracking continuous drag gestures with a moving white specular reflection sheen that shifts across the card surface during touch manipulation and scroll pull.
- **Swipe-to-Shuffle Card Promotion**: Horizontal drag-to-promote gesture on background cards in the deck, allowing quick slide-out and promotion of stacked cards to the front with tactile haptics.
- **Accessible Card Deck Controls**: Full accessibility support with custom "Flip card" accessibility actions, dedicated front and back buttons, and context menu shortcuts.

## [0.5.0] - 2026-09-11
### Added
- **Visual Analytics & Spending Trends**: Pure native SwiftUI + Swift Charts spending analytics suite accessible from the Book Home options menu and Budgets screen.
- **Cumulative Trajectory Curve**: Burn-up cumulative area and line chart tracking daily spend progression against linear monthly budget pacing, complete with interactive `.chartXSelection` date scrubbing and precise point callouts.
- **Daily Spending Rhythm**: High-density daily expense bar chart highlighting peak spending days alongside period average reference rule lines.
- **Month-over-Month Velocity Comparison**: Day-by-day velocity curves comparing current month spending velocity against the prior month's trajectory on an aligned calendar timeline.
- **Category Donut Breakdown**: Interactive SectorMark donut chart with center totals, dynamic slice expansion, category proportion percentages, and ranked expenditure cards with progress indicators.
- **Cross-Book Distribution**: Consolidated portfolio breakdown utilizing book card palette color coding when analyzing "All books" scope.
- **Flexible Time Horizons & Multi-Book Scoping**: Seamless horizon toggling across This Cycle, This Month, Last Month, Last 30 Days, Last 90 Days, and Year-to-Date, with instant switching between Current Book and All Books.
- **Spending Pace KPIs**: Real-time spending pace status (Under Budget, On Pace, Ahead of Pace, Over Budget) with daily average metrics and projected period end calculations.

## [0.4.0] - 2026-09-11
### Added
- **RFC 4180 CSV Export & Import Engine**: Robust RFC 4180-compliant CSV engine supporting quoted fields, escaped quotes, multiline notes, and CRLF line endings without proprietary dependencies.
- **Smart Delimiter Sniffing**: Automatic detection of comma (`,`), semicolon (`;`), and tab (`\t`) separators across varied spreadsheet exports and bank statements.
- **Flexible Multi-Format Parsing**: Intelligent date parsing (ISO8601, YYYY-MM-DD, DD/MM/YYYY, DD-MM-YYYY) and localized currency parsing (`Rp`, `IDR`, `k` thousands multipliers, negative debit parenthesis, and European/US decimal conventions).
- **Intelligent Column Mapping**: Automatic column header recognition for Date, Amount, Note/Description, and Category with customizable fallback pickers.
- **Duplicate Detection & Interactive Review**: Real-time matching against existing book expenses, duplicate badges, automatic skip toggles, and individual row inclusion checkmarks.
- **Granular Export Filters**: Export current book or consolidated all-books data across date ranges (All Time, This Month, Last Month, Custom) with spreadsheet-ready whole IDR amounts and native FileExporter / ShareLink sharing.
- **Zero-Overwrite Safety**: Guaranteed additive batch import preserving all preexisting user data.

## [0.3.1] - 2026-09-11
### Added
- **Kinetic Spring Card Stack Transitions**: Unified single continuous spring shuffle when switching card stacks (swift 100ms kinetic gather into immediate spring fan-down), completely eliminating middle pauses or frozen stutter.
- **Vertical Activity Synchronization**: Dynamically synchronized vertical position of Recent Activities across stack size changes using spring-interpolated card metrics, preventing abrupt layout jumps.
- **Bring to Front Context Menu**: Added quick card promotion from the main home card deck via long-press "Bring to Front" context menu action with tactile haptic feedback.
- **Stack Customizer Quick Promotion**: Added dedicated "Move to Top" button (`arrow.up.to.line`) and context menu actions in the Stack Customizer for instant card reordering.
- **Automated SideStore Release Notes**: Automatic version-specific changelog extraction from `CHANGELOG.md` for SideStore release descriptions and repository manifests.

## [0.3.0] - 2026-09-10
### Added
- **Recurring Commitments & Bills**: Persisted recurring bill rules with monthly, weekly, and yearly recurrence intervals.
- **Reconciliation Engine**: Automatic catch-up reconciliation upon app launch and foreground transitions.
- **Action Required Queue**: Due bills appear in an actionable queue with quick "Record" (saves expense to current book) and "Skip" actions.
- **Scheduled Bills & History**: Full management of upcoming commitments (next 30 days) and expandable payment history.
- **Due Date Reminders**: Local notification scheduling via UNUserNotificationCenter with customizable lead times (on due date, 1, 2, 3, or 7 days before).
- **Core Data Model V3**: Migration adding `BillRuleRecord` and `BillOccurrenceRecord` entities with multi-book isolation and zero data loss.
- **Workspace Backup Format 6**: Portable backup export/restore supporting recurring bills alongside expenses, budgets, and custom card artwork.

## [0.2.5] - 2026-09-10
### Added
- **Card Customizer Snapping**: iOS Home Screen widget picker-style horizontal carousel snapping with native `.scrollTargetBehavior(.viewAligned)`.
- **Depth & Scale Transitions**: Centered active card remains at 100% scale and full opacity; adjacent cards smoothly scale down to 92% and subtly dim to 65% opacity.
- **Tactile Haptic Feedback**: Crisp tactile feedback tick upon locking onto a card.
- **Edge Peeking**: Adjacent cards peek cleanly into the screen edge to invite horizontal swiping.

## [0.2.4] - 2026-09-10
### Added
- **Deck Transition Animation**: Optimized stack-up, gather, and fan-out physics when switching between custom card stacks.
- **Cross-Dissolve Morphing**: Smooth cross-dissolve when front-most card differs across stacks to eliminate visual popping.
- **Bottom Navigation**: Two-bubble floating glass navigation bar with activity filter bubble and quick add action.

## [0.2.3] - 2026-09-10
### Added
- **Card Stack Management**: Customizable card stacks (e.g. Daily, Travel, Bills, Family) with custom names and icons.
- **Stack Filtering**: Quick switching of active card deck via bottom filter button.
