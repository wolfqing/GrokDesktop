# Grok Build features Desktop has not shipped as first-class UI

Research date: 2026-08-30  
Grok Desktop baseline: `main` at v0.1.18 (`e7ccadd`).  
Sources: `~/.grok/docs/user-guide/` (27 guides), `grok --help` and subcommands, Desktop `AppModel.handleCommand`, Settings, Skills, Automations, Dashboard, Inspector.

This is a product inventory, not a build plan. Desktop is an ACP client for the local `grok` CLI. The query loop, tools, sandbox, and most compaction already live in grok. Desktop should not grow a second agent runtime. The question is which Build surfaces deserve a native window versus a slash that already reaches the CLI.

Related: [Claude Code harness lessons](claude-code-harness-lessons.md) (visibility of the same harness).

## How to read the gap

Three buckets:

1. **Aligned** — Desktop already has a native surface, or the slash opens that surface.
2. **TUI / CLI only** — do not port. Terminal chrome, headless SDK, Grove, fleet config.
3. **Pass-through or missing UI** — grok already does the work; Desktop either dumps CLI text or never draws the ACP event.

Pass-through means the feature *works* if you type the slash. It is not a first-class Mac UI.

## Already aligned

| Build | Desktop |
| --- | --- |
| New / resume / continue / history / rename / delete / export / copy reply / fork / rewind | Matching UI or slash |
| Find, timeline, jump to latest | `/find` `/timeline` `/jump` |
| `/compact`, auto-compact at 85% | Command + Settings threshold; orange “Context compacted” chip |
| Model / effort; Ask / Plan / Auto / always-approve | Composer + `Shift+Tab` |
| Permission bar, question cards, plan approve / request changes | Present; inspector reads `plan.md` |
| Prompt queue, `/btw` asides | Composer queue |
| `@` files, paste / attach images | Composer |
| Copy-on-select | 0.1.16 |
| Skills catalog, click sends `/slug`, new-skill draft | Skills page via `grok inspect` (0.1.17–0.1.18) |
| MCP add (stdio / http / sse), toggle, doctor | Connectors + Settings |
| Workflows Saved / Runs, pause / resume / stop | Left Automations |
| Agents / Personas | Sheet |
| Live agents: dispatch, open, stop, approvals | Dashboard |
| `/imagine`, `/imagine-video` | Imagine page |
| Login, usage, docs, tutorial, shortcuts, feedback | Settings / Help |
| Sandbox profile, memory on/off, codebase indexing | Settings → Agent |

Desktop-only (not in the TUI): grok.com Chat embed, sidebar history grouped by project folder, Imagine recents library, native inspector + file preview, macOS attention notifications.

## Do not port (TUI / CLI)

Desktop already flashes “That command is terminal-only” for `/vim-mode`, `/minimal`, `/fullscreen`, `/edit-prompt`, `/expand`.

Leave with the CLI:

- TUI themes: GrokNight, TokyoNight, RosePine, Oscura (Desktop is system light / dark only)
- Status line, `pager.toml`, vim scrollback keys, `Ctrl+E` thought-fold
- `/doctor` terminal / tmux / clipboard / microphone checks
- `grok -p` headless, `grok agent serve` WebSocket, `grok wrap`, `grok leader`, `grok completions`, `grok setup`, `grok trace`
- `grok clone` (Grove NFS / FUSE lazy clone; gated on Grove config)
- Enterprise MDM / `requirements.toml` / external OpenTelemetry

## Pass-through: slash exists, no native product

| Command | What Desktop does today | What Build actually ships |
| --- | --- | --- |
| `/marketplace` | `grok plugin marketplace list` text dump | Extensions modal: browse, install, trust |
| `/plugins` with args | `grok plugin …` | Install / trust / enable / disable / component inventory |
| `/plugins` bare | Settings → Extensions, **name list** | Same modal as marketplace |
| `/hooks*` | Settings → Extensions, hook **filenames** | Editor, per-hook toggle, folder trust |
| `/worktree` | `grok worktree list` (or extra args) dump | Isolated checkouts; create / switch / gc; resume `--restore-code` |
| `/inspect` | Last 40 **ACP events** | `grok inspect`: effective config, skills, MCP, LSP |
| `/doctor` `/du` `/models` `/update` | CLI text sheet | TUI doctor / disk / model table / upgrade |
| `/memory` (no `on`/`off`) | Settings → Agent memory toggle | Browse `~/.grok/memory/` files |
| `/loop` `/goal` `/deep-research` `/remember` `/flush` `/dream` | Prefix or **send the slash to the agent** | Scheduler, goal state machine, research workflow pane |
| `/workflow runs` | Automations overlay JSON + session `workflows/` scan | Live Runs: phase, child roster, budget, pause / resume |
| Skill card click | Always `/{slug}` | Qualified `/local:`, `/user:`, `/plugin:`; `[skills].disabled` keeps a skill listed but inert |
| `/import-claude` | Import MCP only; rest “ask Grok” | Permissions, env, hooks, paths |

`/inspect` in Desktop is misnamed relative to the CLI: it is an ACP event log, not `grok inspect`.

## Missing first-class UI

ACP already delivers unused signal: `hook_execution`, `compaction_checkpoint`. Subagent spawn / finish is listed; the child transcript is not opened.

### High leverage

1. **Plugin marketplace + trust** — browse sources, `install --trust`, enable / disable, show bundled skills / MCP / hooks. Today: CLI dump.
2. **Memory file browser** — list `~/.grok/memory/MEMORY.md` and per-project dirs; open / edit. Today: boolean only. Grok memory is markdown files, not a vector DB.
3. **Hook timeline + editor** — render `hook_execution` (blocked?, duration); add / remove; trust project hooks. Today: filename list.
4. **Compaction as an object** — checkpoint list, tokens before / after, what was kept; one-click `/compact` from the context pane. Today: one chip + short recap.
5. **Subagent = child session** — open the child transcript; badge isolation (in-process vs worktree); parent chat keeps the summary. Today: type / status / elapsed.
6. **Permission provenance** — say why a call was allowed: session / config / hook / mode / classifier. Settings omit `acceptEdits` and `dontAsk`. Composer has Plan; the Settings permission menu does not.

### Medium

7. **Worktree sessions** — create / switch isolated checkouts from the project header. CLI also has show / rm / gc / detach / salvage.
8. **Skill disable + qualified names** — `[skills].disabled`; collisions as `/local:commit`. A skill named `compact` currently still hits the builtin.
9. **Scheduler / goal / deep-research** — `/loop` job list and cancel (7-day expiry); `/goal` status / pause / resume / clear (composer only prefixes `/goal` today); deep-research progress tied to workflow runs.
10. **Workflow Runs dashboard** — phase, child roster, remaining `agent_budget`, budget-limited resume rules. Overlay can pause / stop; it is not the live TUI pane.
11. **Custom models** — `[model.*]`, `api_backend`, self-hosted endpoints. Fast / Auto / Expert / Heavy only map the built-in `BuildModel` enum.
12. **Plan surface** — line comments; keep the plan in the inspector for the whole turn after the approve card dismisses. Approve / request-changes already exist; TUI `c` comments do not.
13. **Live Dashboard extras** — TUI peek, pin, reply without opening, Inactive sessions owned by other processes. Desktop: Open / Stop.

### Low / wait for matching ACP

14. LSP (`~/.grok/lsp.json`, `.grok/lsp.json`, plugin LSP; `features.lsp_tools` defaults off)
15. Folder trust (hooks / MCP / LSP share `~/.grok/trusted_folders.toml`)
16. Permission allow / ask / deny rule editor
17. Custom sandbox profiles + deny globs (UI today: off / workspace / read-only / strict)
18. `AGENTS.md` / `.grok/rules` editor
19. Effective-config view: real `grok inspect --json` (do not reuse the ACP-event sheet name)
20. MCP env / OAuth credential UI
21. Send a running foreground command to background (`Ctrl+B` in the TUI)
22. Claude import of permissions / hooks / env, not only MCP
23. Privacy / ZDR team admin (`/privacy` only opens Data controls)
24. Thought-block fold, collapsed edit blocks, grouped tool verbs (TUI density)

## Suggested next wave

If the goal is “Desktop is not a thinner TUI,” draw what is already on disk or on the ACP wire. Do not copy terminal chrome.

1. Plugin marketplace + trust
2. Memory files
3. Hook timeline
4. Compaction checkpoints
5. Subagent transcripts
6. Worktree / skill disable / `/loop` scheduler

Skip: vim mode, fullscreen / minimal, status line, Grove clone, headless SDK, OTEL, tmux doctor.
