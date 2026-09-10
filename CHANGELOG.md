# Changelog

All notable changes to Monocle are documented in this file.

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
