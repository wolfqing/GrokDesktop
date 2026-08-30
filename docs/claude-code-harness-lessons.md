# Claude Code harness lessons for Grok Desktop

Research date: 2026-08-25  
Baseline: Claude Code **v2.1.88** sourcemap leak (2026-03-31) plus later public prompt extracts (Piebald through v2.1.246).  
Grok Desktop baseline: `main` at v0.1.15 (`c0e30d7`).

This note is product research, not a source dump. It does not reproduce leaked TypeScript, system prompts, classifier templates, or internal flags.

Related: [Grok Build feature gap](build-feature-gap.md) — inventory of TUI/CLI surfaces Desktop has not shipped as first-class UI (v0.1.18).

## What leaked, and what it actually proves

On 2026-03-31, `@anthropic-ai/claude-code@2.1.88` shipped a ~60 MB `cli.js.map`. That exposed the **client harness** (~1,900 TypeScript files, ~512K lines): agent loop, tools, permissions, compaction, hooks, subagents, session persistence. Model weights were not involved.

Independent analyses converge on one number: **~1.6% of the codebase is AI decision logic; ~98.4% is deterministic infrastructure.** The loop is a ReAct `while (tool_call)` generator. The product is everything around it.

Primary public sources:

- VILA-Lab, *Dive into Claude Code*, arXiv:2604.14228 — 7 components, 13 principles, 5 compaction stages, 7 safety layers
- cablate/claude-code-research — 12 transferable harness principles from v2.1.88
- Piebald-AI/claude-code-system-prompts — prompt/tool inventory across later versions
- Community write-ups of query loop, cache boundary, and permission pipeline

**Harness formula (cablate):** `Tools + Knowledge + Observation + Action interfaces + Permissions`

## Grok Desktop's place in that architecture

Grok Desktop is **not** Claude Code. It is a native SwiftUI client:

- Chat embeds grok.com
- Build talks to the local `grok` CLI over ACP
- Sessions, skills, config, and transcripts live in `~/.grok`

The query loop, tool execution, sandbox, and most compaction already belong to **grok CLI**. Desktop should not grow a second agent runtime.

The Mac app's job is the layer Claude Code had to squeeze into Ink: **make the harness visible, interruptible, and trustworthy**. A native inspector can show permission provenance, compaction checkpoints, subagent trees, memory files, and hook timelines in ways a TUI cannot.

ACP already carries more harness signal than the UI uses:

| Event / RPC already in Desktop | Current UI |
|---|---|
| `auto_compact_started` / `completed`, `compaction_checkpoint` | One orange "Context compacted" chip + short recap |
| `subagent_spawned` / `finished` | Inspector list; no child transcript |
| `hook_execution`, `hooks_changed` | Slash commands only |
| `plan`, plan-review questions | Question card exists; not a first-class plan surface |
| `x.ai/rewind`, `x.ai/compact_conversation` | Commands exist; no timeline of checkpoints |
| Permission request + session remember | Allow once / this session / deny |
| AgentMode: ask / plan / auto / always-approve | Composer cycle + Settings string |
| Context breakdown (messages / reasoning / tools / free) | Inspector pie, coarse |
| Todos, terminals, diffs, workflows | Inspector panes, reasonably strong |

## What Claude Code got right

### 1. One loop, thick OS

All surfaces (CLI, SDK, IDE) share one `queryLoop`. Settings, context assembly, five cheap-to-expensive shapers, model call, tool dispatch, permission gate, execute, stop.

Desktop already follows this: one ACP client, many views. Keep it that way. Do not add a Desktop-side planner DAG.

### 2. Context is a pipeline, not a truncate

Before every model call, Claude Code runs cheapest first:

1. Budget reduction (per-message caps)
2. Snip older history
3. Microcompact (cache-aware)
4. Context collapse (read-time projection, non-destructive)
5. Auto-compact (model summary, last resort)

Grok CLI already has `/compact` and `auto_compact_threshold_percent` (Desktop settings default 85%). Desktop only shows a boolean + 3-line recap. The leak's lesson for a GUI is: **compaction is a user-visible object**, with before/after tokens, what was kept, and a way back (`compaction_checkpoint`).

### 3. Deny-first, graduated trust, never restore on resume

Claude Code modes: `plan` → `default` → `acceptEdits` → `auto` (ML classifier) → `dontAsk` → `bypassPermissions`. Deny always beats allow. Session permissions are **not** restored on resume.

Desktop already has four live modes (`AgentMode`) and a settings string (`ask` / `auto` / `always-approve`). Gaps:

- Settings menu does not include **plan**, while the composer does
- `remember_tool_approvals` can persist trust across sessions; Claude Code refused this for a reason
- Permission bar does not say **why** (rule / mode / hook / classifier / session)
- No reversibility weighting: file edit, network, and `rm -rf` look the same

Approval fatigue (Claude saw ~93% prompt-approval) was fixed by **restructuring boundaries**, not more dialogs. Desktop's "Allow edits this session" is the right shape. Expand that pattern (edits vs network vs destructive) instead of adding more buttons.

### 4. Subagents isolate context; skills do not

- **SkillTool**: inject into current window (cheap)
- **AgentTool**: new window (~7× tokens, parent only gets a summary)
- Isolation: in-process (default), git worktree, remote
- Each child writes its own JSONL; POSIX `flock` for multi-instance

Desktop tracks spawn/finish and shows type/status/elapsed. It does **not** open the child transcript, show isolation mode, or keep parent chat free of child tool spam. `/worktree` is a slash builtin with no session UI.

### 5. Messages are typed objects, not strings

Claude Code tags messages: meta (hidden from user), virtual (display-only), compact summary, tool-result pairing, origin. That split is how they hide harness chatter without losing auditability.

Desktop's `ConversationItem` is already typed (user / agent / tool / notice / …). Use that more aggressively: compaction summaries, hook traces, and permission decisions should be **inspectable notices**, not dumped as assistant prose.

### 6. Errors are instructions to the model

Denied tools and cancelled actions return text that tells the model to stop, not to jailbreak around the deny. When grok CLI emits those, Desktop should surface a short human line ("denied, waiting for you") and keep the model-facing text out of the chat bubble.

### 7. File-based memory, not a vector DB

CLAUDE.md hierarchy: managed → user → project → local (gitignored). Memory files are scanned by header, max ~5 loaded. Users can open, edit, and commit them.

Grok already has `/memory`, `/remember`, `/dream`, and `memory.enabled` in config. Desktop settings only expose an on/off toggle. Inspector should list the actual files.

### 8. Extensibility has a cost ladder

Hooks (zero context) → Skills (low) → Plugins (medium) → MCP (high). Three injection points: assemble / model / execute.

Desktop already catalogs skills, MCP, agents, workflows, and hook slash commands. Missing: a **hook timeline** (`hook_execution` is already an ACP event) and a clear Skill vs Agent explanation in the Agents sheet.

### 9. Prompt-cache stability is a product constraint

Static prefix (identity, tools, rules) vs dynamic suffix (date, git status, CLAUDE.md) split at an explicit boundary. Sticky latches keep cache keys from flapping mid-session. Tool lists are never sorted. Deferred tools (`ToolSearch`) keep schemas out of the prefix until discovered.

Desktop implication: **do not reshuffle MCP/tool order, session metadata, or mode flags** on every turn. If the CLI adds deferred tools, show "discovered" vs "available" in the inspector.

### 10. Observation is part of the harness

Claude Code invested heavily in statusline, turn telemetry, and permission-decision provenance (`rule` / `hook` / `mode` / `classifier`). Desktop already has `TurnNarrative`, dock badges, and notifications. Next step is provenance and a live cost/context/git strip, not a mascot.

## Already in Grok Desktop — do not rebuild

Keep and polish these; they already match the leak's "thick OS" shape:

- ACP as the single execution engine
- Permission bar + Question / plan-review cards
- Inspector: context slices, todos, terminals, diffs, workflows
- Session index grouped by project folder
- `/compact`, `/rewind`, `/plan`, `/worktree`, `/hooks`, `/memory`, `/loop`, `/goal`
- Subagent and todo fold into session snapshots
- Attention notifications when a session needs the user
- File-based config at `~/.grok/config.toml`

## Recommended borrows (Desktop-shaped)

Priority is **user-visible harness**, not copying Claude's prompt text.

### P0 — high leverage on the Mac UI

1. **Permission provenance + reversibility**
   - Show source: session / config / hook / mode
   - Split "Allow edits this session" from network and destructive shell
   - Align Settings `permission_mode` with composer modes (include Plan)
   - Default: do not restore session-only approvals on resume

2. **Compaction as an object**
   - Expand recap; list `compaction_checkpoint`s
   - Inspector: tokens before/after, what layer fired
   - One-click `/compact` from the context pane when free window is low
   - If CLI supports it, restore or inspect a checkpoint (pairs with existing rewind)

3. **Subagent = child session**
   - Click a subagent to open its transcript, not a two-line status
   - Badge isolation: in-process vs worktree
   - Parent chat keeps the summary; child tools stay in the child
   - Dashboard already counts running subagents — drill in from there

### P1 — make CLI features the UI already knows about

4. **Memory files in the inspector** — list `~/.grok` memory / `AGENTS.md` / project instructions; open in Finder or preview
5. **Hook timeline** — render `hook_execution` as a pane (event, blocked?, duration)
6. **Skill vs Agent copy** — Agents sheet should say: skill = this chat; agent = isolated child
7. **Worktree sessions** — create / switch isolated checkouts from the project header, not only `/worktree`
8. **Plan surface** — plan-review card is good; persist the plan in the inspector for the whole turn, not only while the question is up
9. **Denied / cancelled as a notice** — "stopped, waiting for you", not a failed tool dump

### P2 — only if grok CLI grows the matching ACP

10. Deferred tool search visibility
11. Streaming tool execution (start tools as they stream)
12. Classifier auto-mode: show "auto allowed because …" or do not ship a silent classifier
13. Coordinator / swarm: Desktop can host a team board; do not fake it in Swift

## What not to copy

- Length caps like "≤25 words between tools" (A/B token trick; hostile in a desktop chat)
- Undercover / employee stealth, fake tools, anti-distillation
- Buddy pet, KAIROS always-on agent, UltraPlan as marketing flags
- Reimplementing the query loop, Bash AST validators, or the ML permission classifier in Swift
- Blind persistence of "always allow" across app relaunch
- Pasting Claude system prompts into Grok

## Suggested implementation order

If we pick this up in product work:

1. Permission provenance + mode alignment (Settings ↔ composer, no new RPC)
2. Compaction checkpoint UI on events Desktop already parses
3. Subagent drill-in using `child_session_id` already stored on `AgentSubagent`
4. Memory / hooks inspector panes on existing catalogs and ACP events

That sequence is UI-only against current ACP. Anything after that needs a grok CLI change.

## References

- [VILA-Lab/Dive-into-Claude-Code](https://github.com/VILA-Lab/Dive-into-Claude-Code) / [arXiv:2604.14228](https://arxiv.org/abs/2604.14228)
- [cablate/claude-code-research](https://github.com/cablate/claude-code-research) — especially `phase-09-harness-engineering/07-harness-design-principles.md`
- [Piebald-AI/claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts)
- Anthropic statement on the 2026-03-31 packaging issue: client source only, no customer data
