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

---

## 3. Parallel Dispatch Rules

### The Non-Overlapping Invariant
When dispatching multiple subagents simultaneously via `invoke_subagent`:
* **Rule**: Parallel subagents must operate on non-overlapping file sets.
* **Reason**: Subagents have isolated workspaces or parallel file handles. If two subagents edit the same file concurrently, the last write silently overwrites the previous write without git merge conflict detection.

### Scope Partitioning Patterns
1. **Vertical Slices by Layer**:
   * Agent 1 (Backend API): `src/api/*`, `src/controllers/*`
   * Agent 2 (Frontend UI): `src/components/*`, `src/styles/*`
   * Agent 3 (Tests): `tests/unit/*`, `tests/integration/*`
2. **Horizontal Slices by Module**:
   * Agent 1: `modules/auth/`
   * Agent 2: `modules/billing/`
   * Agent 3: `modules/notifications/`

---

## 4. Context Compression Protocol

Subagents must never dump raw files or unrestricted terminal output back to the Supervisor.

### Standard Subagent Return Contract
When a subagent completes its task, it must format its response with the following concise structure:

```markdown
### Subagent Result: [Role Name]
- **Status**: [SUCCESS | FAILED | BLOCKED]
- **Target Files**:
  - `path/to/fileA` (MODIFIED: +12, -4)
  - `path/to/fileB` (NEW)
- **Summary**: Concise 2-3 sentence description of the change or findings.
- **Verification Evidence**:
  - Test command: `pytest tests/test_auth.py`
  - Result: `4 passed, 0 failed in 0.42s`
- **Blockers / Notes**: Any follow-up decisions needed from Supervisor.
```

---

## 5. Subagent Error Recovery & Feedback Loop

When a subagent reports a test failure or code syntax issue:
1. **Do not switch to manual implementation immediately**: The Supervisor should first message the subagent using `send_message` with the exact error message:
   ```text
   The test 'test_token_expiry' failed with:
   AssertionError: expected 3600, got 0.
   Please inspect line 42 of src/auth/token.py and correct the expiry calculation.
   ```
2. **Two-Strike Rule**: If a subagent fails verification twice on the same step, terminate the subagent (`manage_subagents(Action='kill')`) and either:
   * Re-decompose the task into smaller sub-steps.
   * Escalate to the human supervisor for architectural clarification.
