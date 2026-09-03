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

## 3. Local Markdown Fallback

If GitHub is unavailable or offline, the orchestrator defaults to a local `.agents/TICKETS.md` file following the format:

```markdown
# Orchestration Task Board

## Open
- [ ] **#1: Add database migration for user roles**
  - Roles: Scout (`flash_lite`), Implementer (`flash`)
  - Status: In Progress

## Closed
- [x] **#0: Project scaffolding**
  - Completed: 2026-09-03
```
