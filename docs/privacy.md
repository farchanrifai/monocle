# Monocle privacy policy (draft)

Last updated: 2026-10-14. Draft for the owner to host; replace the contact line before publishing.

Monocle keeps your spending on your device. There is no account, no sign-in, no analytics or advertising SDK, and no Monocle server. The only optional exception is a relay you run yourself (see below).

## What stays on your device
Cards, expenses, categories, budgets, bills, settings, backups and the chat history (`chat.json`). Your personal Anthropic API key, if you add one, sits in the iOS/macOS Keychain on that device only. Face ID / passcode app lock is handled by the system; Monocle never sees your biometrics.

## The network requests the app can make

| Request | When | What is sent | Who receives it |
|---|---|---|---|
| Exchange rates | You record or view an expense in a currency other than your reporting currency | Two currency codes and a date range, e.g. `JPY` to `IDR`, 2026-10-01 to 2026-10-13. Nothing about your expenses. | Frankfurter (`api.frankfurter.dev`, European Central Bank reference rates). Like any web request it also sees your IP address. |
| AI chat | Only after you turn on AI Chat in Settings and add your own API key, or register with an invite code to use your own Luna server | Your message, the names of your cards, stacks and categories, and the results of the questions you ask (aggregates for the requested range; at most 50 rows). Never: app-lock settings, backups, card artwork, cards outside the chat scope. | Anthropic (`api.anthropic.com`), straight from your device using your own key; or, with a Luna invite, your own Luna server (a Cloudflare Worker that you run), which relays the request to Anthropic and keeps only token counts, never message content. Anthropic's own terms and privacy policy apply to that request. |
| Share with Luna | Only after you register with a Luna invite and turn on Share with Luna in Settings → Luna; sent after changes and when the app opens | Names of your cards, bills and categories; bill amounts and due dates; budget limits, spending and pace; monthly totals per card and category. You choose which of bills, budgets and monthly totals to include. Never individual expenses, notes, backups or app-lock settings. | Your own Luna server (Cloudflare Worker and database in your own Cloudflare account), which stores only the latest snapshot. Turning the switch off stops all sending. |

AI chat is off by default. Turning it off, or clearing the key, stops the requests. Chat history is deleted by Clear chat, Reset data, Clear all transactions and backup restore.

## Sharing, selling, tracking
Monocle does not sell or share your data and does not track you across apps or sites.

## Contact
<owner contact here>

---

# App Store privacy label (answers, if the app ships there)

- **Data collected by the developer:** none. Monocle has no server; nothing is sent to the developer.
- **Third-party data collection:** the two requests above go to third parties, but the data they receive is not linked to an identity by the app and is not used for tracking.
  - Frankfurter: currency codes, dates (not personal data). IP address is incidental to the request.
  - Anthropic (opt-in, user's own key): user content (the chat message and the spending context above). Declare "User Content" as collected by a third party only if Apple's review treats the user's own API key flow as developer-routed. The safer answer, if a proxy is added (CHAT_SPEC §8), is to declare User Content and Other Data collected, used for App Functionality, not linked to identity, not used for tracking.
- **Tracking:** No.
- **Required-reason APIs / `PrivacyInfo.xcprivacy`:** `Monocle/Resources/PrivacyInfo.xcprivacy` (iOS and Mac apps, since 0.9.8): no tracking, no collected data types, UserDefaults with reason `CA92.1`. Re-check it when adding file-timestamp, disk-space or system-boot-time APIs, or a third-party SDK.

# Before publishing
1. Host this page and set the URL in App Store Connect (Privacy Policy URL).
2. If the Cloudflare proxy lands, update the AI chat row: requests go to the proxy first, which forwards them and logs no message content.
3. If sync (iCloud) is ever added, this page and the label change.
