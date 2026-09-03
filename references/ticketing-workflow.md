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
   * Produces atomic commits and closes the parent ticket upon verification.

---

## 2. GitHub Issues Workflow (`gh` CLI)

When GitHub integration is active:

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
  --label "orchestrate:task"
```

### Linking Subagent Branches & PRs
For non-trivial features, subagents can work on scoped git branches:
```bash
git checkout -b feature/issue-12-auth-expiry
# Subagents perform changes and tests...
git add src/auth/ tests/
git commit -m "feat(auth): validate token expiry (#12)"
gh pr create --fill --issue 12
```

### Closing the Issue
Once all verification checks pass and the diff is reviewed:
```bash
gh issue close 12 --comment "Completed and verified by multi-agent team. All tests passing."
```

---

## 3. Local Markdown Task Board (`.agents/TICKETS.md`)

When local markdown tracking is chosen, the repository uses a self-contained `.agents/TICKETS.md` board (scaffolded from `templates/TICKETS.md.template`). This provides offline capability and zero dependency on remote issue APIs.

### Lifecycle of a Markdown Ticket

#### 1. Creation by Supervisor
When planning a feature, the Supervisor adds tickets to `## 🟢 Open Tickets`:
```markdown
- [ ] **#T-101: Add Rate Limiting Middleware**
  - **Role**: `implementer` (Model: `flash`)
  - **Scope**: `src/middleware/rate_limit.py`, `tests/test_rate_limit.py`
  - **Objective**: Limit requests to 100/min per IP using in-memory token bucket.
```

#### 2. Discovery by Subagents
While executing `#T-101`, if the subagent discovers an unhandled edge case or missing service:
1. The subagent does NOT unilaterally expand its scope to rewrite foreign files.
2. The subagent appends a new discovery under `## 🟣 Subagent Discoveries`:
```markdown
- [ ] **#T-102: Redis dependency needed for distributed rate limiting (discovered during #T-101)**
  - **Discovered by**: `implementer` (`flash`)
  - **Note**: In-memory bucket works locally, but cluster deployment requires shared store.
```
3. The subagent informs the Supervisor via its summary return.

#### 3. Closure by Subagent / Tester
Upon successful test verification:
1. The subagent (or QA tester) moves the ticket to `## 🏁 Closed Tickets`.
2. Marks the box checked `[x]`.
3. Adds a concrete resolution note with test results and git commit:
```markdown
- [x] **#T-101: Add Rate Limiting Middleware**
  - **Resolution**: Implemented token bucket rate limiter in src/middleware/rate_limit.py. 6 unit tests passing.
  - **Commit**: `b4e2f91` | **Verified by**: `tester` (`flash_lite`)
```

