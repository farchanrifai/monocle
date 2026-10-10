## 1. Immediate Next Step

Model B (purpose cards) is decided and planned; nothing is implemented yet. Branch `feat/model-b` (worktree `.claude/worktrees/model-b`, from `feat/apple-intelligence-chat` at `23e8586`).

- Plan: `docs/planning/model-b-plan.md` (phases 0–6: UI copy → V5 storage + backup 8 → stacks ≤1 per card + cap → budget kinds/goals → Paid with + form customization → currency + FX → code renames).
- Decisions and glossary: Monocle Data Model page https://claude.ai/artifact/8vedGpoUBw6J97NBgRZqPg (version 4).
- Waiting on the user: (1) rename all ~680 `bookID` references in phase 6, or only the types; (2) FX source (Frankfurter proposed). Then start phase 0.
- Don't merge to main; `feat/apple-intelligence-chat` (AI chat, Mac Analytics, Mac toolbar) is still unmerged and its open items still apply.

## 2. Last Completed Checkpoint

Fixed both known AI Chat bugs (Apple on-device backend); merged into `feat/apple-intelligence-chat` (commit `3657720`, pushed). Do NOT merge to main until the user says so.

- "updated"/"saved" before confirm: `AppleChatAgent.claimsDone` drops the reply text when the turn shows a proposal/change/bill card and the text uses a done verb (EN + ID word list).
- "what categories?" echoing the list: Apple's app_context no longer lists categories (`ChatAgent.context(listCategories: false)`); instead `category` in the propose_* tool schemas is an enum of the target card's categories (session rebuilt when they change). Claude backend unchanged.
- On-device probe (`AppleChatTests.testGoldenPromptsOnDevice`): 9/11 → 10/11. Remaining ✗: the 3-turn follow-up "what categories?" answers this month instead of keeping last month (period carry-over, separate issue). Netflix bill picked category Wellbeing and record automatic (valid but odd).
- Verified: Mac unit tests 20 pass (1 skipped), iOS sim build OK. Mac UI tests not run; Claude golden prompts not rerun (Claude path only lost nothing; context default unchanged); no IPA built.

Still open (AI Chat): live check of Quick Chat, charts, @ picker (Mac + iOS on device); keep/remove Apple backend decision; follow-up period carry-over; proxy before sharing; chat v2 streaming + localized strings. Mac Analytics live feedback (previous checkpoint) still pending.

Mac toolbar (commit `a88a4e3`, pushed): window title hidden (`.windowToolbarStyle(.unified(showsTitle: false))` in MonocleMacApp; each page draws its own large title) and toolbar background hidden so every page matches. `.toolbar` sits on the detail column in MacRootView (on the split view, macOS 26 ignored `ToolbarSpacer`); layout (Search) (Commands | Inspector) (+), inspector icon `pointer.arrow.click`. Verified by window capture.
- Screen checks without focus: `screencapture -x -o -l <windowID>` works (window id via CGWindowListCopyWindowInfo, owner "Monocle"); the window must be on screen, not in the Stage Manager strip. A post-launch capture showed an empty sidebar Cards section and 0 bills in the demo; likely still loading, unconfirmed.
