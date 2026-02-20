# Journal - 2026-02-19

## 22:08 - Stress-tested and rebuilt message passing system

Comprehensive stress testing of the CMUX inter-agent message passing system, followed by a full migration from custom text format to JSONL.

Ran 4 parallel test batteries covering mailbox format parsing, router line-tracking, tools/mailbox edge cases, and Python API endpoints. Found 19 bugs total (3 critical, 3 high, 5 medium, 8 low).

Migrated mailbox from custom text format to JSONL. Files changed: `router.sh` (parse with jq), `tools/mailbox` (write via jq -cn), `mailbox.py` (write via json.dumps), `lib/tmux.sh` (fixed grep regex injection).

Key decision: Chose JSONL over SQLite-as-bus or API-first because it preserves file-based resilience while eliminating parsing ambiguity. jq is now a runtime dependency.

## 22:13 - Built journal system

Created `tools/journal` CLI for dead-simple agent journaling. Added `/journal` skill. Modified `agent_events.py` to nudge agents to self-journal via tmux after 15 tool uses or 5 minutes. Supervisor now reads the most recent journal on startup for session continuity.

Decision: Use nudge-based auto-journaling instead of server-written mechanical summaries. The server prompts agents via tmux to write their own entries with full context, rather than writing tool-count summaries itself.

## 12:26 - Committed JSONL migration + journal system

Commit `289ac09`: 12 files changed across mailbox migration, journal system, and documentation updates.

## 12:43 - Enhanced activity panel and chat live indicator

Commit `99909e0`: Added smart tool call summaries to the activity panel (file paths, commands, patterns instead of generic "Tool: Read"). Structured expanded views with labeled input/output fields instead of raw JSON dumps. Tool-specific icons (FileText for Read, Play for Bash, etc.). Chat activity indicator now shows a live feed of recent tool calls with expandable history. Fixed agent_id missing from WebSocket AgentEvent mapping.

## 14:19 - Fixed journal formatting: removed title/body duplication in tools/journal, updated nudge to tell agents to resume work after journaling, cleaned up today's journal entries


## 14:34 - Added per-message inline tool call history: each agent response shows clickable N steps badge expanding to show all tool calls between user input and response


## 15:01 - Identified gap: agent events are in-memory only, lost on restart. SQLite persistence needed. Also noted Claude Code hooks don't expose intermediate thinking, only tool calls.


## 15:09 - Migrated agent events from in-memory deques to SQLite persistence. Added agent_events table to conversations.db with message_id FK. Backend now stores all tool call events in SQLite and links them to messages on Stop events. Frontend fetches persisted tool calls via bulk API endpoint, with activity store fallback for live updates.


## 15:22 - Persisted agent events in SQLite with message_id FK. Moved from in-memory deques to conversations.db. Fixed journal nudge wording to be clearly system-automated. Next: moving nudge logic from Python backend to bash daemon.


## 15:32 - Moved journal nudge from Python agent_events.py to bash daemon (journal-nudge.sh). Nudging is orchestration, not backend logic — needs to survive server restarts. Daemon queries SQLite directly for tool counts and sends tmux nudges independently. Also made nudge message explicitly mechanical so agents don't confuse it with user instructions.


## 15:33 - Persisted agent events in SQLite with message_id FK, moved journal nudge to bash daemon, made nudge message explicitly mechanical


## 15:35 - Persisted agent events in SQLite, moved nudge to bash
Replaced in-memory deque event buffers with an agent_events table in conversations.db. Each tool call is now persisted with a message_id FK that gets set when the agent's Stop event creates a message. Added bulk API endpoint (POST /agent-events/by-messages) so the frontend can fetch tool calls for all visible messages in one request. Frontend merges SQLite-backed data with live activity store for real-time updates. Moved journal nudge logic out of agent_events.py into a standalone bash daemon (journal-nudge.sh) that queries SQLite directly — keeps orchestration in the bash layer where it survives backend restarts. Fixed nudge to use 'note' instead of 'log' so entries get body paragraphs.

## 15:39 - Fixed empty directories rendering as files
Empty directories like artifacts/ were falling through to the file renderer in FileTree.tsx because the condition checked hasChildren (false for empty dirs). Changed to check isDirectory instead so all directories get the folder icon and collapsible chevron regardless of contents. Also had to remember to actually run npm run build after frontend changes — the served static files were stale.

## 16:54 - Context limit & compact failure
Previous supervisor instance hit context limit and auto-compact failed. Manual /compact from tmux also didn't work. Need to investigate compaction reliability as a follow-up task after the current deep system analysis.

## 17:22 - Starting SQLite WAL task
Enabling WAL mode and busy timeout for conversations.db to fix concurrent access SQLITE_BUSY errors

## 17:23 - Starting health.sh timeout task
Adding timeouts to health.sh rollback operations to prevent hangs from network issues or corrupted caches. Also wiring check_frontend_health() into the main loop.

## 17:23 - Completed SQLite WAL mode fix
Enabled PRAGMA journal_mode=WAL and PRAGMA busy_timeout=5000 in conversation_store.py _get_connection() and both sqlite3 CLI calls in journal-nudge.sh. This fixes SQLITE_BUSY errors when the FastAPI server, router, and shell daemons access conversations.db concurrently. All 12 tests pass. Commit 5632060.

## 17:25 - Compaction Investigation: Critical Findings & Recommendations
INVESTIGATION SUMMARY: Context compaction has CRITICAL reliability issues that caused a supervisor to hit context limits with no recovery path.

FINDING 1 — compact.sh IS MISSING. CLAUDE.md (line 142) and README.md (line 276) both reference 'compact.sh — Periodic context compaction scheduler' as a key orchestration component. But this file DOES NOT EXIST in the codebase. The status.log shows it DID work historically — there are dozens of 'Periodic compact completed' entries from 2026-01-29 on ~15-minute intervals. At some point it was deleted or lost, leaving agents with NO proactive compaction.

FINDING 2 — Current compaction is REACTIVE ONLY. Two mechanisms exist: (a) POST /api/agents/{id}/compact endpoint (agents.py:104-112) sends '/compact' as text input to the agent's tmux window, (b) Frontend 'Compact' button in AgentDetail.tsx calls that API. Both rely on Claude Code's built-in /compact slash command. There is no daemon, no periodic trigger, no automatic monitoring.

FINDING 3 — /compact delivery is UNRELIABLE via tmux. The API endpoint calls tmux_service.send_input(window, '/compact') which uses send-keys -l followed by Enter. This WILL FAIL if: (a) the agent is mid-tool-execution and not at a prompt, (b) the terminal has pending paste buffer content, (c) the agent is in vim mode, (d) the context is so full that Claude Code cannot process the command. The journal entry from 16:54 confirms: 'auto-compact failed. Manual /compact from tmux also didn't work.'

FINDING 4 — NO VERIFICATION after compact. After sending /compact, nothing checks whether compaction succeeded. No pane capture to verify, no retry logic, no fallback behavior. The old compact.sh logged 'Periodic compact completed' but it's unclear if it verified success or just logged that it sent the command.

FINDING 5 — RACE CONDITIONS with tmux sends. The journal-nudge daemon, message router, and compact endpoint all send text to agent tmux windows via send-keys. There is no locking or queuing. Simultaneous sends (nudge + compact, or message delivery + compact) can interleave and corrupt both inputs.

FINDING 6 — No context usage monitoring. Claude Code shows context usage in the status line, but CMUX never reads it. Compaction is either manual or (when compact.sh existed) on a blind timer. There is no way to know when an agent is approaching its limit.

RECOMMENDATIONS — P0 (IMMEDIATE):
1. Recreate compact.sh daemon. It should: enumerate all active agent windows, check if agent is at a prompt (capture pane, look for the prompt indicator), send /compact, verify success by capturing pane output after a delay, log result. Run every 10-15 min.
2. Add pre-flight idle check before sending /compact — capture pane, verify agent is at prompt (look for the > indicator), abort if agent is mid-execution.
3. Add post-compact verification — capture pane after 10-15 seconds, confirm Claude Code reported compaction success.

RECOMMENDATIONS — P1 (MEDIUM TERM):
4. Monitor context usage. Parse Claude Code status line via capture-pane to read context % used. Trigger compact at 60% instead of waiting for 95%.
5. Graceful agent restart as fallback. If /compact fails: journal the agent's current task, kill the window, respawn agent, send it the task context from journal. The journal system makes this viable.
6. Add tmux send mutex. Simple lock file (.cmux/.tmux-send-{window}.lock) checked by router.sh, journal-nudge.sh, and compact endpoint before sending to any agent window.

RECOMMENDATIONS — P2 (ARCHITECTURE):
7. Update CLAUDE.md and README.md to remove references to compact.sh until it is recreated.
8. Consider adding a /compact hook to Claude Code hooks system (PostToolUse event count threshold) as an alternative trigger mechanism.
9. Consider pre-emptive agent rotation: spawn a new agent, transfer task context via journal, kill the old one — instead of compacting in-place.

## 17:25 - Completed health.sh timeout hardening
Added timeouts to all rollback operations in health.sh: 30s for git reset, 120s per rebuild command (uv sync, npm ci, npm run build), and 5-minute overall rollback timeout. Uses a portable run_with_timeout() bash function since macOS lacks GNU timeout. Also wired check_frontend_health() into the main loop. Commit 406263f.

## 17:26 - Starting: Add flock-based file locking to all mailbox write operations

## 17:31 - Completed flock-based mailbox locking
Added cross-process file locking to all mailbox write operations using flock(2). Created portable src/orchestrator/lib/filelock.sh that uses flock on Linux and Python fcntl fallback on macOS. All 6 files that touch the mailbox now coordinate through /tmp/cmux-mailbox.lock: tools/mailbox, router.sh, mailbox.py, health.sh, log-watcher.sh. Router.sh was restructured to snapshot lines under lock then process outside lock to minimize contention. All 12 tests pass. Cross-process contention test confirmed blocking works.

## 17:31 - Tier 1 fixes complete
All 4 Tier 1 reliability fixes delivered by workers. SQLite WAL mode (5632060), cross-process mailbox flock (9b894ce), health.sh timeouts + frontend health check (406263f), compaction investigation (journaled). Key outstanding: compact.sh daemon needs to be rebuilt — it's completely missing from codebase, causing agents to brick when context fills up. Ready for Tier 2 or compact.sh rebuild.
