# monocle — prototype 0.1.1, build 3

Updated: 2026-09-08

## What you can try

- Recents with an actual spending total, date groups, and category labels.
- Add Expense with a custom keypad and one shared draft across keypad/text modes.
- Type `Coffee 28k`: amount and category update as you type. Review and Record.
- Edit an entry by tapping it; touch and hold to repeat or delete. Undo restores the last deleted entry.
- Interrupt the app with an unfinished draft, then reopen and continue. Explicit Close or swipe-down asks Discard/Keep editing; discarding frees entry for another transaction.
- Browse a compact horizontal category row, or open All categories for a searchable native sheet.
- Home uses a small native Settings control and floating bottom controls with the list visible behind them. The keypad adapts to available height; press/amount animations and haptics provide brief feedback.
- Explore a sample budget and start-day preview.
- Choose automatic or pending recording for the sample bill, with an independent reminder preference.

The bill and budget settings are interaction previews. Scheduling and notifications are inactive. The sample cycle editor changes the sample display immediately; production historical-period transitions have not been implemented.

## Data and foundation

Records use a versioned Core Data model, with book, category, expense, and allocation entities. Amounts use exact integer minor units. UI and the text Shortcut call the same validated save operation. The persistence layer can store and validate splits, but the split editor is deferred to the next milestone.

Sample records are created once with stable identifiers. Clearing a book does not reseed it. Edits and retries retain the transaction ID. Draft and prototype-setting files are saved atomically. Data lives under the app's Application Support `monocle-prototype` folder, separate from the eventual personal book. Automated UI tests use distinct stores.

Full backup/restore, app locking, category/rule editing, scheduled occurrences, CSV import/export, and production budget history remain unimplemented. No sync/cloud entitlements are enabled. Use test purchases in this version.

## Current Shortcuts

- **Open Quick Entry**: opens the shared draft.
- **Add Expense from Text**: validates and records a recognized expense in the sample book, without a confirmation screen.

The intent declares local-device authentication. Actual locked/unlocked behaviour and discovery in Shortcuts must be validated in the SideStore-signed installation. Structured Add Expense parameters are a later capture-milestone addition.

## Validation evidence

The simulator build and Release arm64 iPhone build succeeded. The device package is unsigned and must be re-signed by SideStore. The compiled bundle identity is `com.farchan.monocle`; keep this stable, and record any identity changes made during SideStore signing.

Six domain/storage tests pass: exact parsing/rejections, ambiguous text categories, split/date validation, month-end and leap-year boundaries, disk-store reopen/upsert/invalid-save preservation, and draft encoding.

Six additional foundation tests cover shared text commands, identity-preserving retries, failed writes/discard/settings, post-commit publication without a second read, old JSON encoding, and corrupt-file preservation. All 20 tests pass (12 unit/storage and 8 UI). Result: `build/FoundationTests-20260908.xcresult`.

The previous 0.1.1 UI pass validated eight flows on the iPhone 15 Pro simulator: interruption recovery, text interpretation/mode switching, invalid save, budget/bill preferences, keypad layout with 18 categories, Close/Keep editing/Discard, swipe discard, and replacing a recovered draft to edit another transaction. Results: `build/Final011Tests.xcresult`. The larger-text keypad/category test also passed in `build/LargeType011Tests.xcresult`. The final Home accessibility label fix compiles and is covered by the current normal-size suite; a further large-type visual check remains.

The user reports working functions and snappy navigation on their SideStore-installed iPhone 15 Pro. Real-device haptic feel, signed Shortcut behaviour, refresh, and update preservation still require phone checks. VoiceOver and Reduce Motion have not received a complete manual audit.

The foundation now separates dependency assembly, shared expense commands, Core Data, atomic local files, and presentation state. The compiled bundle identity, database model, storage folder, and draft/settings encoding remain unchanged. See [architecture](../planning/architecture.md) for implemented boundaries and remaining work.

## Current screens (0.1.1)

![Recents](screenshots/recents-011-light.png)

![Add Expense](screenshots/entry-011-light.png)

![All categories](screenshots/categories-011-light.png)

## Earlier visual baseline (0.1.0)

![Recents](screenshots/recents-dark.png)

![Add Expense](screenshots/entry-dark.png)

![Budget cycle](screenshots/budgets-dark.png)

![Bill settings](screenshots/bill-settings-dark.png)

## Device package

Local deliverable: `build/deliverables/monocle-prototype-0.1.1-build-3.ipa` (excluded from Git). Release build 3, arm64, iPhone only, minimum iOS 26.0. Unsigned; SideStore must sign it. Package integrity, version, device family and bundle identity verified. Earlier build 1 and build 2 artifacts are preserved.

SHA-256: `1e8e35240a439791d9b2b424ff3f7781c1134db0e89c1e36f78a762cb2173f7f`.

## iPhone / SideStore checkpoint

1. Transfer the supplied unsigned IPA to the iPhone and import it through SideStore. Let SideStore sign it with the existing account/setup.
2. Open monocle and record a test coffee through each entry mode. Assess thumb reach, keyboard feel, readability, and haptics.
3. Try Open Quick Entry and Add Expense from Text in Shortcuts. Test `Coffee 28k`, an unknown category, and locked/unlocked invocation.
4. Refresh the installation through SideStore and verify records and the draft remain.
5. On the next build, install over this one without uninstalling and compare the same records and Shortcut behaviour.

The user confirmed the original installation works on iPhone 15 Pro. The updated build has not yet been verified on that phone. Install over the existing app using the same SideStore setup; do not uninstall to update. Credentials and provisioning profiles are not part of the repository.

## Next implementation checkpoint

Collect feedback on the native flow. Then finish reliable capture and recovery: full backup/restore, app lock, category editing, split UI, structured Shortcut parameters, and old-store/update fixtures. Only mark daily use ready when those checks and the user's phone review pass. Budget history, real bills, and CSV follow the agreed implementation plan; they remain in v1 scope.
