# monocle — product specification

Updated: 2026-09-07. Confirmed requirements come from the original handoff and subsequent conversation. New implementation defaults are identified below and in the decision log.

## Scope

English interface, IDR initially, offline operation, one visible book in v1. Required v1 input methods: manual fields, local text parsing, CSV import, and Apple Shortcuts. All remain in v1 even if delivered across several milestones.

No initial account-balance tracking. Native Mac, sync, shared books, and public distribution come later. Sync is expected near public release. Repayments, paid-for-others tracking, multiple-book UI, tags, multiple currencies, and cash-flow projections are deferred.

## Recents and navigation

- Open to Recents grouped by transaction date, with compact spending/budget summary.
- Make Add Expense prominent and comfortable with one hand.
- Provide fast editing, duplication/repetition, deletion with Undo, and access to budgets, bills, and settings.
- Budget/bill/settings navigation placement is a prototype decision; it must not crowd everyday capture.

## One entry screen, two modes

The user requested keypad entry and text such as `Coffee 28k`, delegating the interface choice. Chosen design: two input modes sharing one editable draft and save action.

Manual flow: open app → + → custom amount keypad → category → optional note → Record.

Text flow: + → Type an expense → `Coffee 28k` → editable amount/category/note → Record. A direct text Shortcut remains available.

- Amount display and text parsing follow the system number separators; currency is still IDR. Whole-rupiah entry remains the initial policy.
- Amount and category are required. Note is optional, with suggestions. Date defaults to today and is editable.
- Switching modes preserves entered values; a parsed preview does not silently overwrite subsequent manual corrections.
- Preserve unfinished drafts after interruption. Record succeeds only after persistence succeeds.
- Deliberately closing or swiping away a changed entry asks **Discard** or **Keep editing**. Discard clears the draft; cancelling preserves it. Unmodified edits close immediately. An interrupted draft must offer a discard-and-continue path when opening another transaction.
- Categories occupy one horizontally scrolling row. An All categories control opens a searchable, scrolling sheet, keeping the keypad reachable as the category collection grows.
- Show errors with the draft intact. Guard repeated taps against duplicate saves.
- Record immediately; confirmation animation and haptics follow the successful save.
- A split transaction has multiple category allocations whose sum exactly equals its total. Ordinary entry uses one allocation. Splitting stays in an advanced path.

Proposed parsing defaults: deterministic local keyword rules, editable by the user, with starter mappings such as coffee → Food & Drink. `28k` becomes Rp28,000. Show interpreted fields before manual recording. Unknown or conflicting required values require correction; no AI service is needed. Detailed accepted number formats and rule precedence must be specified and tested during implementation.

## Shortcuts

- Add Expense: amount, category, optional note/date.
- Add Expense from Text.
- Open Quick Entry.
- A valid submission saves immediately without a review screen. Missing or ambiguous required input asks for clarification or returns a useful error without saving.
- Support preconfigured Coffee and Action Button workflows.
- Proposed authentication policy: require device authentication when locked; avoid a second app-lock prompt for a valid capture while unlocked. Verify actual App Intent behaviour on the signed phone build.
- Shortcuts and UI use the same validation and persistence path.

## Categories

Editable categories: create, rename and choose an icon. The current implementation permits deletion only while unused; archive is pending. Proposed default: archive used categories instead of deleting historical allocations. Each book owns its categories, allowing later shared books to carry their own labels and rules.

## Budgets

Confirmed:

- Overall and category budgets are independent limits. Category limits do not have to sum to the overall limit.
- Custom monthly start day; no unused-budget carry-forward initially.
- Show spending and remaining amount for the active period. Count each payment once overall; use allocations for category totals.
- Amount changes affect the current cycle unless the user chooses the next cycle.
- Start-day changes take effect at the next boundary and preserve historical reports.

Proposed calendar details from the handoff: start on the 25th means 25th through the following 24th; clamp a nonexistent day to that month's last day. Use explicit period boundaries, not a hard-coded number of days.

The user's actual start day is not yet supplied. Make it a setting; use day 1 as the proposed initial value. A start-day change needs a visible transition-period preview and a tested rule for its budget amount before that setting ships. No gaps, overlaps, or silent historical regrouping.

## Bills

Support repeating an existing transaction manually, due-date reminders, and scheduled occurrences. Each bill independently chooses:

- Automatically record on its due date: count it in spending; label it Automatically added; permit correction. It is an assumed expense, not evidence of payment.
- Keep pending for confirmation: show it as due/upcoming; exclude it from recorded spending until confirmed.

Reminder on/off is independent of the recording mode. Occurrences retain their scheduled identity even if edited. Catch up missed dates when the app runs; do not rely on exact background execution. Reopening, retrying, or confirming an already handled occurrence must not create another expense.

Proposed details for later review: pending confirmation defaults the expense date to the due date and allows editing; skipped/deleted occurrences retain a marker so catch-up cannot recreate them. Schedule edits affect future occurrences without rewriting recorded history.

## CSV and full backup

CSV import supports column mapping, preview, row validation, and suspected-duplicate review before committing. Never silently drop invalid rows or merge plausible repeated purchases.

CSV export is for interchange. Full backup must preserve stable identifiers, transactions and splits, categories, budget periods/rules, bill rules/occurrences, and parsing rules. Include portable preferences and drafts where useful; never export device authentication credentials.

Proposed first restore mode: replace local data after validation, a clear preview, and creation of a safety backup. Treat backup merge as future work. Reject unsupported versions or broken references before changing the active store. Demonstrate restoration into a fresh store and matching totals before daily use.

## Locking and experience

Face ID is available as an optional app lock with iPhone passcode fallback. Configurable timeout: proposed choices immediately, 1 minute, and 5 minutes. No separate monocle PIN. Defaults for enabling the lock and notification detail remain prototype choices.

Use black/off-white foundations and deliberate red accents, large aligned amounts, custom keypad/category controls, and Liquid Glass on navigation/floating controls. Avoid copying reference brands. Keep transaction content legible and save feedback subtle.

Support Dynamic Type, VoiceOver, Reduce Motion, and reduced transparency. Aim for a familiar expense recorded within five seconds after opening; measure on the phone and document whether app authentication was involved.
