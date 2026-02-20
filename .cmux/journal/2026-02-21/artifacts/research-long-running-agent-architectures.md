# Research Report: Long-Running Autonomous AI Agent Architectures

*Generated 2026-02-21 by Supervisor Prime research agent*

## 1. Memory and Context Management

### The Three-Tier Memory Model

The consensus across research (including the NeurIPS 2025 A-MEM paper, the December 2025 "Memory in the Age of AI Agents" survey, and multiple framework implementations) is that persistent agents need three distinct types of long-term memory:

**Episodic Memory** -- stores specific past events and experiences. An agent remembers "last time I tried to refactor the auth module, the tests broke because of circular imports." This is the raw record of what happened, including failures and successes. Implementation: typically a timestamped log or database of (action, context, outcome) tuples, often with vector embeddings for semantic retrieval.

**Semantic Memory** -- stores generalized knowledge, facts, and learned rules. This is distilled from episodic memory over time. "The auth module depends on the user module; always run auth tests after user module changes." Implementation: knowledge graphs, structured databases, or embedding-indexed fact stores.

**Procedural Memory** -- stores learned skills and operational patterns. "The optimal process for deploying is: run tests, build, stage, smoke test, promote." Implementation: stored as reusable prompt templates, tool-calling sequences, or explicit workflow definitions.

The critical insight: **memory consolidation** is the mechanism that makes agents get better over time. Raw episodic experiences get consolidated into semantic facts and procedural patterns.

### A-MEM: The State of the Art

A-MEM (NeurIPS 2025) introduced a self-organizing memory system based on the Zettelkasten method:
- **Atomic note-taking**: Each memory is a structured note with contextual descriptions, keywords, and tags
- **Dynamic linking**: When new memories arrive, the system retrieves related historical memories and determines whether connections should be established
- **Memory evolution**: Historical memories get updated with new experiences, developing higher-order attributes over time

Directly relevant to CMUX: the journal system is already episodic memory. What's missing is the consolidation step that turns journal entries into reusable semantic knowledge and the linking step that connects related experiences.

### How Claude Code Manages Context

- Fixed overhead: system prompt (5-15K tokens), CLAUDE.md files (1-10K), tool schemas
- Usable context: ~140-150K tokens for conversation and tool results
- Auto-compaction triggers at ~83.5% usage
- Compaction process: analyze conversation, identify key information, create concise summary, replace old messages with summary

### Concrete Implementation Patterns

From LangGraph's memory architecture:
- **Short-term memory**: Message history within a session, checkpointed to database so threads can resume
- **Long-term memory**: Cross-thread stores with vector search, shared across sessions
- **Checkpointing**: Every state transition is persisted, enabling replay, resumption after failure, and time-travel between states

## 2. Autonomy Loops

### How Long-Running Agents Decide What to Do

**The Core Autonomy Loop:**
1. Check for explicit tasks/messages (highest priority)
2. Check for in-progress work that needs continuation
3. Check for scheduled/deferred tasks whose time has come
4. If idle: scan for maintenance work, improvements, or backlog items
5. If truly nothing to do: schedule a self-check-in for later

Tmux-Orchestrator implements this with self-scheduling:
- Agents use `schedule_with_note.sh` to schedule their own future check-ins with specific, actionable notes
- When the timer fires, the agent picks up exactly where it left off with the note as context
- This creates a persistent work loop that survives detachment and reconnection

BabyAGI's key insight: separate the "what should I do next" decision from the "do the thing" execution. Use a priority queue, not a FIFO.

### Preventing Infinite Loops and Useless Work

**Detection mechanisms:**
- **Action history tracking**: Hash recent actions, detect when the same operation repeats 3+ times or oscillates between two states (A-B-A-B pattern)
- **Result comparison**: When the same tool returns identical results multiple times consecutively, the agent is stuck
- **Progress checkpointing**: Compare system state snapshots over time; if state is unchanged across multiple attempts, progress has stalled

**Prevention strategies:**
- **Hard limits**: Cap tool calls per task (start at 5-10 steps), set max tokens per run, implement per-task cost ceilings
- **Failure memory**: Document unsuccessful attempts explicitly; require meaningfully different approaches rather than retries
- **Diversity enforcement**: Maintain a record of attempted actions, reject duplicates
- **Separation of planning and execution**: Limit replanning attempts separately from execution steps
- **Escalation paths**: After N failed attempts, escalate to supervisor or human with a summary of what was tried

## 3. Self-Improvement Patterns

### The Reflection Pattern

The Reflexion architecture is the most practical self-improvement pattern:
1. **Generate**: Agent attempts a task
2. **Evaluate**: Outcome is assessed (tests pass/fail, user feedback, self-evaluation)
3. **Reflect**: Agent critiques its own approach, identifying what went wrong
4. **Store**: Lessons learned are saved in plain language
5. **Retry with lessons**: Next attempt includes accumulated lessons

Measured results: On HumanEval, a Reflexion-augmented GPT-4 agent reached 91% success vs 80% without reflection.

### DSPy: Automated Prompt Optimization

DSPy treats prompts as programs that can be automatically optimized:
- **COPRO**: Generates and refines new instructions for each step
- **MIPROv2**: Optimizes instructions and few-shot examples using Bayesian Optimization
- **SIMBA**: Uses stochastic mini-batch sampling to identify challenging examples and generate self-reflective improvement rules

Practical results: accuracy from 46.2% to 64.0% through systematic prompt optimization.

### AlphaEvolve Pattern (Google DeepMind, May 2025)

Evolutionary optimization where the LLM generates variations of its own instructions/code, evaluates them against metrics, and selects the best candidates for further iteration.

## 4. Multi-Agent Coordination

### Four Orchestration Patterns

**1. Orchestrator-Worker (Centralized)** — what CMUX currently uses
- Single supervisor decomposes tasks, delegates to workers, synthesizes results
- Pros: Clear accountability, easy to reason about
- Cons: Supervisor is bottleneck and single point of failure

**2. Hierarchical**
- Layered delegation: orchestrator -> project managers -> engineers
- Tmux-Orchestrator uses this three-tier model to manage context window limitations
- Pros: Scales better, enables parallel workstreams

**3. Blackboard/Shared State**
- All agents read/write to a shared knowledge store
- Agents independently decide to act when they see relevant information
- Pros: Loosely coupled, agents can be added/removed dynamically

**4. Event-Driven/Market-Based**
- Work items are claimed by available agents with matching capabilities
- Pros: Highly scalable, natural load balancing, resilient to individual failures

### Failure Recovery Patterns

- **Checkpoint-based recovery**: Save state at every step, resume from last good checkpoint
- **Task re-queuing**: Failed tasks return to queue with failure context attached
- **Circuit breakers**: After N failures of a particular type, stop attempting that category and escalate

## 5. Notable Open-Source Projects

### Most Relevant to CMUX

| Project | Architecture | Key Innovation |
|---------|-------------|----------------|
| **Tmux-Orchestrator** | Three-tier hierarchy in tmux | Self-scheduling check-ins, LEARNINGS.md knowledge accumulation, 30-min auto-commits |
| **Agent Conductor** | CLI-first supervisor/worker in tmux | Canned workflows, approval gates, API-driven status relay |
| **AI Maestro** | Peer mesh, agent-to-agent messaging | AMP protocol, code graph visualization, multi-machine networking |
| **Claude Code Agent Farm** | Parallel Claude Code sessions | Lock-based coordination for 20+ agents |
| **Claude-Flow** | Swarm intelligence with MCP | 87 MCP tools, RAG integration, distributed swarm intelligence |
| **Agent Deck** | TUI for multi-agent tmux sessions | Session forking with context inheritance, smart status detection |

### Broader Ecosystem

| Project | Type | Status |
|---------|------|--------|
| **OpenHands** (formerly OpenDevin) | Sandboxed coding agent platform | Docker-sandboxed, bash/browser/IPython interface |
| **CrewAI** | Role-based multi-agent framework | Mature, role/goal/backstory model |
| **MetaGPT** | Software company simulation | Full documentation pipeline |
| **LangGraph** | Durable agent framework | v1.0 Jan 2026, graph-based state machines with checkpointing |
| **DSPy** | Prompt programming framework | Automated prompt optimization |
| **Open SWE** | Async coding agent | Cloud-native, parallel task execution |

## 6. Concrete Takeaways for CMUX

### High Impact, Low Effort

**1. Structured Failure Memory** — Add a "lessons learned" field to journal that records: what failed, why, what was tried, what worked instead. Query before starting related tasks.

**2. Stuck Agent Detection Watchdog** — Track sliding window of recent tool calls per agent. Same tool+args N times in M calls = stuck. Escalate to supervisor.

**3. Self-Scheduling Check-ins** — Agents schedule their own future wake-ups with context notes. Better than fixed heartbeat because it carries forward actionable context.

### High Impact, Medium Effort

**4. Memory Consolidation Pipeline** — Daily: summarize journal into "today's learnings". Weekly: consolidate into updated rules. Store as `LEARNINGS.md` fed into agent context.

**5. Reflection-After-Task** — After every task: "What worked? What failed? What differently next time?" Store structured reflections, periodically update role templates.

**6. Lock-Based Coordination** — Lock files prevent two workers from modifying the same files simultaneously.

### High Impact, High Effort

**7. Hierarchical Agent Architecture** — Three-tier (supervisor -> team leads -> workers). Team leads manage domain context, only escalate cross-cutting concerns.

**8. Event-Driven Mailbox with Priority Queuing** — Priority levels, capability matching, failed task re-queuing with failure context.

**9. Automated Instruction Evolution** — DSPy-inspired loop evaluating instructions against outcomes, proposing refinements. Supervisor reviews and approves.

## Sources

- A-MEM: Agentic Memory for LLM Agents (NeurIPS 2025) — arxiv.org/abs/2502.12110
- Memory in the Age of AI Agents Survey — arxiv.org/abs/2512.13564
- Tmux-Orchestrator — github.com/Jedward23/Tmux-Orchestrator
- Agent Conductor — github.com/gaurav-yadav/agent-conductor
- AI Maestro — github.com/23blocks-OS/ai-maestro
- Claude Code Agent Farm — github.com/Dicklesworthstone/claude_code_agent_farm
- Claude-Flow — github.com/ruvnet/claude-flow
- Agent Deck — github.com/asheshgoplani/agent-deck
- DSPy — dspy.ai
- Reflexion — promptingguide.ai/techniques/reflexion
- LangGraph Memory — docs.langchain.com/oss/python/langgraph/memory
- Confluent Event-Driven Multi-Agent Systems — confluent.io/blog/event-driven-multi-agent-systems/
- Kore.ai Orchestration Patterns — kore.ai/blog/choosing-the-right-orchestration-pattern-for-multi-agent-systems
