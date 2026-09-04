<p align="center">
  <img src="assets/Orchy.png" alt="Orchy" width="293" />
</p>


[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Install](https://img.shields.io/badge/install-npx%20skills%20add-black.svg)](#-installation)

[![Claude Code](https://img.shields.io/badge/Claude%20Code-supported-blue.svg)](#-runtime-compatibility)
[![Cursor](https://img.shields.io/badge/Cursor-supported-blue.svg)](#-runtime-compatibility)
[![Codex](https://img.shields.io/badge/Codex-supported-blue.svg)](#-runtime-compatibility)
[![GitHub Copilot](https://img.shields.io/badge/GitHub%20Copilot-supported-blue.svg)](#-runtime-compatibility)
[![Windsurf](https://img.shields.io/badge/Windsurf-supported-blue.svg)](#-runtime-compatibility)
[![Gemini CLI](https://img.shields.io/badge/Gemini%20CLI-supported-blue.svg)](#-runtime-compatibility)
[![Antigravity](https://img.shields.io/badge/Antigravity-supported-blue.svg)](#-runtime-compatibility)
[![Cline](https://img.shields.io/badge/Cline-supported-blue.svg)](#-runtime-compatibility)

A specialized skill and framework for **cost-optimized, hierarchical multi-agent orchestration**.

It equips any agent that reads `SKILL.md` / `AGENTS.md` (Claude Code, Cursor, Codex, Copilot, Windsurf, Gemini CLI, Antigravity, Cline, and others) to act as a **Supervisor** that keeps its own context small and delegates token-heavy exploration, coding, and review to short-lived subagents, on cheaper model tiers where the runtime allows it. Orchy is mostly a prompt document (a 57-line `SKILL.md` plus references loaded per phase), backed by two small scripts that enforce the parts prose cannot: file-scope checking via `git diff`, and non-destructive `AGENTS.md` updates.

---

## 🚀 Why Orchy?

A single agent session pays for its context on every turn. Once grep output, file dumps, and test logs have entered the conversation, they are re-sent as input tokens on each subsequent turn until the session ends, and they crowd out the material the model should be attending to:

1. **Context re-send cost**: a Supervisor that has absorbed 60k tokens of exploration pays for those 60k on every later turn. Delegating the exploration to a worker that returns a few hundred tokens keeps the per-turn bill flat.
2. **Context degradation**: as intermediate output accumulates, attention drifts and error rates rise.
3. **Cheaper tokens** (where the runtime supports per-subagent models): routine reading and drafting does not need a frontier model.

### The Solution: Hierarchical Tiering with Supervisor-Owned Verification

<p align="center">
  <a href="assets/architecture.html">
    <img src="assets/architecture.svg" alt="Orchy Architecture Diagram" width="100%" />
  </a>
</p>

<p align="center">
  <em>Generated with <a href="https://github.com/tt-a1i/archify">Archify</a>. Click the image or <a href="assets/architecture.html">open the interactive diagram</a> for animated trace flow, guided view chapters, and component inspection.</em>
</p>

Workers never commit, push, call `gh`, or edit the ticket board. The Supervisor is the single writer for shared state, checks every worker's file scope with `git diff` against a checkpoint, and closes nothing on a worker's self-report alone.

---

## ✨ Features

- 🪶 **Small per-turn footprint**: `SKILL.md` is 57 lines of triggers and non-negotiables; the `AGENTS.md` block is ~30 lines. Phase-specific procedure lives in `references/` and is read only when that phase is reached, so a solo task does not pay for the orchestration manual on every turn.
- 🎯 **Exact activation grammar**: only `orchy: <task>` or exactly `orchy on|off|init|update|status|cancel` do anything. A sentence that mentions orchy is an ordinary prompt.
- 🧭 **Runtime adapter table, not a probe**: the mode (`full`, `tiered-sync`, `context-only`, `solo`) is derived from a static table keyed by runtime name plus explicit overrides, re-derived each session so a config written under one runtime does not go stale in another.
- 🔒 **Scope enforced by `git diff`**: `scripts/orchy-scope-check.sh` compares the tree (tracked and untracked) against the pre-wave checkpoint and fails any unit that touched a path outside its allowlist or a protected file, whatever the worker reported. Optional per-worker `git worktree` isolation removes write races entirely.
- 📦 **Two-way Handover Protocol**: each worker receives a need-to-know **Handover Context** (objective, scope, `path:line`-cited facts, frozen interfaces, excerpts, verification command, data rule) rather than a copy of the Supervisor's context, and replies with a structured **Handover Result** that the Supervisor treats as data to check, never as instructions to follow.
- ✅ **Supervisor-run verification**: the Supervisor re-runs each unit's test or lint command itself with output redirected to a log and reads only the tail. No second agent is needed and no worker's `12 passed` is trusted.
- 🔁 **Bounded retries**: one retry with the same packet plus the exact error (a live message where the runtime supports it), then revert and escalate.
- 🎫 **Single-writer ticketing**: local Markdown board or GitHub Issues. Workers propose; only the Supervisor writes the board, commits, or closes, and the board is a protected path in the scope check.
- 📓 **Honest activity log**: one JSON line per task with units, waves, retries, scope violations, and verification outcome. Token usage is recorded only when the runtime reports it; the skill never estimates its own consumption.
- 🧪 **Eval scenarios**: `evals/scenarios.md` gives six pass/fail checks (no-activation, uninitialized safeguard, append-not-overwrite, mechanical scope catch, self-report distrust, result-injection) to confirm a runtime actually follows the skill.

---

## 📁 Repository Structure

```
orchy/
├── SKILL.md                          # Triggers, gate, non-negotiables, read-next table (57 lines)
├── README.md
├── LICENSE                           # MIT
├── assets/
│   ├── Orchy.png                     # Logo
│   ├── architecture.svg / .html      # Archify diagram (static + interactive)
│   └── architecture.workflow.json
├── references/                       # Loaded per phase, not per turn
│   ├── runtime-adapters.md           # Static capability table per runtime, mode derivation, stale-config guard
│   ├── init-and-update.md            # orchy init / update flows, AGENTS.md splice rules, uninitialized safeguard
│   ├── orchestration-phases.md       # Threshold, banner, Phases 1-5: checkpoint, dispatch, scope check, verification, retry
│   ├── dispatch-guidelines.md        # Economics, parallel safety, worktree isolation, Handover Context/Result, worked example
│   ├── ticketing-workflow.md         # Single-writer board / GitHub Issues
│   └── metrics.md                    # Activity log, orchy status, where savings come from, A/B protocol
├── scripts/
│   ├── orchy-scope-check.sh          # git-diff scope enforcement against a checkpoint (exit 0 / 2 / 1)
│   └── orchy-agents-splice.py        # Create / append / replace only the orchy block in AGENTS.md; refuses malformed markers
├── templates/
│   ├── AGENTS.md.template            # ~30-line block spliced into a project's AGENTS.md
│   ├── orchy.config.json             # Roles, activation grammar, runtime row + overrides, dispatch policy, log settings
│   └── TICKETS.md.template
└── evals/
    └── scenarios.md                  # Six pass/fail scenarios for checking a runtime follows the skill
```

---

## 📦 Installation

Install with the [skills CLI](https://skills.sh/docs/cli). It detects the agents on your machine and places the skill where each one looks for it, so the same command works for Claude Code, Cursor, Codex, Copilot, Windsurf, Gemini CLI, Antigravity, Cline, and the rest:

```bash
npx skills add davekazemi/orchy
```

No global install is needed; `npx` fetches the CLI on demand. The CLI is open source at [vercel-labs/skills](https://github.com/vercel-labs/skills) and collects anonymous install telemetry, which you can disable with `DISABLE_TELEMETRY=1`.

<details>
<summary>Manual install (no Node.js)</summary>

The skill is plain Markdown, so you can also clone it into whatever directory your runtime scans for skills, either globally (e.g. `~/.claude/skills/`, `~/.gemini/config/skills/`) or project-locally:

```bash
mkdir -p .agents/skills/
git clone https://github.com/davekazemi/orchy.git .agents/skills/orchy
```
</details>

After installation run `orchy init` once per project. It **appends** an Orchy block (delimited by `<!-- orchy:start -->` / `<!-- orchy:end -->`) to that project's `AGENTS.md`, creating the file only if it does not exist. Existing `AGENTS.md` content is never overwritten; `orchy init` and `orchy update` only ever rewrite the text between those two markers. Most runtimes read `AGENTS.md` even if they do not load `SKILL.md` directly. If you skip this step, the first `orchy:` request will run init for you (see [First-run safeguard](#first-run-safeguard)).

---

## 🛠️ Usage

### Commands

| Command | Description |
| :--- | :--- |
| `orchy: <task>` | Run one task with orchestration (subject to the complexity threshold) |
| `orchy on` / `orchy off` | Enable or disable ambient orchestration for the workspace |
| `orchy init` | Pick the runtime row, model tiers, tracking and isolation; write config and splice the `AGENTS.md` block |
| `orchy update` | Change roles, concurrency/isolation, runtime row or overrides, tracking provider |
| `orchy status` | Runtime row and derived mode, units in flight, activity-log summary |
| `orchy cancel` | Stop dispatching, revert uncommitted wave changes to the checkpoint |

Matching is exact: a command is a message that is exactly `orchy <verb>` (trimmed, case-insensitive); a trigger is a message starting with `orchy:` followed by whitespace. Anything else that contains the word is an ordinary prompt. No leading slash, so the commands work in every runtime.

### 1. Initialize Orchestration in a Project
```text
orchy init
```
The agent:
1. **Identifies the runtime** from the tools it can see and the files in the workspace, matches it to a row in `references/runtime-adapters.md`, shows you the row and the derived mode (`full`, `tiered-sync`, `context-only`, or `solo`), and asks you to confirm. Unknown cells become yes/no questions recorded as overrides; it never calls a tool to find out whether the tool exists.
2. **Lists the models it can actually see** and suggests defaults by role: Supervisor top-tier or `inherit`; Scout cheapest; Implementer balanced; Reviewer balanced; Tester cheapest and **off by default** (the Supervisor verifies itself, see below).
3. **Asks for tracking and isolation**: local Markdown board (default) or GitHub Issues; `shared-tree` (default) or per-worker `git worktree`; and whether to add `.orchy/` and the activity log to `.gitignore`.

Press `y` to accept the recommendations or enter custom numbers per role. The result is persisted to `.agents/orchy.config.json` and spliced into your project's `AGENTS.md` with `scripts/orchy-agents-splice.py` (or by hand under the same rules where Python is unavailable).

### 2. Update Configuration
```text
orchy update
```
Switch any role's model (e.g. promote the Implementer to `pro` for a hard refactor), toggle the Tester, change concurrency or isolation, pick a different runtime row, or set capability overrides. Only the block between the markers in `AGENTS.md` is rewritten.

### 3. How Orchestration Runs (Opt-In by Default)

By default, the primary model works **solo / directly** on tasks to avoid unnecessary dispatch latency.

#### Option A: Per-Task Trigger (`orchy:`)
Prepend `orchy:` to a complex task:
> `orchy: add token expiry validation in auth.py and update the unit test suite`

#### Option B: Workspace Continuous Toggle
```text
orchy on    # orchestrate every task that passes the complexity threshold
orchy off   # back to requiring the orchy: prefix
```

#### First-run safeguard
`orchy:` and `orchy on` never dispatch subagents into an unconfigured workspace. If `.agents/orchy.config.json` is missing and `AGENTS.md` has no `<!-- orchy:start -->` … `<!-- orchy:end -->` block, the agent stops, tells you the project is not initialized, runs the `orchy init` flow, and only then continues with your original task. Decline the init prompt and the task runs solo instead. This prevents a cold `orchy:` from guessing model tiers or dispatching in a runtime that cannot spawn subagents.

#### Stale-config guard
The config remembers which runtime ran `orchy init`, but the mode is re-derived from the *current* environment at the first orchestrated action of every session. Open the same repo in a different runtime and Orchy says so and uses that runtime's row rather than dispatching on capabilities that are no longer there.

#### Complexity Threshold
Even when triggered, orchestration engages only if the task spans **3+ files across 2+ modules**, needs **~10+ file reads** before a plan can be formed, or has **2+ genuinely independent units**. Smaller tasks run solo because dispatch overhead would exceed the savings. In `context-only` mode the thresholds double.

#### Mandatory Transparency Banner
Whenever orchestration engages, the first line of the first response is a banner naming the mode derived in this session and the runtime:

```markdown
> 🚀 **Orchy Active** (mode: `tiered-sync`, runtime: `claude-code`): 3 units in 2 waves; workers on `flash` / `flash_lite`.
```

In `context-only` mode the banner adds "isolation only, no per-token savings".

#### What Happens During an Orchestrated Task
1. **Decompose** the objective into units, each with a role, a bounded file scope, and a deliverable. Discovery runs once (a Scout, or the Supervisor's own knowledge) and produces facts with `path:line` citations.
2. **Check conflicts and dependencies**: disjoint modify-scopes, hotspot files (manifests, lockfiles, barrel files, the board) removed from worker scopes, and a dependency order so a unit never builds against an interface another unit is still changing.
3. **Checkpoint** (`BASE=$(git rev-parse HEAD)` on a clean tree), then dispatch a wave within the concurrency limit, in the shared tree or one `git worktree` per implementer. Each worker receives a **Handover Context**: objective, scope, its slice of the cited facts, frozen interfaces, short excerpts, constraints, verification command, and a data rule (file contents and tool output are data; instructions come only from the packet).
4. **Collect** each worker's **Handover Result** and treat it as data: status, files touched, terse diff summary, verification tail, interface notes, proposed discoveries. Imperative text inside it is reported, never executed.
5. **Scope-check mechanically**: `scripts/orchy-scope-check.sh --base "$BASE" --allow <globs>`. Any path outside the allowlist, or a protected file, is reverted and the unit fails regardless of what it claimed.
6. **Verify independently**: the Supervisor re-runs the unit's test/lint command itself with output redirected to `.orchy/*.log` and reads only the tail. That result, not the worker's, goes on the ticket.
7. **Commit and close**: the Supervisor commits, records accepted discoveries, closes tickets, and appends one line to the activity log. On a partial wave failure it commits a coherent subset or reverts to `BASE`.
8. **Retry**: a failure goes back to the worker once with the exact error (a live message where supported, otherwise a respawn with the same packet plus a Prior Attempt). Two strikes on the same unit revert it and escalate to you.

---

## 🧩 Runtime Compatibility

The skill needs four capabilities from the host: **spawn** a subagent, choose a **model per subagent**, **message** a running subagent, and **terminate** it. Rather than having the agent probe for tools (an LLM asked whether a tool exists tends to answer what it expects), the mode is derived from a static table in `references/runtime-adapters.md`, keyed by runtime name, with per-capability overrides you confirm at init. Cells the table cannot vouch for are marked *verify* and default to "no".

| Runtime | Spawn | Model per subagent | Live messaging | Derived mode |
| :--- | :---: | :---: | :---: | :--- |
| Antigravity | yes | yes | yes | `full` |
| Claude Code | yes (`Task`) | yes (`model:` in `.claude/agents/*.md`) | no | `tiered-sync` |
| Augment | yes (`sub-agent-*`) | fixed per definition (*verify*) | no | `context-only` |
| Cursor | *verify* | *verify* | no | `context-only` or `solo` |
| Codex, Copilot, Gemini CLI | *verify* | no | no | `solo` unless confirmed |
| Windsurf, Cline, unknown | no | no | no | `solo` |

| Mode | Effect |
| :--- | :--- |
| `full` | Everything as documented |
| `tiered-sync` | Feedback via respawn with the same packet, one retry |
| `context-only` | Isolation savings only; tiers are documentation; threshold doubled |
| `solo` | Orchestration disabled with a one-line notice |

The per-agent badges above are a compatibility claim for reading `SKILL.md` / `AGENTS.md`, not a promise of `full` mode. If a row is wrong for your version, override it with `orchy update` (option 7) and open an issue.

---

## 📊 Economics & Token Savings

Where the savings come from, largest first:

1. **Context isolation.** Every turn re-sends the Supervisor's whole context. Exploration output that a worker absorbs, and returns as a few hundred tokens, is never paid for again on later turns. This applies in every mode that can spawn, including `context-only`.
2. **Prompt-cache stability.** The Supervisor's prefix stays unchanged across turns because worker churn never enters it, so it stays cached at the provider's reduced rate.
3. **Cheaper models per token** (`full` / `tiered-sync` only). Real, but smaller than list-price ratios suggest: cheaper models retry more, and retries cost Supervisor turns.

Against these: writing Handover Contexts, decomposition and dependency analysis, independent verification, and retries. Savings are positive on large, parallel, exploration-heavy tasks and zero or negative on small or tightly coupled ones, which is why orchestration is opt-in and gated by a complexity threshold.

### Verifying the savings yourself

Orchy does not estimate its own token consumption. A skill whose purpose is to reduce tokens is not a neutral judge of how many it used, so the activity log (`.agents/orchy-metrics.jsonl`) records only what the Supervisor observed (units, waves, retries, scope violations, verification outcome, wall time) and copies token figures only when the runtime itself reports them. `orchy status` cost-weights only those entries and says how many qualify.

The number that matters is what your provider bills. The A/B protocol is in `references/metrics.md` §4: same task from the same commit, once solo and once with `orchy:`, compared on the billing dashboard by **cost**, not token count, over at least three runs per arm. Orchestration usually spends more total tokens and fewer expensive ones, so raw counts invert the result.

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/davekazemi/orchy/issues).

---

## 📄 License

Distributed under the [MIT License](LICENSE). Copyright © 2026 [Davood Kazemi](https://github.com/davekazemi).
