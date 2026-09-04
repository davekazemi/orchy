---
name: orchy
description: Hierarchical cost-optimized agent orchestration skill. Sets up a Supervisor agent with lightweight tiered subagents (Scout, Implementer, Tester, Reviewer) using flash/flash_lite models. Provides runtime capability detection with fallback modes, interactive init and update workflows, task decomposition, dependency-ordered non-conflicting dispatch, independent verification of subagent claims, context window pruning, and single-writer Git/GitHub ticketing integration.
---

# orchy: Cost & Context Optimization Skill

This skill organizes agent workflows into a **Hierarchical Supervisor-Subagent architecture**. The primary conversational agent acts as the **Supervisor** (focusing on high-level reasoning, planning, synthesis, and user alignment), while delegating code exploration, drafting, testing, and review to specialized, cost-effective subagent tiers (`flash` and `flash_lite`).

---

## Capabilities & Commands

Command / Trigger | Description
:--- | :---
`orchy: <task>` | **Per-Task Trigger**: Runs the given task with multi-agent orchestration (e.g. `orchy: add oauth auth`).
`orchy on` | **Workspace Toggle**: Activates continuous ambient orchestration for all complex tasks without needing the `orchy:` prefix.
`orchy off` | **Workspace Toggle**: Reverts to default opt-in mode (orchestration only triggers when prefixed with `orchy:`).
`orchy cancel` | **Abort In-Flight**: Immediately terminates all running subagents and restores manual control.
`orchy init` | Interactive onboarding: configures model tiers, tracking mode, and writes settings to `AGENTS.md`.
`orchy update` | Re-configures role-to-model assignments and execution policies without manual edits.
`orchy status` | Inspects currently active subagents, detected runtime mode, and the token/cost ledger summary (see Section 7).

All commands are plain chat messages beginning with the word `orchy` (no leading slash), so they work in any runtime regardless of whether it supports slash commands. `orchy:` (with a colon) followed by a task is the per-task trigger; `orchy <verb>` is a command.

> [!NOTE]
> **Default Behavior**: By default, the main model executes tasks **solo / directly**. Multi-agent orchestration only engages when triggered via the `orchy:` prefix or when the workspace toggle is turned `orchy on`.

> [!IMPORTANT]
> **Uninitialized workspace safeguard**: `orchy:` and `orchy on` require a configured workspace. If `.agents/orchy.config.json` is absent and `AGENTS.md` contains no `<!-- orchy:start -->` block, do not dispatch anything. Run the `orchy init` flow first (Section 2), then resume the original request. Details in Section 4.

---

## 1. Runtime Capability Detection & Fallback Modes

The dispatch mechanics below are written against Antigravity tool names (`invoke_subagent`, `send_message`, `manage_subagents`). Other runtimes expose different, often weaker, primitives. Before the first dispatch of a session, and during `orchy init`, the agent MUST determine which primitives actually exist and select a fallback mode. Never assume a tool is present because this document names it.

| Capability | Antigravity | Typical Equivalent Elsewhere | Behavior If Absent |
| :--- | :--- | :--- | :--- |
| **Spawn subagent** | `invoke_subagent` | Claude Code `Task`, Cursor background agents, Augment `sub-agent-*` | Orchestration cannot engage. Run solo and say so. |
| **Per-subagent model selection** | `Model` field | Frequently unavailable | Tiering is impossible; delegation still isolates context but saves no cost. Warn the user and raise the complexity threshold. |
| **Message a running subagent** | `send_message` | Usually absent (subagents are synchronous and stateless) | Feedback = respawn a fresh worker with the same Handover Context plus the prior Handover Result and exact error. Each retry re-pays the packet. |
| **Terminate subagent** | `manage_subagents(Action='kill')` | Usually absent | Two-strike rule = stop dispatching and escalate. |
| **Parallel dispatch** | Multiple `Subagents` entries | Parallel tool calls | Dispatch sequentially. |

### Fallback Modes

| Mode | Conditions | What Changes |
| :--- | :--- | :--- |
| `full` | Spawn + per-role models + live messaging | Everything in this document applies as written. |
| `tiered-sync` | Spawn + per-role models, no live messaging | Feedback loop uses respawn-with-context; cap retries at 1 before escalating. |
| `context-only` | Spawn only, single model | Delegate for context isolation only. Orchestrate only large tasks (double the complexity threshold); expect no cost savings. |
| `solo` | No spawn primitive | Orchestration disabled. `orchy:` prints a one-line notice and proceeds directly. |

Record the detected mode in `.agents/orchy.config.json` under `runtime.detectedMode` and name it in the activation banner.

---

## 2. Initialization Workflow (`orchy init`)

When the user runs `orchy init` (or asks to set up agent orchestration):

### Step 0: Runtime Capability Probe
Run the capability detection from Section 1 and record `runtime.capabilities` and `runtime.detectedMode`. If the mode is `solo`, stop here and report that orchestration is unavailable in this runtime.

### Step 1: Dynamic Model Discovery & Capability Matching
The skill is platform-neutral and functions across **Antigravity**, **Cursor**, **Claude Code**, and custom agent runners. Because available models differ across environments, the agent does NOT assume fixed model names.

Instead, the agent determines recommendations by matching each role's **Capability Requirements** against the runtime's available model tiers:

| Role | Capability Requirement | Token Velocity & Cost | Recommended Tier |
| :--- | :--- | :--- | :--- |
| **Supervisor** | **High Reasoning & Planning**: Needs planning mode, macro decomposition, dependency analysis, independent verification, user alignment. | Low token volume (orchestration only) | **Top-tier Reasoning** (e.g. `pro`, Opus/Pro-class) |
| **Codebase Scout** | **Fast Read & Symbol Search**: Greps patterns, reads files, discovers dependencies. Pure read-only. | Highest token volume (~50-80% of session) | **Ultra-lightweight / Cheap** (e.g. `flash_lite`, Haiku, mini) |
| **Implementer** | **Precise Code Synthesis**: Edits functions, writes scoped modules, preserves conventions. | Moderate token volume | **Fast Balanced Coding** (e.g. `flash`, Sonnet-class, mini) |
| **Tester / QA** | **CLI Execution & Log Parsing**: Executes test suites, linters, parses build error traces. | High volume, routine logs | **Ultra-lightweight / Cheap** (e.g. `flash_lite`, Haiku, mini) |
| **Reviewer** | **Spec & Standards Critique**: Verifies against specs, flags anti-patterns and smells. | Moderate token volume | **Fast Balanced Reasoning** (e.g. `flash`, Sonnet) |

### Step 2: Interactive Numbered Selection
1. The agent inspects or lists the models available in the current environment (e.g., options 1 through N).
2. The agent auto-selects its **recommended smart defaults** based on the criteria above, but displays the numbered menu so the user has full control:

```text
Configuring Agent Orchestration Roles:
Available Models in this environment:
 [1] <top-tier reasoning model exposed by this runtime> (Pro / Opus-class)
 [2] <balanced model exposed by this runtime> (Flash / Sonnet-class)
 [3] <lightweight model exposed by this runtime> (Flash-Lite / Haiku-class)
 [4] inherit (Match active session model)

Smart Recommended Setup:
 • Supervisor: [1] Top-tier (or [4] inherit)
 • Implementer: [2] Balanced
 • Scout / Explorer: [3] Ultra-light
 • Tester / QA: [3] Ultra-light
 • Reviewer: [2] Balanced

Type 'y' to accept these defaults, or enter custom numbers (e.g. "Supervisor: 1, Implementer: 2...").

Ticketing & Task Tracking Preference:
 [1] Local Markdown (.agents/TICKETS.md - self-contained, offline-ready, zero network overhead) [Recommended Default]
 [2] GitHub Issues (Sync with remote repository issue tracker via 'gh' CLI)
```

### Step 3: Persist Configuration
1. Record choices in `.agents/orchy.config.json` with the selected model names, capability requirements, and the detected runtime mode.
2. In the target workspace's `AGENTS.md` (creating it if absent):
   * Look for existing `<!-- orchy:start -->` marker.
   * Inject or update the orchestration matrix using `templates/AGENTS.md.template`.
3. Report the saved configuration back to the user with an estimated token efficiency summary.

---

## 3. Reconfiguration Workflow (`orchy update`)

When the user triggers `orchy update`:
1. Read the current configuration from `.agents/orchy.config.json` or `AGENTS.md`.
2. Present the current mapping in a clear table.
3. Prompt the user: "Which role would you like to update? (1) Supervisor, (2) Scout, (3) Implementer, (4) Tester, (5) Reviewer, (6) Parallelism limits, (7) Runtime capability overrides / re-probe".
4. Update `.agents/orchy.config.json` and refresh the section in `AGENTS.md`.

---

## 4. Activation Conditions, Visibility Banner & Task Decomposition

### Activation Conditions (Opt-In by Default)
To ensure the primary model handles normal tasks directly without unwanted subagent overhead, orchestration runs **only** when one of these conditions is met:

1. **Per-Task Trigger (`orchy:`)**: The user prefixes their prompt with `orchy:`, for example:
   > `orchy: add rate limiting middleware and write tests`
2. **Workspace Toggle (`orchy on`)**: The user has explicitly turned orchestration on for the workspace. (Can be reverted anytime with `orchy off`).

### Uninitialized Workspace Safeguard
Before acting on either trigger, check that the workspace is configured:
* `.agents/orchy.config.json` exists, **or**
* `AGENTS.md` contains a `<!-- orchy:start -->` block.

If neither is present, the workspace has never been initialized. Do **not** guess model tiers, do not assume a runtime mode, and do not spawn subagents. Instead:
1. Tell the user: "Orchestration is not initialized in this workspace. Running `orchy init` first."
2. Run the full init flow from Section 2 (capability probe, model menu, ticketing choice, persist).
3. If the probe returns `solo`, or the user declines the init prompts, execute the original request directly and say so.
4. Otherwise resume the original request with orchestration, applying the complexity threshold and banner as normal.

Treat a `.agents/orchy.config.json` that fails to parse the same as absent. If `AGENTS.md` has the block but the config file is missing, rebuild the config from the block's values and continue without re-prompting.

> [!IMPORTANT]
> **Mandatory Activation Banner**:
> Whenever orchestration is engaged, the agent **MUST prepend an alert banner at the very top of its initial response**:
> ```markdown
> > [!NOTE]
> > 🚀 **Orchestration Active** (mode: `full`): Multi-agent delegation engaged. Sub-tasks assigned to tiered models per `AGENTS.md`.
> ```
> The banner names the detected runtime mode. In `context-only` mode it must also state "no cost savings expected".
> This provides immediate visual transparency so the user always knows whether subagents are running and under which guarantees.

When activated, the Supervisor applies the **Task Complexity Threshold**. Orchestrate only when at least one condition holds:
* Expected edits span **3+ files across 2+ modules or layers** (e.g. API + UI + tests).
* Exploration is expected to exceed roughly **10 file reads or broad greps** before a plan can be formed.
* The task contains **2+ independent units** that can genuinely run in parallel after dependency analysis (Phase 2).

Otherwise handle the task directly: for small tasks, decomposition, writing a Handover Context for each worker, and synthesis cost more Supervisor tokens than they save. In `context-only` mode, double these thresholds.

Complex tasks are decomposed into the phases below:

### Phase 1: Task Decomposition
1. Break down the user's objective into distinct, isolated units of work.
2. For each unit, assign:
   * A designated role (`scout`, `implementer`, `tester`, `reviewer`).
   * A bounded set of file paths / directories.
   * An expected deliverable (e.g. "Report on symbol callers", "Write unit test in `tests/test_x.py`").

### Phase 2: Conflict & Dependency Verification (Safety Invariant)
> [!IMPORTANT]
> Never spawn two concurrent subagents that modify the same file.
> Parallel subagents must target strictly disjoint file paths. Disjoint paths are necessary but **not sufficient**; the checks below must also pass.

1. **File disjointness**
   * Sub-task A modifies `src/api/routes.py` and Sub-task B modifies `src/api/routes.py` → **execute sequentially**.
   * Sub-task A modifies `src/api/` and Sub-task B modifies `tests/` → passes this check; continue to 2 and 3.
2. **Shared hotspot files**: package manifests and lockfiles, barrel/`index` files, route registries, DI containers, migrations, generated files, and `.agents/TICKETS.md` are touched by many tasks. Either serialize every unit that touches one, or exclude the hotspot from all worker scopes and let the Supervisor apply that edit once after the workers finish.
3. **Logical dependencies**: build a dependency order before dispatch. If unit B consumes an interface, type, or signature that unit A changes, then either B runs after A, or the new contract is written into both prompts verbatim (an **interface freeze**) so both sides implement against the same definition. Only units with no unresolved edges run in the same wave.
4. **Git is single-writer**: all workers share one working tree and one index. Workers never run `git add`, `git commit`, `git push`, or `gh`. The Supervisor performs these after the wave is verified.

### Phase 3: Subagent Dispatch (`invoke_subagent` or runtime equivalent)

Before dispatching a wave:
1. **Checkpoint**: require a clean working tree, or record HEAD / `git stash` so a failed wave can be reverted as a unit.
2. **Concurrency**: respect `dispatchPolicy.maxConcurrentSubagents`, and lower it if the provider rate-limits; four throttled workers are slower than two that are not.
3. **Handover Context**: workers start with an empty context and must **not** be given a copy of the Supervisor's. Build one need-to-know packet per worker (format in `references/dispatch-guidelines.md` Section 4.2): objective for this unit only, scope (may modify / may read / must not touch), Known Facts resolved by the Scout, frozen interfaces verbatim, short verbatim excerpts of the code it will certainly open, constraints, the exact verification command, and the instruction to reply with a Handover Result. Discovery is done once and its relevant slice fanned out; no worker should re-grep for something the Supervisor or Scout already located. Leave out the user conversation, other units' scopes, ticket contents, and previous waves.

Use the configured model tiers where the runtime supports them. Each `Prompt` is a Handover Context:

```json
{
  "Subagents": [
    {
      "TypeName": "self",
      "Role": "Backend Implementer",
      "Model": "flash",
      "Prompt": "## Handover Context\n- Objective: add a POST /auth/login endpoint that validates credentials and returns a JWT.\n- Role & Tier: implementer, flash.\n- Scope: may modify src/api/auth.py; may read src/api/, src/models/user.py, tests/test_auth.py; must not touch anything else, .agents/TICKETS.md, git, or gh.\n- Known Facts: routes are registered with @router.post in src/api/*.py; User model is src/models/user.py:User with verify_password(plain) -> bool; JWT helper is src/core/security.py:create_access_token(sub: str, expires_minutes: int) -> str; tests use pytest + httpx AsyncClient fixture 'client' from tests/conftest.py.\n- Frozen Interfaces (do not change): response body {\"access_token\": str, \"token_type\": \"bearer\"}; request body {\"email\": str, \"password\": str}.\n- Relevant Excerpts: src/api/users.py lines 12-31 (existing router pattern): <paste>.\n- Constraints: no new dependencies; return 401 on bad credentials, not 400.\n- Verification: pytest tests/test_auth.py -q ; all tests must pass.\n- Return: reply with a Handover Result only (status, files touched, diff summary, verification command + last 20 raw output lines, interface notes, proposed discoveries, blockers). No exploration logs, no full files."
    },
    {
      "TypeName": "self",
      "Role": "Frontend Implementer",
      "Model": "flash",
      "Prompt": "## Handover Context\n- Objective: build the login form component and wire it to the login API.\n- Role & Tier: implementer, flash.\n- Scope: may modify src/components/Login.tsx; may read src/components/, src/api/client.ts; must not touch anything else, .agents/TICKETS.md, git, or gh.\n- Known Facts: API client is src/api/client.ts:post(path, body); components use function components + Tailwind; lint is 'npm run lint'.\n- Frozen Interfaces (do not change): POST /auth/login accepts {email, password} and returns {access_token, token_type}.\n- Relevant Excerpts: src/components/Signup.tsx lines 1-40 (form pattern to mirror): <paste>.\n- Constraints: no new dependencies; no global state changes.\n- Verification: npm run lint ; exit 0.\n- Return: reply with a Handover Result only (status, files touched, diff summary, verification command + last 20 raw output lines, interface notes, proposed discoveries, blockers). No exploration logs, no full files."
    }
  ]
}
```

### Phase 4: Handover Result, Independent Verification & Synthesis
The Supervisor consumes only the worker's **Handover Result** (format in `references/dispatch-guidelines.md` Section 4.3):
1. **Discard Intermediate Noise**: The Supervisor does not read or retain the subagent's step-by-step exploration logs, tool output, or reasoning. If the runtime returns them, skip to the Handover Result.
2. **Accept Only the Handover Result**, which must contain:
   * Status (`SUCCESS` / `FAILED` / `BLOCKED`)
   * Files touched, checked against the handed-over Scope; any out-of-scope file is reverted and the unit is treated as FAILED
   * Terse diff summary
   * Verification command and the **last ~20 lines of its raw output** (not a paraphrase)
   * Interface notes (new exports, changed signatures, new config keys), which are copied into the Handover Context of dependent units in the next wave
   * Proposed discoveries (out-of-scope issues found; see Section 5)
   * Token usage, if the runtime exposes it, for the metrics ledger (Section 7)
3. **Treat self-reports as claims, not evidence**: a `flash_lite` worker reporting `12 passed` can be wrong. Before closing a ticket or committing, the Supervisor re-runs the verification command itself (or dispatches a fresh Tester that has not seen the claimed result) and compares. Only the independent run counts.
4. **Supervisor Integration Review**: The Supervisor inspects the combined diff as a coherent whole, ensuring naming consistency and interface compatibility across units, especially at any interface-freeze boundary from Phase 2.

### Phase 5: Feedback, Error Correction & Partial Failure
If a subagent's work fails verification or produces errors:
1. Do not rewrite the code directly in the Supervisor's context.
2. Send targeted feedback to the worker:
   * In `full` mode, use `send_message` to the existing subagent with the exact test failure or lint error and the specific file/line to fix.
   * Without live messaging, respawn a fresh worker with the **same Handover Context** plus a `Prior Attempt` section containing the previous Handover Result and the exact error. Reusing the packet means the retry costs the packet again, not a fresh discovery; still cap it at one retry.
3. If the worker fails twice on the same step, stop dispatching for that unit and ask the human user for guidance. Re-decompose only if the user agrees.
4. **Partial wave failure**: if some units of a wave succeed and one fails, do not commit the successful subset unless it is independently coherent (builds, tests pass, no dangling references to the failed unit). Otherwise revert to the Phase 3 checkpoint and re-plan.

---

## 5. Ticketing & Task Tracking Integration

The orchestrator supports two interchangeable tracking modes configured during `orchy init`.

> [!IMPORTANT]
> **Single-Writer Rule**: only the Supervisor writes to `.agents/TICKETS.md` and `.agents/orchy-metrics.jsonl`, runs `git commit`/`push`, or calls `gh`. Subagents *propose* discoveries and closures inside their Handover Result; they never mutate the board or repository history. A shared board edited by parallel workers is the same write race the disjoint-file invariant exists to prevent.

### Option A: Local Markdown Tracker (`.agents/TICKETS.md`) [Default]
Ideal for local projects, offline work, or repositories without remote issue trackers.

1. **Board Structure**: `.agents/TICKETS.md` contains sections for `🟢 Open Tickets`, `🟡 In Progress`, `🟣 Subagent Discoveries`, and `🏁 Closed Tickets`.
2. **Supervisor Creation**: When decomposing a macro task, the Supervisor appends ticket entries:
   ```markdown
   - [ ] **#T-001: Implement Password Reset Endpoint**
     - **Role**: `implementer` (Model: `flash`)
     - **Scope**: `src/auth/reset.py`, `src/api/routes.py`
     - **Depends on**: —
     - **Objective**: Create reset token generation and endpoint logic.
   ```
3. **Subagent Discoveries (proposed, not written)**:
   * If a worker finds an unanticipated dependency or bug outside its scope, it does **not** expand scope and does **not** edit the board. It lists the item under `Proposed Discoveries` in its Handover Result.
   * The Supervisor records accepted discoveries under `🟣 Subagent Discoveries`:
     ```markdown
     - [ ] **#T-002: Missing email SMTP client configuration (found by #T-001)**
       - **Reported by**: `implementer` (`flash`)
       - **Note**: `src/services/mailer.py` throws unhandled ConnectionError.
     ```
4. **Closure by Supervisor after independent verification**:
   * Once the Supervisor has re-run verification (Phase 4, step 3) and committed, it updates `.agents/TICKETS.md`:
     * Moves the item to `🏁 Closed Tickets` and marks the checkbox `[x]`.
     * Appends the resolution summary, the independently observed test result, and the commit hash:
     ```markdown
     - [x] **#T-001: Implement Password Reset Endpoint**
       - **Resolution**: Added reset token generation and verification endpoint.
       - **Verified**: `pytest tests/test_reset.py` re-run by Supervisor → `5 passed, 0 failed`
       - **Commit**: `a1b2c3d` | **Implemented by**: `implementer` (`flash`)
     ```

---

### Option B: Remote GitHub Issues (`gh` CLI)
Ideal for collaborative teams and open-source projects. All `gh` and `git` commands are executed by the Supervisor.

1. **Ticket Creation**: Major milestones are created as GitHub issues labeled `orchy:task` via `gh issue create`.
2. **Branching**: For multi-step implementations, create a branch `feature/issue-<id>` before dispatching workers.
3. **Closing**: Once the Supervisor has independently verified the combined diff and test output, commit the changes, push, and close the issue via `gh issue close <id> --comment "Resolved; verification re-run by supervisor."`.

---

## 6. Cross-Platform Model Tier Guidelines & Economics

Model names below are illustrative classes, not a list to trust verbatim; use whatever the runtime actually exposes at init time.

| Role | Antigravity Tier | Equivalent Class Elsewhere | Token Cost Ratio (indicative) | Best Used For |
| :--- | :--- | :--- | :--- | :--- |
| **Supervisor / Architect** | `inherit` or `pro` | Opus / Pro / frontier-class | 1.0x (Baseline) | System design, user consultation, dependency analysis, diff reviews, independent verification |
| **Implementer / Coder** | `flash` | Sonnet / mid-tier coding class | ~0.15x - 0.25x | Scoped feature implementation, targeted refactors, boilerplate |
| **Scout / Explorer** | `flash_lite` | Haiku / mini class | ~0.05x - 0.10x | Grep searches, reading source files, tracing symbol references |
| **Tester / QA** | `flash_lite` or `flash` | Haiku / mini class | ~0.05x - 0.15x | Running test suites, interpreting compiler errors, checking linters |
| **Reviewer** | `flash` | Sonnet / mid-tier class | ~0.15x - 0.25x | Checking coding standards, detecting code smells, verifying specs |

### Break-Even Reality Check
Per-token ratios overstate real savings. Three costs are paid on top of them:
* **Cold start**: every worker begins empty. The Handover Context (Phase 3) bounds this to the cost of writing and sending one small packet per worker instead of a full re-discovery, but the packet is not free and a worker that still has to search re-pays the exploration.
* **Retry inflation**: cheaper models need more iterations and more correction cycles, and the correction cycles run on the expensive Supervisor.
* **Orchestration overhead**: decomposition, dependency analysis, synthesis, and independent verification all run on the Supervisor.

Net savings are meaningful on large, genuinely parallel tasks and can be zero or negative on small or tightly coupled ones. This is why orchestration is opt-in, gated by the complexity threshold, and restricted to large tasks in `context-only` mode.

---

## 7. Measuring & Verifying Savings

The ratios in Section 6 are assumptions. The Supervisor records what actually happened so the user can check them.

### Metrics Ledger (`.agents/orchy-metrics.jsonl`)
After every orchestrated task (and every solo task when `metrics.recordSoloBaseline` is true), the Supervisor appends exactly one JSON line. The Supervisor is the only writer, consistent with Section 5. Fields:

```json
{"ts":"2026-09-04T10:12:00Z","task":"add token expiry validation","mode":"full","orchestrated":true,
 "wallSeconds":412,"waves":2,"retries":1,"verifiedIndependently":true,"outcome":"SUCCESS",
 "usage":{"supervisor":{"model":"pro","in":18400,"out":3100},
          "scout":{"model":"flash_lite","in":42000,"out":2600},
          "implementer":{"model":"flash","in":31000,"out":5400},
          "tester":{"model":"flash_lite","in":12000,"out":900}},
 "source":"runtime_usage_api"}
```

Rules for populating `usage`:
* Prefer token counts the runtime reports (per-subagent usage, `manage_subagents` stats, or the equivalent). Set `source` to `runtime_usage_api`.
* If the runtime exposes nothing, estimate as `ceil(characters / 4)` over each prompt sent and each result received, and set `source` to `estimated`. Never present an estimate as measured.
* If a role was never dispatched, omit it rather than writing zeros.
* Record the solo baseline the same way, with `orchestrated: false` and a single `supervisor` entry.

### `orchy status` Summary
When invoked, read the ledger and report:
* Total tokens per model and the share consumed on non-Supervisor tiers.
* Cost-weighted total using `metrics.pricing` from the config (per-million input/output prices per model). If pricing is unset, print raw tokens and say cost weighting is unavailable.
* Retry rate and independent-verification pass rate.
* If solo baselines exist, the median cost-weighted total for orchestrated vs. solo tasks, with the sample sizes. Below three samples per group, state that the comparison is not yet meaningful.
* The proportion of entries with `source: estimated`, so the user knows how much of the summary is measured.

### Verification Protocol the Supervisor Should Suggest
When the user asks whether orchestration is saving anything, do not answer from the ratio table. Recommend the A/B protocol: same task, same starting commit, once solo and once with `orchy:`, comparing the provider's billing or usage dashboard before and after each run. Point out that orchestration typically spends more *total* tokens and fewer *expensive* tokens, so only a cost-weighted comparison is valid, and that a single sample proves nothing. The billing dashboard is the ground truth; if it disagrees with the ledger by more than ~20%, the ledger's `source` for that runtime should be treated as unreliable.

