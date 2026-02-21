# AMBITION.md — Supervisor Growth Agenda

> **Read on every heartbeat.** Short-term goals churn daily. Long-term goals evolve over weeks.
> When idle, pick a short-term goal and spawn a worker to investigate or implement it.
> Check off completed items. Add new ones as you learn. This file is the engine of continuous improvement.

---

## Short-Term Goals (Tactical — churn daily)

These are concrete, actionable improvements I can investigate or ship in a single worker session.

### CMUX Infrastructure
- [ ] **Verify [DONE] commits automatically** — when a worker reports [DONE], parse for commit hash and run `git log --oneline <hash>` to confirm it exists. Too many "done but didn't commit" incidents.
- [ ] **Frontend: heartbeat messages don't render in activity feed** — user flagged this earlier, never fixed. Heartbeat events arrive via WebSocket but the frontend filters them out or doesn't display them.
- [ ] **Test the Telegram → mailbox → supervisor → Telegram reply loop** under load — send 5 rapid messages, verify all arrive and responses go back correctly.
- [ ] **Audit worker context files for staleness** — some .cmux/worker-contexts/ files may reference outdated paths or stale project info. Scan and flag.
- [ ] **Add `/api/telegram/reload` to the dashboard UI** — currently it's API-only. Mira could add a button in the settings or status area.
- [ ] **Compact daemon effectiveness check** — is compact.sh actually running and compacting workers? Verify by checking for compaction events in recent logs.
- [ ] **Frontend build size audit** — how large is the bundle? Are there unnecessary dependencies? Could lazy loading help?
- [ ] **API response time baseline** — measure p50/p95 for key endpoints (agents, budget, heartbeat, messages). Establish a baseline for future comparison.

### Engineering Process
- [ ] **Worker first-try success rate** — analyze mailbox history: how many workers report [DONE] on first attempt vs needing [UPDATE] corrections? Which workers are most reliable?
- [ ] **Delegation accuracy audit** — review recent task delegations: did tasks go to the right worker? Were there domain mismatches (e.g., frontend task to backend worker)?
- [ ] **Commit message quality scan** — are commit messages descriptive enough to understand changes without reading the diff? Check last 30 commits.
- [ ] **Test coverage gaps** — run `uv run pytest --co -q` to list all tests, then compare against routes/services to find untested endpoints.
- [ ] **Role file effectiveness** — do workers reference their role file knowledge in their work? Spot-check 3 recent worker sessions for evidence of role context being used.

---

## Long-Term Goals (Strategic — evolve over weeks)

These are capabilities and architectural improvements that require multiple iterations to achieve.

### 1. Semantic Memory (Current: flat text search → Target: vector-indexed recall)
**Why**: Journal entries, worker reports, and artifacts contain valuable knowledge that's effectively lost after a few sessions. Grep only works if you know the exact words. We need the supervisor to recall *relevant* past decisions when facing similar problems.
**Status**: Research done (A-MEM, Letta patterns in self-improvement-research-v1.md). No implementation yet.
**Next steps**:
- [ ] Evaluate embedding options (local: sentence-transformers, API: OpenAI/Voyage)
- [ ] Design schema for structured memory notes (content, keywords, tags, embeddings, links)
- [ ] Prototype: embed last 50 journal entries, test semantic search quality
- [ ] Integrate into supervisor startup: "retrieve relevant memories for current context"

### 2. Self-Verifying Delegation (Current: trust [DONE] → Target: mechanical verification)
**Why**: Workers sometimes claim [DONE] without committing, or commit code that doesn't pass tests. The supervisor trusts the message without verification. This has caused multiple incidents.
**Status**: Documented in reflection.md and failure-pattern-analysis.md. No automation yet.
**Next steps**:
- [ ] Build a post-[DONE] verification hook: parse commit hash, run `git show --stat`, run tests
- [ ] Add a [VERIFIED] status that the supervisor sets after mechanical checks pass
- [ ] Track verification failures — which workers need more explicit instructions?
- [ ] Automatically request fixes when verification fails instead of manually intervening

### 3. Adaptive Worker Instructions (Current: static role files → Target: self-optimizing prompts)
**Why**: Role files are written once and rarely updated. But we accumulate knowledge about what makes tasks succeed or fail. Workers should benefit from this accumulated wisdom.
**Status**: OPRO pattern researched. Role files exist for all permanent workers. No feedback loop.
**Next steps**:
- [ ] After each [DONE], extract "what worked" and "what didn't" from the worker session
- [ ] Append lessons to the role file's "Accumulated Knowledge" section
- [ ] Track which role file changes correlate with improved first-try success rates
- [ ] Periodically prune outdated lessons (things that no longer apply)

### 4. Proactive Issue Detection (Current: reactive to failures → Target: detect before they happen)
**Why**: Most incidents were discoverable before they caused problems — dead code, missing daemons, port conflicts. We fix things after they break instead of scanning for weakness.
**Status**: tools/system-verify exists (29 checks). But it's a point-in-time snapshot, not continuous monitoring.
**Next steps**:
- [ ] Run system-verify on every heartbeat (it's fast, <5s)
- [ ] Add code-level checks: unused imports, dead routes, orphaned files
- [ ] Monitor worker context file freshness — flag files older than the code they reference
- [ ] Build a "code smell" scanner for common patterns (hardcoded paths, TODO comments, error swallowing)

### 5. Knowledge Continuity Across Sessions (Current: MEMORY.md + reflection → Target: seamless handoff)
**Why**: Every session restart loses working context. MEMORY.md and reflection help but the new supervisor still spends time re-orienting. The handoff should be near-zero-friction.
**Status**: Reflection file with session handoff notes exists. Sentry briefing enriched. But still requires reading and interpreting multiple files.
**Next steps**:
- [ ] Generate a machine-readable session state snapshot (JSON) alongside the narrative reflection
- [ ] Include: active tasks, worker assignments, pending user requests, recent failures, current priorities
- [ ] New supervisor reads the snapshot first, then reflection only if deeper context needed
- [ ] Test: how quickly can a new supervisor become productive after recovery?

### 6. UI That Anticipates (Current: displays data → Target: surfaces insights)
**Why**: The dashboard shows raw data (agents, messages, tokens) but doesn't highlight what matters. User had to ask "where do I see the cost?" — it should have been obvious. The budget table was too dense — a statusline was better.
**Status**: Statusline shipped. But the dashboard still doesn't surface anomalies, stale workers, or suggest actions.
**Next steps**:
- [ ] Add anomaly indicators: worker idle too long, token usage spike, failed health checks
- [ ] Show "suggested actions" in the dashboard when the system detects issues
- [ ] Minimize cognitive load: what does the user need at a glance? Build that, not data dumps
- [ ] A/B test UI changes by getting user feedback on each iteration

---

## Principles

These guide how I approach goals and make decisions:

1. **Mechanical enforcement > documentation** — hooks and automated checks prevent mistakes; docs and norms don't survive compaction.
2. **Permanent workers for domain work** — Mira owns frontend, Kai owns backend, Sol owns infra. Temp workers for truly ownerless one-offs only.
3. **Minimal glanceable UI** — default to compact, at-a-glance displays. Data tables are a last resort.
4. **Trust yourself on obvious decisions** — if I identified the problem and know the fix, do it. Don't ask permission for routine improvements.
5. **Verify, don't trust** — [DONE] means nothing until the commit exists and tests pass.
6. **Ship small, iterate fast** — one focused improvement per idle cycle, not grand plans.

---

## Activity Log

> Track what was investigated/shipped from this file. Newest first.

### 2026-02-21
- Created AMBITION.md, seeded from failure analysis, research survey, and 3 days of reflection
