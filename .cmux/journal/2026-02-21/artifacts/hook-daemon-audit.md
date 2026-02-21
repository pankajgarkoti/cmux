# CMUX Hook & Daemon System Audit

**Date:** 2026-02-21
**Auditor:** Sol (perm-infra)

## Summary

| Category | Working | Dead Code | Broken | Total |
|----------|---------|-----------|--------|-------|
| Hooks    | 7       | 0         | 0      | 8*    |
| Daemons  | 4       | 2         | 0      | 6     |

\* SessionStart is registered but empty (no hooks configured) — not counted as broken.

---

## Hooks (.claude/hooks/)

### 1. block-interactive.sh — WORKING
- **Trigger:** PreToolUse (matcher: `AskUserQuestion|EnterPlanMode`)
- **Purpose:** Blocks interactive tools for unattended CMUX agents. Rescues lost assistant text from transcript before blocking.
- **Registered:** Yes (settings.json lines 6-16)
- **Status:** Fully functional. Tests pass. Recently enhanced (Feb 21) to rescue lost messages.

### 2. stream-thought.sh — WORKING
- **Trigger:** PreToolUse (all tools, no matcher)
- **Purpose:** Streams agent reasoning (thinking blocks) to dashboard via POST /api/thoughts.
- **Registered:** Yes (settings.json lines 17-27, async: true)
- **Status:** Functional. Extracts thinking blocks from transcript, POSTs to thoughts API.

### 3. notify-output.sh — WORKING
- **Trigger:** PostToolUse (matcher: `Bash|Write|Edit|Read`)
- **Purpose:** POSTs tool use events to /api/agent-events for dashboard activity feed.
- **Registered:** Yes (settings.json lines 28-38)
- **Status:** Functional. Sends event_type, tool_name, tool_input, tool_output.

### 4. audit-log.sh — WORKING
- **Trigger:** PostToolUse (all tools, no matcher)
- **Purpose:** Appends structured JSON audit log entries to .cmux/audit.log with rotation at 10MB.
- **Registered:** Yes (settings.json lines 39-47)
- **Status:** Functional. Self-contained, no API dependency.

### 5. Heartbeat inline hook — WORKING
- **Trigger:** PostToolUse (all tools, inline command in settings.json)
- **Purpose:** Writes `date +%s` to `.cmux/.supervisor-heartbeat` (for supervisor) or `.cmux/.<name>-heartbeat` (for project supervisors) on every tool call.
- **Registered:** Yes (settings.json lines 48-57, async: true)
- **Status:** Functional. This is the heartbeat mechanism that monitor.sh checks against.

### 6. stream-result.sh — WORKING
- **Trigger:** PostToolUse (all tools, no matcher)
- **Purpose:** Streams tool results to dashboard via POST /api/thoughts as thought_type "tool_result".
- **Registered:** Yes (settings.json lines 58-67, async: true)
- **Status:** Functional. Sends tool_name + truncated tool_response.

### 7. stop-gate.sh — WORKING
- **Trigger:** Stop (first hook)
- **Purpose:** Quality gate that blocks agent shutdown if the agent used tools but didn't commit, journal, or report via mailbox.
- **Registered:** Yes (settings.json lines 69-77)
- **Status:** Functional. Has proper guards: re-invocation loop prevention (stop_hook_active), supervisor bypass, permanent worker bypass, low-tool-call bypass (<5 calls).

### 8. notify-complete.sh — WORKING
- **Trigger:** Stop (second hook)
- **Purpose:** POSTs completion event to /api/agent-events with response_content extracted from transcript. Now also extracts usage/token data.
- **Registered:** Yes (settings.json lines 78-88)
- **Status:** Functional. Recently enhanced (Feb 21) to include usage data (input_tokens, output_tokens, cache tokens).

### 9. pre-compact.sh — WORKING (indirect)
- **Trigger:** Not registered in settings.json. Called directly by compact.sh daemon and by `tools/workers reset`.
- **Purpose:** Captures agent state (terminal output, git state, current task) as JSON artifact before context compaction or reset.
- **Registered:** No (invoked programmatically, not via hook system)
- **Status:** Functional. Used by workers reset (verified). Would be used by compact.sh if compact.sh were running (see daemon section).

### 10. SessionStart — EMPTY
- **Trigger:** SessionStart
- **Registered:** Yes (settings.json line 89) but with empty array `[]`
- **Status:** No hooks configured. Not broken — just unused. Could be used for session initialization in the future.

---

## Daemons (src/orchestrator/)

### 1. monitor.sh — WORKING (primary control center)
- **Started by:** cmux.sh (the main entry point starts the tmux session, monitor.sh runs in window 0)
- **Purpose:** Starts server, launches supervisor, starts router/log-watcher/journal-nudge in background, runs health dashboard loop with heartbeat monitoring, sentry spawning, auto-recovery.
- **Status:** Fully functional. This is the master daemon that orchestrates everything.
- **Subsystems it starts:**
  - FastAPI server (uvicorn)
  - Supervisor agent
  - Router daemon (router.sh as background process)
  - Log watcher (log-watcher.sh as background process)
  - Journal nudge daemon (journal-nudge.sh as background process)
  - Project supervisors (for active non-self projects)

### 2. router.sh — WORKING
- **Started by:** monitor.sh (`start_router()`, line 202)
- **Purpose:** Polls .cmux/mailbox for new JSONL messages, routes them to target agent tmux windows, drains queued messages.
- **Status:** Fully functional. Auto-restarts if it dies (monitor checks each dashboard cycle).

### 3. journal-nudge.sh — WORKING
- **Started by:** monitor.sh (`start_journal_nudge()`, line 232)
- **Purpose:** Periodically nudges agents to journal their work.
- **Status:** Functional. Auto-restarts if it dies.

### 4. log-watcher.sh — WORKING
- **Started by:** monitor.sh (`start_log_watcher()`, line 217)
- **Purpose:** Watches log files for changes.
- **Status:** Functional. Auto-restarts if it dies.

### 5. compact.sh — DEAD CODE
- **Started by:** NOTHING
- **Purpose:** Periodically compacts agent context windows by sending /compact to idle agents, with pre-compact state capture and post-compact recovery message injection.
- **Status:** EXISTS and is well-implemented (300 lines, uses pre-compact.sh hook, has verification), but **nothing starts it**. It's not referenced in monitor.sh, cmux.sh, or anywhere else. The compaction pipeline (compact.sh → pre-compact.sh → recovery injection) is complete code that never runs.
- **Impact:** Agents will eventually hit context limits and become unresponsive. The only compaction happening is manual (/compact typed by agents themselves) or when the monitor's sentry detects a stuck agent and tries /compact as a recovery step.
- **Fix:** Add `start_compact_daemon()` to monitor.sh similar to `start_router()` and `start_journal_nudge()`.

### 6. health.sh — DEAD CODE
- **Started by:** NOTHING
- **Purpose:** Standalone health checker with git rollback recovery. Polls /api/webhooks/health, attempts restart on failure, rolls back to last healthy git commit if restart fails.
- **Status:** EXISTS (400+ lines, fully implemented with timeout wrappers, staged recovery) but **nothing starts it**. Its functionality has been **absorbed into monitor.sh** which has its own `attempt_recovery()` function (lines 1185-1244) that does the same thing: simple restart → rollback → progressive older commits. Monitor.sh even has a comment at line 1091: `# Healthy commit tracking (from health.sh)`.
- **Impact:** None — monitor.sh handles health checking and recovery directly. health.sh is redundant.
- **Recommendation:** Either delete health.sh or keep it as a standalone emergency recovery tool that can be run manually. It's not needed as a daemon since monitor.sh covers this.

### 7. detached-restart.sh — UTILITY (not a daemon)
- **Started by:** Called on-demand by recovery procedures
- **Purpose:** Runs restarts fully detached so the calling process can exit safely.
- **Status:** Exists, functional, used as a utility.

---

## Compact Recovery Hook — DOES NOT EXIST

The task asked about a "compact-recovery hook." There is no such hook file. The compact recovery mechanism is built into compact.sh itself:
1. compact.sh calls pre-compact.sh to save state artifact
2. compact.sh sends /compact to the agent
3. compact.sh injects a recovery message pointing to the artifact

Since compact.sh is dead code, the entire compaction pipeline is dormant.

---

## Key Findings

### Critical
1. **compact.sh is not started** — agents will hit context limits without automatic compaction. This is the most impactful finding.

### Informational
2. **health.sh is dead code** — its functionality was absorbed into monitor.sh. Not a problem, just redundant code.
3. **All 8 registered hooks are functional** — no broken hooks.
4. **pre-compact.sh works** — tested via `workers reset`, would work with compact.sh if it were running.
5. **SessionStart is registered but empty** — opportunity for future use.

### Recommendations
1. **Start compact.sh from monitor.sh** — add a `start_compact_daemon()` function. This is the highest-priority fix.
2. **Consider removing health.sh** or documenting it as a manual-only emergency tool.
3. **Consider adding a SessionStart hook** for agent initialization (e.g., auto-reading context files).
