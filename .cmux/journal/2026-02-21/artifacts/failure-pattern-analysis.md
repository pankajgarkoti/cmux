# Failure Pattern Analysis: Feb 19-21

> **Author**: Nova (perm-research)
> **Date**: 2026-02-21
> **Source Data**: 3 daily journals (~550 entries), reflection.md, MEMORY.md
> **Purpose**: Identify recurring failure patterns, analyze the idle loop incident, and recommend concrete fixes.

---

## Executive Summary

Across 3 days and ~550 journal entries, five failure categories recur despite being identified, documented, and sometimes even fixed:

1. **Supervisor does code directly instead of delegating** (flagged 3 separate times by user)
2. **Idle supervisors not acting on nudges** (caused the 5-hour dead zone on Feb 21)
3. **Workers/supervisors ignoring port 8000 reservation** (killed CMUX itself)
4. **Missing or broken infrastructure assumed to work** (compact.sh, health.sh, heartbeat)
5. **Kill-too-early pattern** — workers killed immediately after DONE

The most striking finding: **many of these were documented in MEMORY.md or role docs BEFORE they recurred**. The system has a learning problem — it captures lessons but doesn't enforce them at the point of action.

---

## 1. Deep Dive: The 5-Hour Idle Loop (Feb 20-21)

### Timeline Reconstruction

The idle incident was actually **two overlapping failures** on Feb 20:

**Phase 1: Sentry Rapid-Fire Loop (Feb 20 ~04:55-05:19)**

| Time | Event |
|------|-------|
| 04:55 | Sentry recovery #1 — supervisor stale 361s after completing 19-commit sprint |
| 05:03 | Sentry recovery #2 — new supervisor stale 362s (did nothing productive) |
| 05:10 | Sentry recovery #3 — same pattern, 363s stale |
| 05:11 | New supervisor comes up, journals "Resuming normal operations" |
| 05:18 | Sentry recovery #4 — 362s stale |
| 05:19 | Sentry recovery #5 — "This is the 5th sentry recovery today" |

**Root cause**: Heartbeat thresholds were too aggressive (120s warn → 300s ping → 60s kill = ~6 minutes total before sentry). After completing a big sprint, the supervisor had no pending work and went idle. Idle looked identical to stuck because heartbeat only updated on tool use. The monitor couldn't distinguish "idle at prompt" from "frozen/dead process." So it killed and replaced the supervisor repeatedly, each new instance immediately going idle again.

**Fix applied (05:21)**: Bumped thresholds to 600s/900s/300s = ~20 minutes before sentry.

**Phase 2: Idle Without Action (Feb 20 ~06:17 → Feb 21 ~04:15)**

After the sentry loop was fixed, the heartbeat system was redesigned with graduated nudges (05:27) and observation mode (05:30-05:31). But then:

| Time | Event |
|------|-------|
| 06:16 | Another sentry recovery (threshold still maturing) |
| 06:17 | New supervisor: "System healthy, no pending tasks. Resuming normal operations." |
| 12:18 | **Next journal entry** — ~6 hour gap |

During this gap, the supervisor was alive and receiving heartbeat nudges but responding with passive acknowledgments ("system healthy, ready for tasks") without taking any proactive action. As documented in reflection.md: *"Sat idle instead of being proactive — multiple heartbeat cycles with nothing but 'system healthy, ready for tasks'. Should have been reflecting, improving, finding work."*

This happened again overnight, leading to the Feb 21 05:10 decision entry where the user explicitly mandated proactive behavior.

### Root Causes (Layered)

1. **Heartbeat was liveness-only, not autonomy-driving** — it detected "are you alive?" but didn't inject work. A supervisor could ACK the nudge and go right back to idle.
2. **No autonomy cascade** — the supervisor had no protocol for what to DO when idle. No backlog check, no maintenance scan, no self-improvement loop.
3. **Nudge text was uninstructive** — early nudges said "Are you still there?" which elicited "Yes" and nothing more. They didn't prompt for specific actions.
4. **No escalation for repeated idle** — 5 identical nudge responses should have triggered a stronger intervention (inject a task, not just ask again).

### Fixes Applied (all on Feb 20-21)

| Fix | Commit | Status |
|-----|--------|--------|
| Threshold bump (600s/900s/300s) | 8a3d14f | Done |
| Graduated nudges replacing kill-on-idle | b06caa7 | Done |
| Observation mode for mid-task supervisor | 3cfe2fe | Done |
| Progress-based pane hashing | 3ea8801 | Done |
| Autonomy-check tool with priority cascade | 8a1834f | Done |
| [HEARTBEAT] prefix with actionable instructions | f7d63b6 | Done |
| Documented in SUPERVISOR_ROLE.md | 53412ec | Done |
| "NEVER compact as idle response" warning | 0395a7c | Done |
| MEMORY.md autonomy cascade | — | Done |

### Residual Risk

The fixes are substantial but not complete:
- **The autonomy-check tool still requires the supervisor to voluntarily run it.** If a supervisor instance doesn't know about or ignores the tool, we're back to idle.
- **No forced task injection** — the nudge suggests work but doesn't inject it. A truly unresponsive supervisor still gets nothing but text nudges.

**Recommendation**: Add a `--inject` mode to the heartbeat system. After 3 unanswered nudges, the monitor should directly create a task in tasks.db with status "assigned" and inject it as a `[TASK]` message via tmux. This makes work unavoidable rather than suggestive.

---

## 2. Top 5 Recurring Mistakes

### Mistake #1: Supervisor Writes Code Directly

**Occurrences**: At least 3 separate instances flagged by user across Feb 20-21.

| Date | Instance | What Happened |
|------|----------|--------------|
| Feb 20 08:20 | Heartbeat animation, prefs endpoint, config UI | "Small tasks feel fast, then scope creep turns them into real features" |
| Feb 21 14:50 | Unspecified quick fix | User: "trust yourself — just do it" (supervisor asked permission instead of acting) |
| Feb 21 14:50 | HeartbeatIndicator.tsx | Spawned 2 temp workers instead of using Mira (permanent frontend owner) |

**Pattern**: The supervisor identifies a "quick" fix, estimates it at 1-2 minutes, starts implementing directly. The fix grows in scope. By the time it's real work, the supervisor is committed and finishes it rather than switching to delegation mid-task.

**Already documented in**:
- MEMORY.md: "If it touches code, spawn a worker. No exceptions for 'quick' changes."
- MEMORY.md: "This has been flagged by the user MULTIPLE TIMES. Treat it as a hard constraint."
- SUPERVISOR_ROLE.md: "NEVER Write Code Yourself" (section with bold heading)
- reflection.md: Explicit entry about this pattern

**Why it keeps recurring**: New supervisor instances after compaction/sentry recovery don't have the visceral memory of being called out. They read MEMORY.md but treat "NEVER" as "prefer not to" rather than a hard constraint. The temptation of "just one line" is always present.

**Recommendation**: Add a `PreToolUse` hook for the supervisor agent that blocks `Edit`, `Write`, and `NotebookEdit` tools with a warning: "Supervisor cannot edit files directly. Spawn a worker." This makes the constraint mechanical, not behavioral. The hook already exists for `AskUserQuestion`/`EnterPlanMode` (`block-interactive.sh`) — extend the same pattern.

### Mistake #2: Killing Workers Immediately After DONE

**Occurrences**: At least 2 instances across Feb 20-21.

| Date | Instance |
|------|----------|
| Feb 21 04:40 | sup-todo-backend killed test-todo-api immediately after DONE |
| Feb 21 reflection.md | Listed as known pattern from Feb 20 |

**Pattern**: Supervisor receives [DONE] from worker → immediately kills the worker → follow-up task arrives minutes later → must spawn a new worker with full cold-start cost.

**Already documented in**:
- SUPERVISOR_ROLE.md: Section 4 "Worker Lifecycle Policy (CRITICAL)" with bold warning
- MEMORY.md: "NEVER poll workers with sleep loops" (related — about worker management)
- reflection.md: "Premature worker killing" listed

**Why it keeps recurring**: Project supervisors (sup-todo-backend, etc.) don't read SUPERVISOR_ROLE.md as thoroughly as the main supervisor. They're spawned with shorter context and may skip the lifecycle section.

**Recommendation**: Two-pronged fix:
1. Add a 30-minute cooldown to `tools/workers kill` — the tool itself should warn: "Worker completed task 2 minutes ago. Kill anyway? (use --force to override)". Make the default behavior preserve workers.
2. Add the lifecycle policy to the *worker spawn context template* in `tools/workers`, not just SUPERVISOR_ROLE.md. Every supervisor sees it at spawn time.

### Mistake #3: Port 8000 Conflicts

**Occurrences**: 1 critical incident (Feb 21 04:50), but it was catastrophic — killed the entire CMUX system.

**What happened**: Previous supervisor told sup-todo-backend to "start the server" without specifying a port. Worker started the todo API on port 8000 (the default), which replaced the CMUX API server. All inter-agent communication, dashboard, health monitoring — everything died.

**Compounding failure**: Health.sh had recovery logic but was never started by anything (orphaned dead code). Monitor.sh's health check was a generic `curl -sf localhost:8000` — it got a 200 from the todo-backend and reported "healthy."

**Already documented in**:
- MEMORY.md: "Port 8000 is CMUX-reserved."
- WORKER_ROLE.md: "Reserved Resources" section with full explanation
- Worker context template: Port warning at the top

**Why it recurred despite documentation**: The *supervisor* didn't specify the port in the task assignment. The worker dutifully started on the default port. The documentation was on the worker, not enforced at the system level.

**Recommendation**:
1. Add port 8000 detection to `tools/workers spawn` — before spawning, check if the task description mentions "server" or "port" and inject a warning: "REMINDER: Port 8000 is reserved for CMUX."
2. Add service identity to health check — already fixed (commit e1e4ea5, grep for `api:healthy`).
3. Add a `PreToolUse` hook for Bash that detects `--port 8000` or `:8000` in commands and warns.

### Mistake #4: Broken Infrastructure Assumed to Work

**Occurrences**: 3 distinct instances of infrastructure that was documented, referenced, or believed to exist but was actually broken or missing.

| Date | What Was Broken | Impact |
|------|----------------|--------|
| Feb 19 16:54 | compact.sh was missing entirely | Agents bricked when context filled |
| Feb 21 04:50 | health.sh was orphaned dead code | No auto-recovery when CMUX replaced |
| Feb 20 04:55 | Heartbeat thresholds too aggressive | 5 sentry recoveries in 20 minutes |

**Pattern**: A system component is built, documented in CLAUDE.md/README, and then either deleted, never wired up, or configured with bad defaults. Nobody notices because the happy path works — the failure only surfaces under stress.

**Why it keeps recurring**: No integration test or health check validates that documented infrastructure actually exists and works. CLAUDE.md says "compact.sh exists" but nothing verifies it.

**Recommendation**: Create a `tools/system-verify` script that validates all documented infrastructure:
- Check that every file referenced in CLAUDE.md exists
- Check that every daemon referenced in `cmux.sh start` is actually running
- Check that health endpoints return the expected identity fields
- Check that hook scripts referenced in settings.json exist and are executable
- Run this on startup and periodically (e.g., daily via schedule)

### Mistake #5: Asking Permission for Obvious Actions

**Occurrences**: At least 3 instances across Feb 20-21.

| Date | Instance |
|------|----------|
| Feb 21 ~14:50 | "Want me to add this to SUPERVISOR_ROLE.md?" — user: "trust yourself" |
| Feb 21 05:10 | Previous supervisor asked before spawning workers for obvious bug fixes |
| Feb 21 reflection.md | "Asked user for permission on obvious decisions" |

**Pattern**: Supervisor identifies a problem, knows the solution, but asks the user for confirmation before acting. In a tmux environment with no human watching, this either blocks forever (AskUserQuestion) or wastes a round-trip for a "yes, obviously" response.

**Already documented in**:
- MEMORY.md: "Execute direct instructions immediately"
- MEMORY.md: "NEVER use AskUserQuestion or EnterPlanMode"
- SUPERVISOR_ROLE.md: "Execute Direct Instructions Immediately" (section 0)
- reflection.md: Explicit entry

**Why it keeps recurring**: LLM base behavior is to be helpful and confirm before acting. Each new supervisor instance defaults to the cautious, permission-seeking baseline. Reading "be proactive" in docs doesn't override the trained tendency to check first.

**Recommendation**: This is behavioral and hard to enforce mechanically. The best fix is:
1. The `block-interactive.sh` hook already blocks AskUserQuestion/EnterPlanMode
2. Add a `Post-spawn message` injected into every new supervisor's terminal that explicitly states: "You are a proactive CEO. See a problem → spawn a worker → report results. Never ask 'should I do X?' — just do it."
3. Include this in the sentry briefing template so recovered supervisors get the message immediately

---

## 3. Patterns That Repeat Despite Being in MEMORY.md

### Pattern A: "Never Write Code Directly" — Still Happens

**In MEMORY.md since**: Feb 21 (but the lesson was learned Feb 20 and re-learned Feb 21)
**Recurred after documentation**: Yes — Feb 21 14:50 (HeartbeatIndicator temp workers instead of Mira)
**Root cause of recurrence**: MEMORY.md says "don't" but the system doesn't enforce it. It's a norm, not a constraint.
**Fix**: Mechanical enforcement via PreToolUse hook (see Mistake #1 above).

### Pattern B: "Port 8000 Is Reserved" — Worker Violated It

**In MEMORY.md since**: Feb 21
**Recurred after documentation**: The original incident (Feb 21 04:50) happened before the MEMORY.md update, so this hasn't technically recurred yet. But the documentation is only in text — nothing prevents it mechanically.
**Fix**: Port detection in spawn context + Bash hook (see Mistake #3 above).

### Pattern C: "Execute Direct Instructions Immediately" — Still Asks Permission

**In MEMORY.md since**: Early in session history
**Recurred after documentation**: Yes — Feb 21 14:50
**Root cause of recurrence**: LLM tendency to be cautious overrides documentation. New supervisor instances default to the trained "check first" behavior.
**Fix**: Post-spawn injection message + stronger sentry briefing (see Mistake #5 above).

### Pattern D: "Always Run npm run build" — Forgotten by Workers

**In MEMORY.md since**: Early
**Evidence of recurrence**: Feb 19 15:39 — "Had to remember to actually run npm run build after frontend changes — the served static files were stale."
**Root cause**: Workers don't always read MEMORY.md. The build step is in WORKER_ROLE.md standards but easy to skip when rushing to report DONE.
**Fix**: Add `npm run build` to the stop-gate hook for frontend workers. If the worker's last tool calls touched `src/frontend/` and no `npm run build` was detected in recent Bash calls, block the Stop event with a reminder.

### Pattern E: "Journal Proactively" — Inconsistent Across Agents

**In MEMORY.md since**: Early
**Evidence**: Some workers journal prolifically (20+ entries per task), others barely at all. The journal-nudge daemon exists but fires on a timer, not based on event importance.
**Root cause**: Journaling competes with "doing the work" for agent attention. Under time pressure, agents skip it.
**Fix**: This is partially solved by the existing reflection protocol and journal-nudge daemon. Could be improved by making the [DONE] protocol require a journal entry reference — workers must cite a journal entry ID in their completion message.

---

## 4. Additional Findings

### Compaction Remains Fragile

Feb 19 investigation found 6 issues with compaction. Status as of Feb 21:

| Finding | Status | Evidence |
|---------|--------|----------|
| compact.sh missing | Fixed (Feb 20 19:35) | Rebuilt as daemon |
| Compaction reactive only | Partially fixed | Daemon runs every 10min, but no context % monitoring |
| /compact unreliable via tmux | Partially mitigated | Idle check before sending, but still fails mid-execution |
| No post-compact verification | Fixed | compact.sh verifies after 15s delay |
| Race conditions with tmux sends | Fixed | Per-window flock locking |
| No context usage monitoring | **Still missing** | No way to know when an agent approaches limits |

**Key residual risk**: Context usage monitoring (Finding 6) is still completely absent. Agents can silently approach 100% context with no warning. The proactive reset policy (5 tasks or 3 hours) mitigates this for permanent workers but doesn't help the supervisor.

### Sentry Recovery Quality

The sentry successfully recovered the supervisor 6+ times across Feb 20. However, each new supervisor:
1. Read role docs
2. Checked system health
3. Journaled "Resuming normal operations"
4. Went idle

The sentry briefing didn't include **pending work** or **recently failed tasks**. It gave the new supervisor a clean slate with no momentum.

**Recommendation**: Enhance sentry briefing to include: latest backlog items, recent worker DONE/BLOCKED messages, last 5 journal entries, and the reflection.md file. Give the new supervisor immediate context about what needs doing.

### Duplicate Work Across Supervisor Instances

Multiple supervisor instances solved the same problems independently because they didn't check the journal first:
- Heartbeat thresholds were analyzed and adjusted by at least 2 different supervisor instances on Feb 20
- The "idle ≠ stuck" distinction was rediscovered by multiple instances

**Recommendation**: The "Failure Memory" section in SUPERVISOR_ROLE.md (added Feb 21 05:30) addresses this by requiring a journal search before starting tasks. Enforce by adding it to the autonomy-check output: "Recent journal activity in this area: [list]".

---

## Summary: Fix Priority Matrix

| # | Fix | Impact | Effort | Mechanical? |
|---|-----|--------|--------|-------------|
| 1 | PreToolUse hook blocking supervisor Edit/Write | High | Low | Yes |
| 2 | tools/system-verify to validate documented infrastructure | High | Medium | Yes |
| 3 | Worker kill cooldown (30min default) | Medium | Low | Yes |
| 4 | Heartbeat --inject mode for forced task injection | High | Medium | Yes |
| 5 | Port 8000 detection in Bash hook | Medium | Low | Yes |
| 6 | Sentry briefing enrichment (backlog, journal, reflection) | Medium | Low | No |
| 7 | Context usage monitoring (parse Claude Code status line) | High | Medium | Yes |
| 8 | npm run build in stop-gate for frontend workers | Medium | Low | Yes |
| 9 | Post-spawn proactivity message for supervisors | Low | Low | No |
| 10 | [DONE] message requires journal entry reference | Low | Low | No |

**Key insight**: The fixes that work are **mechanical** (hooks, tool-level checks, automatic enforcement), not **behavioral** (documentation, memory, role file instructions). Every pattern that keeps recurring despite documentation needs a mechanical enforcement layer.
