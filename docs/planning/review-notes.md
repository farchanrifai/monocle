# App Review notes (paste into App Store Connect ▸ App Review Information ▸ Notes)

Anka is an expense tracker that stores everything on the device. There is no account or sign-in, so no demo login is needed.

- First launch: onboarding offers a Sample card with example expenses. Keep it to see every screen with data.
- Anka Pro (auto-renewable subscription, monthly or yearly, with a free trial) unlocks more cards and stacks, foreign currencies, Analytics trends, all widgets and Live Activities, and unlimited chat. Open the paywall from Settings ▸ Upgrade to Anka Pro, or by tapping any locked feature. Purchases can be tested in the sandbox; Restore is in Settings and on the paywall.
- Chat (the Chat button in the bottom bar): for Anka Pro (including the free trial), chat uses Claude by Anthropic. Before the first message, a sheet explains what is sent (the message and the spending details needed to answer) and asks permission ("Use Claude" / "Keep on iPhone"); Settings ▸ Chat with Claude changes it. Without Pro, or if declined, chat runs on Apple Intelligence on the device; without either, chat explains why and the rest of the app works normally. A screen recording of both is attached.
- Network requests: exchange rates (European Central Bank via api.frankfurter.dev: two currency codes and dates, no user data), and, only with Chat with Claude on, the chat conversation through our server (anka-chat.farchan.workers.dev), which verifies the App Store subscription transaction and forwards to Anthropic. The server stores no messages.
- Widgets: add any Anka widget. Free users see a "Widgets are part of Pro" state.

Contact: anka@pakaryan.com
