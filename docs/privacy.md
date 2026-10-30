# Ankka privacy policy

Last updated: 2026-10-30. Published at https://pakaryan.com/ankka/privacy (site repo ~/Xcode/pakaryan).

Ankka keeps your spending on your device. There is no account, no sign-in, and no analytics or advertising SDK. The only Ankka server passes Ask Ankka to Claude, and only when you turn on Chat with Claude.

## What stays on your device
Cards, expenses, categories, budgets, bills, settings, backups and the chat history. Ask Ankka answers on your device with Apple Intelligence unless Chat with Claude is on (below). Face ID / passcode app lock is handled by the system; Ankka never sees your biometrics.

## Network requests the app makes

| Request | When | What is sent | Who receives it |
|---|---|---|---|
| Exchange rates | You record or view an expense in a currency other than your reporting currency | Two currency codes and a date range, e.g. `JPY` to `IDR`, 2026-10-01 to 2026-10-13. Nothing about your expenses. | Frankfurter (`api.frankfurter.dev`, European Central Bank reference rates). Like any web request it also sees your IP address. |
| Chat with Claude | You message Ask Ankka with Chat with Claude on (Pro; asked once before the first message; Settings ▸ Chat with Claude) | The message and conversation so far; the spending details the app looks up to answer (amounts, dates, notes, category, card and Paid with names); the App Store subscription transaction, which shows Pro. | Ankka's chat server (`ankka-chat` Cloudflare Worker, `server/ankka-chat`) checks the subscription and passes the conversation to Anthropic (Claude). The server keeps no messages: only the transaction ID, its expiry and a monthly token count per subscription (fair-use cap). Anthropic processes it under its commercial terms (no training on it). Both see the IP address. |

## Purchases
Ankka Pro is an Apple subscription. Apple handles payment; Ankka learns from the App Store whether your Apple Account has an active subscription. Manage or cancel it in Settings ▸ Apple Account ▸ Subscriptions.

## Backups
Backups you export are files you control. Ankka doesn't upload them anywhere.

## Sharing, selling, tracking
Ankka does not sell your data and does not track you across apps or sites. Apart from Chat with Claude, nothing you record is shared.

## Contact
anka@pakaryan.com

---

# App Store privacy label (answers)

- **Data collection:** Data Not Linked to You, all for App Functionality, none for tracking:
  - User Content ▸ Other User Content (chat messages, sent to Anthropic).
  - Financial Info ▸ Other Financial Info (the spending details a chat answer needs).
  - Purchases ▸ Purchase History (the subscription transaction ID the chat server keeps for its monthly cap).
- **Frankfurter:** currency codes and dates are not personal data; the IP address is incidental.
- **Tracking:** No.
- **Privacy manifests:** `Ankka/Resources/PrivacyInfo.xcprivacy` declares the three types above (not linked, no tracking, App Functionality) and UserDefaults reasons `CA92.1` and `1C8F.1`. `AnkkaWidgets/PrivacyInfo.xcprivacy`: nothing collected. Re-check when adding file-timestamp, disk-space or system-boot-time APIs, or a third-party SDK.

# Before publishing
1. The live pages are in the site repo `~/Xcode/pakaryan`: `src/pages/ankka/privacy.astro` (mirror of this file) and `src/pages/ankka/support.astro`; deploy with `npm run deploy`. In App Store Connect: Privacy Policy URL = /ankka/privacy, Support URL = /ankka/support.
2. If iCloud sync is added, this page and the label change.
