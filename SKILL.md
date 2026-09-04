---
name: agent-orchestrator
description: Hierarchical cost-optimized agent orchestration skill. Sets up a Supervisor agent with lightweight tiered subagents (Scout, Implementer, Tester, Reviewer) using flash/flash_lite models. Provides interactive init and update workflows, task decomposition, parallel non-conflicting dispatch, context window pruning, and Git/GitHub ticketing integration.
---

# Agent Orchestrator: Cost & Context Optimization Skill

This skill organizes agent workflows into a **Hierarchical Supervisor-Subagent architecture**. The primary conversational agent acts as the **Supervisor** (focusing on high-level reasoning, planning, synthesis, and user alignment), while delegating code exploration, drafting, testing, and review to specialized, cost-effective subagent tiers (`flash` and `flash_lite`).

---

## Capabilities & Commands

Command / Trigger | Description
:--- | :---
`orch: <task>` | **Per-Task Trigger**: Runs the given task with multi-agent orchestration (e.g. `orch: add oauth auth`).
`/orchestrate on` | **Workspace Toggle**: Activates continuous ambient orchestration for all complex tasks without needing the `orch:` prefix.
`/orchestrate off` | **Workspace Toggle**: Reverts to default opt-in mode (orchestration only triggers when prefixed with `orch:`).
`/orchestrate cancel` | **Abort In-Flight**: Immediately terminates all running subagents and restores manual control.
`/orchestrate init` | Interactive onboarding: configures model tiers, tracking mode, and writes settings to `AGENTS.md`.
`/orchestrate update` | Re-configures role-to-model assignments and execution policies without manual edits.
`/orchestrate status` | Inspects currently active subagents, background tasks, and token efficiency statistics.

> [!NOTE]
> **Default Behavior**: By default, the main model executes tasks **solo / directly**. Multi-agent orchestration only engages when triggered via the `orch:` prefix or when the workspace toggle is turned `/orchestrate on`.

---

## 1. Initialization Workflow (`/orchestrate init`)

When the user runs `/orchestrate init` (or asks to set up agent orchestration):

### Step 1: Dynamic Model Discovery & Capability Matching
The skill is platform-neutral and functions across **Antigravity**, **Cursor**, **Claude Code**, and custom agent runners. Because available models differ across environments, the agent does NOT assume fixed model names.

Instead, the agent determines recommendations by matching each role's **Capability Requirements** against the runtime's available model tiers:

| Role | Capability Requirement | Token Velocity & Cost | Recommended Tier |
| :--- | :--- | :--- | :--- |
| **Supervisor** | **High Reasoning & Planning**: Needs planning mode, macro decomposition, conflict detection, user alignment. | Low token volume (orchestration only) | **Top-tier Reasoning** (e.g. `pro`, Claude 3.7 Sonnet, GPT-4o) |
| **Codebase Scout** | **Fast Read & Symbol Search**: Greps patterns, reads files, discovers dependencies. Pure read-only. | Highest token volume (~50-80% of session) | **Ultra-lightweight / Cheap** (e.g. `flash_lite`, Haiku, mini) |
| **Implementer** | **Precise Code Synthesis**: Edits functions, writes scoped modules, preserves conventions. | Moderate token volume | **Fast Balanced Coding** (e.g. `flash`, Sonnet, GPT-4o-mini) |
| **Tester / QA** | **CLI Execution & Log Parsing**: Executes test suites, linters, parses build error traces. | High volume, routine logs | **Ultra-lightweight / Cheap** (e.g. `flash_lite`, Haiku, mini) |
| **Reviewer** | **Spec & Standards Critique**: Verifies against specs, flags anti-patterns and smells. | Moderate token volume | **Fast Balanced Reasoning** (e.g. `flash`, Sonnet) |

### Step 2: Interactive Numbered Selection
1. The agent inspects or lists the models available in the current environment (e.g., options 1 through N).
2. The agent auto-selects its **recommended smart defaults** based on the criteria above, but displays the numbered menu so the user has full control:

```text
Configuring Agent Orchestration Roles:
Available Models in this environment:
 [1] Gemini 3.8 Pro / Claude 3.7 Sonnet (Top-tier reasoning)
 [2] Gemini 3.8 Flash / Claude 3.5 Sonnet (Balanced speed & code generation)
 [3] Gemini 3.8 Flash-Lite / Claude 3.5 Haiku (Ultra-fast, lowest cost)
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
1. Record choices in `.agents/orchestration.config.json` with the selected model names and capability requirements.
2. In the target workspace's `AGENTS.md` (creating it if absent):
   * Look for existing `<!-- agent-orchestration:start -->` marker.
   * Inject or update the orchestration matrix using `templates/AGENTS.md.template`.
3. Report the saved configuration back to the user with an estimated token efficiency summary.

---

## 2. Reconfiguration Workflow (`/orchestrate update`)

When the user triggers `/orchestrate update`:
1. Read the current configuration from `.agents/orchestration.config.json` or `AGENTS.md`.
2. Present the current mapping in a clear table.
3. Prompt the user: "Which role would you like to update? (1) Supervisor, (2) Scout, (3) Implementer, (4) Tester, (5) Reviewer, (6) Parallelism limits".
4. Update `.agents/orchestration.config.json` and refresh the section in `AGENTS.md`.

---

## 3. Activation Conditions, Visibility Banner & Task Decomposition

### Activation Conditions (Opt-In by Default)
To ensure the primary model handles normal tasks directly without unwanted subagent overhead, orchestration runs **only** when one of these conditions is met:

1. **Per-Task Trigger (`orch:`)**: The user prefixes their prompt with `orch:`, for example:
   > `orch: add rate limiting middleware and write tests`
2. **Workspace Toggle (`/orchestrate on`)**: The user has explicitly turned orchestration on for the workspace. (Can be reverted anytime with `/orchestrate off`).

> [!IMPORTANT]
> **Mandatory Activation Banner**:
> Whenever orchestration is engaged, the agent **MUST prepend an alert banner at the very top of its initial response**:
> ```markdown
> > [!NOTE]
> > 🚀 **Orchestration Active**: Multi-agent delegation engaged. Sub-tasks assigned to tiered models per `AGENTS.md`.
> ```
> This provides immediate visual transparency so the user always knows whether subagents are running.

When activated, the Supervisor applies the **Task Complexity Threshold**:
* **Trivial / Single-step Tasks**: Handled directly to avoid dispatch latency.
* **Complex / Multi-file / Multi-step Tasks**: Decomposed into the phases below:

### Phase 1: Task Decomposition
1. Break down the user's objective into distinct, isolated units of work.
2. For each unit, assign:
   * A designated role (`scout`, `implementer`, `tester`, `reviewer`).
   * A bounded set of file paths / directories.
   * An expected deliverable (e.g. "Report on symbol callers", "Write unit test in `tests/test_x.py`").

### Phase 2: File Overlap Verification (Safety Invariant)
> [!IMPORTANT]
> Never spawn two concurrent subagents that modify the same file.
> Parallel subagents must target strictly disjoint file paths.

* If Sub-task A modifies `src/api/routes.py` and Sub-task B modifies `src/api/routes.py`:
  * **Execute sequentially**, NOT in parallel.
* If Sub-task A modifies `src/api/` and Sub-task B modifies `tests/`:
  * **Safe for parallel dispatch**.

### Phase 3: Subagent Dispatch (`invoke_subagent`)
Use the `invoke_subagent` tool with the configured model tiers:

```json
{
  "Subagents": [
    {
      "TypeName": "self",
      "Role": "Backend Implementer",
      "Model": "flash",
      "Prompt": "Implement user authentication endpoint in src/api/auth.py according to implementation_plan.md. Run pytest tests/test_auth.py. Return only modified files, status, and concise test output."
    },
    {
      "TypeName": "self",
      "Role": "Frontend Implementer",
      "Model": "flash",
      "Prompt": "Implement the login form component in src/components/Login.tsx. Return only modified files, status, and lint results."
    }
  ]
}
```

### Phase 4: Context Compression & Synthesis
To keep the Supervisor's context window clean:
1. **Discard Intermediate Noise**: The Supervisor does not retain the subagent's step-by-step exploration logs.
2. **Accept Only Structured Summaries**: Subagents must return:
   * Status (`SUCCESS` / `FAILED`)
   * Affected file list
   * Terse diff summary
   * Verification command output (e.g. `12 passed, 0 failed`)
3. **Supervisor Integration Review**: The Supervisor inspects the combined diff as a coherent whole, ensuring naming consistency and interface compatibility.

### Phase 5: Feedback & Error Correction Loop
If a subagent's work fails verification or produces errors:
1. Do not rewrite the code directly in the Supervisor's context.
2. Send targeted feedback to the existing subagent using `send_message`:
   * State the exact test failure or lint error.
   * Provide the specific line or file to fix.
3. If the subagent fails twice on the same step, terminate it and ask the human user for guidance.

---

## 4. Ticketing & Task Tracking Integration

The orchestrator supports two interchangeable tracking modes configured during `/orchestrate init`:

### Option A: Local Markdown Tracker (`.agents/TICKETS.md`) [Default]
Ideal for local projects, offline work, or repositories without remote issue trackers.

1. **Board Structure**: `.agents/TICKETS.md` contains sections for `🟢 Open Tickets`, `🟡 In Progress`, `🟣 Subagent Discoveries`, and `🏁 Closed Tickets`.
2. **Supervisor Creation**: When decomposing a macro task, the Supervisor appends ticket entries:
   ```markdown
   - [ ] **#T-001: Implement Password Reset Endpoint**
     - **Role**: `implementer` (Model: `flash`)
     - **Scope**: `src/auth/reset.py`, `src/api/routes.py`
     - **Objective**: Create reset token generation and endpoint logic.
   ```
3. **Subagent Work & Discoveries**:
   * While executing, if a subagent discovers an unanticipated dependency or bug outside its scope, it appends a discovery under `🟣 Subagent Discoveries`:
     ```markdown
     - [ ] **#T-002: Missing email SMTP client configuration (found by #T-001)**
       - **Discovered by**: `implementer` (`flash`)
       - **Note**: `src/services/mailer.py` throws unhandled ConnectionError.
     ```
4. **Subagent / Supervisor Resolution & Closure**:
   * When a task is verified by tests, the assigned subagent (or Supervisor) updates `.agents/TICKETS.md`:
     * Moves the item from `Open` / `In Progress` to `🏁 Closed Tickets`.
     * Marks the checkbox `[x]`.
     * Appends the resolution summary and relevant commit hash:
     ```markdown
     - [x] **#T-001: Implement Password Reset Endpoint**
       - **Resolution**: Added reset token generation and verification endpoint. 5/5 unit tests passing.
       - **Commit**: `a1b2c3d` | **Closed by**: `tester` (`flash_lite`)
     ```

---

### Option B: Remote GitHub Issues (`gh` CLI)
Ideal for collaborative teams and open-source projects.

1. **Ticket Creation**: Major milestones are created as GitHub issues labeled `orchestrate:task` via `gh issue create`.
2. **Branching**: For multi-step implementations, create a branch `feature/issue-<id>`.
3. **Closing**: Once the Supervisor verifies the combined diff and test outputs, commit the changes, push, and close the issue via `gh issue close <id> --comment "Resolved and verified by subagents."`.

---

## 5. Summary of Cross-Platform Model Tier Guidelines

| Role | Antigravity Tier | Claude Code / Cursor Equivalent | Token Cost Ratio | Best Used For |
| :--- | :--- | :--- | :--- | :--- |
| **Supervisor / Architect** | `inherit` or `pro` | Claude 3.7 Sonnet / Opus / GPT-4o | 1.0x (Baseline) | System design, user consultation, conflict resolution, diff reviews |
| **Implementer / Coder** | `flash` | Claude 3.5 Sonnet / GPT-4o-mini | ~0.15x - 0.25x | Scoped feature implementation, targeted refactors, boilerplate |
| **Scout / Explorer** | `flash_lite` | Claude 3.5 Haiku / GPT-4o-mini | ~0.05x - 0.10x | Grep searches, reading source files, tracing symbol references |
| **Tester / QA** | `flash_lite` or `flash` | Claude 3.5 Haiku / GPT-4o-mini | ~0.05x - 0.15x | Running test suites, interpreting compiler errors, checking linters |
| **Reviewer** | `flash` | Claude 3.5 Sonnet / GPT-4o-mini | ~0.15x - 0.25x | Checking coding standards, detecting code smells, verifying specs |

