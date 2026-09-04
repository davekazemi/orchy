# Activity Log and Verifying Savings

`.agents/orchy-metrics.jsonl` is an **activity log**, not a cost report. It records what Orchy did so the user can audit it and correlate it with the provider's billing dashboard, which is the only ground truth for cost.

---

## 1. What Is Recorded

One JSON line per orchestrated task (and per solo task when `metrics.recordSoloBaseline` is true), appended by the Supervisor only, after the task ends:

```json
{"ts":"2026-09-04T10:12:00Z","task":"add token expiry validation","runtime":"claude-code","mode":"tiered-sync",
 "orchestrated":true,"units":3,"waves":2,"retries":1,"scopeViolations":0,
 "verifiedIndependently":true,"outcome":"SUCCESS","wallSeconds":412,
 "roles":{"scout":"flash_lite","implementer":"flash"},
 "usage":null,"usageSource":"none"}
```

Field rules:
* `units`, `waves`, `retries`, `scopeViolations`, `verifiedIndependently`, `outcome` are facts the Supervisor observed. They are always present.
* `usage` is populated **only** from numbers the runtime reports (per-subagent token usage, a usage API, a cost line in the tool result). Then `usageSource` is `runtime_usage_api` and `usage` has the shape `{"supervisor":{"in":18400,"out":3100},"scout":{"in":42000,"out":2600},...}`.
* If the runtime reports nothing, `usage` is `null` and `usageSource` is `none`. **Do not estimate tokens.** An LLM estimating its own consumption, in a system whose stated purpose is to reduce that consumption, is not a neutral measurement.
* Roles never dispatched are omitted from `roles`.

Add `.agents/orchy-metrics.jsonl` and `.orchy/` to the project's `.gitignore` (offered during `orchy init`); the log is per-developer and per-runtime and has no place in the repository history.

---

## 2. `orchy status`

Report, from the log and the current session:
* Current runtime row and derived mode; units in flight, if any.
* Counts: tasks orchestrated, waves, retry rate, scope-violation count, independent-verification pass rate.
* Token totals per role and the share on non-Supervisor roles, **only over entries with `usageSource: runtime_usage_api`**, with the fraction of entries that qualify. If none qualify, say "no runtime-reported usage available; see Section 3 to measure".
* Cost-weighted totals only when `metrics.pricing` is filled in **and** every included entry is runtime-reported. Never mix measured and unmeasured entries in one figure.
* Solo-vs-orchestrated comparison only when both groups have at least three runtime-reported entries; otherwise state that the sample is too small.

---

## 3. Where the Savings Actually Come From

State these in this order when the user asks; do not lead with per-token price ratios.

1. **Context isolation (largest, present in every mode with spawn).** Every turn re-sends the Supervisor's entire context as input tokens. A Supervisor that has absorbed 60k tokens of grep output and test logs pays for those 60k on every subsequent turn until the session ends. Workers absorb that material instead and return a packet of a few hundred tokens, so the Supervisor's per-turn input stays small for the rest of the task. This is why `context-only` mode still saves money on large tasks.
2. **Prompt caching.** Providers charge cached prefix tokens at a fraction of the normal input price. The Supervisor's prefix (system prompt, `AGENTS.md`, plan) stays stable across turns because worker churn does not enter it, so it stays cached. Each worker is a short, separate cache lifetime.
3. **Cheaper models per token (only in `full` / `tiered-sync`).** Real but smaller than the list-price ratio suggests, because cheaper models retry more and every retry costs Supervisor turns.

Costs paid against these: writing Handover Contexts, decomposition and dependency analysis, independent verification, and retries. Net savings are positive on large, parallel, exploration-heavy tasks and zero or negative on small or tightly coupled ones. The threshold in `orchestration-phases.md` §0 exists for that reason.

---

## 4. Measuring It Yourself

The only trustworthy comparison is an A/B on the provider's billing or usage dashboard:
1. Pick a task that clears the complexity threshold. Note the starting commit.
2. Run it solo. Record the dashboard delta (input, cached input, output, per model).
3. `git reset --hard` to the starting commit. Run the same prompt with `orchy:`. Record the delta.
4. Compare **cost**, not token count: orchestration usually spends *more* total tokens and *fewer expensive* ones, so raw token counts invert the result.
5. Repeat at least three times per arm before drawing a conclusion; single runs vary by more than the effect.

If the log's runtime-reported usage disagrees with the dashboard by more than ~20%, treat that runtime's usage numbers as unreliable and rely on the dashboard.
