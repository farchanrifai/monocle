# Changelog

All notable changes to Monocle are documented in this file.

## [0.7.9] - 2026-09-13
### Compact Liquid Glass Expense Sheet
- **Tactile Compact Liquid Glass Input Mode**:
  - Added a third expense entry mode alongside numeric keypad and natural language text.
  - Implemented 100% native custom liquid glass compact sheet that springs smoothly from the Add Expense capsule button with interactive drag-to-dismiss gesture and darkened frosted backdrop.
  - **Two-Column Ergonomic Layout**:
    - **Left Column**: Card selector pill with active card palette badge, Date selector pill (Today, Yesterday, Custom graphical picker), Amount Hero display box with dynamic monospaced formatting, and Category dropdown menu with glyph icons and live selection indicators.
    - **Right Column**: Tactile 3×4 mini numeric keypad (`1-9`, `000`, `0`, `⌫`) styled with specular rim highlights, subtle shadow depths, and light sensory haptics.
    - **Bottom Action**: High-prominence glowing liquid glass Record Expense capsule button with adaptive active/disabled states.
    - **Expand Action**: Top-left header button to expand into full Keypad mode with note and split capabilities without state loss.
  - **Settings Integration**: Added `Compact` option to `Default input method` segmented picker in Settings.
- **Automated Test Coverage**:
  - Added unit test coverage in `MultiBookTests.swift` (`testCompactEntryDraftExpenseCreation`).
  - Added UI automation test `testCompactEntrySheetKeypadAndRecord` in `MonocleUITests.swift` verifying Settings configuration, sheet presentation, mini keypad typing, backspace, and expense recording.
  - All 93 unit tests and UI automation passing.

## [0.7.8] - 2026-09-12
### Native Progressive Blur Toolbar Matching Home
- **Eliminated UIKit NavigationBar Hard Stop**:
  - Replaced internal `NavigationStack` in `AnalyticsView` with a native `ZStack` layout, custom topBar, and progressive blur header background identical to `BookHomeView`.
  - Removed UIKit's `_UIBarBackground` and fixed 44pt hard-stop cutoff, allowing scrolling charts and content to feather continuously and smoothly under the title and status bar.
  - Provided custom centered header with theme-aware `ink` typography and dismiss button when presented modally.
- **Test Suite Consistency**:
  - Verified 92 unit tests in `MonocleTests` and all UI tests in `MonocleUITests`.

## [0.7.7] - 2026-09-12
### Progressive Blur Toolbar & Bottom Navigation Clearance
- **Progressive Blur Toolbar Background**:
  - Implemented the same smoothstep progressive blur overlay (`.ultraThinMaterial` + theme-aware paper tint) on the Analytics navigation bar.
  - Hidden native toolbar background so the "Analytics & Trends" title and actions float over the progressive blur, allowing scrolling charts to smoothly glide and feather out under the status bar.
- **Bottom Navigation Clearance**:
  - Added 96pt bottom padding to the Analytics scroll view so the lowest card is never obscured by the floating bottom navigation bar.

## [0.7.6] - 2026-09-12
### Cumulative Trajectory Decoupling & Stacks-First Analytics Scope
- **Cumulative Trajectory Decoupling**:
  - Decoupled `Actual Spend` and `Budget Pace` into two strictly independent Swift Charts series with explicit series keys (`"Actual Spend"` vs `"Budget Pace"`).
  - Eliminated the saw-tooth zigzag caused by alternating line marks, rendering a smooth monotonic burn-up curve ending at today and a clean dashed guide across the entire 30-day billing cycle.
- **Stacks & Cards Scope Redesign**:
  - Replaced the rigid binary `[ Current card | All cards ]` segmented control with an interactive **Scope Menu Pill** (`[ 􀏅 Everyday · Stack ▾ ]`).
  - **Home Flow Continuity**: Automatically initializes and synchronizes scope with whichever context was active on Home (Active Stack, All Cards, or selected Card).
  - **Categorized Drilldown**: Provides 1-tap switching between Stacks (with icons and live checkmarks), Individual Cards, and All Active Cards.
  - **Stack-Scoped Cross-Card Breakdown**: Dynamic "Spending by Card" chart adapts to display spending distribution among cards in the selected stack, or across all active cards.
- **Domain & Tests**:
  - Added `AnalyticsFilterScope` in `AnalyticsEngine.swift` supporting stack, card, and global overview scopes.
  - Added unit test coverage in `AnalyticsTests.swift` and updated UI test suite in `MonocleUITests.swift` (92 unit tests passing).

## [0.7.5] - 2026-09-12
### Analytics Audit & Presentation Enhancements
- **Calculation & Data Structure Reliability**:
  - **Full Cycle Budget Pace Continuity**: Extended budget pace trajectory across the full 30 days of the billing cycle or month, displaying the linear target pace into the future while halting actual spend at the current day (`isFuture: Bool`, optional `cumulativeAmount: Int64?`).
  - **Unallocated & Archived Category Reconciliation**: Reconciled transactions without categories into an "Uncategorized" bucket and deleted/archived categories into "Other", ensuring 100% mathematical integrity across cards and category breakdowns.
  - **Fast Month-over-Month Comparison**: Optimized comparison algorithm with instant day-prefix matching and flatline handling for shorter prior months (e.g. February).
  - **Pace Phrasing Clarity**: Clarified budget pacing copy to explicitly state `"X% above budget pace"` or `"X% under budget pace"`.
- **Enhanced Charts & 120Hz Scrubbing**:
  - **Day 1 PointMark Anchors**: Added single-point indicators to Trajectory and Month-over-Month charts ensuring immediate visual feedback on the first day of a cycle before line interpolation begins.
  - **Interactive Daily Rhythm Scrubbing**: Added `.chartXSelection` scrubber with synchronized peak day indicators and live daily IDR spend callouts.
  - **Donut Chart Slice Selection**: Implemented native `.chartAngleSelection` allowing direct touch selection of category slices.
  - **Category Budget Allowance Markers**: Displayed subtle guideline indicators for categories with configured budget caps.
  - **Card Ranking Visual Hierarchy**: Inverted cross-card breakdown Y-axis so the highest spending card appears at the top.
  - **ProMotion 120Hz Gesture Throttle**: Throttled scrub state emissions with microsecond timestamp checks for 120 FPS fluidity.
- **Harness & Widget Store Resilience**:
  - Added cache directory fallback to `WidgetSnapshotStore` when App Group container permissions are unavailable in simulator test harnesses.

## [0.7.4] - 2026-09-12
### User-Facing Terminology Standardization
- **Unified Card Experience**:
  - Standardized user-facing copy from "Book" to "Card" across Settings (Active Card section, Card name, Start your real card), Card Customizer, and Book Home options ("New Card").
  - Updated Backup & Restore ("Replace current card", "Includes your cards, categories...") and CSV Interchange ("Destination Card", "Target Card & Category") while preserving existing underlying Core Data schema.
  - Aligned Analytics breakdown with "Spending by Card", "Current card", and "All cards" filters.
- **Consistent Navigation & Eyebrows**:
  - Standardized bottom navigation tab bar item from "Analysis" to "Analytics" to match section headers and reporting contexts.
  - Standardized recurring bills header eyebrow from "Recurring commitments" to "Recurring bills" in `BillsView`.
- **Test Suite Alignment**:
  - Updated XCUI automation flows and unit tests to match standardized Card and Analytics naming.

## [0.7.3] - 2026-09-12
### Apple HIG-Compliant Settings Organization
- **Structured Hierarchy & Icon Badges**:
  - Reorganized Settings into 6 clear sections: Active Book, Data & Storage, Expense Input, Appearance, Security, and About.
  - Added native iOS Settings-style icon badges (`SettingsIcon`) featuring SF Symbols on vibrant gradient rounded tiles.
  - Consolidated book identification and rename/onboarding into an interactive row with trailing state details.
  - Displayed live badges and status details (active category counts, app lock timeout state, book name, and version).
- **Streamlined Preferences & Accessibility**:
  - Maintained direct 1-tap in-line controls for high-frequency settings (Auto Switch, Light/Dark appearance, Theme style, and Input mode).
  - Positioned Data & Storage directly beneath Active Book for immediate visibility and rapid access.

## [0.7.2] - 2026-09-12
### Settings-Configured Expense Input & Consistent Record Button
- **Separated Expense Input Mode**:
  - Moved entry mode selection (Keypad vs. Natural Language Text) into Settings under a dedicated "Expense Input" section.
  - Removed the segmented picker header in `EntryView` to recover vertical layout space and streamline fast logging.
  - Preserved automatic keyboard focusing on the natural language field when Text mode is chosen.
  - Persisted `preferredEntryMode` in `WorkspacePreferences` across app restarts and workspace backups.
- **Unified Record Button Styling**:
  - Aligned `RecordButton` in `EntryView` with the card transaction detail's Add Expense button.
  - Employs a 56pt Liquid Glass Capsule (`.glassEffect(.regular.tint(MC.red.opacity(0.85)).interactive(), in: .capsule)`), centered icon and title label, and dark-mode glass styling.

## [0.7.1] - 2026-09-12
### Differentiated Widget Navigation & Stacks Widget
- **New Stacks Widget (`StackWidget`)**:
  - Home and Lock Screen widget showcasing active stack identity, member card count, and total stack spend.
  - Tapping the Stacks widget deep links into Monocle with that stack selected in the Home deck (`monocle://stack?id=...`).
- **Contextual Tap Actions Across Widget Suite**:
  - **`+` Capture Widgets** (`QuickCaptureWidget`): Category shortcuts pre-select the category in the entry sheet (`monocle://entry?category=...`), and `+ Add` directly opens expense logging.
  - **Card Stats Widgets** (`BudgetWidget`): Tapping directly opens the card's transaction list in the Home deck (`monocle://card?id=...`).
  - **Today Stats Widgets** (`TodaySpendingWidget`): Opens Monocle Home without triggering the Add modal (`monocle://home`), with individual recent items deep linking to their parent card.
  - **Live Activity** (`SpendingActivityWidget`): Background tap navigates to active session/home, while the `+ Add expense` pill opens quick entry.
- **Deep Link Routing**:
  - Added URL routes for `monocle://card`, `monocle://stack`, `monocle://home`, and category-aware `monocle://entry`.

## [0.7.0] - 2026-09-12
### Interactive WidgetKit Suite & Live Activities
- **Home & Lock Screen Widgets**:
  - `BudgetWidget`: `.systemSmall` and `.systemMedium` cycle budget health, remaining IDR, daily allowance pace, and `.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline` Lock Screen gauges.
  - `TodaySpendingWidget`: track today's spending, transaction count, and recent purchases directly from Home and Lock Screen.
  - `QuickCaptureWidget`: interactive widget with direct category shortcuts for one-tap expense logging.
- **ActivityKit & Dynamic Island Live Activity**:
  - `SpendingActivityWidget`: real-time Active Spending Session with Dynamic Island (compact leading/trailing, minimal, expanded layout with budget progress bar) and Lock Screen live banner.
  - In-app Session Management: Start/End sessions from Home Options menu (`⋯` -> Tools & Insights -> Start Spending Session) or via URL scheme (`monocle://session`).
  - Real-time session telemetry: logging expenses while a session is active automatically increments session totals in Dynamic Island and Lock Screen.
- **Architecture & Packaging**:
  - Lightweight, atomic `WidgetSnapshot` in shared App Group container (`group.com.farchan.monocle`).
  - Embedded `MonocleWidgets.appex` extension cleanly packaged for SideStore sideloading.

## [0.6.22] - 2026-09-12
### Native Liquid Glass tab selector
- Replace the custom Home and Analysis selector with the native iOS tab bar, including hold-and-drag selection.
- Align the Filter, tab switcher, and Add controls on the same visual centerline.

## [0.6.21] - 2026-09-12
### Three-island bottom navigation
- Add separate Liquid Glass Filter and Add bubbles around a two-button Home and Analysis island.
- Promote Analytics & Trends to a persistent root tab and remove its duplicate Options-menu entry while preserving direct sheet access from card telemetry and Budgets.
- Preserve the centered Add Expense card-detail morph, Reduce Motion behavior, selection feedback, and accessible selected-tab state.

## [0.6.20] - 2026-09-12
### Shorter header gradient
- Shorten the header fade by 25%, from 88 pt to 66 pt, so the blur ends 22 pt higher and covers less content.
- Preserve the smooth fade, tint strength, scroll response, and toolbar layout.

## [0.6.19] - 2026-09-12
### Softer header transition
- Reduce the header paper tint and extend its feathering for a gentler transition into translucent content.
- Use one smooth fade for the native material and tint, removing the abrupt shoulder beneath the toolbar.
- Ease header visibility over a longer scroll distance while keeping scrolling directly responsive to the finger.
- Preserve toolbar layout, controls, and card spring physics.

## [0.6.18] - 2026-09-12
### Reliability and performance audit
- Commit CSV batches and bill expense/occurrence updates atomically; prevent repeated confirmation and cross-book occurrence deletion.
- Promote pending automatic bills when due, refresh edited reminders, and serialize notification cancellation/replacement.
- Restore all book drafts, preserve multi-book recovery snapshots, and keep backup previews free of artwork writes.
- Validate backup artwork paths and occurrence references; report scoped read failures instead of substituting another book.
- Fix analytics cycle boundaries, one-day target pacing, and book-distribution date filtering.
- Share strict amount parsing between CSV and manual entry; use lookup sets for duplicate detection, bound CSV input size, and reset category selection when switching destinations.
- Load transaction rows lazily, reuse native number-formatting caches, avoid observable cache writes during rendering, and invalidate activity caches after reload and stack edits.
- Remove competing card-open animation and duplicate dismissal recognizers, guard directional releases and close completion, and preserve the existing layout and spring parameters.
- Prepare photos off the main thread with cancellation, immutable filenames, abandoned-import cleanup, and a decoded-image cache budget.
- Keep app-lock grace periods anchored to the first suspension. Modernize UI test menu navigation and retain screenshots in test results.

## [0.6.17] - 2026-09-12
### Refined & Perfected
- **Persistent Monocle Brand Logo Across All Views**: Unlocked complete top toolbar consistency between the resting home deck and the card transaction page. The `monocle.` brand logo remains permanently anchored on the left across both views, eliminating unnecessary view switches and title transitions.
- **Pure Gesture-Driven Card Dismissal**: Completely removed the `✕` close button from the card transaction header, fully leveraging Apple Wallet's 1:1 physical interactive pull-to-dismiss gesture and spring momentum release. Tapping the brand logo also serves as an intuitive alternate dismiss trigger.
- **Uncluttered Identity Hierarchy**: Removed redundant stack title text from the navigation bar, allowing the hero card's native artwork to serve as the singular, clear identity focal point.

## [0.6.16] - 2026-09-12
### Refined & Perfected
- **Streamlined Minimal Top Toolbar**: Removed the dedicated Settings button from the top navigation bar, leaving an uncluttered, distraction-free header featuring only the brand logo / card close button and the `⋯` options menu (Settings is directly accessible as an action inside the options menu).
- **True Full-Coverage Progressive Material Blur**: Pinned the progressive blur container to `y = 0` (`ignoresSafeArea(edges: .top)`), guaranteeing complete 100% solid `.ultraThinMaterial` and theme tint coverage across the entire status bar, dynamic island, and toolbar icons, with a progressive feathering transition smoothly softening over 28pt below the header.
- **Right-Aligned & Vertically Centered Stacks Indicator**: Repositioned the stacks filter badge (`activityScopeBadge`) to the far right of the activity section, aligned with perfect vertical centering against the section title ("All Transactions" / "Recent Activities"), eliminating baseline offset and visual clutter.
- **Robust UI Test Coverage**: Updated test automation suite to verify the minimal toolbar layout, right-aligned stacks indicator, and seamless options-menu navigation to Settings.

## [0.6.15] - 2026-09-12
### Refined & Perfected
- **Collapsible Hierarchical Options Submenus**: Reorganized the top-right options menu into clean, logically grouped collapsible submenus: `Cards & Stacks` (`Create New Book`, `Customize Card`, `Stacks & Card Visibility`), `Tools & Insights` (`Budgets`, `Analytics & Trends`, `Recurring Bills`), and `Data & Backup` (`Export CSV`, `Import CSV`), plus a direct `Settings` item. Eliminated redundant visual direction controls, duplicate stack manager entry points, return-to-stack actions, and raw cards dumps for a fast, uncluttered menu interaction.
- **Distinct Top Toolbar & Progressive Material Blur**: Replaced the hard-stop full-opacity navigation header with an authentic progressive variable material blur (`.ultraThinMaterial` and tint gradient smoothly feathered with a 5-stop linear gradient across 72pt depth). Separated navigation into a distinct Settings button (`gearshape`) and Options menu button (`ellipsis.circle`).
- **Native Inset Platter for Home Screen Transactions**: Brought the exact native Apple Wallet continuous rounded inset platter container (`24pt` corner radius, `MC.surface`, zero row divider lines) to the main home screen activity section, creating seamless aesthetic parity between resting stack browsing and opened card inspection.
- **Physical Device Scaled-Down Typography**: Visually scaled and balanced typography across all card and transaction surfaces for iPhone 15 Pro: card amount reduced from 28pt bold to 22pt bold (`.system(size: 22, weight: .bold)`), section titles scaled to 15pt semibold, navigation bar book title to 16pt semibold, monocle brand logo to 24pt/26pt, transaction row titles to 14pt semibold, dates to 11.5pt, amounts to 13.5pt semibold, and floating add button labels to 14.5pt semibold with 17pt symbol.
- **Automated UI Testing Suite**: Added `testOptionsCollapsibleMenuAndHomePlatter` validating home platter presence, progressive blur header rendering, hierarchical submenu navigation, Budgets screen routing, and transaction platter continuity.

## [0.6.14] - 2026-09-12
### Refined & Perfected
- **Scaled-Down Typography Hierarchy**: Refined typographic balance across the detail view and bottom navigation. Reduced the navigation bar book title from 20pt bold to 17pt semibold (`.system(size: 17, weight: .semibold)`). Scaled down the "Latest Transactions" section title to 17pt semibold, transaction row titles to 15pt semibold, dates to 12pt, amounts to 14.5pt semibold, empty state title to 15pt, and floating button text to 15pt semibold with 18pt symbol. Decreased row vertical padding and minimum height for a sleek, compact Apple Wallet aesthetic.
- **Mid-Way Cancellable Opening & Closing Movements**: Conformed completely to Apple's 120Hz fluid gesture guidelines by making opening and closing animations fully interruptible and reversible at any frame. Removed restrictive state guards so tapping a card mid-close immediately catches it in-flight and reverses it back to hero detail, tapping the close button mid-open immediately reverses it back to the deck, and tapping another card mid-flight immediately redirects to the newly selected card.
- **Comprehensive Responsiveness Test Suite**: Added `testRapidCardOpenCloseAndMidwayCancellation` verifying mid-flight opening cancellation, mid-flight closing cancellation, mid-flight card switching, and rapid burst open/close cycles without dropped gestures or hitching.

## [0.6.13] - 2026-09-12
### Refined & Perfected
- **Native Apple Wallet Inset Transaction Platter**: Rendered transaction activity in an authentic inset continuous rounded platter (`RoundedRectangle(cornerRadius: 24, style: .continuous)`) filled with `MC.surface`, completely eliminating row divider lines for a clean, distraction-free Apple Wallet aesthetic.
- **Clean Transaction Detail Header**: Removed the redundant inline `+` add button and paintbrush customizer button adjacent to "Latest Transactions", and cleanly hid the home filter menu button while viewing card transaction details.
- **Fluid Liquid Glass Centered Add Button Morph**: Re-architected the bottom navigation bar so the floating red add button dynamically animates and morphs between a bottom-right circular action button (`56x56`) on the home screen and a centered, expanded pill button (`+ Add Expense`) at the bottom of the card transaction page using `.glassEffect(.regular.tint(MC.red.opacity(0.85)).interactive(), in: .capsule)`. Tapping pre-populates the currently opened book, and dismissing the card reverses the morph seamlessly.
- **Automated UI Testing Suite**: Added `testTransactionPageLiquidGlassAddButtonAndPlatter` verifying button positions, morphing geometry, header cleanliness, modal presentation, and reverse transitions.

## [0.6.12] - 2026-09-12
### Fixed & Refined
- **Discrete Card Context Menu Targeting**: Repositioned `CardGesturesModifier` (and `.contextMenu`) and `CardAccessibilityModifier` directly onto the discrete card artwork (`width` x `height` with continuous 16pt rounded rectangle) *prior* to parent `.position(x:y:)`. This prevents `UIContextMenuInteraction` from targeting the full-screen container, eliminating the semi-transparent box artifact and anchoring context menus directly adjacent to the touched card.
- **Home Header State Guard**: Updated home header logic to explicitly check `if expanded, let current` rather than `if let current`. When resting in the home card stack (`expanded == false`), the header is guaranteed to always display the brand logo (`monocle.`) rather than prematurely showing the detail view header (`✕ Book Name`).
- **Deck Rest Card Face Cleanliness**: Restricted the card front flip action button (`⟳`) to expanded detail cards (`if isCurrent && expanded`), keeping resting stack cards perfectly clean.
- **Single Active Card Back Instance**: Restricted `CardBackTelemetryView` rendering strictly to the active selected card (`if isCurrent`), eliminating background duplicate accessibility tree elements and optimizing memory.
- **Robust Collapse State Cleanup**: Removed the restrictive `completionCriteria: .removed` from `closeCard()` so that state variables (`selectedID`, `model.selectedBookID`, dismiss offsets) reliably reset upon collapse completion across all spring animations.

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
