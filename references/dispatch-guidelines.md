# Multi-Agent Dispatch & Context Optimization Guidelines

This guide details the operating mechanics for managing multi-agent teams, optimizing token usage, and avoiding race conditions during execution.

---

## 1. Why Hierarchical Orchestration?

In conventional single-agent sessions, a single LLM:
1. Greps across the codebase (tens of thousands of tokens).
2. Reads whole files (hundreds of lines of context).
3. Executes builds and dumps megabytes of log files.
4. Writes fixes and runs tests again.

### The Problem
* **Token Cost Explosion**: Using top-tier reasoning models (`pro`, Opus-class) for reading static files or log scraping burns costly compute.
* **Context Dilution**: Large context windows slow down response latency and increase the risk of attention drift and hallucinations.
* **Lack of Parallelism**: Sequential workflows take longer to execute.

### The Hierarchical Solution
By appointing a single **Supervisor** and offloading sub-tasks to specialized subagents:
* Top-tier reasoning is reserved exclusively for orchestration and final verification.
* The bulk of token consumption moves to economical models (`flash`, `flash_lite`); the actual share is recorded per task in the metrics ledger.
* The Supervisor maintains a clean context containing only plans, high-level summaries, and verified diffs.

---

## 2. Model Tier Matrix & Economics

| Tier | Typical Models | Relative Cost | Best Used For |
| :--- | :--- | :--- | :--- |
| **Architect / Supervisor** | `pro`, `inherit` | Baseline (1.0x) | Strategic planning, user interaction, complex integration reviews |
| **Coder / Implementer** | `flash` | ~0.15x - 0.25x | Modifying existing functions, writing new modules, refactoring |
| **Scout / Explorer** | `flash_lite` | ~0.05x - 0.10x | Keyword searches, file listing, locating declarations, docs lookup |
| **Tester / Runner** | `flash_lite` | ~0.05x - 0.10x | Running `npm test`, `pytest`, cargo tests, parsing failure logs |

### Break-Even Reality Check
The ratios above are per-token list-price ratios. Real savings are lower because:
* **Cold start**: workers begin with an empty context. If the Supervisor hands over nothing, each worker re-discovers what the Supervisor already knew, and with N workers that cost is paid up to N+1 times. The Handover Context in Section 4 caps this: the Supervisor pays once to write a small packet, and workers start from it instead of from a grep.
* **Retry inflation**: cheaper models fail more often; every correction cycle runs on the Supervisor.
* **Orchestration overhead**: decomposition, dependency analysis, synthesis, and independent re-verification are Supervisor work.

Expect meaningful savings on large, genuinely parallel tasks; expect zero or negative savings on small or tightly coupled ones. Apply the complexity threshold in `SKILL.md` before dispatching.

### Measuring Instead of Assuming
Do not quote the table above as evidence. The Supervisor appends a per-task entry to `.agents/orchy-metrics.jsonl` (per-role token usage, retries, verification result, and whether the counts were runtime-reported or estimated), and `orchy status` summarizes it. The authoritative check is an A/B run: same task from the same commit, once solo and once with `orchy:`, compared on the provider's billing dashboard with tokens weighted by each model's price. Orchestration typically spends more total tokens and fewer expensive ones, so an unweighted token count will understate or invert the result. See `SKILL.md` Section 7.

---

## 3. Parallel Dispatch Rules

### The Non-Overlapping Invariant
When dispatching multiple subagents simultaneously via the runtime's spawn primitive:
* **Rule**: Parallel subagents must operate on non-overlapping file sets.
* **Reason**: Subagents share one working tree. If two subagents edit the same file concurrently, the last write silently overwrites the previous write without git merge conflict detection.

Disjoint paths are necessary but not sufficient. The following checks also apply.

### Shared Hotspot Files
Some files are touched by almost every task and defeat partitioning: package manifests and lockfiles, barrel/`index` files, route registries, DI containers, migrations, generated code, and `.agents/TICKETS.md`. For each hotspot either:
* serialize every unit that touches it, or
* remove it from all worker scopes and have the Supervisor apply the single combined edit after the wave finishes.

The default hotspot list lives in `dispatchPolicy.sharedHotspotFiles` in `orchy.config.json`.

### Logical Dependencies (Dependency Order)
Two units can be on disjoint paths and still break each other: Agent A changes a signature in `src/api/`, Agent B writes tests in `tests/` against the old one, both report SUCCESS, and integration fails.
1. Before dispatch, list the interfaces, types, and signatures each unit **produces** and **consumes**.
2. If B consumes what A produces, either run B in a later wave, or write the exact new contract into both prompts (**interface freeze**) so both sides implement against the same definition.
3. Only units with no unresolved edges are dispatched in the same wave.

### Git Is Single-Writer
All workers share one index. Concurrent `git add`/`commit` on the same working tree collide even when the edited files are disjoint. Workers never run `git add`, `git commit`, `git push`, or `gh`. The Supervisor checkpoints before a wave (clean tree, or recorded HEAD / `git stash`) and commits after independent verification.

### Scope Partitioning Patterns
1. **Vertical Slices by Layer**:
   * Agent 1 (Backend API): `src/api/*`, `src/controllers/*`
   * Agent 2 (Frontend UI): `src/components/*`, `src/styles/*`
   * Agent 3 (Tests): `tests/unit/*`, `tests/integration/*`
   * Note: layer slices almost always carry a dependency edge (API → tests). Freeze the interface or run tests in a second wave.
2. **Horizontal Slices by Module**:
   * Agent 1: `modules/auth/`
   * Agent 2: `modules/billing/`
   * Agent 3: `modules/notifications/`
   * Module slices are the safer default for parallelism; they rarely share contracts.

### Concurrency & Rate Limits
`maxConcurrentSubagents` is an upper bound, not a target. Parallel workers on one provider share a rate limit; if throttling appears, halve concurrency. Two unthrottled workers finish sooner than four throttled ones.

---

## 4. Handover Protocol (Context In, Result Out)

Every dispatch is a two-way handover. The Supervisor sends a **Handover Context** down; the worker sends a **Handover Result** back. Both are bounded, structured packets. Neither side ever transfers its full conversation.

### 4.1 Why Not Hand Over the Supervisor's Whole Context
Workers do not inherit the Supervisor's context, and they should not receive a copy of it either:
* Most of it is irrelevant to any single unit of work (other units' scopes, user conversation, prior waves, ticket history). Sending it costs input tokens on every worker and dilutes the instructions that matter.
* It leaks scope: a worker that sees the whole plan is more likely to "helpfully" edit files outside its unit, which breaks the disjoint-file invariant.
* It does not remove cold start, it moves it: the worker still has to search a large blob to find its task.

The rule is **need-to-know**: a worker receives exactly what it needs to do its unit without re-discovery, and nothing that belongs to another unit. A well-formed Handover Context is typically a few hundred to a couple of thousand tokens.

### 4.2 Handover Context (Supervisor → Worker)
Build one packet per worker. Sections marked *required* must always be present; omit optional sections rather than filling them with filler.

````markdown
## Handover Context
- **Objective** (required): One or two sentences. What "done" means for this unit, not for the whole task.
- **Role & Tier**: scout | implementer | tester | reviewer, and the model tier it runs on.
- **Scope** (required):
  - May modify: `src/api/auth.py`
  - May read: `src/api/`, `tests/test_auth.py`, `src/models/user.py`
  - Must not touch: anything else, `.agents/TICKETS.md`, git, `gh`
- **Known Facts** (required if a Scout ran): The findings this unit needs, already resolved. Paths, symbol names and signatures, where the relevant tests live, project conventions (formatter, import style, test runner). Paste them; do not tell the worker to go find them.
- **Frozen Interfaces**: Any type, signature, or contract this unit must implement against, verbatim (from Phase 2 interface freeze). Mark as "do not change".
- **Relevant Excerpts**: Short verbatim snippets (with path and line range) the worker will otherwise have to open first. Prefer 10-40 lines of the exact function over "see file X".
- **Constraints**: Non-obvious rules: no new dependencies, keep backward compatibility, do not rename public symbols, etc.
- **Verification** (required for implementer/tester): The exact command(s) to run and the expected pass condition.
- **Prior Attempt** (retry only): The previous Handover Result and the exact error, verbatim. Nothing else about the history.
- **Return** (required): "Reply with a Handover Result (format below). Do not include exploration logs, full files, or full terminal output."
````

Rules for building it:
* **One Scout, many consumers.** Run discovery once (Scout, or the Supervisor's own knowledge) and fan the relevant slice of the findings out to each worker. Never make N implementers each locate the same symbol.
* **Slice by unit, not by task.** Two workers on the same task should receive different Known Facts and Relevant Excerpts. Shared items (conventions, frozen interfaces) may be repeated; unit-specific items must not cross.
* **Excerpts beat pointers.** A path with a line range costs the worker a read; the excerpt itself costs nothing extra. Include the excerpt when the worker will certainly need it, the pointer when it might.
* **Do not include**: the user's original conversation, other units' scopes or progress, ticket board contents, earlier waves' results (except the Prior Attempt on retry), or the Supervisor's reasoning about the decomposition.
* **Size check**: if the packet is approaching the size of the files the worker would read anyway, the unit is probably too large or the excerpts are too generous. Split the unit or trim to pointers.

### 4.3 Handover Result (Worker → Supervisor)
The worker's only output to the Supervisor. It must never contain raw files or unrestricted terminal output.

````markdown
## Handover Result: [Role Name]
- **Status**: [SUCCESS | FAILED | BLOCKED]
- **Files Touched**:
  - `path/to/fileA` (MODIFIED: +12, -4)
  - `path/to/fileB` (NEW)
- **Diff Summary**: 2-3 sentences. What changed and why, at the level of functions and behaviour, not lines.
- **Verification Evidence**:
  - Command: `pytest tests/test_auth.py`
  - Raw output (last 20 lines, verbatim, not paraphrased):
    ```
    ...
    4 passed, 0 failed in 0.42s
    ```
- **Interface Notes**: Anything a sibling unit or the Supervisor must know to integrate: new exports, changed signatures, new env vars or config keys. "None" if none.
- **Proposed Discoveries**: Out-of-scope issues found. Title + one-line note each. Do NOT edit `.agents/TICKETS.md`.
- **Blockers / Questions**: Decisions needed from the Supervisor. Only present when Status is FAILED or BLOCKED, or when a genuine ambiguity was resolved by assumption (state the assumption).
- **Usage** (if the runtime exposes it): input/output tokens consumed, for the metrics ledger.
````

Rules for consuming it:
* The Supervisor reads the Handover Result and **nothing else** from the worker. Exploration logs, intermediate tool output, and reasoning are discarded, not skimmed.
* `Files Touched` is checked against the `Scope` that was handed over. Any file outside scope is a contract violation: revert that file and treat the unit as FAILED, regardless of Status.
* `Interface Notes` are propagated into the Handover Context of any dependent unit in the next wave.
* `Verification Evidence` is an input to Section 4.4, not a conclusion.

### 4.4 Self-Reports Are Claims, Not Evidence
A worker's `Status: SUCCESS` and pasted test summary are inputs to verification, not a substitute for it. Before committing or closing a ticket the Supervisor re-runs the verification command itself, or dispatches a fresh Tester that has not seen the claimed result. Only the independently observed result is recorded on the ticket.

---

## 5. Subagent Error Recovery & Feedback Loop

When a subagent reports a test failure or code syntax issue:
1. **Do not switch to manual implementation immediately**: The Supervisor should first return the exact error to the worker:
   ```text
   The test 'test_token_expiry' failed with:
   AssertionError: expected 3600, got 0.
   Please inspect line 42 of src/auth/token.py and correct the expiry calculation.
   ```
   * With live messaging (`full` mode): message the existing subagent directly.
   * Without live messaging (`tiered-sync` / `context-only`): respawn a fresh worker with the **same Handover Context** plus a `Prior Attempt` section holding the previous Handover Result and the exact error. Because the packet is reused, the retry costs the packet size again, not a fresh discovery. Allow only one such retry.
2. **Two-Strike Rule**: If a subagent fails verification twice on the same step, stop dispatching for that unit (terminate it where the runtime offers a kill primitive) and:
   * Escalate to the human user for clarification.
   * Re-decompose into smaller sub-steps only if the user agrees.
3. **Partial Wave Failure**: If some units of a wave succeed and one fails, commit the successful subset only if it is independently coherent (builds, tests pass, no dangling references to the failed unit). Otherwise revert to the pre-wave checkpoint and re-plan.

---

## 6. Runtime Capability Fallbacks

This document describes capabilities (spawn, per-subagent model, message, terminate), not a specific runtime's tool names. Runtimes differ, and most lack live messaging and per-subagent model selection. Probe before dispatching and pick a mode:

| Mode | Available | Effect |
| :--- | :--- | :--- |
| `full` | spawn + per-role model + live messaging | This document applies as written. |
| `tiered-sync` | spawn + per-role model | Feedback via respawn-with-context, one retry max. |
| `context-only` | spawn only | Context isolation only, no cost savings. Orchestrate only large tasks. |
| `solo` | nothing | Orchestration disabled; say so and proceed directly. |

Record the mode in `runtime.detectedMode` and state it in the activation banner.
