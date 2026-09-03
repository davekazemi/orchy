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
`/orchestrate init` | Interactive onboarding: guides the user through selecting models for the Supervisor and Subagent roles, writing configuration to `AGENTS.md` and `.agents/orchestration.config.json`.
`/orchestrate update` | Re-configures role-to-model assignments and execution policies without manual edits.
`/orchestrate dispatch` | Decomposes a user task or ticket into non-overlapping sub-tasks, dispatches parallel subagents, monitors progress, and synthesizes results.
`/orchestrate status` | Inspects currently active subagents, logs, and token efficiency statistics.

---

## 1. Initialization Workflow (`/orchestrate init`)

When the user runs `/orchestrate init` (or asks to set up agent orchestration):

### Step 1: Prompt for Model Preferences
Ask the user to configure or confirm their model preferences. Present sensible defaults:

1. **Supervisor Model**
   * Default: `inherit` (uses the active model, e.g. `pro` / Gemini 3.8 / Claude 3.7)
   * Role: Task decomposition, planning, final review, and user communication.

2. **Codebase Scout / Explorer Model**
   * Default: `flash_lite` (or `flash`)
   * Role: Reading files, searching symbols, grepping, surveying dependencies.
   * Rationale: High token volume, pure read operations, ~90% cost savings.

3. **Feature Implementer / Coder Model**
   * Default: `flash` (or `pro` for complex refactors)
   * Role: Writing isolated modules, editing targeted files, formatting code.

4. **Test & QA Runner Model**
   * Default: `flash_lite` (or `flash`)
   * Role: Executing test suites, linting, build scripts, reporting concise logs.

5. **Code Reviewer Model**
   * Default: `flash`
   * Role: Validating standards, finding smells, verifying against specifications.

### Step 2: Persist Configuration
1. Read existing `.agents/orchestration.config.json` if present, or copy from `templates/orchestration.config.json` with user choices.
2. In the target workspace's `AGENTS.md` (creating it if absent):
   * Look for existing `<!-- agent-orchestration:start -->` marker.
   * Inject or update the orchestration matrix using `templates/AGENTS.md.template`.
3. Report the saved configuration back to the user with an efficiency summary.

---

## 2. Reconfiguration Workflow (`/orchestrate update`)

When the user triggers `/orchestrate update`:
1. Read the current configuration from `.agents/orchestration.config.json` or `AGENTS.md`.
2. Present the current mapping in a clear table.
3. Prompt the user: "Which role would you like to update? (1) Supervisor, (2) Scout, (3) Implementer, (4) Tester, (5) Reviewer, (6) Parallelism limits".
4. Update `.agents/orchestration.config.json` and refresh the section in `AGENTS.md`.

---

## 3. Task Decomposition & Parallel Dispatch

When executing complex tasks, the Supervisor MUST follow these orchestration phases:

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

## 4. Ticketing & Git Integration

The orchestrator integrates with **GitHub Issues** (using the `gh` CLI) or local markdown files:

1. **Ticket Creation**: Major tasks are opened as issues labeled `orchestrate:task` via `gh issue create`.
2. **Branching**: For multi-step implementations, create a branch `feature/issue-<id>`.
3. **Closing**: Once the Supervisor verifies the combined diff and test outputs, commit the changes, push, and close the issue via `gh issue close <id>`.

---

## 5. Summary of Model Tier Guidelines

Role | Model Value in Antigravity | Token Cost Ratio | Best Used For
:--- | :--- | :--- | :---
**Supervisor / Architect** | `inherit` or `pro` | 1.0x | System design, user consultation, conflict resolution, diff reviews
**Implementer / Coder** | `flash` | ~0.2x | Scoped feature implementation, targeted refactors, boilerplate
**Scout / Explorer** | `flash_lite` | ~0.05x | Grep searches, reading source files, tracing symbol references
**Tester / QA** | `flash_lite` or `flash` | ~0.05x - 0.2x | Running test suites, interpreting compiler errors, checking linters
**Reviewer** | `flash` | ~0.2x | Checking coding standards, detecting code smells, verifying specs
