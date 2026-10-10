## 1. Immediate Next Step

2026-10-10: Chat v2 tool set done. (1) Splits: `propose_expense`/`propose_edit` take `split` (2+ distinct categories summing to amount) instead of `category`; amount-only edit of a split refused (give new split); cards list each part. Committed da7a8c5. (2) Bills: `propose_bill` (name, amount, category, monthly/weekly/yearly, day/weekday/month default to today, record automatic|confirm default confirm, reminder default on, card) → `BillProposalCard` (in ExpenseProposalCard.swift) Save/Discard → `AppModel.saveBill`; `list_bills` (scope). 10 tools now. Golden prompts cover split + "netflix 186rb tiap bulan tanggal 5". iOS unit + Mac 9 unit pass. UI tests not run. IPA 0.7.27 (92) published earlier today (edit/delete only; splits + bills not in an IPA yet).

Next: remaining chat v2 is streaming + localized UI strings (bigger). Alternatives: F26 background persistence work, M4 accessibility audit, refresh stale docs/planning/roadmap.md. Golden prompts + cache check need Anthropic credits.

Other pending: proxy (Cloudflare Worker; user deploys).

## 2. Last Completed Checkpoint

2026-10-10: Chat edit/delete (CHAT_SPEC §4). `query_expenses` rows now carry `id`; new tools `propose_edit` (id + only changed amount/category/note/day; splits allow note/day only) and `propose_delete` (id). Both return `shown_to_user` and an `ExpenseChange` (original + updated, nil = delete) — nothing writes. `ExpenseChangeCard` (in ExpenseProposalCard.swift, shared iOS/Mac): before → after or the expense, Save/Discard or Delete/Keep, then "Updated/Deleted" + Undo. `ChatSession.resolveChange` refuses if the stored expense no longer equals the snapshot; delete goes through `AppModel.delete` (bill links kept for undo via `restore`); edit undo saves the original. App notes tell Claude each choice. System prompt no longer says it can't edit/delete. Golden prompts updated (delete → card for newest; "ubah kopi kemarin jadi 30rb" → 28k→30k edit). Tests: 4 new in ChatToolTests (edit fields/no write, split rules, delete no write, apply/undo/stale refusal). iOS unit + Mac 9 unit pass; Mac builds; card rendered to image and checked. UI tests not run. Committed c59debd; shipped in IPA 0.7.27 (92).

Next: build + publish IPA when the user wants it on the phone (bump MARKETING_VERSION + CURRENT_PROJECT_VERSION). Then chat v2 remainder (bill proposals, splits, streaming) or F26 background work. Golden prompts + cache check still need Anthropic credits. Refresh stale docs/planning/roadmap.md.

Other pending: proxy (Cloudflare Worker; user deploys).
