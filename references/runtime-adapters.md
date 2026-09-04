# Runtime Adapters

Orchy needs four capabilities from the host runtime: **spawn** a subagent, choose a **model per subagent**, **message** a running subagent, and **terminate** it. Runtimes expose different subsets under different names. Instead of probing at run time (an LLM "probing" for tools tends to hallucinate the answer it expects), the mode is **derived from a static table keyed by `runtime.name`**, with explicit per-capability overrides for anything the table gets wrong.

---

## 1. Adapter Table

Cells marked *verify* are not confirmed for the current version of that runtime. Treat them as `no` until the user or the runtime's documentation confirms otherwise, then record the answer in `runtime.overrides`.

| `runtime.name` | Identify by | Spawn | Model per subagent | Live messaging | Terminate | Parallel | Derived mode |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :--- |
| `antigravity` | `invoke_subagent`, `send_message`, `manage_subagents` tools present | yes | yes (`Model` field) | yes | yes | yes | `full` |
| `claude-code` | `Task` tool; `.claude/` directory; `CLAUDE.md` | yes | yes (`model:` in `.claude/agents/*.md`) | no | no | yes | `tiered-sync` |
| `augment` | `sub-agent-*` tools; `.augment/` directory | yes | fixed per sub-agent definition (*verify*) | no | no | yes | `context-only` |
| `cursor` | `.cursor/` directory; Cursor rules | *verify* (background agents / subagents) | *verify* | no | no | *verify* | `context-only` if spawn confirmed, else `solo` |
| `codex` | `codex` CLI; `AGENTS.md` only | *verify* | no | no | no | no | `solo` |
| `copilot` | VS Code agent mode; `.github/copilot-instructions.md` | *verify* | no | no | no | no | `solo` |
| `gemini-cli` | `gemini` CLI; `GEMINI.md`; `.gemini/` | *verify* | *verify* | no | no | no | `solo` |
| `windsurf` | `.windsurf/` directory | no | no | no | no | no | `solo` |
| `cline` | `.clinerules` | no | no | no | no | no | `solo` |
| `unknown` | none of the above | no | no | no | no | no | `solo` |

Mode derivation (after overrides are applied):

| Mode | Requires | What changes |
| :--- | :--- | :--- |
| `full` | spawn + model per subagent + live messaging | Everything in the references applies as written. |
| `tiered-sync` | spawn + model per subagent | Feedback = respawn with the same Handover Context plus Prior Attempt; one retry. |
| `context-only` | spawn only | Isolation savings only (Supervisor context stays small); no per-token price savings. Double the complexity threshold. |
| `solo` | nothing usable | `orchy:` prints one line ("Orchy: no subagent primitive in this runtime, running solo") and proceeds directly. |

---

## 2. Choosing and Recording the Runtime

During `orchy init`:
1. Match the **Identify by** column against what is actually visible: the tool list the runtime advertises to you, and files in the workspace root. Do not call a tool to find out whether it exists.
2. Show the user the matched row and the derived mode. Ask them to confirm or pick a different row. If nothing matches, use `unknown`.
3. For every *verify* cell, ask one yes/no question ("Can this runtime spawn subagents? If unsure, answer no.") and record the answer under `runtime.overrides`.
4. Persist:

```json
"runtime": {
  "name": "claude-code",
  "overrides": { "spawnSubagent": null, "perSubagentModelSelection": null, "liveMessaging": null, "terminateSubagent": null, "parallelDispatch": null },
  "lastDerivedMode": "tiered-sync",
  "lastDerivedAt": "2026-09-04T10:12:00Z"
}
```

`null` means "use the table". `true`/`false` overrides it. `lastDerivedMode` is a cache for display only; it is never the source of truth.

---

## 3. Re-Deriving at Session Start (Stale-Config Guard)

`runtime.name` was written by whichever runtime ran `orchy init`. The same repository is routinely opened later in a different runtime, so the mode is **re-derived at the first orchestrated action of every session**, not read from the file:

1. Re-run the match from Section 2 step 1 against the current environment.
2. If it matches `runtime.name`, derive the mode from the table plus overrides and proceed.
3. If it matches a different row, tell the user in one line ("Config was initialized for `antigravity`; this session looks like `claude-code`. Using `tiered-sync` for this session.") and use the current runtime's row. Update `lastDerivedMode` / `lastDerivedAt`; do not change `runtime.name` unless the user confirms via `orchy update`.
4. If the current environment matches nothing and `runtime.name` is not `unknown`, run in `solo` mode and say so; never keep dispatching on a mode the current environment cannot support.

The activation banner always shows the mode derived in the current session.

---

## 4. Mapping the Handover Context onto a Spawn Call

The Handover Context (`dispatch-guidelines.md` §4.2) is the worker's entire prompt. How it reaches the worker differs:

| Runtime | Where the packet goes | Where the model tier goes |
| :--- | :--- | :--- |
| `antigravity` | `Prompt` of each entry in the `Subagents` list | `Model` field of the same entry |
| `claude-code` | The `Task` prompt; the role maps to a subagent file in `.claude/agents/` | `model:` frontmatter of that subagent file (written by `orchy init`) |
| `augment` | The `instruction` of `sub-agent-code` / `sub-agent-research` etc. | Not settable per call |
| others with spawn | The spawn call's prompt/instruction argument | Only if the call accepts one; otherwise ignore the tier |

Where the runtime's subagent is synchronous (returns once), the Handover Result is simply its final message. Where it is asynchronous, wait for completion and read only the final message.
