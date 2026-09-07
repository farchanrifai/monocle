# monocle — Planning Handoff

## Project and current stage

- **App name:** monocle
- **Project folder:** `/Users/farchan/Xcode/monocle-ios-v1`
- The folder is blank. No app code or prototype has been created.
- Planning originated in an unrelated accounting conversation. This is an independent app project; do not carry over JAG accounting workflows or workbook standards.
- The user wants a clear specification and key decisions as the foundation for building, followed by an interactive prototype.
- The user has no coding experience. Explain decisions plainly and handle technical implementation.

## Product purpose

A beautiful, simple personal expense tracker that makes recording purchases fast enough to become a habit.

Main problems to solve:
- Too many clicks.
- Forgetting purchases.
- Poor shortcut support.

Primary outcomes:
- Understand where money went.
- Stay within budgets.
- Add cash-flow projections later.

Initially for personal use. If successful, the user may release it publicly as a subscription app.

## Platforms and installation

- Build for **iOS 26+ first**.
- Primary test device: **iPhone 15 Pro**.
- Development machine: **14-inch MacBook Pro M5, macOS 26+**.
- Native macOS app planned later.
- No paid Apple Developer membership currently; user may enrol later.
- Weekly signing renewal is acceptable.
- User already has **SideStore** installed and wants an installable **IPA**, ideally refreshed through SideStore.
- Validate signing, installation, updates, Shortcuts integration, and data preservation early. SideStore background refresh depends on its operating requirements; do not promise guaranteed automatic renewal.

## Confirmed v1 requirements

### Home and entry

- Open to **Recents**, grouped by date.
- Show a compact spending/budget summary.
- Prioritise minimal taps and comfortable one-handed entry.
- Required fields: **amount and category**.
- Notes are **optional**, with suggestions.
- Date defaults to today and can be changed.
- Preserve unfinished drafts.
- Provide quick editing, transaction duplication/repetition, and Undo.

### Input methods

All of these are in v1:
1. Manual entry through individual fields.
2. Text entry, such as `coffee 28k`.
3. CSV import.
4. Apple Shortcuts.

Use predictable local text parsing initially. Make interpreted values visible and editable in the normal entry flow. No AI backend is required.

CSV import should support preview, column mapping, validation, and suspected-duplicate review.

### Apple Shortcuts

- Valid shortcut submissions should **save immediately**, without a review screen.
- Proposed actions:
  - Add Expense: amount, category, note, optional date.
  - Add Expense from Text.
  - Open Quick Entry.
- Enable useful workflows such as a preconfigured Coffee shortcut and iPhone Action Button capture.
- Missing or ambiguous required information must not silently produce an incorrect transaction.
- Authentication behaviour still needs validation. The proposed default is device authentication when locked, without a second app-lock prompt for every shortcut while unlocked.

### Categories and splits

- Support editable categories.
- Support **one payment allocated across multiple categories**.
- Split amounts must equal the transaction total.
- Keep advanced options out of the ordinary entry path.

### Budgets

- Support **both an overall budget and category budgets**.
- Support a **custom monthly rollover/start date**.
- Show spending and remaining budget for the active cycle.

Proposed defaults, not separately confirmed:
- A cycle starting on the 25th runs through the 24th.
- If a selected day does not exist in a month, use that month’s last day.
- Unspent budget does not carry forward initially; carry-forward is distinct from choosing a cycle date.
- Count expenses once in overall totals, including category splits.
- Define how changing the cycle date affects historical budget periods before implementation.

### Bills

Support all three, with enable/disable options:
- Manually repeat a past transaction.
- Due-date reminders.
- Automatically create scheduled transactions.

Proposed behaviour:
- Separate reminder and automatic-recording switches per bill.
- Clearly mark automatically generated transactions and allow correction.
- A scheduled entry is an assumed expense, not proof of payment.
- Prevent duplicates and catch up missed occurrences when the app runs.
- Do not rely on iOS executing background work at an exact time.

### Privacy and data

- **Face ID required as an available app-lock feature.**
- Offline operation.
- No sync required in the first iPhone version.
- English interface.
- IDR only initially.
- No account-balance tracking required.
- Provide backup/export and tested restoration.
- CSV is for interchange; a complete backup must also preserve splits, budgets, categories, and bill rules.

## Deferred features

- **Repayments and “paid for someone else” tracking: v2.**
- Account balances and reconciliation.
- Multiple books, potentially separating daily spending and bills.
- Tags.
- Multiple currencies.
- Cash-flow projection.
- macOS interface and cross-device sync.
- Subscription billing and public distribution.

Repayments are a real future use case: the user sometimes pays for others and receives reimbursement. Keep future extensibility in mind, but do not add repayment UI to v1.

## Design direction

The user selected **black/white/red graphic precision**.

References:
- Nothing
- Teenage Engineering
- Anthropic
- Apple’s interaction quality and Liquid Glass

Desired qualities:
- Minimalist and distinctive.
- Beautiful typography and custom elements.
- Smooth, responsive animation.
- Interactive haptic feedback where meaningful.
- Native Liquid Glass.
- Fast enough that entering an expense never feels like a chore.

Proposed expression:
- Black and off-white foundations with deliberate red accents.
- Large, aligned amounts.
- Custom keypad, category controls, and budget indicator.
- Readable transaction content.
- Liquid Glass on navigation and floating controls.
- Short, interruptible transitions.
- Subtle selection feedback and confirmation after successful saving.
- Support Dynamic Type, VoiceOver, Reduce Motion, and reduced transparency.

Avoid copying any reference brand literally. Develop a coherent identity for monocle.

## Recommended technical foundation

These are assistant recommendations; the user is flexible about language and prioritises reliability, UI flexibility, and ease of iteration.

- **Swift + SwiftUI**.
- UIKit only for specific capabilities where needed.
- Local **SwiftData** storage as the initial candidate, validated against the final model.
- Separate financial calculations and transaction validation from UI code.
- Keep a small storage boundary for future evolution.
- Centralise colours, typography, spacing, and motion settings.
- Store money using exact decimal or integer minor-unit representations with currency identifiers; never floating-point financial arithmetic.
- Use explicit save/error handling and versioned data migrations.
- Share financial logic and data infrastructure with the future Mac app; design a proper Mac interface later.
- Consider a default internal book identifier while keeping v1’s interface single-book.
- Minimise dependencies and avoid adding infrastructure for speculative features.

## Quality goals

- Proposed target: familiar expense entered within **five seconds after opening**, measured on the user’s phone.
- Saving must not wait for an animation.
- Confirm success only after data is stored.
- No duplicate scheduled entries.
- Correct totals across category splits and custom budget periods.
- Recover drafts after interruption.
- Test import errors, migrations, backup restoration, and app updates.
- Treat animation, haptics, and accessibility as part of the core experience.

## Suggested next steps

1. Inspect the project folder and any applicable instructions.
2. Save a concise product specification, decision log, and implementation plan.
3. Resolve only material open behaviours; keep confirmed decisions intact.
4. Prototype **Recents → Add expense → Save**, plus a budget-cycle view and a configurable bill.
5. Test the feel on the actual iPhone and validate SideStore delivery early.
6. Implement persistent transactions, splits, budgets, bills, Shortcuts, CSV import, and backup/restore in manageable stages.

The immediate goal is to establish the project documents and a reviewable interaction prototype—not to build every future feature at once.