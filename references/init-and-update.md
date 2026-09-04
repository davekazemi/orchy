# `orchy init` and `orchy update`

Both commands are run by the Supervisor in conversation with the user. Neither dispatches a subagent. Read `runtime-adapters.md` first.

---

## 1. `orchy init`

### Step 0: Runtime
Follow `runtime-adapters.md` §2: match the runtime, confirm with the user, record `runtime.name` and any overrides, derive the mode. If the mode is `solo`, say so, still offer to write the config (so `orchy:` degrades gracefully instead of erroring), and skip Step 1.

### Step 1: Model tiers by capability
Available models differ per runtime, so never assume fixed names. Match each role's capability requirement to whatever the runtime exposes:

| Role | Needs | Volume | Tier |
| :--- | :--- | :--- | :--- |
| **Supervisor** | Planning, decomposition, dependency analysis, verification, user alignment | Low (orchestration only) | Top-tier reasoning (`inherit` is acceptable) |
| **Scout** | Fast read, grep, symbol lookup; read-only | Highest | Cheapest available |
| **Implementer** | Precise scoped code edits that follow conventions | Moderate | Balanced coding model |
| **Reviewer** | Spec and standards critique of a diff | Moderate | Balanced reasoning model |
| **Tester** (disabled by default) | Run a command, summarize a log | High, routine | Cheapest available |

Verification is done by the Supervisor itself with output redirected to a file (`orchestration-phases.md` Phase 4), which is why the Tester role is off by default. Enable it only where a runtime cannot redirect output.

Present a numbered menu and smart defaults; accept `y` or per-role numbers. If the runtime has no per-subagent model selection, show a single line instead: "This runtime runs all subagents on the session model; tiers are recorded for documentation only."

```text
Configuring Orchy roles (runtime: claude-code, mode: tiered-sync)
Available models:
 [1] <top-tier reasoning model exposed by this runtime>
 [2] <balanced model exposed by this runtime>
 [3] <lightweight model exposed by this runtime>
 [4] inherit (session model)

Recommended: Supervisor [4]  Implementer [2]  Scout [3]  Reviewer [2]  Tester [3, disabled]
Type y to accept, or e.g. "Implementer: 1, Scout: 2".
```

### Step 2: Tracking and hygiene
```text
Task tracking:
 [1] Local Markdown board  .agents/TICKETS.md   (default, offline)
 [2] GitHub Issues via gh
Worker isolation:
 [1] shared-tree   workers edit the main checkout; scope enforced by scripts/orchy-scope-check.sh   (default)
 [2] worktree      one git worktree per implementer under .orchy/wt/; requires subagents that accept a working directory
Add ".orchy/" and ".agents/orchy-metrics.jsonl" to .gitignore?  [Y/n]
```

### Step 3: Persist
1. Write `.agents/orchy.config.json` from `templates/orchy.config.json` with the choices above. Set `version` from the template.
2. Render `templates/AGENTS.md.template` (fill the `{{...}}` placeholders) and splice it into the workspace `AGENTS.md`:
   * Preferred: `python3 scripts/orchy-agents-splice.py --target AGENTS.md --block-file <rendered>` (run `--dry-run` first and show the diff when the file already exists).
   * Without Python, apply the same rules by hand: create the file if absent; **append** the block after one blank line if the markers are absent; replace only the text between `<!-- orchy:start -->` and `<!-- orchy:end -->` inclusive if both are present; if exactly one marker is present, stop and ask.
   * Never rewrite, reformat, or reorder anything outside the markers.
3. If tracking is Markdown and `.agents/TICKETS.md` does not exist, create it from `templates/TICKETS.md.template`. Never overwrite an existing board.
4. For `claude-code`, write one subagent file per enabled role into `.claude/agents/` with the chosen `model:` (skip files that already exist and say so).
5. Report the saved configuration in a short table. Do not report an estimated savings figure; there is no measurement yet.

---

## 2. `orchy update`

1. Read `.agents/orchy.config.json`. If it is missing but `AGENTS.md` has the block, rebuild the config from the block's values first.
2. Show the current mapping and mode as a table.
3. Ask which item to change: `(1) Supervisor (2) Scout (3) Implementer (4) Reviewer (5) Tester on/off (6) Concurrency and isolation (7) Runtime row / overrides (8) Tracking provider`.
4. Apply the change to the config, re-render the block, and splice it exactly as in init Step 3.2. Nothing outside the markers changes.
5. If the runtime row changed, re-derive the mode and print it.

---

## 3. Uninitialized Workspace

`orchy:` and `orchy on` require either `.agents/orchy.config.json` (parseable) or an `AGENTS.md` block with both markers. If neither is present:
1. Say: "Orchy is not initialized in this workspace. Running `orchy init` first."
2. Run Sections 1.0 to 1.3 above. Do not guess tiers, do not assume a mode, do not spawn anything before persisting.
3. If the mode is `solo` or the user declines, run the original request directly and say so.
4. Otherwise resume the original request under the complexity threshold and banner rules in `orchestration-phases.md`.

A config that fails to parse is treated as absent. A block without a config is rebuilt into a config without re-prompting.
