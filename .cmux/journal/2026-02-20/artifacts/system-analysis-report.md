# CMUX Deep System Analysis Report
*Generated: 2026-02-20*

## Part 1: Reliability Audit

**20 issues found across 4 severity levels.**

### CRITICAL (5 issues)

| # | Issue | Root Cause | Status |
|---|-------|-----------|--------|
| 1 | SQLite concurrent access without WAL mode | Python server + 4 bash daemons hit conversations.db with default locking | **FIXED** `5632060` |
| 2 | Mailbox corruption under concurrent writes | No cross-process file locking on JSONL mailbox | **FIXED** `9b894ce` |
| 3 | Router line-marker TOCTOU race | wc -l then tail with no lock between calls | Mitigated by flock |
| 4 | Health daemon hangs during rollback | No timeout on npm ci / uv sync / git reset | **FIXED** `406263f` |
| 5 | Context compaction failure | compact.sh daemon MISSING from codebase | **FIXED** `4938630` |

### HIGH (8 issues)

| # | Issue | Status |
|---|-------|--------|
| 6 | Supervisor can die silently | **FIXED** `634f03c` |
| 7 | Zombie agents accumulate — registry checks window not process | Open |
| 8 | Router skips messages when API down — no retry, marker advances | Open |
| 9 | WebSocket connections lost during restart — no reconnect signal | Open |
| 10 | Health daemon marks rollback healthy without verification | Open |
| 11 | Detached restart can leave server in partial state | Open |
| 12 | Agent registry can become stale | Open |
| 13 | Message router can get stuck if API unavailable | Open |

### MEDIUM (8 issues)

- Journal write interleaving from concurrent agents
- Stale agent registry entries
- Partial line reads from mailbox
- Supervisor startup timeout (vim mode detection)
- Frontend build failures misdiagnosed as bad commits
- No cross-daemon flock coordination (now partially fixed)
- Agent event linking by timestamp (should use auto-increment IDs)
- Router doesn't handle partial line writes

### LOW (4 issues)

- No metrics/observability of message loss
- No graceful shutdown flush
- Port binding errors unclear
- Agent event timestamp edge case

---

## Part 2: Multi-Repo Readiness Assessment

**Overall: 40% ready. Single-project assumptions baked throughout.**

### Hardcoded to "self"

| Layer | Problem | Severity |
|-------|---------|----------|
| Config | `.cmux/` path hardcoded in config.py, all services, all bash scripts | Blocking |
| Git | health.sh rollback targets CMUX repo | Blocking |
| Workers | CMUX_PROJECT_ROOT set once at startup | Blocking |
| File browser | filesystem.py restricted to .cmux/ directory | Blocking |
| Frontend | No concept of "project" — no store, selector, or context | Major gap |
| Sessions | session_manager.py uses os.getcwd() at creation time | Major gap |
| Journal | Per-date only, not per-project | Medium gap |
| Health | Only monitors CMUX server health | Medium gap |
| Claude Code hooks | Assume git repo, no project routing | Minor gap |

### Migration Path

1. Add `target_project_path` to Settings + Session model
2. Make `.cmux` operations project-aware (or session-per-project)
3. Add project context to all API routes
4. Build project selector in frontend
5. Separate CMUX health from project-specific health

---

## Part 3: Industry Landscape (Early 2026)

### Where CMUX is ahead
- **Self-healing**: health.sh with escalating recovery is more sophisticated than LangGraph, CrewAI, or Agent Teams
- **Observability**: Journal + dashboard + real-time WebSocket activity feed
- **File-based resilience**: JSONL mailbox survives server restarts

### Where CMUX is behind
| Gap | Industry Standard | CMUX Today |
|-----|-------------------|------------|
| Context management | Structured compaction at 60%, event-based logs | Auto-compact at 95%, narrative journal |
| Agent budgets | Per-agent iteration/token/time limits | None |
| Audit trail | OpenTelemetry-compatible traces | **FIXED** `c3f3a5f` |
| Permission boundaries | Per-agent tool allowlists | All agents run --dangerously-skip-permissions |
| Task lifecycle | A2A-style states | **FIXED** `bfa3465` |
| Human approval gates | Risk-based approval tiers | No approval queue |
| Agent capability cards | JSON manifests per agent | Agents are generic |

### Key Industry Developments
- **Claude Code Agent Teams** (Feb 2026): Native multi-agent, potential hybrid with CMUX
- **Google A2A Protocol**: Formal inter-agent communication standard
- **Context Engineering**: Treat context as a system, not just a token budget
- **Observational Memory**: Event-based decision logs, 10x cheaper than RAG
- **E2B Sandboxing**: Firecracker microVMs for agent isolation

---

## Part 4: Implementation Plan

### Completed

| # | Item | Commit | Tier |
|---|------|--------|------|
| 1 | SQLite WAL mode + busy timeout | `5632060` | Tier 1 |
| 2 | Cross-process mailbox flock | `9b894ce` | Tier 1 |
| 3 | Health.sh rollback timeouts + frontend health | `406263f` | Tier 1 |
| 4 | compact.sh daemon rebuilt | `4938630` | Tier 1 |
| 5 | Compaction investigation | journaled | Tier 1 |
| 6 | PostToolUse audit logging | `c3f3a5f` | Tier 2 |
| 7 | Supervisor heartbeat monitoring | `634f03c` | Tier 2 |
| 8 | Task lifecycle states | `bfa3465` | Tier 2 |

### In Progress

| # | Item | Priority | Status |
|---|------|----------|--------|
| 9 | Structured compaction to journal | Tier 2 | Next up |
| 10 | Per-agent resource budgets | Tier 2 | Queued |

### Planned (Tier 3)

| # | Item | Impact | Effort |
|---|------|--------|--------|
| 11 | Approval queue + UI | Human oversight for risky actions | Medium |
| 12 | Multi-project support | Unlocks CMUX for external repos | Large |
| 13 | Branch-based worker isolation | Git-level blast radius | Medium |
| 14 | Claude Code Agent Teams evaluation | Hybrid orchestration | Large |
| 15 | Langfuse observability | Production-grade traces | Medium |

### Item 9: Structured Compaction to Journal (DETAILED SPEC)

**Goal**: When an agent's context is compacted, preserve structured state in the journal so a fresh agent can seamlessly continue the work. If the journal entry is unclear, the new agent should check the previous agent's conversation history.

**Architecture**:

1. **Pre-compaction hook**: Before `/compact` runs, capture the agent's current state as structured JSON:
   - `files_modified`: List of files the agent has touched
   - `decisions`: Key decisions made and rationale
   - `open_questions`: Unresolved issues or ambiguities
   - `current_task`: What the agent is currently working on
   - `blockers`: Anything blocking progress
   - `git_state`: Current branch, uncommitted changes, recent commits

2. **Journal entry format**: Write to `.cmux/journal/YYYY-MM-DD/artifacts/compaction-{agent}-{timestamp}.json`

3. **Post-compaction recovery**: When a compacted agent resumes (or a new agent takes over):
   - Read the most recent compaction artifact for that agent
   - Restore context from the structured JSON
   - If the journal entry is unclear or missing info, check the previous conversation history via `/api/agents/{id}/terminal` capture or conversation store

4. **Fallback behavior**: If the agent encounters a user reference to something not in its context:
   - Query the conversation store for recent messages involving that agent
   - Read the journal for related entries
   - Ask the user for clarification as last resort

5. **Integration points**:
   - compact.sh: Before sending `/compact`, capture state via pane capture + structured extraction
   - Monitor.sh: After compaction verified, inject recovery context
   - Conversation store: Add endpoint to retrieve recent conversation for an agent
   - Worker role docs: Update WORKER_ROLE.md to instruct agents on recovery behavior

6. **Agent behavior change**: Update WORKER_ROLE.md and SUPERVISOR_ROLE.md to instruct agents:
   - After compaction, read your latest compaction artifact from the journal
   - If a user mentions something you don't have context for, check conversation history
   - Always journal your current state before long-running operations
