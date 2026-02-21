# Autonomous LLM Agent Systems: Research Survey for CMUX Self-Improvement

> **Author**: Nova (perm-research)
> **Date**: 2026-02-21
> **Purpose**: Identify concrete, implementable improvements to CMUX based on state-of-the-art research in autonomous LLM agent systems.

---

## Executive Summary

After surveying recent research (2024-2026) across memory systems, retrieval-augmented cognition, multi-agent coordination, self-improvement patterns, and cognitive architectures, the most actionable improvements for CMUX fall into three tiers:

### Tier 1: High Impact, Low Effort (implement now)
1. **Structured memory notes with linking** (A-MEM pattern) — transform CMUX's flat journal entries into interconnected knowledge notes with keywords, tags, and cross-references
2. **Observation masking for compaction** — replace or supplement LLM summarization with simpler observation masking (JetBrains research shows it's cheaper and often better)
3. **Skill library pattern** (Voyager) — formalize the `tools/` directory as a self-extending skill library where agents can propose and create new tools

### Tier 2: Medium Impact, Medium Effort (plan and build)
4. **Tiered memory architecture** (Letta/MemGPT pattern) — add archival memory with vector embeddings alongside the existing journal for semantic retrieval
5. **Sleep-time memory consolidation** — batch-process journal entries during idle periods to extract and link semantic knowledge
6. **Structured intermediate outputs** (MetaGPT pattern) — require agents to produce structured artifacts (not just chat messages) at each stage of task execution

### Tier 3: High Impact, High Effort (research further)
7. **Episodic memory framework** — implement the five-property episodic memory model for richer agent recall
8. **Prompt self-optimization** (OPRO pattern) — agents refine their own role files based on task outcomes
9. **Graph-based memory** (Mem0g pattern) — entity-relationship graphs for agent knowledge

---

## 1. Memory Systems for Long-Running Agents

### 1.1 Letta/MemGPT: Tiered Memory as an OS

**Key insight**: Treat the context window as RAM and external storage as disk. The agent manages its own memory through tool calls, moving information between tiers.

**Architecture** (from [Letta docs](https://docs.letta.com/concepts/memgpt/)):
| Tier | Analogy | CMUX Equivalent | Gap |
|------|---------|-----------------|-----|
| Message Buffer | CPU registers | Current conversation | Exists |
| Core Memory | RAM (in-context) | MEMORY.md + role files | Exists but static |
| Recall Memory | Disk (searchable history) | Journal entries | Exists but unsearchable semantically |
| Archival Memory | Cold storage (vector DB) | None | **Missing** |

**Self-editing memory**: Letta agents rewrite their own core memory blocks using tool calls. Each block has a label, description, value, and character limit. The agent decides what to remember and what to forget.

**Letta V1 evolution** ([blog post](https://www.letta.com/blog/letta-v1-agent)): Moved from ReAct-style tool loops to native reasoning. Key lesson: agent architecture must align with how models are trained. Forced tool-call patterns (like heartbeat flags) create friction with modern reasoning models.

**CMUX relevance**: Our `MEMORY.md` + journal system is a primitive version of core + recall memory. The critical missing piece is **archival memory** — a searchable, semantically-indexed store that agents can query. Currently, journal search is text-only via `grep` or the `/api/journal/search` endpoint. Adding vector embeddings would enable semantic retrieval of past decisions, patterns, and lessons.

### 1.2 A-MEM: Zettelkasten-Inspired Agentic Memory

**Key insight**: Memories should be structured notes with metadata, not flat text. Notes link to each other, forming a knowledge graph that evolves as new information arrives.

**Architecture** ([arxiv 2502.12110](https://arxiv.org/abs/2502.12110), NeurIPS 2025):

Each memory note contains:
- Original content (c_i)
- Timestamp (t_i)
- LLM-generated keywords (K_i)
- Categorical tags (G_i)
- Contextual description (X_i)
- Embedding vector (e_i)
- Linked memory references (L_i)

**Link generation**: Two-stage process:
1. Cosine similarity between embeddings to find candidate connections
2. LLM analysis to validate and describe the relationship

**Memory evolution**: When a new memory is added, it can trigger updates to existing memories' descriptions and tags. The knowledge network continuously refines itself.

**CMUX relevance**: This is directly applicable. Our journal entries are flat markdown with titles, content, and manual tags. We could:
1. Auto-generate keywords and tags from journal content
2. Compute embeddings for each entry
3. Link related entries (e.g., "this bug fix relates to the architecture decision from 3 days ago")
4. Surface connected memories when agents start related tasks

### 1.3 Hierarchical Memory: Working → Episodic → Semantic

**Key insight**: Different memory types serve different purposes. Working memory holds the current task. Episodic memory stores specific experiences. Semantic memory holds generalized knowledge extracted from episodes.

**Research highlights**:
- **HiAgent**: Chunks working memory using subgoals, summarizing action-observation pairs when goals complete. Retains hierarchical context. ([emergentmind.com](https://www.emergentmind.com/topics/memory-mechanisms-in-llm-based-agents))
- **MIRIX**: Multi-module system with Core, Episodic, Semantic, Procedural, Resource, and Knowledge Vault memories, each with type-specific fields and access policies.
- **Episodic Memory Position Paper** ([arxiv 2502.06975](https://arxiv.org/abs/2502.06975)): Argues episodic memory is the missing piece for long-term agents. Proposes five properties:
  1. Long-term storage
  2. Explicit reasoning over stored memories
  3. Single-shot learning (capture from one exposure)
  4. Instance-specific memories (not just generalized facts)
  5. Contextual relations (when, where, why, how)

**Consolidation pathway**: Episodic → Semantic is the primary mechanism for lifelong learning. Specific experiences ("the auth fix failed because of circular imports") consolidate into general knowledge ("watch for circular imports in the auth module").

**CMUX relevance**: Our journal system captures episodic memories (specific events) but lacks:
- Automated consolidation from episodic → semantic (journal → MEMORY.md)
- Contextual binding (linking memories to the files, agents, and decisions they relate to)
- Single-shot learning formalization (capturing lessons immediately, not just when we remember to journal)

### 1.4 Context Compression: Masking vs. Summarization

**Key insight**: Simpler compression often beats sophisticated summarization.

**JetBrains Research** ([blog](https://blog.jetbrains.com/research/2025/12/efficient-context-management/)):
- **Observation masking**: Replace older environment observations with placeholders, keep agent reasoning intact. Won 4/5 benchmarks.
- **LLM summarization**: Compress past interactions. More expensive, agents ran 13-15% longer because summaries masked "stop signals."
- **Hybrid**: Masking as primary, selective summarization as supplement. Best overall.
- **Cost**: Both approaches achieved >50% cost savings vs. unmanaged context.

**Mem0** ([arxiv 2504.19413](https://arxiv.org/abs/2504.19413)):
- Two-phase pipeline: Extraction (identify candidate memories from conversation) → Update (consolidate into store)
- Graph-based variant (Mem0g) stores memories as directed labeled graphs with entity extraction and relation generation
- 91% lower p95 latency, >90% token cost savings
- 26% accuracy improvement over OpenAI's memory system

**CMUX relevance**: Our current compaction process uses Claude's built-in summarization. The JetBrains research suggests we might get better results by:
1. Preserving agent reasoning/decisions verbatim
2. Masking older tool outputs and environment observations
3. Only summarizing when the masked context still exceeds limits

---

## 2. Retrieval-Augmented Agent Cognition

### 2.1 Self-RAG: Agents That Know When to Retrieve

**Key insight**: Not every query needs retrieval. Agents should decide *when* and *how much* to retrieve, then self-critique the retrieved content.

**Self-RAG** trains models to:
1. Decide whether retrieval is needed for the current step
2. Retrieve if needed
3. Critique retrieved content for relevance
4. Generate response with or without retrieved content
5. Self-evaluate output quality

**CMUX relevance**: Our agents currently do manual journal searches (`./tools/journal read`, `grep`). A self-RAG pattern would let agents automatically retrieve relevant past decisions before starting new tasks — without requiring the supervisor to manually search and include context.

### 2.2 Graph RAG and Structured Retrieval

**Key insight**: Vector similarity alone misses relational context. Knowledge graphs capture entity relationships that embeddings flatten.

**Microsoft GraphRAG**: Builds entity-relationship graphs over corpus, enabling both local (specific entity) and global (theme-level) retrieval.

**LightRAG**: Combines knowledge graphs with vector retrieval for hybrid local/global search.

**A-RAG** ([arxiv 2602.03442](https://arxiv.org/html/2602.03442v1)): Hierarchical retrieval interfaces that scale agentic retrieval.

**CMUX relevance**: Our codebase knowledge is scattered across:
- Journal entries (narrative)
- MEMORY.md (curated facts)
- CLAUDE.md (project conventions)
- Role files (agent-specific context)
- Git history (change patterns)

A graph connecting these sources — agents → tasks → files → decisions → outcomes — would enable queries like "what happened last time someone changed the WebSocket manager?" that currently require manual archaeology.

### 2.3 Embedding-Based vs. Structured Retrieval

| Approach | Strengths | Weaknesses | CMUX Fit |
|----------|-----------|------------|----------|
| Vector embeddings | Semantic similarity, fuzzy matching | Loses structure, requires embedding model | Good for journal search |
| SQL/structured | Exact queries, relational data | Rigid schema, no semantic matching | Good for task/agent registry |
| Knowledge graph | Relational reasoning, multi-hop queries | Complex to build and maintain | Aspirational for cross-session knowledge |
| Hybrid | Best of all worlds | Implementation complexity | Ideal long-term target |

**Practical recommendation for CMUX**: Start with vector embeddings on journal entries (low effort, high value), add structured queries on the existing SQLite databases, defer graph-based retrieval until the volume of knowledge justifies the complexity.

---

## 3. Multi-Agent Coordination Patterns

### 3.1 Framework Comparison

| Framework | Coordination Model | Memory Model | Task Decomposition | CMUX Parallel |
|-----------|-------------------|--------------|-------------------|---------------|
| **CrewAI** | Role-based (workplace metaphor) | Shared memory + individual context | Hierarchical delegation | Very similar to our supervisor→worker model |
| **AutoGen** | Conversation-driven | Conversation history as shared memory | Through dialogue | Our mailbox system |
| **MetaGPT** | SOP-driven (structured outputs) | Structured artifacts as shared state | Role-based pipeline | Closest to our team template approach |
| **LangGraph** | Graph-based workflows | Checkpointed state + stores | Conditional branching | More structured than our approach |

### 3.2 MetaGPT: SOPs and Structured Outputs

**Key insight**: The biggest source of multi-agent failure is ambiguous intermediate outputs. MetaGPT's breakthrough was requiring structured artifacts at each stage.

**Architecture** ([arxiv 2308.00352](https://arxiv.org/abs/2308.00352), ICLR 2024 Oral):
- Five roles: Product Manager, Architect, Project Manager, Engineer, QA
- Each role produces structured outputs: PRDs, system designs, task lists, code, test reports
- SOPs define the pipeline: requirements → design → implementation → testing
- Structured intermediate outputs "significantly increase the success rate of target code generation"

**CMUX relevance**: Our current workflow is:
1. Supervisor assigns task (free text)
2. Worker does the work
3. Worker reports [DONE] (free text summary)

MetaGPT suggests we should formalize intermediate artifacts:
- Task assignment should include structured context (files to modify, acceptance criteria, constraints)
- Workers should produce structured [DONE] reports (files changed, tests run, decisions made)
- Reviews should follow structured templates (which we already do with Flint and Sage)

### 3.3 Shared vs. Isolated Memory

| Pattern | Pros | Cons | When to Use |
|---------|------|------|-------------|
| **Fully shared** (all agents see everything) | No information loss | Context pollution, scaling issues | Small teams, tightly coupled work |
| **Fully isolated** (agents only see own context) | Clean contexts, parallel work | Duplication, coordination overhead | Independent tasks |
| **Hybrid** (shared store + private context) | Balanced | Implementation complexity | **Most production systems use this** |

**CMUX's current model**: Hybrid — agents have private context (tmux windows) with shared communication (mailbox) and shared persistent memory (journal). This aligns with best practices.

**Gap**: No mechanism for agents to query *other agents' knowledge* without going through the supervisor. A shared knowledge store (beyond the journal) would help.

### 3.4 Task Decomposition Patterns

**CrewAI approach**: Hierarchical — a "crew" has a manager agent that decomposes and delegates. Very similar to our supervisor model.

**AutoGen approach**: Conversational — agents negotiate task boundaries through dialogue. More flexible but less predictable.

**LangGraph approach**: Graph-based — tasks are nodes in a DAG with conditional edges. Most structured but requires upfront workflow design.

**CMUX insight**: Our supervisor-based decomposition is the right default. Where we could improve: the supervisor currently decomposes tasks intuitively. A more structured decomposition (like LangGraph's DAG) for complex tasks would improve reliability. The team templates in `docs/templates/teams/` are a step toward this.

---

## 4. Self-Improvement and Meta-Learning

### 4.1 Reflexion: Learning from Verbal Feedback

**Key insight**: Instead of updating model weights, store verbal self-reflections in an episodic memory buffer. Use these reflections to improve future attempts.

**Architecture** ([arxiv 2303.11366](https://arxiv.org/abs/2303.11366)):
1. Agent attempts task
2. Evaluator provides feedback (success/failure + details)
3. Self-reflection module generates a verbal analysis of what went wrong
4. Reflection stored in memory buffer
5. Next attempt includes relevant reflections in context

**Results**: 22% absolute improvement on AlfWorld decision-making tasks in 12 iterative steps.

**CMUX relevance**: We already have a primitive version of this:
- Workers journal their work (episodic logging)
- The supervisor checks journal for past failures before delegating ("Failure Memory" in SUPERVISOR_ROLE.md)
- But it's **manual** — the supervisor must remember to search

An automated Reflexion loop would:
1. After each task completion, generate a structured reflection (what worked, what didn't, what to do differently)
2. Store reflections tagged to the task type, files touched, and patterns encountered
3. Automatically inject relevant reflections when similar tasks are assigned

### 4.2 LATS: Tree Search for Agent Reasoning

**Key insight**: Don't commit to the first reasoning path. Explore multiple paths, evaluate them, and pursue the most promising one.

**LATS (Language Agent Tree Search)** combines:
- Reflection (evaluate past attempts)
- Monte Carlo Tree Search (explore multiple paths)
- LLM-based evaluation (score reasoning paths)

**CMUX relevance**: Lower applicability for our use case. LATS is best for single-agent reasoning tasks, not multi-agent coordination. However, the principle of "explore before committing" could apply to our debate pair pattern — which already implements a form of adversarial exploration.

### 4.3 Prompt Self-Optimization (OPRO and variants)

**Key insight**: LLMs can optimize their own prompts by treating prompt engineering as an optimization problem.

**OPRO** ([arxiv](https://openreview.net/forum?id=Bb4VGOWELI), Google DeepMind):
- Describe the optimization target in natural language
- LLM generates candidate prompts
- Evaluate candidates on benchmark tasks
- Best candidates inform next generation
- Results: Up to 8% improvement on GSM8K, up to 50% on Big-Bench Hard

**Recent variants**:
- **AMPO**: Tree-structured multi-branch optimization with conditional logic
- **Adaptive-OPRO**: Online optimization with delayed rewards
- **PromptBreeder** ([ICLR 2024](https://openreview.net/pdf?id=HKkiX32Zw1)): Self-referential self-improvement — prompts evolve mutation operators that in turn evolve task prompts

**CMUX relevance**: High potential, moderate effort. Our role files are essentially optimizable prompts. A self-optimization loop could:
1. Track task outcomes per worker (success rate, revision requests, review scores)
2. Periodically generate candidate improvements to role file sections
3. A/B test improvements across subsequent tasks
4. Merge successful variations back into role files

This would make role files **living documents** that improve automatically based on outcomes, rather than requiring manual updates.

### 4.4 Tool Creation: Agents That Build Their Own Tools

**Voyager Skill Library** ([arxiv 2305.16291](https://arxiv.org/abs/2305.16291)):
- Skills stored as executable code (Python/JS functions)
- Retrieved via embedding similarity to task description
- Compositional: new skills can compose existing skills
- Result: 3.3x more unique items, 15.3x faster milestone achievement

**LATM (LLMs As Tool Makers)** ([arxiv 2305.17126](https://arxiv.org/abs/2305.17126)):
- Tool Maker (powerful model) creates reusable Python functions
- Tool User (lightweight model) applies tools to new problems
- Dispatcher determines if existing tools suffice or new ones are needed
- Performance equivalent to GPT-4 for both roles but at GPT-3.5 cost

**CREATOR**: LLMs create tools through documentation first, then code realization.

**CMUX relevance**: This is highly actionable. Our `tools/` directory is already a manually-curated skill library. We could:
1. Let agents propose new tools when they encounter repetitive patterns
2. Review and test proposed tools through the existing review pipeline
3. Add tools to the library with metadata (description, usage examples, author)
4. Retrieve relevant tools when assigning tasks (like Voyager's skill retrieval)

The key constraint: tool creation needs review (security, correctness). Our adversarial review pipeline (Sage/Flint) is already set up for this.

---

## 5. Cognitive Architecture for Persistent Agents

### 5.1 CoALA: Cognitive Architectures for Language Agents

**Key insight**: Language agents need the same architectural components as classical cognitive architectures (Soar, ACT-R): structured memory, defined action spaces, and explicit decision-making cycles.

**Framework** ([arxiv 2309.02427](https://arxiv.org/abs/2309.02427)):

**Memory modules**:
- **Working memory**: Short-term scratchpad for current context
- **Episodic memory**: Records of specific past events ("what happened last time I tried X?")
- **Semantic memory**: Factual knowledge ("the API uses JWT authentication")
- **Procedural memory**: How to perform tasks (embedded in code or model parameters)

**Action spaces**:
- **Internal actions**: Reasoning, retrieval, memory updates
- **External actions**: Tool use, environment interaction, communication

**Decision cycle**:
1. Retrieve relevant memories
2. Reason about possible actions
3. Propose and evaluate candidates
4. Select and execute best action
5. Observe result
6. Update memories

**CMUX mapping**:
| CoALA Component | CMUX Implementation | Gap |
|----------------|---------------------|-----|
| Working memory | Current conversation context | Adequate |
| Episodic memory | Journal entries | Needs structure + retrieval |
| Semantic memory | MEMORY.md, CLAUDE.md, role files | Needs auto-consolidation |
| Procedural memory | tools/ directory, role file instructions | Needs self-extension |
| Internal actions | Agent reasoning (implicit) | No explicit reasoning traces |
| External actions | Tool calls, mailbox, git | Adequate |
| Decision cycle | Supervisor delegation logic | Could be more structured |

### 5.2 Attention and Priority Systems

**Key insight**: Persistent agents need explicit mechanisms for deciding what to attend to, not just what to do.

**Patterns from research**:
- **Priority queues**: Ranked task lists with urgency/importance scoring (our backlog system)
- **Interrupt handling**: High-priority events preempt current work (our mailbox routing)
- **Attention budgets**: Limit time/tokens on any single task to prevent rabbit holes
- **Salience scoring**: Weight memories by recency, frequency, and relevance (not implemented in CMUX)

**CMUX relevance**: Our `autonomy-check` tool implements a priority cascade (health → blocked → questions → done reports → backlog → idle workers → git → self-improvement). This is a good attention system. What's missing:
- **Salience scoring for memories**: When retrieving past context, we don't weight by relevance
- **Attention budgets**: No mechanism to prevent an agent from spending too long on a tangent
- **Proactive retrieval**: Agents don't automatically check for relevant past experiences

### 5.3 Planning vs. Reactive Balance

**Key insight**: Pure planners over-commit to initial plans. Pure reactive agents lack coherence. The best systems blend deliberative planning with reactive adjustment.

**Patterns**:
- **Hierarchical Task Networks (HTN)**: Decompose goals into subgoals, subgoals into actions. Adjust plan when actions fail.
- **BDI (Belief-Desire-Intention)**: Maintain beliefs about world state, desires about goals, and intentions about current plan. Re-plan when beliefs change.
- **Reactive planning**: Plan one step ahead based on current state. Simple but can miss long-term coherence.

**CMUX currently**: Our supervisor is largely reactive (respond to messages, delegate tasks). The backlog system adds some planning capability. The debate pair pattern enables deliberative planning for complex decisions. This is a reasonable balance.

---

## Concrete Recommendations for CMUX

Ranked by impact-to-effort ratio. Each includes a specific implementation sketch.

### R1: Structured Journal Notes with Auto-Linking
**Impact**: High | **Effort**: Low-Medium | **Source**: A-MEM

**What**: Transform flat journal entries into structured notes with auto-generated keywords, tags, and cross-references.

**Implementation**:
1. Modify `./tools/journal` to accept optional `--tags` and `--related` flags
2. After writing each entry, use a lightweight LLM call to extract keywords and suggest tags
3. Store metadata alongside entry (could be YAML frontmatter or a parallel JSON index)
4. When writing a new entry, auto-search for related entries and append "Related:" links
5. Expose a `journal search --semantic` command that uses keyword/tag matching

**Why**: This turns the journal from a write-only log into a queryable knowledge base. Agents can find relevant past decisions before starting tasks — which is currently the supervisor's manual responsibility.

### R2: Observation Masking for Compaction
**Impact**: High | **Effort**: Low | **Source**: JetBrains Research

**What**: When compacting agent context, preserve reasoning and decisions verbatim but mask older tool outputs.

**Implementation**:
1. In `compact.sh`, modify the compaction prompt to instruct: "Preserve all agent reasoning, decisions, and status messages verbatim. Replace tool output blocks older than N turns with `[tool output omitted — see journal for details]`."
2. Before compaction, auto-journal any unreported decisions or findings
3. After compaction, inject the compaction recovery artifact (already exists)

**Why**: JetBrains research shows this is cheaper and often more effective than full summarization. It prevents the "smooth over stop signals" problem where summarization hides signs that the agent should change approach.

### R3: Automated Reflexion After Task Completion
**Impact**: High | **Effort**: Low | **Source**: Reflexion

**What**: Auto-generate structured reflections after every task, tagged for retrieval.

**Implementation**:
1. Modify the worker [DONE] protocol to include a mandatory reflection step (already partially exists in WORKER_ROLE.md)
2. Formalize the reflection format: `{task_type, files_touched, what_worked, what_failed, lesson_learned, tags}`
3. Store reflections as a separate journal type (e.g., `journal reflection "title" "body"`)
4. When supervisor delegates a task, auto-search reflections matching the task type and include relevant ones in the worker's context

**Why**: This closes the learning loop. Currently, lessons are journaled sporadically and retrieved manually. Automation ensures every task contributes to the system's knowledge base.

### R4: Skill Library Formalization
**Impact**: Medium-High | **Effort**: Low | **Source**: Voyager, LATM

**What**: Treat `tools/` as a searchable skill library. Agents can propose new tools.

**Implementation**:
1. Add a `tools/README.md` or `tools/registry.json` listing all tools with descriptions, usage examples, and authorship
2. Add a `tools/propose` script that: takes a description, generates a tool skeleton, submits it for review
3. When assigning tasks, the supervisor checks the tool registry for relevant existing tools and mentions them in the task description
4. Track tool usage frequency to identify which tools are most valuable

**Why**: The `tools/` directory already contains 10+ tools, but new agents don't know about all of them. Making the library discoverable and extensible amplifies the system's capabilities over time.

### R5: Vector-Embedded Journal Search
**Impact**: Medium-High | **Effort**: Medium | **Source**: Mem0, RAG research

**What**: Add vector embeddings to journal entries for semantic search.

**Implementation**:
1. When a journal entry is written, compute an embedding (could use a local model like `all-MiniLM-L6-v2` or an API)
2. Store embeddings in a SQLite table alongside journal metadata
3. Add a `journal search --semantic "query"` command that returns the most relevant entries by cosine similarity
4. Expose via API: `GET /api/journal/semantic-search?q=...`

**Why**: Text search (`grep`) misses semantically related entries with different wording. "Auth token bug" wouldn't find "JWT expiration issue" via text search but would via semantic search. This is the single most impactful retrieval improvement.

### R6: Structured Task Artifacts (MetaGPT-inspired)
**Impact**: Medium | **Effort**: Medium | **Source**: MetaGPT

**What**: Require structured intermediate outputs at each stage of task execution.

**Implementation**:
1. Define task artifact schemas: `TaskAssignment`, `ProgressReport`, `CompletionReport`, `ReviewReport`
2. Modify mailbox message protocol to support structured fields (or use JSON payloads)
3. Supervisor produces structured `TaskAssignment` with: description, acceptance criteria, relevant files, constraints, related past work
4. Workers produce structured `CompletionReport` with: files changed, tests run, decisions made, open questions

**Why**: MetaGPT's research shows structured intermediate outputs significantly reduce multi-agent failure modes. Free-text messages are ambiguous; structured artifacts are precise.

### R7: Sleep-Time Memory Consolidation
**Impact**: Medium | **Effort**: Medium | **Source**: Letta, Episodic Memory research

**What**: During idle periods, batch-process recent journal entries to extract and consolidate knowledge.

**Implementation**:
1. Add a `consolidate` command to the journal tool
2. When triggered (manually or by idle detection), read recent entries and generate:
   - Updated MEMORY.md sections (if patterns are confirmed)
   - New cross-links between related entries
   - Extracted "lessons learned" from reflection entries
3. Run during heartbeat idle periods (when `autonomy-check` finds no work)

**Why**: This automates the episodic → semantic consolidation pathway. Currently, MEMORY.md is manually maintained. Automated consolidation ensures knowledge compounds over time.

### R8: Role File Self-Optimization
**Impact**: High | **Effort**: High | **Source**: OPRO, PromptBreeder

**What**: Track worker performance metrics and periodically optimize role file sections.

**Implementation**:
1. Track per-worker metrics: tasks completed, revision requests, review pass rate, time per task
2. Periodically (weekly), analyze metrics against role file content
3. Generate candidate improvements to underperforming sections
4. Test improvements on next N tasks
5. Merge successful improvements

**Why**: Role files are the most leveraged artifact in the system — every task a worker does is influenced by its role file. Small improvements compound across all future tasks. But the implementation complexity is high (needs A/B testing infrastructure).

### R9: Entity-Relationship Graph for Cross-Session Knowledge
**Impact**: High | **Effort**: High | **Source**: Mem0g, GraphRAG

**What**: Build a knowledge graph connecting agents, tasks, files, decisions, and outcomes.

**Implementation**:
1. Extract entities (agents, files, functions, decisions) from journal entries and task reports
2. Build relationships (agent → modified → file, decision → caused → outcome)
3. Store in a graph structure (could be SQLite with adjacency tables or a lightweight graph DB)
4. Enable queries: "What has changed in websocket/manager.py recently?" "What decisions affect the auth module?"

**Why**: This is the gold standard for agent self-knowledge. But the implementation complexity (entity extraction, relationship inference, graph maintenance) is significant. Best as a long-term investment.

---

## Open Questions for Follow-Up Research

1. **Embedding model selection**: What's the best lightweight embedding model for code + natural language mixed content? Need one that runs locally without a GPU for CMUX's self-contained architecture.

2. **Memory pruning**: As the journal grows, how should we decide what to forget? The Mem0 conflict detection pattern (detect contradictions, merge/invalidate) is promising but needs adaptation.

3. **Cross-agent memory sharing**: Should agents share embeddings/memories, or should each maintain its own view? Research suggests hybrid approaches work best, but the implementation specifics depend on our scale.

4. **Compaction artifact quality**: Our current compaction produces JSON artifacts. Would a more structured format (following the episodic memory five-property model) improve recovery quality?

5. **Tool proposal governance**: If agents can propose tools, who reviews them? The adversarial review pipeline handles code changes but would need adaptation for tool creation.

6. **Measuring self-improvement**: How do we know if the system is actually getting better over time? Need metrics: task completion rate, revision frequency, time-to-completion, review pass rate. Currently not tracked systematically.

---

## Sources

### Memory Systems
- [Letta: Agent Memory Blog](https://www.letta.com/blog/agent-memory) — Tiered memory architecture
- [MemGPT Paper (arxiv 2310.08560)](https://arxiv.org/abs/2310.08560) — Original OS-inspired memory management
- [Letta V1 Agent Architecture](https://www.letta.com/blog/letta-v1-agent) — Evolution from ReAct to native reasoning
- [A-MEM: Agentic Memory (arxiv 2502.12110)](https://arxiv.org/abs/2502.12110) — Zettelkasten-inspired self-organizing memory (NeurIPS 2025)
- [A-MEM GitHub](https://github.com/agiresearch/A-mem) — Implementation code
- [Episodic Memory Position Paper (arxiv 2502.06975)](https://arxiv.org/abs/2502.06975) — Five properties of episodic memory for agents
- [Mem0 Paper (arxiv 2504.19413)](https://arxiv.org/abs/2504.19413) — Production-ready memory with graph extension
- [Mem0 GitHub](https://github.com/mem0ai/mem0) — Universal memory layer implementation
- [Agent Memory Paper List (GitHub)](https://github.com/Shichun-Liu/Agent-Memory-Paper-List) — Comprehensive paper collection
- [ICLR 2026 MemAgents Workshop Proposal](https://openreview.net/pdf?id=U51WxL382H) — Research agenda for agent memory

### Context Management
- [JetBrains: Efficient Context Management](https://blog.jetbrains.com/research/2025/12/efficient-context-management/) — Masking vs. summarization benchmark
- [LightMem (arxiv 2510.18866)](https://arxiv.org/html/2510.18866v1) — Multi-stage Atkinson-Shiffrin memory model

### RAG and Retrieval
- [A-RAG: Hierarchical Retrieval (arxiv 2602.03442)](https://arxiv.org/html/2602.03442v1) — Scaling agentic retrieval
- [RAG 2025 Guide (EdenAI)](https://www.edenai.co/post/the-2025-guide-to-retrieval-augmented-generation-rag) — Current state overview

### Multi-Agent Coordination
- [MetaGPT Paper (arxiv 2308.00352)](https://arxiv.org/abs/2308.00352) — SOP-driven multi-agent framework (ICLR 2024)
- [MetaGPT GitHub](https://github.com/FoundationAgents/MetaGPT) — Implementation
- [CrewAI vs LangGraph vs AutoGen (DataCamp)](https://www.datacamp.com/tutorial/crewai-vs-langgraph-vs-autogen) — Framework comparison
- [Multi-Agent Frameworks Tier List (LangCopilot)](https://langcopilot.com/posts/2025-11-01-top-multi-agent-ai-frameworks-2024-guide) — Practical evaluation
- [LangGraph Memory Docs](https://docs.langchain.com/oss/python/langgraph/add-memory) — Checkpointing and persistent state

### Self-Improvement
- [Reflexion Paper (arxiv 2303.11366)](https://arxiv.org/abs/2303.11366) — Verbal reinforcement learning
- [OPRO Paper (OpenReview)](https://openreview.net/forum?id=Bb4VGOWELI) — LLMs as prompt optimizers (Google DeepMind)
- [PromptBreeder (ICLR 2024)](https://openreview.net/pdf?id=HKkiX32Zw1) — Self-referential prompt evolution

### Tool Creation
- [Voyager Paper (arxiv 2305.16291)](https://arxiv.org/abs/2305.16291) — Skill library for lifelong learning
- [Voyager Project](https://voyager.minedojo.org/) — Project page
- [LATM Paper (arxiv 2305.17126)](https://arxiv.org/abs/2305.17126) — LLMs as Tool Makers
- [LATM GitHub](https://github.com/ctlllll/LLM-ToolMaker) — Implementation

### Cognitive Architecture
- [CoALA Paper (arxiv 2309.02427)](https://arxiv.org/abs/2309.02427) — Cognitive Architectures for Language Agents
- [CoALA Explained (Cognee)](https://www.cognee.ai/blog/fundamentals/cognitive-architectures-for-language-agents-explained) — Practical breakdown
- [Awesome Language Agents (GitHub)](https://github.com/ysymyth/awesome-language-agents) — Curated list from CoALA authors
