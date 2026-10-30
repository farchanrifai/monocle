# Anka privacy policy

Last updated: 2026-10-30. Published version: `docs/site/anka/privacy.html`.

Anka keeps your spending on your device. There is no account, no sign-in, no analytics or advertising SDK, and no Anka server.

## What stays on your device
Cards, expenses, categories, budgets, bills, settings, backups and the chat history. Chat runs on Apple Intelligence on your iPhone; your messages and spending never leave the device for it. Face ID / passcode app lock is handled by the system; Anka never sees your biometrics.

## The one network request the app makes

| Request | When | What is sent | Who receives it |
|---|---|---|---|
| Exchange rates | You record or view an expense in a currency other than your reporting currency | Two currency codes and a date range, e.g. `JPY` to `IDR`, 2026-10-01 to 2026-10-13. Nothing about your expenses. | Frankfurter (`api.frankfurter.dev`, European Central Bank reference rates). Like any web request it also sees your IP address. |

## Purchases
Anka Pro is an Apple subscription. Apple handles payment; Anka only learns from the App Store whether your Apple Account has an active subscription. Manage or cancel it in Settings ▸ Apple Account ▸ Subscriptions.

## Backups
Backups you export are files you control. Anka doesn't upload them anywhere.

## Sharing, selling, tracking
Anka does not collect, sell or share your data and does not track you across apps or sites.

## Contact
anka@pakaryan.com

---

# App Store privacy label (answers)

- **Data collection:** Data Not Collected. Nothing is sent to the developer; chat is on-device.
- **Frankfurter:** currency codes and dates are not personal data; the IP address is incidental to the request and not linked to an identity or used for tracking.
- **Tracking:** No.
- **Privacy manifests:** `Anka/Resources/PrivacyInfo.xcprivacy` (app) and `AnkaWidgets/PrivacyInfo.xcprivacy` (widgets): no tracking, no collected data, UserDefaults with reasons `CA92.1` (app only) and `1C8F.1` (app group shared with the widgets). Re-check when adding file-timestamp, disk-space or system-boot-time APIs, or a third-party SDK.

# Before publishing
1. Upload `docs/site/anka/` so it serves https://pakaryan.com/anka/privacy and /anka/support (folders with index.html, `/anka/style.css`). In App Store Connect: Privacy Policy URL = /anka/privacy, Support URL = /anka/support. `AppLinks.privacy` already points there.
2. If Claude chat returns (plan "Later"), add its row, a consent sheet (guideline 5.1.2(i)), and change the label to "Data Not Linked to You".
3. If iCloud sync is added, this page and the label change.
