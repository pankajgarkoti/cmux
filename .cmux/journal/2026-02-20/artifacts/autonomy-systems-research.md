# Autonomous Agent Systems: Heartbeat, Liveness & Autonomy Loop Research

**Date**: 2026-02-20
**Researcher**: worker-autonomy-research
**Purpose**: Deep research on how autonomous AI agent frameworks handle heartbeats, liveness, and autonomy loops — with concrete recommendations for CMUX.

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [CMUX Current State](#cmux-current-state)
3. [Framework-by-Framework Analysis](#framework-analysis)
   - [OpenClaw](#1-openclaw)
   - [AutoGPT / AgentGPT](#2-autogpt--agentgpt)
   - [CrewAI](#3-crewai)
   - [BabyAGI](#4-babyagi)
   - [LangGraph](#5-langgraph)
   - [Microsoft AutoGen](#6-microsoft-autogen)
   - [Semantic Kernel](#7-semantic-kernel)
   - [MetaGPT](#8-metagpt)
   - [Claude Code / Anthropic](#9-claude-code--anthropic)
   - [Devin / SWE-Agent / OpenHands](#10-devin--swe-agent--openhands)
   - [SuperAGI](#11-superagi)
   - [CAMEL-AI](#12-camel-ai)
   - [Agency Swarm](#13-agency-swarm)
4. [Cross-Framework Comparison](#cross-framework-comparison)
5. [Common Patterns](#common-patterns)
6. [CMUX Recommendations](#cmux-recommendations)

---

## Executive Summary

Across 13 autonomous agent frameworks, a clear finding emerges: **no framework has solved the "autonomy pulse" problem that CMUX is trying to solve.** Almost every system is run-to-completion — agents execute assigned tasks and stop. The concept of a persistent agent daemon that proactively finds work when idle is unique to CMUX and OpenClaw.

Key findings:

1. **Most frameworks are reactive, not proactive.** Agents execute when given work and terminate when done. None (except OpenClaw) have a built-in mechanism for agents to autonomously discover and pursue new tasks.

2. **Liveness monitoring is primitive everywhere.** No framework has sophisticated heartbeat-based agent health monitoring. AutoGPT has WebSocket ping/pong. SuperAGI and OpenHands have looping/stuck detection. Most have nothing.

3. **The "idle but healthy" state is universally unhandled.** Every framework either terminates idle agents or blocks them on a queue. CMUX's autonomy-check + backlog polling model is architecturally novel.

4. **Event-driven architectures outperform polling loops.** OpenClaw, LangGraph, and AutoGen all demonstrate that event-driven models (heartbeat, cron, webhook as first-class events) are more efficient than polling-based loops.

5. **Self-improvement is rare.** Only OpenClaw (Foundry extension) and BabyAGI 2.0 (self-building) attempt automated capability expansion. CMUX's self-modification model is architecturally distinct.

**Bottom line**: CMUX's heartbeat-to-autonomy vision is validated by the research. The system should evolve from a passive liveness signal into an active event-driven autonomy loop, drawing from OpenClaw's event model, MetaGPT's dependency-driven activation, and OpenHands' stuck detection.

---

## CMUX Current State

### How the Heartbeat Works Today

The CMUX heartbeat is a **PostToolUse hook** in `.claude/settings.json`:

```bash
# On every tool use by the supervisor agent:
date +%s > .cmux/.supervisor-heartbeat
```

This writes a Unix timestamp to a file every time the supervisor uses any Claude Code tool. The monitor daemon (`monitor.sh`) reads this file every 5 seconds in its dashboard loop.

### The Monitor's Decision Tree

```
Read .supervisor-heartbeat → compute staleness (now - last_beat)

IF staleness < 600s:
  → HEALTHY (green dot)

IF staleness >= 600s AND supervisor is NOT at prompt:
  → MID-TASK PATH: Enter observation mode
  → Watch pane hash for output changes
  → If pane frozen for 1200s → spawn sentry

IF staleness >= 600s AND supervisor IS at prompt:
  → IDLE PATH: Send nudges
  → Run autonomy-check for actionable work
  → Up to 3 nudges, 120s cooldown between each
  → After 3 failed nudges + process alive → reset (not stuck, just quiet)
  → After 3 failed nudges + process dead → spawn sentry
```

### What autonomy-check Scans

The `tools/autonomy-check` script checks (in priority order):
1. **Mailbox** — unprocessed messages
2. **Backlog** — pending backlog items
3. **Workers** — idle workers (30+ min)
4. **Health** — system health endpoint
5. **Git** — uncommitted tracked changes

### Current Limitations

1. **The heartbeat is purely defensive.** It detects failure, it doesn't drive productivity.
2. **Nudges are interruptive.** They inject text into the supervisor's tmux pane, which can disrupt in-progress work.
3. **No structured event system.** Events are ad-hoc (heartbeat files, mailbox, log watching).
4. **No progress tracking.** The monitor can't distinguish "working productively" from "spinning wheels."
5. **No graduated response.** The escalation path is: nudge → nudge → nudge → sentry. No intermediate actions.

---

## Framework Analysis

### 1. OpenClaw

**Architecture**: Event-driven state machine with Gateway daemon (WebSocket), Agent Runtime (LLM), Session Store (JSONL).

**Autonomy Model**: "Always listening, not always thinking." Six event types:
| Event | Trigger | Purpose |
|-------|---------|---------|
| `heartbeat` | Periodic (30 min default) | Proactive: "what should I do next?" |
| `cron` | Scheduled | Time-triggered automation |
| `webhooks` | External systems | Reactive to GitHub, Gmail, etc. |
| `chat` | User messages | Respond to conversations |
| `presence` | Contact status | Awareness of user availability |
| `health` | System checks | Self-monitoring |

**Key Insight**: The heartbeat IS the autonomy pulse. Every 30 minutes, the agent evaluates its environment and decides what to do. It's not a liveness check — it's a productivity driver.

**Self-Improvement**: OpenClaw Foundry extension implements "pattern crystallization" — when a workflow reaches 5+ uses with 70%+ success rate, it's automatically converted into a dedicated tool.

**CMUX Relevance**: ★★★★★ — OpenClaw validated at 140k-star scale that the heartbeat-as-autonomy-pulse model works. CMUX should adopt this exact pattern.

---

### 2. AutoGPT / AgentGPT

**AutoGPT Classic**: While loop with cycle budget counter. Each cycle: propose_action() → get_user_feedback() → execute(). Uses ReACT framework (Thoughts, Reasoning, Plan, Criticism, Command). No task queue — the LLM decides next action each cycle.

**AutoGPT Platform**: DAG-based graph execution with RabbitMQ queues. Nodes execute, produce outputs, trigger downstream nodes. The "loop" is a queue drain. Scheduler supports cron-triggered graph executions.

**AgentGPT**: Frontend-driven task queue with lifecycle state machine (offline → running → pausing → paused → stopped). `addTasksIfWorklogEmpty()` checks for new work when queue drains.

**Heartbeat**: AutoGPT Platform has WebSocket ping/pong (connection-level, not agent-level) and Redis distributed lock refresh. Classic and AgentGPT have nothing.

**Idle Handling**: All variants terminate when done. No proactive work-finding.

**Budget Controls**: Classic has cycle limit + SIGINT handler. Platform has per-user rate limits, billing pre-checks, cancellation events. AgentGPT has configurable max loops (default 25).

**CMUX Relevance**: ★★☆☆☆ — AutoGPT is primarily a run-to-completion system. The Platform's cron-triggered execution and distributed locking are useful patterns, but the core autonomy model doesn't apply.

---

### 3. CrewAI

**Architecture**: Agents are reactive — invoked by the Crew when a task is assigned. Within a task, agents have a full ReAct loop (`CrewAgentExecutor`). Two strategies: text-based ReAct or native function calling with parallel tool execution (ThreadPoolExecutor, 8 workers).

**Process Types**:
- **Sequential**: Tasks in order, each output becomes context for the next
- **Hierarchical**: Manager agent dynamically assigns tasks to workers
- **Flows** (recommended for production): Event-driven via `@start`, `@listen`, `@router` decorators with state persistence

**Delegation**: Implemented as LLM tool calls (`DelegateWorkTool`, `AskQuestionTool`). Blocking — delegator waits for delegatee to complete. Delegation result becomes a tool observation.

**Memory**: Sophisticated unified system with vector embeddings, composite scoring (semantic + recency + importance), hierarchical scoping (`/project/alpha`, `/agent/researcher`), automatic consolidation above 0.85 similarity threshold.

**Event System**: 70+ typed events on a singleton `CrewAIEventsBus` with dependency-aware handlers. Comprehensive but run-to-completion — no daemon mode.

**Idle Handling**: Strictly run-to-completion. When all tasks finish, the crew stops. No idle loop, no work polling.

**CMUX Relevance**: ★★★☆☆ — CrewAI's memory system (vector search + LLM-inferred scoping + consolidation) is more sophisticated than CMUX's journal. The event bus with 70+ typed events suggests CMUX needs a more structured event taxonomy. Flows' `@persist` decorator for crash recovery is useful.

---

### 4. BabyAGI

**Architecture**: The canonical 3-function loop:
1. `execution_agent(objective, task)` — execute current task with vector-retrieved context
2. `task_creation_agent(objective, result, task_description, task_list)` — generate follow-up tasks
3. `prioritization_agent(task_id)` — reorder remaining task queue

Main loop: `while True` with 5-second sleep between iterations. Tasks stored in `collections.deque`.

**The Infinite Loop Problem**: The task creation agent almost always generates new tasks, so the queue rarely empties. Solutions: KeyboardInterrupt handler, kill switch, max iteration counter, empty queue check.

**Evolution**:
- **BabyBeeAGI**: Consolidated creation+prioritization, added task dependencies and tools, added completion detection
- **BabyCatAGI**: Front-loaded planning (task creation runs once at start), major speedup
- **BabyDeerAGI**: User input during execution, parallel task execution
- **BabyElfAGI**: Multi-file architecture, Skills class, reflection agent
- **BabyFoxAGI**: FOXY method (final reflection after each task, retrieved on new tasks = self-improving loop)
- **BabyAGI 2.0**: Complete departure — self-building agent that generates Python functions as reusable tools

**CMUX Relevance**: ★★★☆☆ — The task creation agent pattern (generating new work from completed results) directly maps to CMUX's autonomy check. BabyFoxAGI's reflection-retrieval pattern could improve CMUX's journal-based learning. BabyAGI 2.0's self-building philosophy aligns with CMUX's self-improvement goals.

---

### 5. LangGraph

**Architecture**: Graph-based state machine execution inspired by Google's Pregel. Nodes are functions, edges define data flow, channels manage state.

**Execution Model**: Superstep-based (Bulk Synchronous Parallel):
1. **Plan Phase**: Determine executable nodes from channel state
2. **Execute Phase**: Run nodes in parallel (threads or asyncio)
3. **Update Phase**: Node outputs write to channels via reducers
4. **Checkpoint Phase**: Persist state snapshot

**Checkpointing**: Full state persistence after each superstep via `BaseCheckpointSaver`. Implementations for SQLite, PostgreSQL. Stores channel values, version numbers, pending writes. Enables time-travel debugging and resume from any checkpoint.

**Multi-Agent Patterns**:
- **Supervisor Pattern**: A supervisor node routes to worker nodes using conditional edges
- **Swarm Pattern**: Agents hand off control via `Command` objects that update `active_agent` state
- **Network Topology**: Explicit handoff tools define which agents can transfer to which

**Long-Term Memory**: `BaseStore` with namespace-scoped JSON documents. Supports semantic search (vector embeddings). Cross-thread persistence for sharing knowledge across conversations.

**Human-in-the-Loop**: Graph execution can pause at `interrupt_before` or `interrupt_after` specified nodes, waiting for external input before resuming.

**Cron Triggers**: LangGraph Platform supports cron-based agent invocation for scheduled autonomous execution.

**CMUX Relevance**: ★★★★☆ — LangGraph's checkpointing model (persist state after every step, resume from any checkpoint) is a gold standard for crash recovery. The supervisor pattern validates CMUX's architecture. Cron triggers for scheduled autonomous execution directly support the heartbeat-to-autonomy evolution. The superstep transactional model (rollback entire step on any node failure) maps to CMUX's git rollback safety model.

---

### 6. Microsoft AutoGen

**Architecture**: Event-driven message-passing. Agents are event processors. GroupChat Manager controls conversation flow via speaker selection.

**Magentic-One**: Standout multi-agent pattern with dual-ledger system:
- **Task Ledger**: Facts and educated guesses about the current task
- **Progress Ledger**: Step-by-step self-reflection on progress

The Orchestrator runs an outer loop (updating Task Ledger, replanning) and inner loop (assigning subtasks). If progress stalls for several steps, the Orchestrator triggers replanning.

**Speaker Selection Strategies**: Round-Robin, Selector-Based (LLM selects next speaker), Custom Functions (return agent, method, or `None` to terminate).

**CMUX Relevance**: ★★★★☆ — The dual-ledger system is highly applicable. CMUX's supervisor could maintain explicit progress tracking with self-reflection at each step. The "stalled progress triggers replanning" heuristic is more sophisticated than nudging.

---

### 7. Semantic Kernel

**Architecture**: Deprecated explicit planners in favor of LLM-native function calling. The LLM iteratively calls registered functions until it determines the task is complete.

**Multi-Agent**: AgentGroupChat → GroupChatOrchestration with configurable SelectionStrategy and TerminationStrategy. `KernelFunctionTerminationStrategy` uses an LLM to analyze conversation history and decide if the chat should end.

**CMUX Relevance**: ★★☆☆☆ — The LLM-based termination evaluation is interesting: instead of fixed heuristics for deciding when a worker is done, use an LLM to evaluate whether the task has been genuinely completed.

---

### 8. MetaGPT

**Architecture**: Software company SOP model. Each Role follows ReAct: `_observe` → `_think` → `_act`.

**React Modes**: "react" (standard), "by_order" (predefined sequence), "plan_and_act" (plan first, execute sequence).

**Coordination**: Publish-subscribe with global message pool. Agents subscribe based on role profiles, filtering irrelevant messages. Assembly-line paradigm with explicit dependency chains.

**Liveness**: `max_react_loop` configurable watchdog prevents infinite loops. Dependency-based activation — agents idle naturally when waiting for upstream inputs.

**CMUX Relevance**: ★★★☆☆ — Publish-subscribe with role-based filtering is more scalable than CMUX's shared mailbox. The `max_react_loop` watchdog is a simple but effective pattern for workers. Assembly-line dependency chains could formalize CMUX's delegation model.

---

### 9. Claude Code / Anthropic

**Architecture**: Single-threaded master loop blending three phases: gather context → take action → verify results.

**Long-Running Agent Patterns** (from Anthropic engineering blog):
- **Two-agent architecture**: Initializer (setup + progress tracking) + Coding Agent (incremental single-feature progress)
- **Progress files**: `claude-progress.txt` with pass/fail status per feature
- **Single feature per session**: Prevents "attempt too much" failure mode
- **Subagent context isolation**: Separate context windows prevent bloat

**Failure Modes Identified**:
- Attempting too much at once → feature lists with pass/fail status
- Premature completion declarations → structured feature files prevent false confidence
- Undocumented progress → git commits + progress file updates
- Testing gaps → browser automation for end-to-end verification

**CMUX Relevance**: ★★★★★ — Directly applicable. CMUX workers should adopt the progress.txt pattern. The initializer + coding agent split validates supervisor + worker model. Single feature per session discipline should be enforced.

---

### 10. Devin / SWE-Agent / OpenHands

**Devin**: Compound AI system with Planner (strategy) + Coder (implementation) + Critic (review). Each instance runs in an isolated VM.

**SWE-Agent**: Agent-Computer Interface (ACI) — structured layer between LLM and computer. Ping-pong pattern: command → output → next command.

**OpenHands**: Event-sourced state model — all interactions are immutable events. Enables deterministic replay, precise debugging, automatic resume.

**Stuck Detection** (OpenHands): Identifies repeated actions, same errors recurring, redundant tool calls. Agent statuses: RUNNING, PAUSED, FINISHED, ERROR.

**CMUX Relevance**: ★★★★☆ — OpenHands' stuck detection is exactly what CMUX needs beyond health checks. The event-sourced model would transform CMUX's journal into something more powerful. Devin's Planner/Coder/Critic maps to CMUX's debate templates.

---

### 11. SuperAGI

**Architecture**: Dev-first framework for concurrent autonomous agents with isolated agent directories.

**Key Feature**: **Looping detection heuristics** — proactively detects agents stuck in loops and notifies developers. Supports pause/resume per execution.

**CMUX Relevance**: ★★★☆☆ — Looping detection is directly applicable. Agent_execution_id pattern (separating identity from execution) is cleaner lifecycle management.

---

### 12. CAMEL-AI

**Architecture**: Role-playing framework with "inception prompting." Conversational loop: AI User instructs AI Assistant.

**Termination**: `<CAMEL_TASK_DONE>` explicit token + 3-round idle timeout + 40-message maximum.

**CMUX Relevance**: ★★☆☆☆ — The structured completion token and idle timeout are simple, adoptable patterns.

---

### 13. Agency Swarm

**Architecture**: Corporate hierarchy model with explicit agency chart defining communication topology. Synchronous `SendMessage` tool as primary coordination primitive.

**State**: OpenAI Assistants API threads with save/load callbacks for session persistence.

**CMUX Relevance**: ★★☆☆☆ — The agency chart formalizes which agents can communicate with which. Thread persistence callbacks could clean up CMUX's worker context management.

---

## Cross-Framework Comparison

### How Agents Know When to Work vs. Wait

| Framework | Mechanism | Proactive? |
|-----------|-----------|------------|
| **OpenClaw** | Event-driven: heartbeat, cron, webhooks, chat | ✅ Yes — heartbeat triggers autonomous evaluation |
| **AutoGPT Classic** | Cycle budget counter in while loop | ❌ No — runs until budget exhausted |
| **AutoGPT Platform** | RabbitMQ queue consumption + cron scheduler | ⚠️ Partial — cron enables scheduled execution |
| **CrewAI** | Called by Crew when task assigned | ❌ No — purely reactive |
| **BabyAGI** | Infinite while loop with 5s sleep | ❌ No — always running, never waiting |
| **LangGraph** | Graph execution + optional cron triggers | ⚠️ Partial — cron on Platform |
| **AutoGen** | Event-driven message delivery | ❌ No — responds to messages |
| **MetaGPT** | Dependency-based activation from message pool | ❌ No — waits for dependencies |
| **Claude Code** | User-initiated sessions | ❌ No — session-based |
| **OpenHands** | Event processor pattern | ❌ No — responds to events |
| **SuperAGI** | Goal-based execution with toolkit | ❌ No — run-to-completion |
| **CAMEL-AI** | Conversational loop with termination tokens | ❌ No — run-to-completion |
| **Agency Swarm** | Synchronous SendMessage | ❌ No — responds to messages |
| **CMUX** | PostToolUse heartbeat + autonomy-check nudges | ⚠️ Partial — nudges drive productivity |

### How Liveness/Health Is Monitored

| Framework | Mechanism |
|-----------|-----------|
| **OpenClaw** | health event type |
| **AutoGPT Platform** | WebSocket ping/pong + Redis lock refresh + Prometheus |
| **CMUX** | Heartbeat file mtime + pane hash change detection + sentry recovery |
| **OpenHands** | Stuck detection (repeated actions, redundant queries) |
| **SuperAGI** | Looping detection heuristics |
| **MetaGPT** | max_react_loop watchdog |
| **All others** | None |

### How "Idle but Healthy" Is Handled

| Framework | Behavior |
|-----------|----------|
| **OpenClaw** | Heartbeat event triggers "what should I do?" evaluation |
| **CMUX** | autonomy-check runs, nudge sent to supervisor |
| **AutoGPT Platform** | Blocks on RabbitMQ queue (no active work-finding) |
| **All others** | Terminate or do nothing |

---

## Common Patterns Across Successful Systems

### 1. The ReAct Loop Is Universal
Every agent framework implements some version of Reason → Act → Observe. The differences are in what triggers the loop (event vs. polling) and what stops it (budget, completion signal, dependency satisfaction).

### 2. Run-to-Completion Is the Default
Except for OpenClaw and CMUX, all frameworks are designed to complete a task and stop. The daemon/persistent-agent model is an outlier.

### 3. Termination Is Harder Than Execution
Every framework struggles with "when to stop." Solutions range from crude (cycle limits) to sophisticated (LLM-evaluated completion, structured tokens). No universal solution exists.

### 4. State Persistence Enables Recovery
Frameworks with strong persistence (LangGraph checkpoints, OpenHands event logs, CrewAI memory) handle failures gracefully. Those without (AgentGPT in-memory, CAMEL-AI conversations) lose everything on crash.

### 5. Multi-Agent Coordination Patterns Converge
Three patterns dominate:
- **Supervisor/Manager**: One agent coordinates others (LangGraph, CrewAI hierarchical, CMUX)
- **Publish-Subscribe**: Agents listen for relevant messages (MetaGPT, AutoGen)
- **Direct Handoff**: Agents pass control to each other (LangGraph Swarm, Agency Swarm)

### 6. Nobody Has Solved Autonomous Self-Improvement at Scale
OpenClaw's Foundry (pattern crystallization) and BabyAGI 2.0 (self-building) are the closest, but both are experimental. CMUX's approach (agents modify their own codebase with git rollback safety) is architecturally unique.

---

## CMUX Recommendations

### Tier 1: Immediate Improvements (Low Effort, High Impact)

#### R1. Structured Completion Signals
**Inspiration**: CAMEL-AI's `<CAMEL_TASK_DONE>` token
**Current**: Workers report `[DONE]` via mailbox, supervisor infers completion from tmux output
**Proposal**: Standardize machine-parseable completion signals:
```
[DONE] {"task": "fix-auth-bug", "status": "success", "files": ["src/auth.py"], "tests": "passing"}
[BLOCKED] {"task": "fix-auth-bug", "blocker": "missing-dependency", "need": "redis package"}
[FAILED] {"task": "fix-auth-bug", "error": "cannot reproduce", "attempts": 3}
```
The monitor could parse these instead of relying on tmux pane heuristics.

#### R2. Worker max_react_loop Watchdog
**Inspiration**: MetaGPT's `max_react_loop`
**Current**: Workers can run indefinitely
**Proposal**: Add configurable maximum tool-use count per worker session. After N tool uses without a `[DONE]` signal, the monitor sends a "[TIMEOUT]" message and marks the worker for supervisor review.

#### R3. Stuck Detection Heuristics
**Inspiration**: OpenHands stuck detection, SuperAGI looping detection
**Current**: Monitor only checks pane hash changes (crude)
**Proposal**: Analyze worker tmux output for:
- Same error message appearing 3+ times consecutively
- Same command executed 3+ times without different output
- Worker asking itself the same question repeatedly
This catches "busy but unproductive" workers that pass health checks.

### Tier 2: Architecture Evolution (Medium Effort, High Impact)

#### R4. Event-Driven Autonomy Pulse
**Inspiration**: OpenClaw's event model
**Current**: Heartbeat is a timestamp file; nudges are injected text
**Proposal**: Replace the heartbeat/nudge system with a formal event system:

```
Event Types:
  HEARTBEAT    → Periodic (configurable, default 5min for supervisor)
  CRON         → Scheduled (e.g., "every 6 hours, check for self-improvement opportunities")
  MAILBOX      → New message received
  WEBHOOK      → External trigger (GitHub push, Slack message)
  WORKER_DONE  → Worker completed task
  HEALTH       → Health check result
  GIT_CHANGE   → Uncommitted changes detected
```

On each event, the supervisor evaluates: "Given this event and my current state, what should I do?" This replaces the crude nudge mechanism with a principled event loop.

#### R5. Progress Ledger System
**Inspiration**: AutoGen Magentic-One dual-ledger, Anthropic progress.txt
**Current**: Supervisor tracks work via journal entries (narrative, not structured)
**Proposal**: Maintain a structured `progress.json`:
```json
{
  "current_task": "implement-meta-events",
  "started_at": "2026-02-20T10:00:00Z",
  "steps_completed": 5,
  "steps_since_progress": 2,
  "status": "in_progress",
  "features": [
    {"name": "event type enum", "status": "done"},
    {"name": "event bus", "status": "in_progress"},
    {"name": "event handlers", "status": "pending"}
  ],
  "last_reflection": "Event bus implemented but needs testing. Worker delegation working."
}
```
If `steps_since_progress` exceeds a threshold, trigger self-reflection and replanning.

#### R6. Checkpoint-Based Recovery
**Inspiration**: LangGraph checkpointing
**Current**: Git rollback on health failure (blunt instrument)
**Proposal**: Before each major operation, create a structured checkpoint:
```json
{
  "checkpoint_id": "cp-20260220-1000",
  "git_sha": "abc123",
  "active_workers": ["worker-1", "worker-2"],
  "mailbox_state": "hash...",
  "backlog_state": "hash...",
  "journal_position": 42
}
```
On recovery, restore to the latest checkpoint rather than just rolling back git. This preserves worker state, mailbox contents, and backlog position.

### Tier 3: Strategic Capabilities (High Effort, Transformative)

#### R7. Event-Sourced Journal
**Inspiration**: OpenHands event-sourced state model
**Current**: Journal is Markdown narrative
**Proposal**: Convert the journal to an append-only event log:
```jsonl
{"ts": "...", "type": "task_started", "agent": "supervisor", "task": "implement-meta-events"}
{"ts": "...", "type": "worker_spawned", "agent": "supervisor", "worker": "impl-meta-events"}
{"ts": "...", "type": "tool_use", "agent": "impl-meta-events", "tool": "Edit", "file": "src/events.py"}
{"ts": "...", "type": "task_completed", "agent": "impl-meta-events", "result": "success"}
```
Benefits: Deterministic replay, precise debugging, automatic resume from last event, structured queries.

#### R8. Dependency-Driven Worker Activation
**Inspiration**: MetaGPT publish-subscribe, CrewAI task context chains
**Current**: Supervisor manually routes all messages and spawns workers
**Proposal**: Workers declare input dependencies. When dependencies are satisfied (upstream worker completes, data arrives), workers auto-activate:
```yaml
worker: code-reviewer
  depends_on: [code-writer.DONE]
  auto_start: true

worker: tester
  depends_on: [code-reviewer.APPROVED]
  auto_start: true
```
This creates a pipeline that flows automatically, reducing supervisor overhead.

#### R9. Pattern Crystallization
**Inspiration**: OpenClaw Foundry, BabyAGI 2.0 self-building
**Current**: Supervisor learns through journal entries (narrative memory)
**Proposal**: Track workflow patterns (goal → steps → outcome → duration). When a pattern reaches 5+ uses with 70%+ success rate, auto-generate a dedicated tool/skill. Example: if the supervisor repeatedly spawns a debate pair for architecture decisions, crystallize a `debate-architecture` skill that automates the setup.

---

## Summary Table: Recommendations by Priority

| # | Recommendation | Effort | Impact | Inspiration |
|---|---------------|--------|--------|-------------|
| R1 | Structured completion signals | Low | High | CAMEL-AI |
| R2 | Worker max_react_loop watchdog | Low | Medium | MetaGPT |
| R3 | Stuck detection heuristics | Low | High | OpenHands, SuperAGI |
| R4 | Event-driven autonomy pulse | Medium | Very High | OpenClaw |
| R5 | Progress ledger system | Medium | High | AutoGen Magentic-One, Anthropic |
| R6 | Checkpoint-based recovery | Medium | High | LangGraph |
| R7 | Event-sourced journal | High | Very High | OpenHands |
| R8 | Dependency-driven worker activation | High | High | MetaGPT, CrewAI |
| R9 | Pattern crystallization | High | Transformative | OpenClaw Foundry, BabyAGI 2.0 |

---

## Appendix: Sources

### OpenClaw
- [github.com/openclaw/openclaw](https://github.com/openclaw/openclaw)
- [docs.openclaw.ai](https://docs.openclaw.ai)
- Previous research: `.cmux/journal/2026-02-20/artifacts/openclaw-research-and-autonomy-vision.md`

### AutoGPT / AgentGPT
- [github.com/Significant-Gravitas/AutoGPT](https://github.com/Significant-Gravitas/AutoGPT)
- [github.com/reworkd/AgentGPT](https://github.com/reworkd/AgentGPT)
- [AutoGPT Re-Architecture Issue #4770](https://github.com/Significant-Gravitas/AutoGPT/issues/4770)
- [AutoGPT Heartbeat PR #8665](https://github.com/Significant-Gravitas/AutoGPT/pull/8665)
- [Decoding Auto-GPT — Maarten Grootendorst](https://www.maartengrootendorst.com/blog/autogpt/)

### CrewAI
- [github.com/crewAIInc/crewAI](https://github.com/crewAIInc/crewAI)
- [docs.crewai.com](https://docs.crewai.com)
- [CrewAI Flows](https://www.crewai.com/crewai-flows)

### BabyAGI
- [github.com/yoheinakajima/babyagi](https://github.com/yoheinakajima/babyagi)
- [Birth of BabyAGI — Yohei Nakajima](https://yoheinakajima.com/birth-of-babyagi/)
- [BabyFoxAGI — Yohei Nakajima](https://yoheinakajima.com/introducing-babyfoxagi-the-next-evolution-of-babyagi/)
- [What is BabyAGI — IBM](https://www.ibm.com/think/topics/babyagi)

### LangGraph
- [github.com/langchain-ai/langgraph](https://github.com/langchain-ai/langgraph)
- [langchain-ai.github.io/langgraph](https://langchain-ai.github.io/langgraph/)
- [deepwiki.com/langchain-ai/langgraph](https://deepwiki.com/langchain-ai/langgraph)
- [Semantic Search for LangGraph Memory](https://blog.langchain.com/semantic-search-for-langgraph-memory/)

### Microsoft AutoGen
- [github.com/microsoft/autogen](https://github.com/microsoft/autogen)
- [Magentic-One](https://microsoft.github.io/autogen/stable/user-guide/agentchat-user-guide/magentic-one.html)
- [Deep Dive into AutoGen Multi-Agent Patterns 2025](https://sparkco.ai/blog/deep-dive-into-autogen-multi-agent-patterns-2025)

### Semantic Kernel
- [learn.microsoft.com/semantic-kernel](https://learn.microsoft.com/en-us/semantic-kernel/)
- [Planning with Automatic Function Calling](https://devblogs.microsoft.com/semantic-kernel/planning-with-semantic-kernel-using-automatic-function-calling/)

### MetaGPT
- [github.com/FoundationAgents/MetaGPT](https://github.com/FoundationAgents/MetaGPT)
- [MetaGPT Paper (arXiv)](https://arxiv.org/abs/2308.00352)
- [MetaGPT Think and Act Docs](https://docs.deepwisdom.ai/main/en/guide/tutorials/agent_think_act.html)

### Claude Code / Anthropic
- [code.claude.com/docs](https://code.claude.com/docs/en/how-claude-code-works)
- [Effective Harnesses for Long-Running Agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Building Agents with Claude Agent SDK](https://www.anthropic.com/engineering/building-agents-with-the-claude-agent-sdk)

### Devin / SWE-Agent / OpenHands
- [OpenHands SDK Paper (arXiv)](https://arxiv.org/html/2511.03690v1)
- [docs.openhands.dev/sdk](https://docs.openhands.dev/sdk)
- [Devin 2.0 Announcement](https://cognition.ai/blog/devin-2)
- [SWE-Agent Paper (arXiv)](https://arxiv.org/abs/2405.15793)

### SuperAGI
- [github.com/TransformerOptimus/SuperAGI](https://github.com/TransformerOptimus/SuperAGI)
- [superagi.com/docs](https://superagi.com/docs/)

### CAMEL-AI
- [github.com/camel-ai/camel](https://github.com/camel-ai/camel)
- [CAMEL Paper (arXiv)](https://arxiv.org/abs/2303.17760)

### Agency Swarm
- [github.com/VRSEN/agency-swarm](https://github.com/VRSEN/agency-swarm)
- [agency-swarm.ai](https://agency-swarm.ai/)

### Microsoft TaskWeaver
- [TaskWeaver Paper (arXiv)](https://arxiv.org/html/2311.17541v3)
- [github.com/microsoft/TaskWeaver](https://github.com/microsoft/TaskWeaver)

### HuggingGPT / JARVIS
- [HuggingGPT Paper (arXiv)](https://arxiv.org/pdf/2303.17580)
- [github.com/microsoft/JARVIS](https://github.com/microsoft/JARVIS)
