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
* 80–90% of token consumption occurs on economical models (`flash`, `flash_lite`).
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
* **Cold start**: each worker re-reads context the Supervisor already had. With N workers, discovery cost is paid up to N+1 times.
* **Retry inflation**: cheaper models fail more often; every correction cycle runs on the Supervisor.
* **Orchestration overhead**: decomposition, dependency analysis, synthesis, and independent re-verification are Supervisor work.

Expect meaningful savings on large, genuinely parallel tasks; expect zero or negative savings on small or tightly coupled ones. Apply the complexity threshold in `SKILL.md` before dispatching.

---

## 3. Parallel Dispatch Rules

### The Non-Overlapping Invariant
When dispatching multiple subagents simultaneously via `invoke_subagent` (or the runtime equivalent):
* **Rule**: Parallel subagents must operate on non-overlapping file sets.
* **Reason**: Subagents share one working tree. If two subagents edit the same file concurrently, the last write silently overwrites the previous write without git merge conflict detection.

Disjoint paths are necessary but not sufficient. The following checks also apply.

### Shared Hotspot Files
Some files are touched by almost every task and defeat partitioning: package manifests and lockfiles, barrel/`index` files, route registries, DI containers, migrations, generated code, and `.agents/TICKETS.md`. For each hotspot either:
* serialize every unit that touches it, or
* remove it from all worker scopes and have the Supervisor apply the single combined edit after the wave finishes.

The default hotspot list lives in `dispatchPolicy.sharedHotspotFiles` in `orchestration.config.json`.

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

## 4. Context Compression Protocol

Subagents must never dump raw files or unrestricted terminal output back to the Supervisor.

### Standard Subagent Return Contract
When a subagent completes its task, it must format its response with the following concise structure:

````markdown
### Subagent Result: [Role Name]
- **Status**: [SUCCESS | FAILED | BLOCKED]
- **Target Files**:
  - `path/to/fileA` (MODIFIED: +12, -4)
  - `path/to/fileB` (NEW)
- **Summary**: Concise 2-3 sentence description of the change or findings.
- **Verification Evidence**:
  - Test command: `pytest tests/test_auth.py`
  - Raw output (last 20 lines, verbatim, not paraphrased):
    ```
    ...
    4 passed, 0 failed in 0.42s
    ```
- **Proposed Discoveries**: Out-of-scope issues found. Title + one-line note each. Do NOT edit `.agents/TICKETS.md`.
- **Blockers / Notes**: Any follow-up decisions needed from Supervisor.
````

### Self-Reports Are Claims, Not Evidence
A worker's `Status: SUCCESS` and pasted test summary are inputs to verification, not a substitute for it. Before committing or closing a ticket the Supervisor re-runs the verification command itself, or dispatches a fresh Tester that has not seen the claimed result. Only the independently observed result is recorded on the ticket.

### Cold-Start Handoff
Workers do not inherit the Supervisor's context. Paste the specific Scout findings a worker needs (file paths, symbol names, conventions, the frozen interface) into its prompt. A worker that has to rediscover this re-pays the exploration cost the orchestration was meant to save.

---

## 5. Subagent Error Recovery & Feedback Loop

When a subagent reports a test failure or code syntax issue:
1. **Do not switch to manual implementation immediately**: The Supervisor should first return the exact error to the worker:
   ```text
   The test 'test_token_expiry' failed with:
   AssertionError: expected 3600, got 0.
   Please inspect line 42 of src/auth/token.py and correct the expiry calculation.
   ```
   * With live messaging (`full` mode): `send_message` to the existing subagent.
   * Without live messaging (`tiered-sync` / `context-only`): respawn a fresh worker whose prompt contains the previous result contract, the exact error, and the identical scope. This re-pays cold start, so allow only one such retry.
2. **Two-Strike Rule**: If a subagent fails verification twice on the same step, stop dispatching for that unit (terminate it with `manage_subagents(Action='kill')` where available) and:
   * Escalate to the human user for clarification.
   * Re-decompose into smaller sub-steps only if the user agrees.
3. **Partial Wave Failure**: If some units of a wave succeed and one fails, commit the successful subset only if it is independently coherent (builds, tests pass, no dangling references to the failed unit). Otherwise revert to the pre-wave checkpoint and re-plan.

---

## 6. Runtime Capability Fallbacks

The tool names in this document are Antigravity's. Other runtimes differ, and most lack live messaging and per-subagent model selection. Probe before dispatching and pick a mode:

| Mode | Available | Effect |
| :--- | :--- | :--- |
| `full` | spawn + per-role model + live messaging | This document applies as written. |
| `tiered-sync` | spawn + per-role model | Feedback via respawn-with-context, one retry max. |
| `context-only` | spawn only | Context isolation only, no cost savings. Orchestrate only large tasks. |
| `solo` | nothing | Orchestration disabled; say so and proceed directly. |

Record the mode in `runtime.detectedMode` and state it in the activation banner.
