# monocle — App Store release plan

Updated: 2026-10-21. Branch: `release/app-store` (from `main` @ `ba4f078`, 0.9.9 build 113).

## Branches

- `main` stays the SideStore line (0.9.x). Fixes land there first and are merged into `release/app-store`.
- `release/app-store` never publishes to the SideStore feed: build with `SKIP_SIDESTORE_PUBLISH=1` or the App Store export script only. `monocle-releases` is public, so a SideStore IPA of this branch would hand out Pro.
- After launch, rename `main` → `sidestore` and `release/app-store` → `main`.

## Decided

| Decision | Consequence |
| --- | --- |
| Individual developer account | Legal name shown as seller; no D-U-N-S; bank account and W-8BEN in own name |
| Drop Luna | Delete invite registration, `LunaProxy`, `LunaBridge`, `LunaSnapshot`, Settings → Luna; no server, no App Store Server Notifications |
| Apple Intelligence is the only chat in 1.0 | No per-user AI cost; chat shown only when `SystemLanguageModel.default.availability == .available`; Pro must not be sold on chat. Claude is removed from 1.0 and revisited for 1.1 |
| iOS first, Mac later | Before the Mac's first release, change its bundle ID to `com.farchan.monocle` (universal purchase) |
| Worldwide from day one | See phase 1b; no China mainland (ICP filing) |

## Free and Pro

| | Free | Pro |
| --- | --- | --- |
| Cards | 1 real card, unlimited expenses. Sample card doesn't count (10 entries) | Unlimited cards, Stacks, stack budgets |
| Budgets | Monthly and Total-until on the card | Plus stack budgets |
| Bills | Up to 3 active, with reminders | Unlimited |
| Currencies | Reporting currency | Spending in other currencies with rates |
| Analytics | Month and category totals on the card | Analytics screen |
| Widgets, Live Activities, spending sessions | — | Yes |
| Shortcuts | Add Expense, Quick entry | All |
| Chat (Apple Intelligence) | 5 questions a day; adding expenses through chat is unlimited | Unlimited |
| Card customizer | Default looks | Full |
| CSV | Export | Import too |
| Backup/restore, App Lock | Always free | Always free |

- **Sample card:** usable for trying things out, capped at 10 entries the user added (seeded entries don't count; deleting one frees a slot), for Free and Pro alike. At the cap: "The Sample card is for trying things out. Add this to your card." Not renamable; hideable (existing Visible cards toggle) and deletable. Onboarding creates the real card, so `startEmptyRealCard` / "Start your real card" goes away.
- **Downgrade (trial end, expiry, refund):** the user picks the 1 card to keep; other cards become read-only (view, export, back up and delete stay allowed). The choice is permanent (confirmation dialog; defaults to the most recently used card). The choice is stored outside the backup; if the kept card is deleted or missing after a restore, the user picks again. Locked cards' bills pause. Bills over 3: the 3 oldest stay active, the rest are paused; the user can swap them within the limit. Stacks stay visible, not editable. Resubscribing unlocks everything immediately.
- Gates go in `ExpenseService` (the single write path) so Shortcuts, chat, widgets, bills, CSV and restore share them.

## Open decisions

1. Prices. Owner's plan: USD 2.99/month, 29.99/year. Alternative: 3.99/month, 29.99/year (yearly ~37% off) with the trial on yearly. Lowering prices later is easy; raising them needs existing subscribers' consent.
2. EU: declare trader status (individual's address, phone and email shown on EU listings) or leave EU storefronts out at launch.

## Later
- Claude provided by the developer, if sales justify it: Haiku via a proxy that checks the StoreKit transaction (Luna rebuilt as a product), sold as Pro chat on any iPhone. Needs the 5.1.2(i) consent sheet and a privacy label update.

## Phases

### 0. Account (owner, this weekend)
- Enroll (Individual). Sign the Paid Apps Agreement; add bank and tax details. Products don't load in sandbox until it is active.
- Apply for the Small Business Program (15%).
- Register `com.farchan.monocle`, `com.farchan.monocle.MonocleWidgets`, `group.com.farchan.monocle`; In-App Purchase capability.
- Create the app record (check the name), subscription group, monthly + yearly products, trial offer.

## Status (2026-10-22)

Done on this branch, no paid account needed (254 iOS + 21 Mac unit tests pass; UI tests not run):
- **Strip:** Luna and Claude removed; chat is Apple Intelligence only, no opt-in, explains itself when unavailable. `MONOCLE_FAKE_CHAT` drives chat in UI tests.
- **Worldwide:** Shortcuts and chat amounts follow the card's currency with decimals; onboarding picks the currency (device's first) and scales the Sample card without exchange rates.
- **Plan:** `Plan` + `ExpenseService.plan` enforce 1 real card, 3 running bills (others frozen: no reconcile, no reminders), 10 user entries on the Sample card (any plan), locked cards after a lapse, Pro-only foreign currency. `AppModel.report` turns refused writes into the paywall.
- **StoreKit:** `ProStore` (entitlements, updates, restore, app-group cache for widgets), `Configuration/Monocle.storekit` (monthly 2.99 / yearly 29.99, 1-week free trial: placeholders until prices are decided), scheme uses it for Run.
- **Screens:** `PaywallView` (SubscriptionStoreView + Free vs Pro table, restore, redeem, terms, privacy), `KeptCardPicker` (permanent choice, stored in UserDefaults), `OnboardingView`, Settings ▸ Subscription and About links; "Start your real card" removed.
- **Gates:** new stacks, stack budgets, CSV import, Analytics, spending sessions, card looks, second card, foreign currencies, Pro Shortcuts (sessions, summary, budget left, Ask), Home Screen widgets, chat after 5 questions a day.
- **Compliance:** `ITSAppUsesNonExemptEncryption = NO`, deprecation fixed, privacy manifests (app + widgets, `1C8F.1`), `scripts/build-appstore.sh`, `build-ipa.sh` never publishes `release/*`, `docs/privacy.md` rewritten.

Needs the account or the owner:
- Team signing: `DEVELOPMENT_TEAM`, then `ProStoreTests` StoreKit cases stop skipping (they need a team-signed build).
- App Store Connect: products with the same IDs (`com.farchan.monocle.pro.monthly` / `.yearly`), group, trial; prices.
- Contact line, privacy page hosting (`AppLinks.privacy` is a placeholder), support URL, rate-the-app link (needs the app ID).
- Phone checks: onboarding, paywall purchase in sandbox/TestFlight, downgrade picker, widgets lock, chat limit.
- Done 2026-10-22: rating prompt (`ReviewPrompt`, once per version after 10 saves); unused `RecentsView` with its "PROTOTYPE 01" label removed.
- Not done yet: iOS/Mac UI test run; simulator screenshots of paywall, onboarding steps and kept-card picker; MARKETING_VERSION 1.0.0 at submission.

### 1. Strip
- Remove Luna code, settings, tests and docs references.
- Remove Claude (`ClaudeClient`, key entry in `ChatSettingsView`); keep `AppleChatAgent` and the shared tool layer. When Claude returns in 1.1 it needs a one-time consent sheet naming Anthropic before the first request (5.1.2(i)).
- Remove the SideStore publish step from this branch's release path.

### 1b. Worldwide
- Done: Shortcuts Add Expense and spending-session budget take decimals in the card's currency (`Money.minor(fromMajor:)`); chat tools take major units with decimals and Apple chat parses "$4.50" / "4,50 €" / "28rb" per currency; manual entry already did; Shortcut field label "Amount"; chat suggestion follows the reporting currency.
- With onboarding (2b): first-launch reporting currency from `Locale.current.currency`; Sample card amounts scaled to that currency.
- English-only listing is fine; localization later.

### 2. StoreKit 2
- `.storekit` configuration file mirroring the App Store Connect products.
- Entitlement: `Transaction.currentEntitlements` at launch, `Transaction.updates` listener; Pro flag written to the app group for widgets.
- Paywall: `SubscriptionStoreView` with Terms and Privacy links; Restore (`AppStore.sync()`); `.manageSubscriptionsSheet`; offer code redemption.
- Gates at the Pro features chosen in decision 2. Existing data over the free limit stays readable and editable; only creating more is gated.
- Tests: `SKTestSession` for purchase, expiry, refund, trial eligibility.

### 2b. Screens
- Onboarding (first launch only): what Monocle does → reporting currency → start blank, with the Sample card, or restore a `.monoclebackup` → trial offer (skippable).
- Paywall: one `SubscriptionStoreView` with the Free vs Pro comparison as its marketing content; Apple's sheet takes payment. Opened from onboarding, Settings and every locked feature.
- Locked states: Pro badge and paywall on tap; widget placeholder when not Pro; lapsed subscription keeps extra cards readable, explained once.
- Settings → Subscription: plan, renewal date, Manage, Restore, Redeem code.
- Settings → About: version, contact support, privacy policy, terms, rate the app.
- Chat unavailable: hide chat, or explain the Apple Intelligence requirement, on devices without it.
- Audit Settings for developer/prototype-only items before review.
- Not screens: review prompt (`requestReview` after a good moment), billing problems (enable Billing Grace Period; StoreKit shows its own message).

### 3. Build and compliance
- `DEVELOPMENT_TEAM`, signing, `ITSAppUsesNonExemptEncryption = NO`.
- App Store archive + export script next to `scripts/build-ipa.sh`; TestFlight upload.
- Fix the `requestConfirmation(result:…)` deprecation in `ExpenseIntents.swift`.
- Privacy manifest re-check after stripping.

### 4. Store listing and legal
- Privacy policy: rewrite `docs/privacy.md` without Luna (and without Claude if removed), add contact, host it.
- Support URL, Terms of Use (Apple standard EULA), age rating, Finance category, privacy label.
- Icon, screenshots, name, subtitle, description, keywords.

### 5. TestFlight
- Sandbox purchase, trial, restore, expiry, upgrade monthly → yearly.
- Device without Apple Intelligence: no chat entry, paywall without chat.
- Move the owner's data from the SideStore install with a `.monoclebackup` (different bundle ID, separate app).

### 6. Submit
- Review Notes: Pro testable in sandbox; Sample card has data; chat needs an Apple Intelligence device.
