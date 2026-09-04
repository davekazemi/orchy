# Ticketing & Git Workflow for Agent Orchestration

This document explains how to integrate issue trackers (GitHub Issues or local markdown tickets) with the multi-agent orchestrator.

---

## 1. Macro Planning vs. Micro Execution

Large tasks should be decoupled into two layers:

1. **Macro Layer (Tickets / Issues)**:
   * Represents decisions, architectural milestones, or functional features.
   * Persisted on GitHub Issues or in a project `TODO.md` / `ISSUES.md`.
   * Survives agent session restarts.
2. **Micro Layer (Subagents / Execution)**:
   * Short-lived workers spawned to fulfill a specific ticket.
   * Runs in parallel using lightweight models (`flash`, `flash_lite`).
   * Returns a Handover Result with proposed discoveries; the Supervisor verifies, commits, and closes.

### Single-Writer Rule
Only the Supervisor mutates shared state: `.agents/TICKETS.md`, `.agents/orchy-metrics.jsonl`, `git add`/`commit`/`push`, and `gh`. Workers propose; the Supervisor writes. Reasons:
* A board edited by parallel workers is a write race on a single file, the exact hazard the disjoint-file invariant prevents.
* All workers share one git index; concurrent commits collide even when edited files are disjoint.
* Closure must follow **independent** verification by the Supervisor, not a worker's self-report.

---

## 2. GitHub Issues Workflow (`gh` CLI)

When GitHub integration is active, every command in this section is run by the Supervisor:

### Creating an Orchestration Ticket
```bash
gh issue create \
  --title "Implement Auth Token Expiry Validation" \
  --body "## Objective
Add token expiry validation in src/auth/token.py and corresponding unit tests.

## Assigned Subagent Roles
- Implementer: Model=flash
- Tester: Model=flash_lite
" \
  --label "orchy:task"
```

### Branches & PRs
For non-trivial features, the Supervisor creates the branch before dispatching workers and commits after the wave is verified:
```bash
git checkout -b feature/issue-12-auth-expiry
# Supervisor dispatches workers; workers edit files only, no git commands...
# Supervisor re-runs verification independently (e.g. pytest tests/test_auth.py)
git add src/auth/ tests/
git commit -m "feat(auth): validate token expiry (#12)"
gh pr create --fill --issue 12
```

### Closing the Issue
Once the Supervisor has independently re-run verification and reviewed the combined diff:
```bash
gh issue close 12 --comment "Completed. Verification re-run by supervisor: 4 passed, 0 failed."
```

---

## 3. Local Markdown Task Board (`.agents/TICKETS.md`)

When local markdown tracking is chosen, the repository uses a self-contained `.agents/TICKETS.md` board (scaffolded from `templates/TICKETS.md.template`). This provides offline capability and zero dependency on remote issue APIs.

### Lifecycle of a Markdown Ticket

#### 1. Creation by Supervisor
When planning a feature, the Supervisor adds tickets to `## 🟢 Open Tickets`, including any dependency edge from Phase 2 analysis:
```markdown
- [ ] **#T-101: Add Rate Limiting Middleware**
  - **Role**: `implementer` (Model: `flash`)
  - **Scope**: `src/middleware/rate_limit.py`, `tests/test_rate_limit.py`
  - **Depends on**: —
  - **Objective**: Limit requests to 100/min per IP using in-memory token bucket.
```

#### 2. Discovery by Subagents (proposed, recorded by Supervisor)
While executing `#T-101`, if the subagent discovers an unhandled edge case or missing service:
1. The subagent does NOT unilaterally expand its scope to rewrite foreign files.
2. The subagent does NOT edit `.agents/TICKETS.md`. It lists the item under `Proposed Discoveries` in its Handover Result.
3. The Supervisor accepts or rejects each proposal and records accepted ones under `## 🟣 Subagent Discoveries`:
```markdown
- [ ] **#T-102: Redis dependency needed for distributed rate limiting (discovered during #T-101)**
  - **Reported by**: `implementer` (`flash`)
  - **Note**: In-memory bucket works locally, but cluster deployment requires shared store.
```

#### 3. Closure by Supervisor
A worker's `SUCCESS` is a claim. Closure happens only after the Supervisor:
1. Re-runs the verification command itself (or via a fresh Tester that has not seen the claimed result).
2. Commits the change.
3. Moves the ticket to `## 🏁 Closed Tickets`, marks `[x]`, and records the independently observed result and commit:
```markdown
- [x] **#T-101: Add Rate Limiting Middleware**
  - **Resolution**: Implemented token bucket rate limiter in src/middleware/rate_limit.py.
  - **Verified**: `pytest tests/test_rate_limit.py` re-run by Supervisor → `6 passed, 0 failed`
  - **Commit**: `b4e2f91` | **Implemented by**: `implementer` (`flash`)
```

