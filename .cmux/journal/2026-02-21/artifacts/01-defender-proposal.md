# Permanent Worker Team — Defender Proposal

## Executive Summary

This proposal introduces **permanent workers** — long-lived specialist agents that persist across tasks, cannot be casually deleted, and receive work via task IDs from the supervisor. They coexist with ephemeral workers (which remain for ad-hoc/unusual tasks). The design builds on existing infrastructure (agent registry, task system, auto-maintenance, worker spawn/kill tooling) with minimal new code.

---

## 1. Permanent Roles

Based on the research analysis of 26 workers across 2 days, these four permanent roles cover ~85% of recurring work:

| Role Name | Window Name | Specialization | % of Historical Work |
|-----------|-------------|----------------|---------------------|
| **Frontend Specialist** | `perm-frontend` | UI rendering, component fixes, styling, Zustand state, CSS, React/TypeScript | 31% |
| **Backend Engineer** | `perm-backend` | FastAPI endpoints, SQLite schemas, service logic, Python | 27% (feature dev backend portion) |
| **Tester** | `perm-tester` | pytest, Chrome MCP browser testing, verification, regression testing | 8% (but required after EVERY impl) |
| **Infra/Tooling Engineer** | `perm-infra` | Orchestrator scripts, bash tooling, monitor/router/health scripts, system reliability | 12% |

### Why These Four

- **Frontend + Backend split over full-stack**: The research shows frontend work (31%) and backend work are distinct enough to specialize. A frontend specialist accumulates knowledge of the component tree, styling patterns, and Zustand stores. A backend specialist accumulates knowledge of FastAPI routes, service patterns, and DB schemas. Full-stack workers constantly context-switch.

- **Tester as permanent**: Testing is required after every implementation (per WORKER_ROLE.md). A permanent tester accumulates knowledge of the test suite, knows which tests are flaky, and builds expertise with Chrome MCP. Ephemeral testers waste tokens re-learning the test infrastructure every time.

- **Infra as permanent**: Orchestrator scripts are the most dangerous to modify (breaking them breaks the system). A permanent infra worker accumulates deep knowledge of health.sh, monitor.sh, router.sh, and the safety model.

### What Stays Ephemeral

- **Debate pairs** (defender/critic) — inherently one-shot
- **Research/investigation workers** — ad-hoc topics
- **Project-specific workers** — external project work (hero, heroweb)
- **Unusual one-off tasks** — anything that doesn't fit the four permanent roles

---

## 2. Task Assignment Protocol

### Current Flow (Ephemeral)

```
Supervisor writes context file → spawns worker → worker reads context → works → reports [DONE] → gets killed
```

### New Flow (Permanent)

```
Supervisor creates/finds task in tasks.db → assigns task to permanent worker →
sends task ID via mailbox → permanent worker reads task details → works →
reports [DONE] → waits for next task (NOT killed)
```

### Detailed Protocol

#### Step 1: Supervisor assigns task

```bash
# Option A: Task already exists in tasks.db
./tools/tasks assign t_a3f8k2m9 perm-frontend
./tools/tasks update t_a3f8k2m9 in-progress

# Option B: Create and assign in one step
./tools/tasks add "Fix button hover state in dashboard" \
  --assign perm-frontend \
  --priority high \
  --desc "The primary button loses hover styling when..."
```

#### Step 2: Supervisor notifies worker via mailbox

```bash
./tools/mailbox send perm-frontend "[TASK] t_a3f8k2m9" "Fix button hover state in dashboard. Read task details: ./tools/tasks show t_a3f8k2m9"
```

Or the shorthand (new tool addition — see Section 5):

```bash
./tools/workers assign perm-frontend t_a3f8k2m9
```

This combines: task assignment + status update + mailbox notification.

#### Step 3: Worker receives and processes

The permanent worker, already running in its tmux window, receives the mailbox message via the router. It:

1. Reads the task: `./tools/tasks show t_a3f8k2m9`
2. Works on it (same as any worker — journal, test, etc.)
3. Reports completion: `./tools/mailbox done "Fixed button hover state. Commit abc1234."`
4. Marks task done: `./tools/tasks done t_a3f8k2m9`
5. **Does NOT exit** — returns to idle, waiting for next task

#### Step 4: Worker idle behavior

When idle (no active task), permanent workers should:
- Respond to `[HEARTBEAT]` nudges with `[SYS] Idle. No active task.`
- NOT proactively seek work (that's the supervisor's job)
- Remain at the Claude Code prompt, ready for the next task

### Message Format Convention

All task assignments to permanent workers use this format:

```
[TASK] <task-id>: <one-line summary>
Details: ./tools/tasks show <task-id>
```

This is parseable, traceable (task ID links to history), and consistent.

---

## 3. Context Reset Mechanism

### The Problem

Over many tasks, a permanent worker's Claude Code context fills up. The system's existing `compact.sh` daemon handles periodic compaction, but eventually a full reset is needed — kill the Claude process and start fresh with the same identity.

### When to Reset

Context reset is triggered when:

1. **Compaction fails** — the compact daemon can't reduce context enough
2. **Worker reports confusion** — `[BLOCKED] Context too long, need reset`
3. **Supervisor detects staleness** — worker's responses become incoherent or slow
4. **Explicit request** — supervisor decides a clean slate is needed

### Reset Procedure

```bash
./tools/workers reset perm-frontend
```

This new command (see Section 5) performs:

1. **Preserve state**: Save a compaction artifact to `.cmux/journal/YYYY-MM-DD/artifacts/compaction-perm-frontend-*.json` with:
   - Current task (if any)
   - Files modified
   - Git branch/uncommitted changes
   - Last 50 lines of terminal output
2. **Archive conversation**: `POST /api/agents/perm-frontend/archive`
3. **Kill Claude process in the tmux window** (Ctrl+C, wait, then send new `claude --dangerously-skip-permissions`)
4. **Re-inject permanent context**: Send the permanent worker's role context file (see below)
5. **Inject recovery context**: Tell the worker to read its compaction artifact and resume
6. **Preserve the tmux window, registry entry, and agent_id** — identity survives reset

### What's Preserved Across Reset

| Preserved | Lost |
|-----------|------|
| tmux window name | Conversation history (archived) |
| agent_id (ag_xxx) | In-memory context |
| Registry entry | Claude process state |
| Role context file | |
| Journal entries | |
| Task history in tasks.db | |

### Permanent Worker Context Files

Each permanent worker gets a **persistent role context file** at:

```
.cmux/worker-contexts/perm-frontend-role.md
```

This file is version-controlled and contains:

- Worker identity (name, role, specialization)
- Domain-specific knowledge (e.g., frontend worker knows about the component tree, styling conventions)
- Standing instructions (e.g., "always run `npm run build` after changes")
- References to key files in their domain

On reset, this role file is re-injected first, followed by the recovery artifact. This ensures the worker "remembers" its specialization even after a full context wipe.

---

## 4. Permanent + Ephemeral Coexistence

### Naming Convention

| Type | Pattern | Examples |
|------|---------|----------|
| Permanent | `perm-<role>` | `perm-frontend`, `perm-backend`, `perm-tester`, `perm-infra` |
| Ephemeral | `<descriptive-name>` | `auth-fix`, `defender-meta`, `test-todo-ui` |
| Supervisor | `supervisor`, `sup-<project>` | `supervisor`, `sup-hero` |

The `perm-` prefix is the discriminator. All existing tooling (workers list, auto-maintenance, dashboard) can check for this prefix to determine worker type.

### Auto-Maintenance Changes

The current `auto-maintenance` script kills workers idle for 30+ minutes. Permanent workers must be exempt:

```bash
# In tools/auto-maintenance, add to is_protected():
is_protected() {
    local name="$1"
    [[ "$name" == "supervisor" ]] && return 0
    [[ "$name" == sup-* ]] && return 0
    [[ "$name" == "sentry" ]] && return 0
    [[ "$name" == "monitor" ]] && return 0
    [[ "$name" == perm-* ]] && return 0   # <-- NEW: protect permanent workers
    return 1
}
```

### Dashboard Display

The dashboard (and API) should distinguish permanent from ephemeral workers. The registry already has a `role` field — extend it:

```python
class AgentRole(str, Enum):
    WORKER = "worker"
    PERMANENT_WORKER = "permanent-worker"   # <-- NEW
    SUPERVISOR = "supervisor"
    PROJECT_SUPERVISOR = "project-supervisor"
```

### Priority / Queueing

- **Permanent workers get first pick** for tasks in their domain. If `perm-frontend` is idle, a frontend task goes to it — not to a new ephemeral worker.
- **If a permanent worker is busy**, the supervisor spawns an ephemeral worker for overflow.
- **Ephemeral workers are still preferred for**: one-off tasks outside permanent roles, tasks in external projects, debate pairs, research.

### Supervisor Decision Flow

```
New task arrives
  → Is it in a permanent role's domain?
    → Yes: Is that permanent worker idle?
      → Yes: Assign via task ID
      → No: Spawn ephemeral worker (or queue if low priority)
    → No: Spawn ephemeral worker
```

---

## 5. Tooling and Code Changes

### 5.1 `tools/workers` — New Commands

#### `workers spawn-permanent <name> <role-context-path>`

Creates a permanent worker with its role context. Different from regular spawn:
- Sets `role: "permanent-worker"` in registry
- Reads role context from a persistent file (not a one-shot task)
- Adds `"permanent": true` to registry entry

```bash
# Example:
workers spawn-permanent perm-frontend .cmux/worker-contexts/perm-frontend-role.md
```

Implementation: Add a `cmd_spawn_permanent()` function that:
1. Creates tmux window (same as regular spawn)
2. Registers with `"role": "permanent-worker", "permanent": true, "role_context": "<path>"`
3. Starts Claude
4. Sends: "Read <role-context-path> for your permanent role assignment."

#### `workers reset <name>`

Context reset for permanent workers (see Section 3). Only works on `perm-*` workers.

```bash
workers reset perm-frontend
```

#### `workers assign <name> <task-id>`

Shorthand for: assign task + update status + send mailbox notification.

```bash
workers assign perm-frontend t_a3f8k2m9
```

Implementation:
```bash
cmd_assign() {
    local name="$1" task_id="$2"
    ./tools/tasks assign "$task_id" "$name"
    ./tools/tasks update "$task_id" in-progress
    local title=$(sqlite3 "$DB" "SELECT title FROM tasks WHERE id='$task_id';")
    ./tools/mailbox send "$name" "[TASK] ${task_id}" "${title}. Read details: ./tools/tasks show ${task_id}"
}
```

#### `workers list` — Enhanced Output

Show permanent workers distinctly:

```
Workers in session 'cmux':

  ● supervisor (supervisor)
  ★ perm-frontend (permanent-worker) [idle]
  ★ perm-backend (permanent-worker) [working: t_a3f8k2m9]
  ★ perm-tester (permanent-worker) [idle]
  ★ perm-infra (permanent-worker) [idle]
  ● auth-fix
  ● debug-worker
```

### 5.2 Permanent Role Context Files

Create these files in `.cmux/worker-contexts/`:

**`.cmux/worker-contexts/perm-frontend-role.md`**
```markdown
# Permanent Worker: Frontend Specialist

You are perm-frontend, a permanent frontend specialist in the CMUX system.

## Your Domain
- React components in src/frontend/src/components/
- Zustand stores in src/frontend/src/stores/
- CSS/Tailwind styling
- TypeScript in the frontend
- Build system (Vite)

## Standing Instructions
- ALWAYS run `cd src/frontend && npm run build` after changes
- ALWAYS run `npm run typecheck` before reporting [DONE]
- Use Chrome MCP for visual verification
- Follow existing component patterns (check similar components first)

## Key Files
- src/frontend/src/App.tsx — main app layout
- src/frontend/src/stores/ — all Zustand stores
- src/frontend/src/components/ — component tree
- src/frontend/src/hooks/useWebSocket.ts — WebSocket connection

## How You Receive Work
- Tasks arrive via mailbox as: [TASK] <task-id>: <summary>
- Read full details: ./tools/tasks show <task-id>
- When done: ./tools/tasks done <task-id> && ./tools/mailbox done "<summary>"
- When idle: wait for next task (don't seek work proactively)
```

Similar files for `perm-backend-role.md`, `perm-tester-role.md`, `perm-infra-role.md`.

### 5.3 Agent Registry Schema Extension

Add these fields to registry entries for permanent workers:

```json
{
  "perm-frontend": {
    "registered_at": "2026-02-21T04:00:00Z",
    "type": "worker",
    "created_by": "tools/workers",
    "agent_id": "ag_pf000001",
    "display_name": "perm-frontend",
    "role": "permanent-worker",
    "project_id": "cmux",
    "permanent": true,
    "role_context": ".cmux/worker-contexts/perm-frontend-role.md",
    "reset_count": 0,
    "last_reset_at": null
  }
}
```

New fields:
- `permanent: true` — flag for permanent status
- `role_context` — path to persistent role file
- `reset_count` — how many times context has been reset
- `last_reset_at` — timestamp of last reset

### 5.4 Agent Model Extension

```python
class AgentRole(str, Enum):
    WORKER = "worker"
    PERMANENT_WORKER = "permanent-worker"
    SUPERVISOR = "supervisor"
    PROJECT_SUPERVISOR = "project-supervisor"
```

In `agent_manager.py`, the `_enrich_from_registry` method already reads `role` from the registry — no change needed there. The new role value flows through automatically.

### 5.5 Auto-Maintenance Update

In `tools/auto-maintenance`:

```bash
is_protected() {
    local name="$1"
    [[ "$name" == "supervisor" ]] && return 0
    [[ "$name" == sup-* ]] && return 0
    [[ "$name" == "sentry" ]] && return 0
    [[ "$name" == "monitor" ]] && return 0
    [[ "$name" == perm-* ]] && return 0   # Permanent workers
    return 1
}
```

### 5.6 Monitor / Heartbeat Integration

Permanent workers should be monitored like project supervisors — if their tmux window dies, it should be restarted:

In `monitor.sh`, add a `check_permanent_workers()` function:

```bash
check_permanent_workers() {
    local reg_file="${CMUX_PROJECT_ROOT}/.cmux/agent_registry.json"
    [[ -f "$reg_file" ]] || return 0

    local perm_workers
    perm_workers=$(jq -r 'to_entries[] | select(.value.permanent == true) | .key' "$reg_file" 2>/dev/null)

    while IFS= read -r worker_name; do
        [[ -z "$worker_name" ]] && continue
        if ! tmux_window_exists "$CMUX_SESSION" "$worker_name"; then
            printf "  %-16s ${YELLOW}●${NC} down — relaunching...\n" "$worker_name:"
            local role_ctx
            role_ctx=$(jq -r --arg k "$worker_name" '.[$k].role_context // empty' "$reg_file")
            if [[ -n "$role_ctx" ]]; then
                # Re-spawn with preserved identity
                workers spawn-permanent "$worker_name" "$role_ctx"
            fi
        else
            printf "  %-16s ${GREEN}●${NC} running\n" "$worker_name:"
        fi
    done <<< "$perm_workers"
}
```

---

## 6. Deletion Protection

### The Mechanism

Permanent workers cannot be deleted via `workers kill` without providing a reason. This prevents accidental cleanup and creates an audit trail.

#### `tools/workers kill` — Modified

```bash
cmd_kill() {
    local name="${1:-}"
    local reason="${2:-}"

    [[ -z "$name" ]] && die "usage: workers kill <name> [reason]"

    if is_supervisor "$name"; then
        die "cannot kill supervisor agents"
    fi

    # Check if permanent worker
    local reg_file="${CMUX_PROJECT_ROOT}/.cmux/agent_registry.json"
    local is_perm=false
    if [[ -f "$reg_file" ]]; then
        is_perm=$(jq -r --arg k "$name" '.[$k].permanent // false' "$reg_file" 2>/dev/null)
    fi

    if [[ "$is_perm" == "true" ]]; then
        if [[ -z "$reason" ]]; then
            die "Cannot kill permanent worker '$name' without a reason.\nUsage: workers kill $name \"<reason for deletion>\"\nUse 'workers reset $name' to reset context without killing."
        fi

        # Log the deletion reason
        local now
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        # Journal the deletion
        ./tools/journal decision "Permanent worker '$name' killed" "Reason: $reason"

        # Archive to deletion log
        local deletion_log="${CMUX_PROJECT_ROOT}/.cmux/permanent-worker-deletions.json"
        if [[ ! -f "$deletion_log" ]]; then
            echo '[]' > "$deletion_log"
        fi
        local tmp
        tmp=$(mktemp)
        jq --arg name "$name" --arg reason "$reason" --arg ts "$now" \
            '. + [{"worker": $name, "reason": $reason, "deleted_at": $ts}]' \
            "$deletion_log" > "$tmp" && mv "$tmp" "$deletion_log"

        warn "Killing permanent worker '$name'"
        warn "Reason: $reason"
    fi

    # ... rest of existing kill logic ...
}
```

#### Alternative: `workers retire <name> <reason>`

Instead of overloading `kill`, provide a dedicated command for permanent worker removal:

```bash
workers retire perm-frontend "Consolidating into full-stack role"
```

This is more explicit and prevents accidental `workers kill perm-frontend` (which would error without a reason). The `retire` command:

1. Requires a reason (mandatory argument)
2. Archives conversation
3. Saves a retirement record to `.cmux/permanent-worker-deletions.json`
4. Journals the decision
5. Removes the `permanent: true` flag from registry (demotes to regular worker)
6. Then kills the window

#### What "Reset vs Kill" Means in Practice

| Action | `workers reset perm-frontend` | `workers kill perm-frontend "reason"` |
|--------|------------------------------|--------------------------------------|
| tmux window | Preserved | Destroyed |
| Registry entry | Preserved | Removed |
| agent_id | Preserved | Lost |
| Claude process | Restarted | Terminated |
| Role context | Re-injected | N/A |
| Conversation | Archived + wiped | Archived |
| Requires reason | No | Yes |

---

## 7. Startup Sequence

When the system starts via `cmux.sh start`, permanent workers should be launched after the supervisor:

In `monitor.sh`, after `launch_supervisor` and `launch_project_supervisors`:

```bash
# Phase 2c: Launch permanent workers
launch_permanent_workers() {
    local reg_file="${CMUX_PROJECT_ROOT}/.cmux/agent_registry.json"
    [[ -f "$reg_file" ]] || return 0

    local perm_workers
    perm_workers=$(jq -r 'to_entries[] | select(.value.permanent == true) | [.key, .value.role_context] | @tsv' "$reg_file" 2>/dev/null)
    [[ -z "$perm_workers" ]] && return 0

    log_step "Launching permanent workers..."
    local count=0

    while IFS=$'\t' read -r name role_ctx; do
        [[ -z "$name" ]] && continue
        if tmux_window_exists "$CMUX_SESSION" "$name"; then
            log_ok "Permanent worker '$name' already running"
            continue
        fi
        workers spawn-permanent "$name" "$role_ctx"
        ((count++))
    done <<< "$perm_workers"

    if ((count > 0)); then
        log_ok "Started $count permanent worker(s)"
    fi
}
```

---

## 8. Implementation Priority

Ordered by impact and dependency:

1. **Registry + model changes** — Add `permanent`, `role_context`, `reset_count` fields; add `PERMANENT_WORKER` role
2. **Auto-maintenance protection** — Add `perm-*` to `is_protected()` (one line, prevents accidental kills)
3. **`workers spawn-permanent`** — New command for creating permanent workers
4. **Role context files** — Create the four `perm-*-role.md` files
5. **`workers assign`** — Shorthand for task assignment + mailbox notification
6. **`workers reset`** — Context reset without killing
7. **Deletion protection** — Modify `workers kill` to require reason for `perm-*`
8. **Monitor integration** — Auto-restart dead permanent workers
9. **Dashboard UI** — Visual distinction for permanent workers (star icon, different color)

---

## 9. Tradeoffs and Acknowledged Limitations

### Tradeoffs

- **4 roles may be too few or too many**: 4 covers ~85% of historical work. If a role is consistently idle, it wastes a tmux window + Claude process. If a role is consistently overloaded, the supervisor still needs to spawn ephemeral overflow.

- **`perm-` prefix is a naming convention, not a hard lock**: Any code that checks for permanent status should use the registry `permanent: true` flag, not just the name prefix. The prefix is for human convenience.

- **Context reset loses conversation history**: Even with compaction artifacts, some nuance is lost. This is an inherent limitation of the Claude Code model. The persistent role context file mitigates this by encoding the most important domain knowledge.

### Things I'm Less Certain About

- **Should the tester be permanent?** Testing is always post-implementation. A permanent tester sits idle most of the time. Counter-argument: the tester accumulates test suite knowledge that's valuable.

- **Should permanent workers auto-claim tasks from a queue?** I proposed supervisor-driven assignment. An alternative is permanent workers polling their own task queue. I lean toward supervisor-driven because it maintains the existing hierarchy, but the critic may have a better model.

---

## 10. Summary of Changes

| File/Component | Change |
|----------------|--------|
| `tools/workers` | Add `spawn-permanent`, `reset`, `assign` commands; modify `kill` for reason requirement |
| `tools/auto-maintenance` | Add `perm-*` to `is_protected()` |
| `src/server/models/agent.py` | Add `PERMANENT_WORKER` to `AgentRole` enum |
| `src/server/services/agent_registry.py` | Handle new fields (`permanent`, `role_context`, `reset_count`) |
| `src/orchestrator/monitor.sh` | Add `launch_permanent_workers()` and `check_permanent_workers()` |
| `.cmux/worker-contexts/perm-*-role.md` | Create 4 role context files (new) |
| `.cmux/permanent-worker-deletions.json` | Deletion audit log (new) |

Total estimated new code: ~200 lines in `tools/workers`, ~30 lines in `monitor.sh`, ~20 lines in `auto-maintenance`, ~4 role context files (~50 lines each), plus minor model changes.
