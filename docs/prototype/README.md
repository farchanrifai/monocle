# monocle — prototype 01

Updated: 2026-09-07

## What you can try

- Recents with an actual spending total, date groups, and category labels.
- Add Expense with a custom keypad and one shared draft across keypad/text modes.
- Type `Coffee 28k`: amount and category update as you type. Review and Record.
- Edit an entry by tapping it; touch and hold to repeat or delete. Undo restores the last deleted entry.
- Close the app with an unfinished draft, then reopen and continue.
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

Three capture UI tests pass: keypad draft recovery across relaunch, automatic text interpretation with mode switching, and validation error feedback without losing the draft. Results: `build/PrototypeTests-2.xcresult`.

The fourth UI test passes: budget/bill navigation and saved reminder choice across relaunch. Results: `build/SettingsTests-2.xcresult`. Ten tests passed across the two final runs. The first settings run tapped the row instead of the switch; the corrected test targets the switch and asserts its changed value before saving.

The dark-mode Recents, keypad, budget, and bill-settings screens were visually inspected. Light appearance, large accessibility sizes, VoiceOver, Reduce Motion, and real-device haptics remain to be checked. Simulator checks do not establish phone signing, refresh, or update preservation.

## Screens

![Recents](screenshots/recents-dark.png)

![Add Expense](screenshots/entry-dark.png)

![Budget cycle](screenshots/budgets-dark.png)

![Bill settings](screenshots/bill-settings-dark.png)

## Device package

Local deliverable: `build/deliverables/monocle-prototype-0.1.0.ipa` (excluded from Git). Release build 1, arm64, iPhone only, minimum iOS 26.0. Package integrity, device family, bundle identity, and App Intent metadata verified. Final device build completed without compiler warnings.

SHA-256: `d1ad7e6573521fea8acb237eaf0f95fd4810a6914dea1be23ea469f6a51dad5f`.

## iPhone / SideStore checkpoint

1. Transfer the supplied unsigned IPA to the iPhone and import it through SideStore. Let SideStore sign it with the existing account/setup.
2. Open monocle and record a test coffee through each entry mode. Assess thumb reach, keyboard feel, readability, and haptics.
3. Try Open Quick Entry and Add Expense from Text in Shortcuts. Test `Coffee 28k`, an unknown category, and locked/unlocked invocation.
4. Refresh the installation through SideStore and verify records and the draft remain.
5. On the next build, install over this one without uninstalling and compare the same records and Shortcut behaviour.

The iPhone 15 Pro was visible as paired during development, but this task has not installed or verified a signed build on it. Credentials and provisioning profiles are not part of the repository.

## Next implementation checkpoint

Collect feedback on the native flow. Then finish reliable capture and recovery: full backup/restore, app lock, category editing, split UI, structured Shortcut parameters, and old-store/update fixtures. Only mark daily use ready when those checks and the user's phone review pass. Budget history, real bills, and CSV follow the agreed implementation plan; they remain in v1 scope.
