# Agent Orchestrator

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Antigravity Skill](https://img.shields.io/badge/Skill-Antigravity-blue.svg)](https://github.com/davekazemi/agent-orchestration)

A specialized skill and framework for **cost-optimized, hierarchical multi-agent orchestration**. 

It equips an AI coding assistant (like Antigravity, Claude Code, or Cursor) to function as an **Architect / Supervisor** that manages context windows and delegates token-heavy exploration, coding, testing, and reviewing tasks to fast, economical subagent tiers (`flash` and `flash_lite`).

---

## 🚀 Why Agent Orchestrator?

In modern AI-assisted engineering, running a top-tier reasoning model (e.g. Gemini 1.5/2.5/3 Pro, Claude 3.7 Sonnet) for every single sub-task has two fatal drawbacks:

1. **Massive Token Inefficiency**: 80% of tokens spent in coding sessions are consumed by repetitive codebase grepping, reading large files, running test commands, and formatting code.
2. **Context Window Degradation**: As intermediate tool calls and test outputs accumulate, the model's context window dilutes, increasing latency and hallucination rates.

### The Solution: Hierarchical Tiering

```mermaid
flowchart TD
    User([User]) <--> Supervisor[Supervisor / Architect\nModel: Pro / Inherit]
    
    Supervisor -->|Task Decomposition| Matrix{Parallel Dispatcher\n(Conflict Check)}
    
    subgraph Economical Subagent Workers
        Matrix -->|Read-only Search| Scout[Codebase Scout\nModel: Flash-Lite (~90% cheaper)]
        Matrix -->|Scoped Code Edit| Coder[Implementer\nModel: Flash (~80% cheaper)]
        Matrix -->|Run Tests & Lint| Tester[QA Runner\nModel: Flash-Lite (~90% cheaper)]
        Matrix -->|Standards & Specs| Reviewer[Reviewer\nModel: Flash (~80% cheaper)]
    end
    
    Scout -->|Compressed Summary| Supervisor
    Coder -->|Diff & Verification| Supervisor
    Tester -->|Test Pass/Fail Logs| Supervisor
    Reviewer -->|Code Smells & Critique| Supervisor
    
    Supervisor -->|Sync Tickets & Milestones| GitHub[(GitHub Issues / PRs)]
```

---

## ✨ Features

- ⚙️ **Interactive Onboarding (`/orchestrate init`)**: Prompts the user to configure model tiers for the Supervisor and subagent roles, then persists the matrix into `AGENTS.md` and configuration files.
- 🔄 **Dynamic Reconfiguration (`/orchestrate update`)**: Easily change assigned models, roles, or concurrency settings at any time.
- ⚡ **Safe Parallel Dispatch**: Enforces the **Disjoint File Invariant**—subagents targeting disjoint directories execute in parallel without merge race conditions.
- 📦 **Context Window Compression**: Subagents report only structured summaries, affected file lists, and test assertions. The Supervisor never gets bogged down with raw dumps.
- 🔁 **Targeted Feedback Loops**: When a subagent encounters a test failure, the Supervisor sends corrective instructions via `send_message` rather than rewriting the code itself.
- 🎫 **Flexible Dual-Mode Ticketing**: Choose between **Local Markdown** (`.agents/TICKETS.md` for offline, zero-network self-containment) or **GitHub Issues** (via `gh` CLI). Subagents can claim, discover new sub-tickets, and close resolved tickets directly in Markdown.

---

## 📁 Repository Structure

```
agent-orchestration/
├── SKILL.md                          # The core Antigravity skill definition
├── README.md                         # Project documentation
├── LICENSE                           # MIT License
├── .gitignore                        # Git ignore rules
├── templates/
│   ├── AGENTS.md.template            # Injectable orchestration rules for target repos
│   ├── orchestration.config.json     # Schema and default role-to-model configuration
│   └── TICKETS.md.template           # Scaffold template for local Markdown task board
└── references/
    ├── dispatch-guidelines.md        # Parallel safety, error recovery & economics
    └── ticketing-workflow.md         # GitHub Issues & local markdown ticket management
```

---

## 📦 Installation

### Option 1: Global Installation (Recommended for Antigravity)

Clone or link this repository into your global Antigravity skills directory:

```bash
# Clone to your local skills directory
git clone https://github.com/davekazemi/agent-orchestration.git ~/.gemini/config/skills/agent-orchestrator
```

The skill will be automatically available across all projects on your machine.

### Option 2: Project-Local Installation

Copy this repository into your project's `.agents/skills/` directory:

```bash
mkdir -p .agents/skills/
git clone https://github.com/davekazemi/agent-orchestration.git .agents/skills/agent-orchestrator
```

---

## 🛠️ Usage

### 1. Initialize Orchestration in a Project
In your chat or CLI:
```text
/orchestrate init
```
The agent scans available models in your runtime environment (Antigravity, Cursor, Claude Code, etc.), presents them in a numbered menu (e.g., `[1]` to `[N]`), and suggests smart defaults matched to each role's capability profile:
- **Supervisor** (High Reasoning & Planning): Top-tier model (e.g. `[1]` Pro / Sonnet)
- **Codebase Scout** (High-throughput Read & Search): Ultra-lightweight model (e.g. `[3]` Flash-Lite / Haiku)
- **Implementer** (Precise Code Synthesis): Balanced model (e.g. `[2]` Flash / Sonnet)
- **Tester / QA** (CLI Exec & Log Parsing): Ultra-lightweight model (e.g. `[3]` Flash-Lite / Haiku)
- **Reviewer** (Spec & Standards Critique): Balanced model (e.g. `[2]` Flash / Sonnet)

You can press `y` to accept the smart recommendations, or enter custom model numbers for each role. It will then persist the matrix to `.agents/orchestration.config.json` and your project's `AGENTS.md`.

### 2. Update Model Assignments
```text
/orchestrate update
```
Allows switching any subagent role (e.g. promoting the Implementer to `pro` for complex refactors, or switching the Tester to `flash`).

### 3. Ambient Execution (Zero Commands Required)
You never need to remember or run an explicit dispatch command. You simply interact with the agent normally:
> *"Add token expiry validation in auth.py and update the unit test suite."*

The Supervisor reads `AGENTS.md` and automatically:
1. **Evaluates Task Complexity**: Trivial single-line fixes are handled directly; complex multi-file tasks trigger decomposition.
2. **Checks File Safety**: Verifies that parallel subagents do not edit conflicting files.
3. **Dispatches Tiered Subagents**: Spawns `flash` for coding and `flash_lite` for testing concurrently.
4. **Compresses & Synthesizes**: Ingests only verified test assertions and diff summaries, keeping the main context window lean.

---

## 📊 Economics & Token Savings

| Role | Standard Single-Agent | Agent-Orchestrator Tier | Typical Token Cost Savings |
| :--- | :--- | :--- | :--- |
| **Exploration / Grep** | `pro` | `flash_lite` | **~90%** |
| **Implementation** | `pro` | `flash` | **~75% - 80%** |
| **Unit Testing / Lint**| `pro` | `flash_lite` | **~90%** |
| **Supervisor Oversight**| `pro` | `pro` | Clean context, minimal tokens |

---

## 🤝 Contributing

Contributions, issues, and feature requests are welcome! Feel free to check the [issues page](https://github.com/davekazemi/agent-orchestration/issues).

---

## 📄 License

Distributed under the [MIT License](LICENSE). Copyright © 2026 [Davood Kazemi](https://github.com/davekazemi).
