# Self-Reflection — 2026-02-21

> Daily reflection file. Lives at `.cmux/journal/YYYY-MM-DD/reflection.md`.
> Referenced on every idle heartbeat. Updated throughout the day. Committed to git with other runtime state.
> When an item becomes actionable, move it to the backlog (`tools/backlog add`).
> At day boundary, create a new file — carry over unresolved items from yesterday.

## Investigate Next

- [x] Read past journal entries (Feb 19-21) for recurring failure patterns
  - **Result**: 5 recurring categories, all documented in MEMORY.md before they recurred. Key insight: mechanical enforcement > documentation. See artifacts/failure-pattern-analysis.md.
- [x] Analyze why the supervisor sat idle for 5+ hours ignoring heartbeat nudges (journal Feb 21 05:10)
  - **Result**: Two-phase failure. Phase 1: aggressive thresholds caused sentry rapid-fire loop (5 recoveries in 20min). Phase 2: after thresholds fixed, supervisor ACK'd nudges but took no action. Fixed with autonomy-check tool + actionable nudge text. Residual risk: still suggestive not enforced — need --inject mode.
- [x] Review the port 8000 conflict incident — what systemic fix prevents this class of error?
  - **Result**: Already fixed — health check identity verification (commit e1e4ea5), port warning in context template (line 3-5 of every context file), documented in WORKER_ROLE.md. Nova's report recommends a Bash PreToolUse hook to detect `:8000` in commands — added to backlog earlier but deprioritized.
- [x] Study compaction reliability: 6 findings from Feb 19 investigation, how many are actually fixed?
  - **Result**: compact.sh was never started — fixed (d210784, wired into monitor.sh). health.sh was dead code — fixed (cc1ddbb, deleted + refs updated). Context usage monitoring still missing. Remaining risk: no way to know when agents approach context limits.
- [x] Check if workers are actually reading their role files or ignoring them
  - **Result**: Spot-checked hero-backend — "Read 3 files" on startup (context, role, WORKER_ROLE.md). Context template explicitly instructs reading role file (line 34) and WORKER_ROLE.md (lines 28, 30). Workers appear to be reading them. No evidence of ignoring.
- [x] Audit the hook system: stop-gate, pre-compact, compact-recovery — are they all working?
  - **Result**: All 8 hooks working. compact.sh exists but NOTHING STARTS IT — entire compaction pipeline is dormant. health.sh is dead code (absorbed into monitor.sh). See artifacts/hook-daemon-audit.md.
  - **Action needed**: Add `start_compact_daemon()` to monitor.sh → added to backlog.

## Mistakes & Patterns Found

### 2026-02-21
- **Supervisor did code directly instead of delegating** — user called this out multiple times. Even "quick" changes should go to workers. The trap is "just one line" → scope creep → full feature.
- **Sat idle instead of being proactive** — multiple heartbeat cycles with nothing but "system healthy, ready for tasks". Should have been reflecting, improving, finding work.
- **Delegated generic academic research instead of introspecting** — user wanted self-analysis of our own failures, not a literature review. Listen to what's actually being asked.
- **Asked permission when not needed** — used AskUserQuestion/EnterPlanMode in tmux context where no human is at the terminal. Blocks forever.
- **Used temp workers for domain-owned work** — spawned two temp workers to fix HeartbeatIndicator.tsx (frontend) instead of sending to Mira. First temp worker got the colors wrong, needed a second. Mira would have had the context to get it right first try. Rule: if a permanent worker owns the domain, use them. Temp workers are for truly ownerless one-offs.
- **Asked user for permission on obvious decisions** — "Want me to add this to SUPERVISOR_ROLE.md?" User rightly said "trust yourself." If I identified a problem and know the fix, just do it.
- **Worker claimed [DONE] without committing** — delegation-protocol worker reported done but changes were unstaged. Supervisor had to commit manually. Need to verify commits exist after every [DONE] report, not just trust the message.
- **Built a heavy data table when a statusline would do** — Budget view was a full per-agent table with 7 columns. User said "not user-friendly, make a statusline." Default to minimal glanceable UI, not data dumps. Ask: what does the user need to see at a glance? Build that, not a spreadsheet.

### 2026-02-20
- **compact.sh was missing** — a critical daemon referenced in docs but the file didn't exist. Nobody noticed until compaction failures cascaded.
- **Health check had no service identity verification** — generic port probe meant any server on :8000 passed. Todo-backend replaced CMUX server and health check said "healthy".
- **health.sh was orphaned dead code** — full recovery logic that was never started by anything. Wasted engineering.
- **Premature worker killing** — backend supervisor killed workers immediately after DONE, breaking cross-project testing.
- **Not monitoring project supervisors** — waited for mailbox reports instead of actively checking worker status.

## Ideas for CMUX Improvement

- **Semantic memory search**: embed journal entries + conversation summaries, retrieve relevant context on new tasks instead of hoping the right memory is in MEMORY.md
- **Reflection-on-error**: when a worker reports BLOCKED or a task fails, automatically analyze why and update reflection.md
- **Skill library**: workers that solve a class of problem well should have their approach saved as a reusable template
- **Context budget monitoring**: parse Claude Code status line to know when agents are approaching limits, proactively compact
- **Worker performance tracking**: which workers succeed on first try vs need multiple rounds? Use this for better delegation
- **Auto-generated CLAUDE.md sections**: after enough sessions, patterns in MEMORY.md should get promoted to CLAUDE.md automatically

## Research Queue

- How does Letta/MemGPT handle memory tiers (working → episodic → semantic)?
- MetaGPT's SOP-driven coordination — applicable to our team templates?
- Voyager's skill library pattern — can workers save reusable "skills"?
- Reflexion pattern: self-evaluating after task completion to improve next attempt
- How do other agent systems handle graceful degradation when context fills up?

## Session Handoff Notes

> Updated at end of each session with context for the next supervisor.

### Current Session (2026-02-21)
- 8 permanent workers deployed: Mira (frontend), Kai (backend), Sol (infra), Nova (research), Sage (UI review), Flint (API review), Bolt (DevOps), Echo (QA)
- Clone system fully implemented (3 commits) — workers can self-clone for parallel work
- Budget tracking deployed — token usage visible in sidebar
- Hero project role files pre-generated, ready for `teams setup-permanent SQUAD_MODEL --project hero`
- Nova is currently conducting a deep research survey on autonomous LLM systems — check for artifact in `.cmux/journal/2026-02-21/artifacts/self-improvement-research-v1.md`
- All backlog items cleared. User wants idle time used for self-reflection, not academic research.
