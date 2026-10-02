# Changelog

## 0.1.28 - 2026-10-02

Coming back shows work that still needs you. The conversation can jump between your prompts.

- Opening the app, or bringing it forward, lands on the live list when a session is waiting for an answer, waiting for approval, or finished out of view. A running task alone does not switch pages. A draft or the web chat stays put.
- A turn that finishes while you are not watching it stays on that list: your prompt, the repo, and how many files changed. Opening the session clears the card. The list is kept on this Mac, up to 12.
- That finished or failed turn notifies once when the app is in the background. Stop does not notify. The Dock badge counts the same three needs, and each project row shows how many belong to that repo.
- The box on the live list can choose the repo for the next task. Choosing a repo does not open an empty session.
- The conversation scrollbar marks each of your prompts. The arrows jump to the previous or next one.
- The context readout uses the session's own window, then the current model's catalog. When resume shrinks an older window, one note explains that the usage itself did not jump.

## 0.1.27 - 2026-10-02

The model menu follows the models installed with Grok.

- Grok 4.7 and Grok 4.7 Fast are listed with 4.6 and 4.5.
- The list is read from Grok's model catalog. A newer model shows up after Grok refreshes that catalog, without an app update.
- The model you pick stays selected for the next send.

## 0.1.26 - 2026-09-26

Opening a long session is faster, and Send now is easier to undo.

- A session log that only grew is replayed from the new tail. Logs larger than 8MB open from the recent end instead of the whole file.
- Plan, diff, and checkpoint files load off the main thread. Grok connects in the background after launch.
- Removing the prompt marked Sending next keeps the rest of the queue. ⌘Return shows the confirm bar before cancelling the turn.
- Send now no longer marks running tools, todos, or background tasks as cancelled.

## 0.1.25 - 2026-09-25

Queued prompts stay under the composer. Send now runs one follow-up next.

- The list shows what will send when this turn finishes. The first row is Next. More than three rows scroll.
- Send now cancels the current turn and runs that follow-up next. That row reads Sending next. Stop still clears the queue.
- Asides wait until the turn finishes and do not interrupt.
- An empty send button no longer starts the queue or stops the turn.

## 0.1.24 - 2026-09-05

Session and project rows in the sidebar are clickable across the whole row, not only the title text.

## 0.1.23 - 2026-09-05

Scrolling the conversation and the live-turn row are quieter.

- Mouse-wheel and trackpad scrolling no longer fight the bottom pin. A short flick away from the latest message releases it; new tokens still follow if you stay at the bottom.
- The row above the composer no longer repeats “Thinking…”. It keeps elapsed time and `[stop]`.

## 0.1.22 - 2026-09-04

The Build window no longer freezes while grok is streaming or reading files.

- Session updates coalesce on the main thread (about 20 UI frames a second). Token chunks no longer rebuild the whole window.
- Streaming replies skip Markdown and link detection until the turn finishes.
- Tool/thought clusters keep a stable identity when new rows append.
- File reads/writes leave the main thread and cap how much is loaded.
- Chat scroll metrics no longer write SwiftUI state on every layout pass.

## 0.1.21 - 2026-09-04

Sending a prompt now shows up immediately, and `/btw` lives in the inspector.

- A sent prompt appears in the transcript right away, with `Received — thinking…` / `已收到，正在思考…` until grok starts answering.
- `/btw` and ⌘⇧B open a Codex-style aside composer in the right sidebar. Side questions stay out of the main thread.
- Drag-select copy on mouse-up works on live streaming text and inside the conversation scroller.

## 0.1.20 - 2026-09-03

Thinking and tool rows now follow Grok Build’s TUI.

- Thought blocks collapse to `Thought for 12.2s` / `思考了 12.2s`, and show `Thinking…` plus the last few lines while they stream.
- Consecutive completed reads and searches fold into `Searched 1 pattern, Read 2 files`, with CLI diamond markers. Shell commands stay as their own `Run …` rows.
- A live turn row sits above the composer: current step, phase timer, elapsed time, context tokens, and `[stop]`.
- Settings can check and install `grok` CLI updates. Queued prompts render in the transcript. Permission mode includes Plan.

## 0.1.19 - 2026-09-01

Grok Build surfaces that were CLI dumps now have native UI.

- Skills page has a Plugins tab: marketplace browse, trust-and-install, enable, disable, uninstall.
- `/memory` lists `~/.grok/memory` files and opens them in the inspector.
- Inspector shows hook timeline, compaction checkpoints with Compact now, clickable subagent transcripts, and `/loop` jobs.
- `/worktree` lists isolated checkouts and can create a git worktree.
- Skill cards toggle `[skills].disabled` and send qualified `/plugin:slug` names.

## 0.1.18 - 2026-08-27

Opening Skills and Connectors no longer stalls the window.

- Catalog load moved off the main thread, with a 90s memory cache and `~/.grok/desktop/catalog-cache.json`.
- Switching back to the page reuses the cache instead of running `grok inspect` again.
- Skill cards render in lazy rows instead of building the whole grid at once.

## 0.1.17 - 2026-08-27

Skills, connectors, workflows, and the inspector now follow what grok actually loads.

- Skills page reads `grok inspect` (user, bundled, and plugin skills), not only `~/.grok/skills`. Clicking a skill sends `/slug`.
- Connectors list inherited Claude/plugin MCP servers. Those are view-only; only grok-native servers can be toggled or removed.
- Add project is a `+` on the Projects header.
- Workflows open on Saved. Creating a script no longer auto-runs. Runs reconcile session `workflows/` folders and live tasks, so stale "running" rows complete.
- Inspector keeps this turn, context, tasks, terminals, and diffs. Workflows and personas left the right rail. Live work is one Now list.

## 0.1.16 - 2026-08-26

- Drag-select or double-click text in a Build conversation copies it and flashes Copied.

## 0.1.15 - 2026-08-24

- Sidebar history groups chats under project folders.
