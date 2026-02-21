# CMUX System Report — Comprehensive Technical Reference

> **Author**: Nova (perm-research)
> **Date**: 2026-02-21
> **Scope**: Complete technical breakdown of the CMUX multi-agent orchestration system.
> **Method**: All claims verified against source code. File paths and line numbers cited.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Orchestration Layer](#2-orchestration-layer)
3. [Agent Lifecycle](#3-agent-lifecycle)
4. [Communication System](#4-communication-system)
5. [Memory & Persistence](#5-memory--persistence)
6. [Self-Improvement Loop](#6-self-improvement-loop)
7. [Hook System](#7-hook-system)
8. [Team Templates & Permanent Workers](#8-team-templates--permanent-workers)
9. [Frontend Dashboard](#9-frontend-dashboard)
10. [Safety Model](#10-safety-model)

---

## 1. Architecture Overview

### Core Concept

CMUX is a **self-improving multi-agent AI orchestration system**. It runs multiple Claude Code instances inside tmux windows, coordinated by a supervisor agent, with a FastAPI backend and React dashboard for monitoring. The defining characteristic: agents can modify the CMUX codebase itself, and a safety system automatically rolls back breaking changes.

### System Topology

```
┌────────────────────────────────────────────────────────────────┐
│                        tmux session: cmux                      │
│                                                                │
│  Window 0: monitor     ← dashboard loop, daemon launcher       │
│  Window 1: supervisor  ← Claude Code (main coordinator)        │
│  Window 2+: workers    ← Claude Code instances (perm- or temp) │
│  Window N: sentry      ← spawned on supervisor failure         │
│  Window N: sup-*       ← project supervisors                   │
│                                                                │
└────────┬───────────────────────┬───────────────────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐   ┌──────────────────────────┐
│  FastAPI Server  │   │  Background Daemons       │
│  (port 8000)     │   │  - router.sh (mailbox)    │
│                  │   │  - compact.sh (context)    │
│  13 route groups │   │  - journal-nudge.sh        │
│  WebSocket mgr   │   │  - log-watcher.sh          │
│  SQLite store    │   └──────────────────────────┘
│                  │
│  /api/agents     │   ┌──────────────────────────┐
│  /api/messages   │   │  .cmux/ runtime state     │
│  /api/journal    │   │  - mailbox (JSONL)         │
│  /api/heartbeat  │   │  - agent_registry.json     │
│  /api/budget     │   │  - conversations.db        │
│  /api/tasks      │   │  - tasks.db                │
│  /api/thoughts   │   │  - journal/YYYY-MM-DD/     │
│  ...             │   │  - worker-contexts/         │
└────────┬─────────┘   └──────────────────────────┘
         │
         ▼
┌─────────────────┐
│  React Frontend  │
│  (served static) │
│  Zustand stores  │
│  WebSocket sub   │
└─────────────────┘
```

### Key Design Principles

1. **Isolation via tmux**: Each agent runs in a separate tmux window. If one agent crashes, others continue unaffected.
2. **File-based IPC**: The mailbox file (`.cmux/mailbox`) is the primary inter-agent communication channel. No shared memory, no RPC — just a JSONL file with file locking.
3. **Git as the safety net**: Health checks run every 5 seconds. If the server goes down, the system stashes changes and rolls back to the last known-good commit.
4. **Supervisor hierarchy**: User → Supervisor → Workers. Workers never communicate with the user directly.
5. **Mechanical enforcement > documentation**: Behavioral rules are enforced by shell hooks (`block-interactive.sh`, `block-supervisor-edits.sh`, `stop-gate.sh`) rather than relying on agents to read and follow docs.

---

## 2. Orchestration Layer

The orchestration layer consists of three shell scripts that form the control plane: `cmux.sh` (entry point), `monitor.sh` (control center), and four background daemons.

### 2.1 cmux.sh — Entry Point

**File**: `src/orchestrator/cmux.sh` (272 lines)

The CLI entry point with three commands: `start`, `stop`, `status`.

**`cmd_start`** (line 33):
1. Checks dependencies: `tmux`, `claude`, `git`, `curl`, `uv`, `jq`, `node`
2. Checks port 8000 is free (or already running CMUX)
3. Creates tmux session `cmux` with window 0 named "monitor"
4. Launches `monitor.sh` in window 0
5. Attaches the terminal to the tmux session

**`cmd_stop`** (line 130):
- Timeout watchdog: sends SIGTERM, waits 5s, then SIGKILL
- Kills ALL `cmux-*` sessions (worker sessions spawned outside the main session)
- Fallback: `pkill -f "claude.*cmux"` if tmux cleanup is insufficient

**Session structure**:
```
cmux:monitor    (window 0) — monitor.sh dashboard loop
cmux:supervisor (window 1) — Claude Code supervisor agent
cmux:worker-1   (window 2+) — worker agents
cmux:sentry     (dynamic)  — recovery agent
cmux:sup-hero   (dynamic)  — project supervisors
```

### 2.2 monitor.sh — Control Center

**File**: `src/orchestrator/monitor.sh` (1447 lines)

The largest and most important orchestration script. Runs in tmux window 0 and serves as both the startup sequencer and the ongoing health dashboard.

**Startup sequence** (`main()`, line 1397):
1. `start_server()` — builds frontend if needed, starts uvicorn via nohup, waits up to 30s for health endpoint
2. `launch_supervisor()` — creates tmux window, starts Claude with `--dangerously-skip-permissions`, sends SUPERVISOR_ROLE.md instruction + latest journal for continuity
3. `launch_project_supervisors()` — reads `.cmux/projects.json`, activates any active non-self projects
4. `start_router()` — launches `router.sh` in background
5. `start_log_watcher()` — launches `log-watcher.sh` in background
6. `start_journal_nudge()` — launches `journal-nudge.sh` in background
7. `start_compact_daemon()` — launches `compact.sh` in background
8. `run_dashboard()` — enters the infinite health dashboard loop

**Identity verification** (`is_server_running()`, line ~62):
Not just a port check — it verifies the response contains `"api":"healthy"` to prevent false positives when another server occupies port 8000.

**Dashboard loop** (`run_dashboard()`, line 1061):
Runs every 5 seconds:
- Checks FastAPI health (triggers recovery after 3 consecutive failures)
- Restarts dead daemons (router, journal-nudge, compact)
- Monitors sentry status (timeout after 300s)
- Checks supervisor heartbeat (graduated escalation)
- Checks project supervisor heartbeats
- Sweeps all panes for stuck paste buffers
- Runs auto-maintenance every 5 minutes

### 2.3 Background Daemons

**router.sh** — See Section 4 (Communication)
**compact.sh** — See Section 6 (Self-Improvement)
**journal-nudge.sh** — Periodically reminds agents to journal their work
**log-watcher.sh** — Watches status log for events to broadcast to dashboard

---

## 3. Agent Lifecycle

### 3.1 Agent Types

| Type | Window Name | Created By | Persistence |
|------|------------|------------|-------------|
| Supervisor | `supervisor` | monitor.sh | Immortal (auto-relaunched) |
| Project Supervisor | `sup-*` | monitor.sh / tools/projects | Session-persistent |
| Permanent Worker | `perm-*` | tools/workers --permanent | Survives task completion |
| Ephemeral Worker | any name | tools/workers spawn | Killed after task or by supervisor |
| Clone Worker | `parent-clone-N` | tools/workers clone | Killed after merge |
| Sentry | `sentry` | monitor.sh | Self-terminates after recovery |

### 3.2 Spawning a Worker

**File**: `tools/workers` — `cmd_spawn()` (line 81, 300 lines)

Spawning sequence:
1. Parse arguments: name, task, --dir, --project, --task, --worktree, --permanent
2. Generate unique agent ID (`ag_` + 8 random alphanumeric chars, collision-checked against registry)
3. Create tmux window: `tmux new-window -t cmux: -n <name>`
4. Lock window name: `tmux set-option allow-rename off`
5. Register in `.cmux/agent_registry.json` with agent_id, display_name, role, project_id, worktree info
6. Set environment variables:
   ```
   CMUX_AGENT=true
   CMUX_AGENT_ID=ag_xxxxxxxx
   CMUX_AGENT_NAME=<name>
   CMUX_SESSION=cmux
   CMUX_HOME=<project-root>
   CMUX_PORT=8000
   CMUX_SUPERVISOR=<spawner-name>
   CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false
   ```
7. Start Claude: `claude --dangerously-skip-permissions`
8. Wait 8 seconds for initialization
9. Disable vim mode if detected
10. Write context file to `.cmux/worker-contexts/<name>-context.md` containing:
    - Identity (name, supervisor, port warning)
    - Hierarchy explanation
    - Communication protocol
    - Journal instructions
    - The task itself
11. Send single-line instruction to read the context file (avoids multiline paste issues)
12. Link to task system if --task provided

**Permanent workers** additionally get:
- `permanent: true` and `role_context` path in the registry
- `tasks_since_reset` and `reset_count` counters
- Deletion protection (requires `--force` to kill)

**Worktree support** (--worktree flag):
- Creates `~/.cmux/worktrees/<project>/<name>` with branch `feat/<name>`
- Branch is created from HEAD of the source repo (supervisor's integration branch)
- Worker commits to their branch; supervisor merges after [DONE]

### 3.3 Worker Reset

**File**: `tools/workers` — `cmd_reset()` (line 607)

For permanent workers whose context is filling up:
1. Run pre-compact hook to capture state artifact
2. Mark active task as "blocked" in tasks.db
3. Archive conversation via API (`POST /api/agents/<name>/archive`)
4. Send `/exit` to Claude, wait up to 10s, fallback to Ctrl+C
5. Restart Claude in the same tmux window with same env vars
6. Send role context reference instruction
7. Update registry: increment `reset_count`, reset `tasks_since_reset`

### 3.4 Worker Kill

**File**: `tools/workers` — `cmd_kill()` (line 383)

1. Block if target is a supervisor
2. Block if permanent worker (unless --force)
3. Archive conversation via API
4. Send Ctrl+C for graceful Claude stop
5. Kill tmux window
6. Print worktree preservation note if applicable

### 3.5 Clone System

**File**: `tools/workers` — `cmd_clone()` (line 745)

Allows a permanent worker to have parallel copies for concurrent work:
1. Verify parent is permanent
2. Generate clone name: `<parent>-clone-<N>` (collision-safe)
3. Write clone-specific role context referencing parent's role file
4. Spawn via `cmd_spawn` with --worktree and parent's project
5. Add clone metadata to registry: `clone_of`, `clone_index`
6. Notify parent via mailbox

**Merge-clone** (`cmd_merge_clone()`, line 833):
- `git merge --no-ff <branch>` into current branch
- Kill clone worker, remove worktree, delete branch, clean registry

---

## 4. Communication System

### 4.1 Mailbox — File-Based Message Queue

**File (shell)**: `.cmux/mailbox` (JSONL format)
**File (Python)**: `src/server/services/mailbox.py` (198 lines)

The mailbox is a single JSONL file where each line is a message:
```json
{"id":"uuid","ts":"ISO8601","from":"cmux:worker-1","to":"cmux:supervisor","subject":"[DONE] Auth implemented","body":"path/to/body.md","status":"submitted"}
```

**Address format**: `<session>:<agent>` (e.g., `cmux:supervisor`, `cmux:perm-frontend`)

**Body handling**: Long message bodies are written to files at `.cmux/journal/YYYY-MM-DD/attachments/msg-<id>.md`. The mailbox entry contains just the path.

**Locking**: Cross-process flock via `/tmp/cmux-mailbox.lock`. The Python MailboxService uses both asyncio locks (intra-process) and fcntl file locks (cross-process).

### 4.2 Router — Message Delivery

**File**: `src/orchestrator/router.sh` (419 lines)

The router is a background daemon that polls the mailbox every 2 seconds.

**Position tracking**: Uses a marker file `.cmux/.router_line` to track the last processed line number. Only processes new lines since last read.

**Message processing pipeline**:
1. `process_mailbox()` — Locks mailbox during read, snapshots new lines, processes outside lock
2. `parse_line()` — Validates JSON with jq, extracts fields, handles `status_update` records
3. `route_message()`:
   - Stores message via API (`POST /api/messages/internal`)
   - Extracts target agent from `to` address
   - Delivers via `tmux_safe_send` (literal flag + Enter, with retry and queue fallback)
   - Updates task status to "working" via API
4. `drain_all_queues()` — Processes `.cmux/send-queue/<window>` files for messages that couldn't be delivered (agent was busy)

**Delivery format in terminal**:
```
[cmux:supervisor] [TASK] Fix the login bug
```

**Status updates**: Lines with `"type":"status_update"` are handled separately — they PATCH the agent status via API rather than delivering to tmux.

### 4.3 Communication Protocol

Agents communicate using prefixed messages:

| Prefix | Direction | Meaning |
|--------|-----------|---------|
| `[TASK]` | Supervisor → Worker | New work assignment |
| `[DONE]` | Worker → Supervisor | Task complete + summary |
| `[STATUS]` | Worker → Supervisor | Progress update |
| `[BLOCKED]` | Worker → Supervisor | Cannot proceed, needs help |
| `[QUESTION]` | Worker → Supervisor | Needs clarification |
| `[REVIEW-REQUEST]` | Worker → Supervisor | Code ready for review |
| `[ERROR]` | System → Supervisor | System-level error |
| `[HEARTBEAT]` | Monitor → Supervisor | Idle nudge with autonomy scan |
| `[SYS]` | Any agent | System notification (compact rendering in dashboard) |

**Mailbox CLI** (`tools/mailbox`):
- `mailbox send <to> <subject> <body>` — Send arbitrary message
- `mailbox done <summary>` — Report task completion to supervisor
- `mailbox blocked <reason>` — Report blocker to supervisor

### 4.4 WebSocket — Real-Time Frontend Updates

**File (Python)**: `src/server/websocket/manager.py` (136 lines)
**File (React)**: `src/frontend/src/hooks/useWebSocket.ts` (232 lines)

The WebSocket manager (`ws_manager`) is a singleton that:
- Maintains a dictionary of `client_id → WebSocket` connections
- Broadcasts events to all connected clients
- Sends periodic pings every 30 seconds to detect dead connections
- Auto-removes stale connections on send failure

**WebSocket events**:
| Event | Source | Payload |
|-------|--------|---------|
| `agent_event` | Hook → API → WS | Tool use events (PostToolUse, Stop) |
| `agent_thought` | Hook → API → WS | Agent reasoning + tool inputs |
| `new_message` | Mailbox/API → WS | Chat messages between agents |
| `user_message` | Dashboard → API → WS | Messages from the human user |
| `heartbeat_update` | Monitor → API → WS | System health snapshot |
| `session_created/terminated` | API → WS | Agent lifecycle events |
| `agent_archived` | API → WS | Worker archived before kill |
| `webhook_received` | External → API → WS | Incoming webhook |

**Frontend reconnection**: Exponential backoff starting at `RECONNECT_DELAY_BASE`, capped at `RECONNECT_DELAY_MAX`. Resets on successful connection.

---

## 5. Memory & Persistence

CMUX uses a multi-tier memory system, each tier serving a different purpose.

### 5.1 Tier 1: MEMORY.md — Cross-Session Stable Knowledge

**File**: `MEMORY.md` (auto-loaded by Claude Code's memory system)

Short, high-value patterns confirmed across multiple interactions. Limited to ~200 lines. Covers:
- Workflow rules (journaling, building, artifact saving)
- Alert tools
- Autonomy guidelines
- Technical patterns (FastAPI route ordering, CSS conventions)
- Delegation rules (NEVER write code directly)

### 5.2 Tier 2: Journal — Daily Append-Only Log

**Path**: `.cmux/journal/YYYY-MM-DD/journal.md`
**API**: `POST /api/journal/entry` with title, content, tags

Append-only markdown file with timestamped entries. Used for:
- Work documentation (what was done, why, key decisions)
- Incident records (rollbacks, recovery)
- Progress tracking across sessions

**Artifacts sub-directory**: `.cmux/journal/YYYY-MM-DD/artifacts/`
Non-trivial outputs (research reports, plans, analysis docs, generated specs) are saved here. They survive compaction and session restarts.

### 5.3 Tier 3: Reflection — Daily Working Document

**Path**: `.cmux/journal/YYYY-MM-DD/reflection.md`

Active self-improvement document, read on every heartbeat nudge. Contains:
- "Investigate Next" checklist
- "Mistakes & Patterns Found" log
- "Ideas for CMUX Improvement"
- "Research Queue"
- "Session Handoff Notes" for supervisor continuity

### 5.4 Tier 4: SQLite Stores

**conversations.db** (`src/server/services/conversation_store.py`, 723 lines):
- `messages` table — All inter-agent messages with from/to/type/content/task_status
- `agent_archives` table — Terminal snapshots captured before worker kill
- `agent_events` table — Every tool call from every agent (PostToolUse, Stop events)
- `thoughts` table — Agent reasoning and tool inputs streamed to dashboard

Uses WAL mode and 5s busy timeout for concurrent access.

**tasks.db** (managed by `tools/tasks`):
- Task tracking: id, title, description, status, priority, assigned_to, linked_workers
- Used by backlog system, task assignment, heartbeat autonomy scans

### 5.5 Tier 5: Agent Registry

**File**: `.cmux/agent_registry.json`

JSON object mapping window names to agent metadata:
```json
{
  "perm-research": {
    "agent_id": "ag_xk9m2p4q",
    "display_name": "Nova",
    "role": "permanent-worker",
    "project_id": "cmux",
    "permanent": true,
    "role_context": ".cmux/worker-contexts/perm-research-role.md",
    "tasks_since_reset": 3,
    "reset_count": 1,
    "last_reset_at": "2026-02-21T10:30:00Z"
  }
}
```

### 5.6 Tier 6: Worker Context Files

**Path**: `.cmux/worker-contexts/<name>-context.md`

Auto-generated when a worker spawns. Contains identity, hierarchy, communication protocol, and task assignment. Read by the agent on startup.

**Role files**: `.cmux/worker-contexts/<name>-role.md`
For permanent workers, contains personality, specialization, project context, standards, and team coordination info.

---

## 6. Self-Improvement Loop

### 6.1 Health Monitoring & Auto-Recovery

**File**: `src/orchestrator/monitor.sh` — `run_dashboard()` (line 1061) + `attempt_recovery()` (line 1331)

Every 5 seconds, the dashboard checks `is_server_running()`. After 3 consecutive failures:

**Stage 1 — Simple restart** (line 1339):
- Kill server processes on port 8000
- Restart uvicorn
- If healthy: done

**Stage 2 — Journal + Rollback** (line 1349):
- Save failure context to journal (both via API and local file)
- `git stash push -m "cmux-auto-rollback-<epoch>"`
- `git reset --hard <last-healthy-commit>`
- Rebuild: `uv sync` + `npm ci && npm run build`
- Restart server
- Notify supervisor via mailbox

**Stage 3 — Progressive rollback** (line 1366):
- Try each of the last 10 commits until one works
- Same rebuild + restart cycle for each

**Healthy commit tracking** (`mark_healthy()`, line 1210):
On successful health check after a failure, writes `HEAD` to `.cmux/.last_healthy_commit`.

### 6.2 Heartbeat System

**File**: `src/orchestrator/monitor.sh` — `check_supervisor_heartbeat()` (line 397)

The heartbeat system detects and recovers from an idle or stuck supervisor. It uses a `.cmux/.supervisor-heartbeat` file (epoch timestamp updated by the supervisor agent).

**Configuration**:
| Variable | Default | Purpose |
|----------|---------|---------|
| `HEARTBEAT_WARN_THRESHOLD` | 600s | Seconds idle before first nudge |
| `HEARTBEAT_NUDGE_INTERVAL` | 120s | Cooldown between nudges |
| `HEARTBEAT_MAX_NUDGES` | 3 | Failed nudges before escalation |
| `HEARTBEAT_OBSERVE_TIMEOUT` | 1200s | Frozen pane time before sentry |

**Escalation path**:

```
Healthy (< 600s idle)
    │
    ▼ staleness > HEARTBEAT_WARN_THRESHOLD
    │
    ├─ Supervisor at prompt (IDLE PATH):
    │   1. Send autonomy nudge with `tools/autonomy-check --summary`
    │   2. Up to 3 nudges with 120s cooldown
    │   3. Force-inject backlog task
    │   4. Reset + try again
    │   5. If process dead → spawn sentry
    │
    └─ Supervisor mid-task (BUSY PATH):
        1. Enter observation mode
        2. Hash pane output every cycle
        3. If output changes → reset frozen timer (progress detected)
        4. If frozen > 1200s → spawn sentry
```

**Hybrid liveness detection**:
- `is_supervisor_at_prompt()` — Delegates to `tmux_pane_state()` which checks for prompt indicators
- `is_supervisor_process_alive()` — Walks the pane PID's process tree looking for a `claude` process

### 6.3 Sentry Agent

**File**: `src/orchestrator/monitor.sh` — `spawn_sentry()` (line 706)

Last-resort recovery. The sentry is a Claude Code agent with a scripted recovery procedure:

1. Gather context: supervisor terminal output (100 lines), recent journal (50 lines), recent mailbox (10 lines), backlog items (top 3)
2. Write dynamic context file with full recovery procedure
3. Spawn Claude in tmux window "sentry" with `--dangerously-skip-permissions`
4. Recovery steps:
   - Try `/compact` on stuck supervisor (wait 30s)
   - Check if heartbeat recovered (if < 120s, done)
   - Kill supervisor window if still stale
   - Wait for monitor.sh to relaunch supervisor
   - Write enriched briefing file and send to new supervisor
   - Journal the incident
   - Self-terminate (remove lockfile, kill own window)

**Safety**: Sentry timeout of 300s — forcibly killed by monitor if it takes too long.

### 6.4 Compaction Daemon

**File**: `src/orchestrator/compact.sh` (276 lines)

Prevents agents from hitting context limits by periodically compacting their conversation history.

**Cycle** (every 600s = 10 minutes):
1. Enumerate all tmux windows
2. Skip monitor and supervisor (configured in `SKIP_WINDOWS`)
3. For each worker:
   - Check if idle (at prompt)
   - Check if there's been activity since last compaction (heartbeat/context file mtime)
   - Run pre-compact hook to save state artifact
   - Send `/compact` via `tmux_safe_send` with 5 retries
   - Wait 15s, verify success (check pane for "compact" indicators)
   - Inject recovery message pointing to the artifact file
4. Record compaction timestamp per window in `.cmux/.compact-timestamps`

### 6.5 Autonomy Check

**Tool**: `tools/autonomy-check`

Scans all work sources and returns a prioritized summary:
- Pending mailbox messages
- Worker status (done, blocked, stuck)
- Backlog items
- Stale workers
- Uncommitted changes

Used by the heartbeat system to give the supervisor actionable nudges instead of generic "you're idle" messages.

---

## 7. Hook System

CMUX uses 9 Claude Code hooks that run as shell scripts on specific events. All hooks check `CMUX_AGENT=true` to only activate for managed agents.

### 7.1 block-interactive.sh (PreToolUse)

**File**: `.claude/hooks/block-interactive.sh` (79 lines)

**Purpose**: Prevents `AskUserQuestion` and `EnterPlanMode` tool calls for all CMUX agents (they run unattended in tmux — these tools would block forever).

**Rescue mechanism**: Before blocking, extracts the assistant's text from the transcript and POSTs it to the messages API. Without this, the text would be lost because the turn aborts before the Stop event fires.

**Behavior by role**:
- Supervisor: "Communicate via direct text output or mailbox"
- Workers: "Send a [REVIEW-REQUEST] to the supervisor via mailbox"

### 7.2 block-supervisor-edits.sh (PreToolUse)

**File**: `.claude/hooks/block-supervisor-edits.sh` (61 lines)

**Purpose**: The #1 recurring failure pattern is the supervisor writing code instead of delegating. This hook makes it mechanically impossible by blocking Edit/Write/NotebookEdit for the supervisor agent.

**Exceptions** (files the supervisor legitimately edits):
- `.cmux/*` — Runtime state (journal, mailbox, config, worker contexts)
- `MEMORY.md` and `memory/` — Memory files
- `reflection.md` — Daily reflection documents

### 7.3 stop-gate.sh (Stop)

**File**: `.claude/hooks/stop-gate.sh` (101 lines)

**Purpose**: Ensures agents persist their work before stopping. Blocks shutdown if the agent used tools (>= 5 tool calls) but didn't:
- Commit changes (git add + git commit)
- Journal work (tools/journal)
- Report completion (tools/mailbox)

**Exemptions**:
- Supervisor (has its own completion workflow)
- Permanent workers during reset (state captured by reset procedure)
- Short sessions (< 5 tool calls)

### 7.4 notify-complete.sh (Stop)

**File**: `.claude/hooks/notify-complete.sh` (125 lines)

**Purpose**: On every Claude Code Stop event, extracts the agent's response from the transcript and POSTs it to `/api/agent-events`. This is how agent messages reach the dashboard.

**Extraction logic**: Reads the last 100 lines of the JSONL transcript, finds the most recent assistant entry with text content, joins multiple text blocks. Also extracts token usage data (input_tokens, output_tokens, cache_read/creation_tokens).

### 7.5 notify-output.sh (PostToolUse)

**File**: `.claude/hooks/notify-output.sh` (56 lines)

**Purpose**: POSTs every tool call (tool_name, tool_input, tool_output) to `/api/agent-events` as a `PostToolUse` event. This provides the activity stream in the dashboard.

### 7.6 stream-thought.sh (PreToolUse)

**File**: `.claude/hooks/stream-thought.sh` (49 lines)

**Purpose**: Before each tool call, extracts the agent's internal reasoning (thinking blocks only, not text blocks) from the transcript and POSTs it to `/api/thoughts`. This powers the "thought stream" feature in the dashboard.

### 7.7 stream-result.sh (PostToolUse)

**File**: `.claude/hooks/stream-result.sh` (35 lines)

**Purpose**: After each tool call, sends the tool name and truncated response (first 500 chars) to `/api/thoughts` as a `tool_result` thought type. Complementary to stream-thought.sh.

### 7.8 audit-log.sh (PostToolUse)

**File**: `.claude/hooks/audit-log.sh` (42 lines)

**Purpose**: Appends a structured JSON line to `.cmux/audit.log` for every tool call:
```json
{"timestamp":"...","agent_name":"perm-research","tool_name":"Read","input_summary":"...","session":"cmux"}
```

Includes log rotation: when audit.log exceeds 10MB, rotates to audit.log.1.

### 7.9 pre-compact.sh (Custom — called by compact.sh)

**File**: `.claude/hooks/pre-compact.sh` (57 lines)

**Purpose**: Captures agent state before compaction for post-compact recovery. Saves a JSON artifact with:
- Terminal snapshot (last 50 lines)
- Git branch, uncommitted changes, staged changes
- Current task from tasks.db

Output: `.cmux/journal/YYYY-MM-DD/artifacts/compaction-<window>-<timestamp>.json`

---

## 8. Team Templates & Permanent Workers

### 8.1 Team Templates

**File**: `tools/teams` (999 lines)
**Templates directory**: `docs/templates/teams/`

6 templates for different task types:

| Template | Workers | Structure | Use Case |
|----------|---------|-----------|----------|
| `SOLO_WORKER` | 1 | Flat | Simple, focused tasks |
| `SQUAD_MODEL` | 5 | Lead + 4 specialists | Cross-functional features |
| `FEATURE_TEAM` | 3 | Tech lead + backend + frontend | Standard features |
| `PLATFORM_TEAM` | 3 | Platform lead + infra + devops | Infrastructure work |
| `TIGER_TEAM` | 3 | Flat peers, no lead | Urgent fixes |
| `DEBATE_PAIR` | 2 | Defender + critic | Design decisions |

**Ephemeral teams** (`teams setup`):
- Quick-spawned teams for a single task
- Auto-generated prefix from task description
- Each worker gets role template + task + team member list
- Leads get full team roster; members report to lead
- Debate pairs write proposals to shared artifacts directory

**Permanent teams** (`teams setup-permanent`):
- For long-running projects
- Scans the target project directory (via `lib/scan-project.sh`)
- Auto-generates role files with project-specific context (tech stack, key files, conventions)
- Spawns workers with `--permanent` flag
- Role files include personality, communication style, specialization, standards, team coordination

### 8.2 Permanent Worker Architecture

**Current CMUX team** (8 permanent workers):

| Worker | Display Name | Specialization |
|--------|-------------|----------------|
| `perm-frontend` | Mira | Frontend (React, Zustand, CSS) |
| `perm-backend` | Kai | Backend (FastAPI, Python, SQLite) |
| `perm-infra` | Sol | Infrastructure (shell scripts, tmux, daemons) |
| `perm-research` | Nova | Research, analysis, documentation |
| `perm-ui-review` | Sage | UI/UX review |
| `perm-api-review` | Flint | API review |
| `perm-devops` | Bolt | DevOps, automation |
| `perm-qa` | Echo | Quality assurance, testing |

**Permanent worker protocol**:
1. Read role file on startup
2. Receive `[TASK]` messages from supervisor
3. Send `[STATUS]` progress updates
4. Report `[DONE]` or `[BLOCKED]` when finished/stuck
5. Journal work frequently
6. Proactive reset policy: after 5 tasks or 3 hours, supervisor resets context

**Registry fields for permanent workers**:
- `permanent: true`
- `role_context`: path to role file
- `tasks_since_reset`: counter, reset on `workers reset`
- `reset_count`: lifetime reset counter
- `last_reset_at`: ISO timestamp

---

## 9. Frontend Dashboard

### 9.1 Architecture

**Framework**: React + TypeScript + Vite
**State**: Zustand stores (13 stores)
**UI**: shadcn/ui components + Tailwind CSS
**Data fetching**: TanStack Query (React Query) for REST, custom WebSocket hook for real-time

**Build**: `npm run build` outputs to `src/frontend/dist/`, served by FastAPI's StaticFiles mount at `/`.

### 9.2 Zustand Stores

| Store | Purpose |
|-------|---------|
| `agentStore` | Agent list, selection, archived agents |
| `agentEventStore` | Tool call events from hooks |
| `activityStore` | General activity feed |
| `connectionStore` | WebSocket connection status |
| `sessionStore` | tmux session tracking |
| `layoutStore` | Panel sizes, collapsed state |
| `thoughtStore` | Agent reasoning stream |
| `heartbeatStore` | Supervisor heartbeat data |
| `projectStore` | Multi-project management |
| `taskStore` | Task tracking |
| `viewerStore` | File viewer state |
| `themeStore` | Dark/light theme |
| `onboardingStore` | First-run guide |
| `budgetStore` | (implied by BudgetPanel) |

### 9.3 Key Components

**Layout** (`components/layout/`):
- `ResizableLayout.tsx` — Three-panel resizable layout (sidebar, main, detail)
- `Sidebar.tsx` — Navigation, agent tree, file explorer
- `Header.tsx` — Top bar with connection indicator, project selector

**Agent views** (`components/agents/`):
- `AgentList.tsx` — List of all agents with status indicators
- `AgentCard.tsx` — Individual agent card with status, type, actions
- `AgentDetail.tsx` — Detailed agent view (terminal output, messages)
- `TerminalView.tsx` — tmux pane capture display
- `OutputPanel.tsx` — Agent output panel

**Chat** (`components/chat/`):
- `ChatPanel.tsx` — Main chat interface for agent interaction
- `ChatMessages.tsx` — Message list with auto-scroll
- `ChatMessage.tsx` — Individual message with markdown rendering
- `ChatInput.tsx` — Message input with send action
- `InterleavedTimeline.tsx` — Messages + tool calls interleaved chronologically
- `ToolCallGroup.tsx` — Grouped tool call display
- `ThoughtGroup.tsx` — Agent reasoning display
- `InboxView.tsx` — Agent inbox with pinned task
- `ChatHeader.tsx` — Agent name, status, actions
- `MarkdownContent.tsx` — Markdown rendering for message content

**Activity** (`components/activity/`):
- `ActivityFeed.tsx` — Scrolling event feed
- `ActivityTimeline.tsx` — Timeline view of events
- `ActivityItem.tsx` / `ActivityTimelineItem.tsx` — Individual event rendering
- `ActivityFilters.tsx` — Filter by event type, agent
- `ThoughtStream.tsx` — Live agent reasoning stream
- `ToolCallDisplay.tsx` — Tool call visualization

**Explorer** (`components/explorer/`):
- `Explorer.tsx` — File system browser
- `FileTree.tsx` — Directory tree navigation
- `AgentTreeItem.tsx` — Agent in sidebar tree
- `JournalTree.tsx` — Journal entries browser
- `MemoryViewer.tsx` — MEMORY.md viewer

**Status** (`components/status/`):
- `HeartbeatIndicator.tsx` — Supervisor heartbeat visualization
- `ConnectionIndicator.tsx` — WebSocket connection status
- `StatusBar.tsx` — Bottom status bar
- `SystemHealth.tsx` — System health overview

**Other**:
- `BudgetPanel.tsx` — Per-agent token usage display
- `TasksPanel.tsx` — Task board
- `CommandCenter.tsx` — Command palette (Ctrl+K)
- `OnboardingModal.tsx` — First-run setup guide
- `RegisterProjectDialog.tsx` — Add new projects

### 9.4 Data Flow

```
Claude Code Hook → POST /api/agent-events → SQLite + WebSocket broadcast
                                                        │
                                                        ▼
                                            React useWebSocket hook
                                                        │
                                    ┌───────────────────┤
                                    ▼                   ▼
                              Zustand stores      React Query invalidation
                                    │                   │
                                    ▼                   ▼
                              Component re-render   API re-fetch
```

---

## 10. Safety Model

### 10.1 Isolation

- **tmux windows**: Each agent runs in a separate tmux window. Process crashes are contained.
- **Environment variables**: Agents inherit `CMUX_AGENT_NAME` which hooks use to apply role-specific policies.
- **Git worktrees**: Clone workers operate on separate branches in separate directories, preventing merge conflicts with the main codebase.
- **Port reservation**: Port 8000 is CMUX-reserved. Workers are warned in their context files (line 3-5 of every context file).

### 10.2 Mechanical Enforcement

Rather than relying on agents reading and following documentation, CMUX enforces critical rules via hooks:

| Rule | Enforcement | Without It |
|------|------------|------------|
| No interactive tools (AskUserQuestion, EnterPlanMode) | `block-interactive.sh` | Agent blocks forever, sentry kills eventually |
| Supervisor can't edit code | `block-supervisor-edits.sh` | Supervisor does work instead of delegating |
| Workers must persist before stopping | `stop-gate.sh` | Work gets lost silently |

### 10.3 Recovery Hierarchy

```
Level 0: Self-healing
  └─ Agent handles its own errors, retries, logs

Level 1: Heartbeat nudge
  └─ Monitor detects idle supervisor, sends autonomy scan results
  └─ Supervisor acts on highest-priority finding

Level 2: Task injection
  └─ After 3 failed nudges, monitor force-injects a backlog task

Level 3: Observation mode
  └─ For mid-task stuck supervisor, monitor hashes pane output
  └─ Progress resets timer; frozen output triggers escalation

Level 4: Sentry agent
  └─ Spawns Claude to try /compact, then kill+relaunch if needed
  └─ Writes enriched briefing for new supervisor

Level 5: Auto-rollback
  └─ Server health check fails 3 times → stash + git reset --hard
  └─ Tries last healthy commit, then progressively older commits
  └─ Rebuilds deps and frontend, restarts server
```

### 10.4 Data Durability

| Data | Storage | Survives Rollback? |
|------|---------|-------------------|
| Journal entries | Git-tracked `.cmux/journal/` | Yes (stashed, not deleted) |
| Agent registry | Git-tracked `.cmux/agent_registry.json` | Yes (stashed) |
| Messages | SQLite `.cmux/conversations.db` | Yes (stashed) |
| Tasks | SQLite `.cmux/tasks.db` | Yes (stashed) |
| Audit log | `.cmux/audit.log` | Yes (stashed) |
| Mailbox | `.cmux/mailbox` | Yes (stashed) |
| Worker contexts | `.cmux/worker-contexts/` | Yes (stashed) |
| MEMORY.md | Git-tracked (auto-memory) | Depends on Claude Code |

### 10.5 Token Budget Tracking

**Collection**: The `notify-complete.sh` hook extracts token usage from every Stop event and POSTs it as part of the event payload.

**Storage**: `agent_events` table in SQLite has a `usage` JSON column with `input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`.

**API**: `GET /api/budget/summary` returns per-agent totals. `GET /api/budget/<agent_id>` returns detailed breakdown.

**Frontend**: `BudgetPanel.tsx` displays token usage in the sidebar.

---

## Appendix A: File Index

### Orchestration
| File | Lines | Purpose |
|------|-------|---------|
| `src/orchestrator/cmux.sh` | 272 | CLI entry point (start/stop/status) |
| `src/orchestrator/monitor.sh` | 1447 | Control center, dashboard, heartbeat, sentry, recovery |
| `src/orchestrator/router.sh` | 419 | Mailbox polling, message delivery |
| `src/orchestrator/compact.sh` | 276 | Context compaction scheduler |

### Tools
| File | Lines | Purpose |
|------|-------|---------|
| `tools/workers` | 1031 | Worker lifecycle (spawn/kill/reset/clone/assign) |
| `tools/teams` | 999 | Team template setup + permanent team generation |
| `tools/mailbox` | — | Inter-agent messaging CLI |
| `tools/journal` | — | Journal entry CLI |
| `tools/backlog` | — | Persistent task queue |
| `tools/autonomy-check` | — | Work source scanner for heartbeat nudges |
| `tools/alert` | — | User notification (chime + voice) |
| `tools/auto-maintenance` | — | Stale worker cleanup |
| `tools/tasks` | — | Task CRUD for tasks.db |
| `tools/projects` | — | Multi-project registry |

### Backend
| File | Lines | Purpose |
|------|-------|---------|
| `src/server/main.py` | 99 | FastAPI app, CORS, route mounting, static files |
| `src/server/config.py` | 37 | Settings with CMUX_ env prefix |
| `src/server/services/mailbox.py` | 198 | Mailbox service (JSONL + SQLite) |
| `src/server/services/conversation_store.py` | 723 | SQLite store (messages, archives, events, thoughts, budget) |
| `src/server/websocket/manager.py` | 136 | WebSocket connection pool + broadcast |

### Hooks
| File | Event | Purpose |
|------|-------|---------|
| `block-interactive.sh` | PreToolUse | Block AskUserQuestion/EnterPlanMode |
| `block-supervisor-edits.sh` | PreToolUse | Block Edit/Write for supervisor |
| `stop-gate.sh` | Stop | Ensure work is committed/journaled |
| `notify-complete.sh` | Stop | POST response text to API |
| `notify-output.sh` | PostToolUse | POST tool calls to API |
| `stream-thought.sh` | PreToolUse | POST reasoning to thoughts API |
| `stream-result.sh` | PostToolUse | POST tool results to thoughts API |
| `audit-log.sh` | PostToolUse | Append to audit log |
| `pre-compact.sh` | Custom | Capture state before compaction |

### Frontend (13 stores)
| Store | Purpose |
|-------|---------|
| `agentStore.ts` | Agent list, selection |
| `agentEventStore.ts` | Tool call events |
| `activityStore.ts` | Activity feed |
| `connectionStore.ts` | WebSocket status |
| `sessionStore.ts` | tmux sessions |
| `layoutStore.ts` | Panel layout |
| `thoughtStore.ts` | Agent reasoning |
| `heartbeatStore.ts` | Heartbeat data |
| `projectStore.ts` | Projects |
| `taskStore.ts` | Tasks |
| `viewerStore.ts` | File viewer |
| `themeStore.ts` | Theme |
| `onboardingStore.ts` | First-run |

---

## Appendix B: API Routes

13 route groups under `/api/`:

| Prefix | Module | Key Endpoints |
|--------|--------|---------------|
| `/api/webhooks` | `webhooks.py` | `POST /{source}`, `GET /health` |
| `/api/agents` | `agents.py` | CRUD, `/ws` WebSocket, `/{id}/archive` |
| `/api/sessions` | `sessions.py` | Session management |
| `/api/messages` | `messages.py` | History, `POST /internal`, inbox |
| `/api/agent-events` | `agent_events.py` | Hook event receiver |
| `/api/journal` | `journal.py` | Daily journal CRUD and search |
| `/api/filesystem` | `filesystem.py` | File browser |
| `/api/thoughts` | `thoughts.py` | Agent reasoning stream |
| `/api/projects` | `projects.py` | Multi-project registry |
| `/api/tasks` | `tasks.py` | Task CRUD |
| `/api/heartbeat` | `heartbeat.py` | Heartbeat data receiver |
| `/api/prefs` | `prefs.py` | User preferences |
| `/api/budget` | `budget.py` | Token usage tracking |

---

*Report complete. All sections verified against source code as of commit `9a4c812` (2026-02-21).*
