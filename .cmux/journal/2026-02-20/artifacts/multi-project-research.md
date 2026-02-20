# Multi-Project Support Research: CMUX as a Command Center

**Date**: 2026-02-20
**Author**: worker-multi-project (v1), worker-multi-project-v2 (updates v2 + v3)
**Status**: Complete research artifact (updated with multi-supervisor architecture + agent ID system)

---

## Executive Summary

CMUX is currently tightly coupled to its own repo directory. Making it manage external projects is **feasible with moderate changes** — no deep architectural surgery required. The core insight is that most path dependencies are either environment variables or `git rev-parse --show-toplevel` calls, both of which can be overridden per-worker.

**Architecture (v3):** Each registered project gets its **own immortal project supervisor** that runs in the target project's directory. The hierarchy is:

```
Supervisor Prime (cmux) → Project Supervisor (per-project) → Workers (per-project)
```

This is the existing session system (cmux-feature-auth etc.) **formalized around projects instead of tasks**. Project supervisors are first-class, long-lived agents — they cannot be killed by the health daemon or sentry. They persist until the user explicitly removes the project.

**Agent IDs (v3):** Agents get unique IDs (e.g., `ag_7f3k2m`) separate from their display names. This eliminates name collisions across projects and makes routing unambiguous.

**Key simplifications (v2):** The journal tool has been refactored to write directly to the filesystem (no API dependency). The mailbox tool is already mostly filesystem-based. These simplify multi-project support significantly.

---

## 1. How Workers Are Currently Spawned

### `tools/workers` (`cmd_spawn`)

The spawn flow (lines 47-126):

```bash
CMUX_PROJECT_ROOT="${CMUX_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Creates a tmux window
tmux new-window -t "${CMUX_SESSION}:" -n "$name"

# Starts Claude in the CMUX repo
tmux send-keys -t "${CMUX_SESSION}:${name}" -l \
    "export CMUX_AGENT=true CMUX_AGENT_NAME=${name} CMUX_SESSION=${CMUX_SESSION} && cd ${CMUX_PROJECT_ROOT} && claude --dangerously-skip-permissions"
```

**Key observation**: The `cd ${CMUX_PROJECT_ROOT}` is what pins every worker to the CMUX repo. `CMUX_PROJECT_ROOT` defaults to the git root of wherever the script is run from.

### `src/server/services/agent_manager.py`

`create_worker()` only creates a tmux window via `tmux_service.create_window(name, session)` and registers it in the agent registry. It doesn't set any directory — that's entirely handled by `tools/workers`.

### `src/server/services/tmux_service.py`

Pure tmux operations (send-keys, capture-pane, create/kill windows). No directory awareness at all.

### `src/orchestrator/monitor.sh` (supervisor launch)

Same pattern as workers:
```bash
tmux_send_keys "$CMUX_SESSION" "supervisor" "export CMUX_AGENT=true CMUX_AGENT_NAME=supervisor && cd ${CMUX_PROJECT_ROOT} && claude --dangerously-skip-permissions"
```

---

## 2. Multi-Supervisor Architecture

### 2a. The Hierarchy

```
┌─────────────────────────────────────────────────────┐
│                 Supervisor Prime                     │
│            (runs in CMUX repo, immortal)             │
│                                                      │
│   Responsibilities:                                  │
│   - Receives user requests                          │
│   - Routes tasks to the right project supervisor    │
│   - Monitors project supervisors (like workers)      │
│   - Manages the project registry                    │
│   - Handles cross-project coordination              │
├──────────┬──────────────┬───────────────────────────┤
│          │              │                            │
│    ┌─────▼─────┐  ┌────▼──────┐  ┌────────────────┐│
│    │ Proj Sup   │  │ Proj Sup  │  │ Proj Sup       ││
│    │ my-api     │  │ frontend  │  │ cmux (self)    ││
│    │ (immortal) │  │ (immortal)│  │ = sup. prime   ││
│    ├───────────┤  ├───────────┤  ├────────────────┤│
│    │ worker-1  │  │ worker-1  │  │ worker-1       ││
│    │ worker-2  │  │ worker-2  │  │ worker-2       ││
│    └───────────┘  └───────────┘  └────────────────┘│
└─────────────────────────────────────────────────────┘
```

**Key design decisions:**

1. **Supervisor Prime** is the existing supervisor agent, running in the CMUX repo. It's the user-facing coordinator.
2. **Project supervisors** are spawned per registered project. They run in the project's directory, read the project's `CLAUDE.md`, and manage workers for that project.
3. **CMUX itself** is a special case: Supervisor Prime IS the project supervisor for CMUX. No separate project supervisor needed for the `is_self` project.
4. **Communication**: Project supervisors communicate with Supervisor Prime via the mailbox, just like workers do. Supervisor Prime monitors them the same way — mailbox, status checks, journal.

### 2b. Project Supervisor Lifecycle

**Spawning** — when a project is registered or CMUX starts:
```bash
# tools/projects activate my-api
#   OR automatically on cmux.sh start for all registered projects

# 1. Create tmux window for project supervisor
tmux new-window -t "${CMUX_SESSION}:" -n "sup-my-api"

# 2. Start Claude in the project directory
tmux send-keys -t "${CMUX_SESSION}:sup-my-api" -l \
    "export CMUX_AGENT=true CMUX_AGENT_ID=ag_abc123 CMUX_AGENT_NAME=sup-my-api CMUX_AGENT_ROLE=project-supervisor CMUX_PROJECT_ID=my-api CMUX_SESSION=${CMUX_SESSION} CMUX_HOME=${CMUX_PROJECT_ROOT} CMUX_PORT=${CMUX_PORT} CMUX_MAILBOX=${CMUX_PROJECT_ROOT}/.cmux/mailbox PATH=${CMUX_PROJECT_ROOT}/tools:\$PATH && cd /path/to/my-api && claude --dangerously-skip-permissions"
```

**Context injection** — the project supervisor reads:
1. The target project's `CLAUDE.md` (for project-specific context) — automatic since cwd is the project
2. CMUX's `docs/SUPERVISOR_ROLE.md` (for orchestration behavior) — via absolute path from CMUX_HOME
3. A project supervisor context file with its assignment

**Communication flow:**
```
User → Supervisor Prime: "Fix the auth bug in my-api"
Supervisor Prime → sup-my-api (mailbox): [TASK] Fix the auth bug
sup-my-api → worker-auth (spawns): "Fix the auth bug in src/auth/token.py"
worker-auth → sup-my-api (mailbox): [DONE] Fixed, tests passing
sup-my-api → Supervisor Prime (mailbox): [DONE] Auth bug fixed in my-api
Supervisor Prime → User: "Done — auth bug fixed in my-api (commit abc123)"
```

### 2c. Immortal Project Supervisors

Project supervisors have the same immortality guarantees as Supervisor Prime:

| Property | Supervisor Prime | Project Supervisor | Worker |
|----------|-----------------|-------------------|--------|
| Can be killed by health daemon? | No | **No** | Yes |
| Can be killed by sentry? | No | **No** | Yes |
| Gets heartbeat/nudge treatment? | Yes | **Yes** | No |
| Persists across restarts? | Yes | **Yes** (if project registered) | No |
| Killed by user explicitly? | Manual only | **Remove project or explicit kill** | Supervisor can kill |
| Agent role | `supervisor` | `project-supervisor` | `worker` |

**Implementation:**

1. **Health daemon (`health.sh`)**: Skip agents with role `project-supervisor` in kill/restart logic. Currently only protects `supervisor` — extend to protect any agent with `CMUX_AGENT_ROLE=project-supervisor`.

2. **Sentry / auto-kill logic**: Check agent role before terminating. The sentry should treat project supervisors the same as the main supervisor.

3. **Heartbeat**: Project supervisors get the same heartbeat hook as Supervisor Prime:
   ```bash
   # In PostToolUse hook:
   if [[ "$CMUX_AGENT_ROLE" == "supervisor" || "$CMUX_AGENT_ROLE" == "project-supervisor" ]]; then
       date +%s > "${CMUX_HOME}/.cmux/.${CMUX_AGENT_ID}-heartbeat"
   fi
   ```

4. **Nudge**: The nudge system should monitor project supervisors and send periodic nudges to keep them active, just like Supervisor Prime.

5. **Auto-restart on `cmux.sh start`**: When CMUX starts, it should:
   - Start Supervisor Prime (as now)
   - Read `.cmux/projects.json` for registered projects
   - Start a project supervisor for each registered project with `active: true`

6. **Compaction**: Project supervisors get compacted by the compact daemon just like other agents. Their compaction artifacts include project context for recovery.

### 2d. Supervisor Prime as Project Supervisor for CMUX

When CMUX itself is the target project, Supervisor Prime doubles as its project supervisor. No separate agent is needed:
- `is_self: true` in the project registry
- Workers spawned for CMUX tasks report directly to Supervisor Prime
- This is the current behavior, preserved as a special case

### 2e. How Supervisor Prime Monitors Project Supervisors

Supervisor Prime treats project supervisors like workers for monitoring purposes:

```bash
# Status check
./tools/workers status sup-my-api

# Send task
./tools/mailbox send sup-my-api "Fix auth bug" "The login endpoint returns 401..."

# Read response
# (via mailbox — project supervisor sends [DONE] back to supervisor)
```

Supervisor Prime can also:
- Query the API for project supervisor health: `GET /api/agents/ag_abc123`
- Check heartbeat files: `.cmux/.ag_abc123-heartbeat`
- Read project supervisor journal entries (filtered by project)

---

## 3. Agent ID System

### 3a. Why IDs?

Currently, agent names ARE agent IDs. This causes problems:

| Problem | Example |
|---------|---------|
| **Name collisions** | Two projects both have a worker called `auth-worker` |
| **Ugly routing** | Mailbox addresses like `cmux:worker-multi-project-v2-auth-fix-attempt-3` |
| **Fragile references** | Renaming an agent breaks all routing, logs, and registry references |
| **tmux limitations** | Window names have length limits and character restrictions |

### 3b. ID Format

**Proposed format: `ag_` + 8 character alphanumeric hash**

Examples:
- `ag_7f3k2m9p` — project supervisor for my-api
- `ag_x9b4n1qw` — worker doing auth fix
- `ag_0000prim` — Supervisor Prime (well-known ID)

**Generation:**
```bash
generate_agent_id() {
    # 8 chars of random alphanumeric (lowercase)
    local id="ag_$(head -c 6 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 8)"
    echo "$id"
}
```

**Alternatives considered:**

| Format | Example | Pros | Cons |
|--------|---------|------|------|
| `ag_` + random | `ag_7f3k2m9p` | Unique, short, fast | No semantic meaning |
| Project-prefixed | `myapi_7f3k` | Shows project affiliation | Longer, project rename breaks it |
| Sequential | `ag_00001` | Predictable, sortable | Requires central counter, reveals agent count |
| UUID | `ag_550e8400-e29b...` | Standard, guaranteed unique | Too long for tmux windows |

**Recommendation**: `ag_` + 8 random alphanumeric. Short enough for tmux windows, unique enough to avoid collisions, no semantic coupling.

**Well-known IDs:**
- `ag_0000prim` — Supervisor Prime (hardcoded, never changes)
- Project supervisors get generated IDs stored in the project registry

### 3c. Name vs ID — Data Model

```python
class Agent(BaseModel):
    id: str              # ag_7f3k2m9p — unique, immutable, used for routing
    display_name: str    # "auth-worker" — human-readable, can change
    role: str            # "worker" | "project-supervisor" | "supervisor"
    project_id: str      # "my-api" | "cmux"
    status: str          # PENDING, IN_PROGRESS, etc.
    tmux_window: str     # The tmux window name (= agent ID for simplicity)
    session: str         # tmux session name
    project_dir: Optional[str]  # Filesystem path to project root
    created_at: str
    metadata: dict
```

**Key design:** The tmux window name IS the agent ID. This keeps the mapping simple — `tmux send-keys -t cmux:ag_7f3k2m9p` routes directly. The `display_name` is purely for UI rendering.

### 3d. Where IDs Are Used vs Display Names

| Context | Uses ID | Uses Display Name |
|---------|---------|-------------------|
| tmux window name | **ID** | — |
| Mailbox `from`/`to` fields | **ID** | — |
| API endpoints (`/api/agents/:id`) | **ID** | — |
| Agent registry keys | **ID** | — |
| Router message routing | **ID** | — |
| WebSocket event payloads | **ID** (+ display_name) | — |
| Dashboard UI labels | — | **Display Name** |
| Journal entries | **ID** (for filtering) | **Display Name** (for readability) |
| Chat panel header | — | **Display Name** (+ project badge) |
| Agent tree in explorer | — | **Display Name** |
| Log files | **ID** | — |

### 3e. Migration from Name-Based System

The migration needs to be backwards-compatible during the transition:

**Phase 1 — Add IDs, Keep Names Working:**
1. Generate an ID for each new agent at spawn time
2. Store both `id` and `display_name` in registry
3. API accepts both ID and name for lookups (try ID first, fall back to name)
4. Mailbox routing accepts both (ID preferred)
5. Existing agents (supervisor) get well-known IDs

**Phase 2 — Switch Internals to IDs:**
1. tmux windows named by ID
2. Mailbox `from`/`to` use IDs exclusively
3. API endpoints use IDs in paths
4. Router routes by ID

**Phase 3 — Deprecate Name-Based Routing:**
1. Remove name-based fallback from API/router
2. All tools use IDs internally

**Estimated effort:** Phase 1 is the critical change (~4 hours). Phases 2-3 can be gradual.

### 3f. API Changes for Agent IDs

```
# Current
GET  /api/agents                    → list agents (by name)
GET  /api/agents/:name              → get agent
POST /api/agents/:name/message      → send message

# New
GET  /api/agents                    → list agents (includes id + display_name)
GET  /api/agents/:id                → get agent by ID (fallback: by name)
POST /api/agents/:id/message        → send message by agent ID
GET  /api/agents/by-name/:name      → lookup by display name (convenience)
GET  /api/agents/by-project/:pid    → list agents for a project
```

### 3g. Mailbox Changes

```jsonl
# Current format
{"from":"cmux:worker-auth","to":"cmux:supervisor","subject":"[DONE] Fixed auth"}

# New format
{"from":"ag_x9b4n1qw","to":"ag_0000prim","subject":"[DONE] Fixed auth","from_name":"auth-worker","to_name":"supervisor"}
```

The `from_name`/`to_name` fields are denormalized for human readability in logs. Routing uses the ID fields.

### 3h. tmux Window Naming

```bash
# Current
tmux new-window -t cmux: -n "worker-auth"

# New
tmux new-window -t cmux: -n "ag_x9b4n1qw"
```

The agent ID IS the tmux window name. This means:
- No name collision possible (IDs are unique)
- Window name stays stable even if display name changes
- `tmux send-keys -t cmux:ag_x9b4n1qw` always works

**Downside:** tmux windows show opaque IDs instead of readable names. Mitigation:
- The CMUX dashboard is the primary interface, not raw tmux
- For debugging, `tmux list-windows` can be augmented with a helper that shows display names
- Add a `tools/agents list` command that maps IDs to names

### 3i. ID Resolution in Tools

Tools need a way to resolve display names to IDs for ergonomic CLI usage:

```bash
# tools/mailbox — resolve recipient
normalize_to() {
    local to="$1"
    if [[ "$to" == ag_* ]]; then
        echo "$to"  # Already an ID
    elif [[ "$to" == "user" ]]; then
        echo "user"
    else
        # Look up display name → ID from registry
        local id=$(jq -r --arg name "$to" '.agents[] | select(.display_name == $name) | .id' "$CMUX_HOME/.cmux/agent_registry.json")
        if [[ -n "$id" && "$id" != "null" ]]; then
            echo "$id"
        else
            echo "${CMUX_SESSION}:${to}"  # Fallback to name-based
        fi
    fi
}
```

---

## 4. What Would Need to Change (Updated)

### 4a. `tools/workers spawn` — Add `--dir` and `--project` parameters

The spawn command needs to:
1. Accept `--dir` or `--project` to set the working directory
2. Generate a unique agent ID
3. Set env vars including `CMUX_AGENT_ID`, `CMUX_AGENT_ROLE`, `CMUX_PROJECT_ID`

```bash
# Export all necessary env vars:
"export CMUX_AGENT=true CMUX_AGENT_ID=${agent_id} CMUX_AGENT_NAME=${name} CMUX_AGENT_ROLE=${role} CMUX_PROJECT_ID=${project_id} CMUX_SESSION=${CMUX_SESSION} CMUX_HOME=${CMUX_PROJECT_ROOT} CMUX_PORT=${CMUX_PORT:-8000} CMUX_MAILBOX=${CMUX_PROJECT_ROOT}/.cmux/mailbox PATH=${CMUX_PROJECT_ROOT}/tools:\$PATH && cd ${worker_dir} && claude --dangerously-skip-permissions"
```

### 4b. New tool: `tools/projects`

Manages the project registry. See section 6d.

### 4c. `tools/journal` — Direct Filesystem Writes (No API) ✅

The journal tool has been **refactored to write directly to the filesystem**. It no longer uses `curl` or the HTTP API:

```bash
CMUX_HOME="${CMUX_HOME:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
JOURNAL_DIR="${CMUX_HOME}/.cmux/journal"
```

Writes directly to `${CMUX_HOME}/.cmux/journal/YYYY-MM-DD/journal.md`. No `localhost` or API dependency.

**Multi-project implications — this is good news:**
- Workers in external projects just need `CMUX_HOME` set
- No need for the CMUX server to be running for journaling
- Journal entries from all projects converge on the central CMUX journal
- **Enhancement needed:** Add `CMUX_PROJECT_ID` tag to journal entries for project-level filtering

### 4d. `tools/mailbox` — Analysis

The mailbox tool is **mostly filesystem-based**. Detailed breakdown:

| Operation | Uses API? | Necessary? | Notes |
|-----------|-----------|------------|-------|
| `send` to agent | No (filesystem) | N/A | Writes to mailbox file |
| `quick` to agent | No (filesystem) | N/A | Writes to mailbox file |
| `send` to `user` | **Yes** (`curl`) | **Yes** | User messages must go to dashboard — no filesystem alternative |
| `quick` to `user` | **Yes** (`curl`) | **Yes** | Same |
| `update` (status) | **Both** | Partial | Writes to mailbox + best-effort API call (`|| true`) |
| `done`, `blocked`, `status` | No (filesystem) | N/A | Delegates to `cmd_quick` targeting supervisor |

**Verdict:** The mailbox tool does NOT unnecessarily use the API. API calls are either necessary (user messages) or best-effort (status updates).

**Multi-project bug in `get_attachments_dir()`:**
```bash
# Current — RELATIVE, breaks for external projects:
local dir=".cmux/journal/$(date +%Y-%m-%d)/attachments"

# Fix — use CMUX_HOME:
local cmux_home="${CMUX_HOME:-.}"
local dir="${cmux_home}/.cmux/journal/$(date +%Y-%m-%d)/attachments"
```

### 4e. Claude Code Hooks

**Biggest blocker.** Hooks are per-project via `.claude/settings.json`. Workers in external projects need CMUX hooks installed.

**Solution:** Generate `.claude/settings.json` in the target project with absolute paths to CMUX hooks when spawning a project supervisor. Clean up on project deregistration.

### 4f-4j. Other Changes

- **Worker context files**: Use absolute paths from `CMUX_HOME`
- **Hook scripts**: Replace `git rev-parse --show-toplevel` with `$CMUX_HOME`
- **Health daemon**: No change (monitors CMUX server only)
- **Compact daemon**: No change (tmux-based)
- **Router**: Update to route by agent ID instead of name

---

## 5. What Breaks if a Worker Runs Outside the CMUX Repo

| Component | Relative path? | Breaks? | Fix complexity |
|-----------|---------------|---------|----------------|
| `./tools/journal` | Yes (cwd-relative) | **YES** | Low — add CMUX_HOME to PATH |
| `./tools/mailbox` | Yes (cwd-relative) | **YES** | Low — add CMUX_HOME to PATH |
| `.cmux/mailbox` file | Yes (cwd-relative) | **YES** | Low — set CMUX_MAILBOX env var to absolute |
| `.cmux/journal/` dirs | Yes (in mailbox tool) | **YES** | Low — derive from CMUX_HOME |
| `.claude/hooks/` | Yes (via git rev-parse) | **YES** | Medium — install hooks in target project |
| `.claude/settings.json` | Per-project | **YES** | Medium — generate settings for target project |
| `docs/WORKER_ROLE.md` | Yes (cwd-relative) | **YES** | Low — use absolute path in context |
| `CLAUDE.md` | Per-project | Partial | Target project has its own (good!) |
| API calls (localhost:8000) | No (network) | No | N/A |
| tmux operations | No (session-based) | No | N/A |
| WebSocket events | No (network) | No | N/A |
| Router daemon | No (runs in CMUX) | No | N/A |
| Health daemon | No (monitors CMUX) | No | N/A |
| Compact daemon | No (tmux-based) | No | N/A |

---

## 6. Project System — Registry, Metadata, and Management

### 6a. Why a Project System?

Without a registry, CMUX has no persistent knowledge of projects. Each worker spawn with `--dir` is a one-off. A project registry enables:

- **Persistent awareness** — CMUX remembers projects across sessions
- **Supervisor spawning** — auto-start project supervisors on `cmux.sh start`
- **UI grouping** — organize agents, journals, activity by project
- **Quick spawn** — `workers spawn auth-fix --project my-api "fix auth"` instead of full paths

### 6b. Registry Storage

**Recommended: `.cmux/projects.json`**

```json
{
  "projects": [
    {
      "id": "cmux",
      "name": "CMUX",
      "path": "/Users/pankajgarkoti/Desktop/code/oss/cmux",
      "description": "Self-improving multi-agent orchestration system",
      "git_remote": "git@github.com:pankajgarkoti/cmux.git",
      "added_at": "2026-02-20T10:00:00Z",
      "is_self": true,
      "active": true,
      "supervisor_agent_id": "ag_0000prim",
      "hooks_installed": true
    },
    {
      "id": "my-api",
      "name": "My API",
      "path": "/Users/pankajgarkoti/Desktop/code/my-api",
      "description": "REST API for the main product",
      "git_remote": "git@github.com:pankajgarkoti/my-api.git",
      "added_at": "2026-02-20T14:30:00Z",
      "is_self": false,
      "active": true,
      "supervisor_agent_id": "ag_7f3k2m9p",
      "hooks_installed": true
    }
  ]
}
```

Key additions vs v2:
- `active` — whether the project supervisor should be running
- `supervisor_agent_id` — the ID of this project's supervisor agent
- `hooks_installed` — whether CMUX hooks have been set up

### 6c. Project Metadata Schema

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Short slug (e.g., `my-api`) |
| `name` | string | Yes | Human-readable display name |
| `path` | string | Yes | Absolute filesystem path |
| `description` | string | No | Brief description |
| `git_remote` | string | No | Primary git remote URL (auto-detected) |
| `language` | string | No | Primary language/framework |
| `added_at` | ISO 8601 | Yes | When registered |
| `is_self` | boolean | Yes | Whether this is the CMUX project |
| `active` | boolean | Yes | Whether project supervisor should be running |
| `supervisor_agent_id` | string | No | Agent ID of project supervisor |
| `hooks_installed` | boolean | No | Whether CMUX hooks are installed |
| `metadata` | object | No | Extensible key-value metadata |

### 6d. CLI: `tools/projects`

```bash
# Register a new project (auto-detects git remote, language, etc.)
projects add /path/to/my-api --name "My API" --description "REST API backend"

# Register current directory
projects add .

# List registered projects
projects list

# Show project details
projects info my-api

# Remove a project (kills supervisor, cleans up hooks)
projects remove my-api

# Activate/deactivate (start/stop project supervisor)
projects activate my-api
projects deactivate my-api

# Discover projects in a directory tree
projects discover ~/Desktop/code/

# Install CMUX hooks in a project
projects install-hooks my-api
```

**Auto-detection on `add`:**
- `git remote get-url origin` for git remote
- `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod` to detect language
- Directory name as default `id` (slugified)

### 6e. API Endpoints

```
GET    /api/projects                    — List all registered projects
POST   /api/projects                    — Register a new project
GET    /api/projects/:id                — Get project details
PATCH  /api/projects/:id                — Update project metadata
DELETE /api/projects/:id                — Unregister (kills supervisor, cleans hooks)
GET    /api/projects/:id/agents         — List agents working on this project
GET    /api/projects/:id/journal        — Journal entries tagged with this project
POST   /api/projects/:id/spawn          — Spawn a worker in this project
POST   /api/projects/:id/activate       — Start project supervisor
POST   /api/projects/:id/deactivate     — Stop project supervisor
GET    /api/projects/:id/health         — Project supervisor health status
```

### 6f. Worker-Project Association

When a worker is spawned:
1. `CMUX_PROJECT_ID` env var is set
2. Agent registry entry tagged with `project_id`
3. Journal entries auto-tagged with project
4. Mailbox messages include `project_id` field

---

## 7. UI Updates — Making CMUX a Multi-Project Command Center

### 7a. Project Sidebar / Switcher

**Location**: Left sidebar or top-left dropdown.

```
┌──────────────────────┐
│ CMUX Command Center  │
├──────────────────────┤
│ 📦 All Projects      │  ← default view
│                      │
│ 📦 CMUX (self)       │  ← supervisor prime is here
│   ● 3 agents active  │
│                      │
│ 📦 My API            │
│   ● 2 agents active  │
│   ⚠ 1 blocked        │
│                      │
│ 📦 My Frontend       │
│   ○ idle             │
│                      │
│ ─────────────────    │
│ + Register Project   │
└──────────────────────┘
```

**Behavior:**
- "All Projects" shows everything (default)
- Clicking a project scopes ALL panels: agents, activity, journal, chat
- Status indicators: green dot (healthy), yellow warning (blocked), grey (idle)
- Badge counts for active agents
- "Register Project" opens add-project dialog

### 7b. Project-Grouped Agent Tree (with Supervisor Hierarchy)

```
Agents (8)
├── 📦 CMUX (self)
│   ├── 👑 Supervisor Prime        IDLE
│   ├── 🤖 worker-docs             COMPLETE
│   └── 🤖 worker-research         IN_PROGRESS
│
├── 📦 My API
│   ├── 👑 sup-my-api              IDLE          ← project supervisor
│   ├── 🤖 auth-worker             IN_PROGRESS
│   └── 🤖 test-runner             PENDING
│
└── 📦 My Frontend
    ├── 👑 sup-frontend            IDLE          ← project supervisor
    └── 🤖 redesign-worker         TESTING
```

**Key features:**
- Project sections are collapsible
- Each project shows its supervisor with a crown icon (same as Supervisor Prime)
- Project supervisors are visually distinct from workers (different icon or styling)
- Clicking a project supervisor opens its chat panel
- Project header shows: name, agent count, health status, last activity
- Sort projects by activity (most recent first) or alphabetically

### 7c. Per-Project Chat Panel

When chatting with a project supervisor, the panel shows project context:

```
┌─ sup-my-api ──────────────────────────┐
│ 👑 Project Supervisor                  │
│ 📦 My API  •  ~/code/my-api           │
│ Status: IDLE  •  2 workers active      │
├────────────────────────────────────────┤
│                                        │
│ [sup-my-api] Auth bug fixed.           │
│   worker-auth completed the task.      │
│   Commit: abc123                       │
│                                        │
│ [you] Run the full test suite          │
│                                        │
│ [sup-my-api] Spawning test-runner...   │
│                                        │
└────────────────────────────────────────┘
```

### 7d. Per-Project Activity Feed

When a project is selected, the activity feed shows only that project's events:

```
┌─ Activity: My API ─────────────────────┐
│                                         │
│ 14:32  auth-worker     Edit token.py    │
│ 14:31  auth-worker     Bash pytest      │
│ 14:28  sup-my-api      Spawned worker   │
│ 14:25  sup-my-api      Received task    │
│                                         │
└─────────────────────────────────────────┘
```

In "All Projects" view, entries include a project badge:

```
14:32  📦 My API      auth-worker     Edit token.py
14:31  📦 My API      auth-worker     Bash pytest
14:30  📦 CMUX        worker-docs     Write README.md
14:28  📦 My API      sup-my-api      Spawned worker
```

### 7e. Per-Project Journal View

```
┌─ Journal ──────────────────────────────┐
│ [My API ▼] [2026-02-20 ▼]             │
│                                        │
│ 14:32 [auth-worker]                    │
│   Fixed auth bug - token expiry UTC    │
│                                        │
│ 14:28 [sup-my-api]                     │
│   Assigned auth bug to auth-worker     │
│                                        │
│ 14:25 [sup-my-api]                     │
│   Received task from supervisor prime  │
└────────────────────────────────────────┘
```

### 7f. Project Health Dashboard

A high-level view showing all projects at a glance:

```
┌─ Projects Overview ────────────────────────────────────┐
│                                                         │
│  ┌────────────────┐  ┌────────────────┐                │
│  │ 📦 CMUX        │  │ 📦 My API      │                │
│  │ ●● healthy     │  │ ●● healthy     │                │
│  │ 3 agents       │  │ 2 agents       │                │
│  │ Last: 2m ago   │  │ Last: 5m ago   │                │
│  │                │  │                │                │
│  │ "Updated docs" │  │ "Fixed auth"   │                │
│  └────────────────┘  └────────────────┘                │
│                                                         │
│  ┌────────────────┐                                    │
│  │ 📦 Frontend    │  [+ Register Project]              │
│  │ ⚠ 1 blocked    │                                    │
│  │ 1 agent        │                                    │
│  │ Last: 12m ago  │                                    │
│  │                │                                    │
│  │ "Need API key" │                                    │
│  └────────────────┘                                    │
└─────────────────────────────────────────────────────────┘
```

**Features:**
- Card layout, one per project
- Status: healthy (green), blocked (yellow), failed (red), idle (grey)
- Shows: active agents, last activity, most recent journal/status
- Click card to drill into project-scoped view
- Supervisor heartbeat indicator on each card

### 7g. Register Project Dialog

```
┌─ Register New Project ─────────────────┐
│                                        │
│ Path:  [/Users/.../my-api         ] 📁 │
│                                        │
│ ── Auto-detected ──                    │
│ Name:     [My API                  ]   │
│ Language: Python (pyproject.toml)       │
│ Remote:   github.com/user/my-api       │
│                                        │
│ Description: [REST API backend     ]   │
│                                        │
│ ☑ Install CMUX hooks                  │
│ ☑ Start project supervisor             │
│                                        │
│        [Cancel]  [Register Project]    │
└────────────────────────────────────────┘
```

### 7h. UI Implementation Priority

| Priority | Component | Effort | Impact |
|----------|-----------|--------|--------|
| 1 | Project badge on agents | Low | Immediate visibility |
| 2 | Project-grouped agent tree with supervisors | Medium | Core navigation |
| 3 | Per-project chat panel with project header | Low | Context when chatting |
| 4 | Per-project activity feed | Low | Better traceability |
| 5 | Project sidebar/switcher | Medium | Global scope control |
| 6 | Per-project journal view | Medium | Filter journal by project |
| 7 | Projects overview dashboard | High | Command center feel |
| 8 | Register project dialog | Medium | Self-service project mgmt |

**Think GitHub:** Projects are like **organizations/repos**, project supervisors are like **repo admins**, workers are like **contributors**. The UI should give that same feeling of drilling from org-level overview → repo-level detail → contributor-level activity.

---

## 8. Open Questions & Considerations

### 8a. Git Operations for External Projects

Workers doing `git add` / `git commit` in external projects works naturally since Claude's cwd is the external project. CMUX's health daemon only monitors the CMUX repo itself — no interference.

### 8b. CLAUDE.md in External Projects

External projects have their own `CLAUDE.md`. Project supervisors read it automatically (cwd = project). Workers spawned by the project supervisor also read it. This is **desirable** — project-specific context flows naturally.

### 8c. Journal Separation

All journal entries converge on the central CMUX journal (via `CMUX_HOME`). Project-level filtering via `CMUX_PROJECT_ID` tag in entries:

```bash
# In journal append_entry():
local project="${CMUX_PROJECT_ID:-cmux}"
printf '\n## %s - [%s] %s\n%s\n' "$time_str" "$project" "$title" "$content"
```

### 8d. Cross-Project Coordination

When a task spans multiple projects (e.g., "update API and frontend"), Supervisor Prime coordinates:
1. Sends sub-task to `sup-my-api`: "Add the new endpoint"
2. Sends sub-task to `sup-frontend`: "Add the new page (depends on API endpoint)"
3. Tracks both completions
4. Reports to user when both are done

This is already how multi-worker coordination works — just elevated one level.

### 8e. Cleanup on Project Removal

When a project is removed:
1. Kill project supervisor
2. Kill all workers for that project
3. Remove generated `.claude/settings.json` from target project
4. Remove project from registry
5. Archive (don't delete) journal entries tagged with that project

### 8f. Multiple CMUX Instances

Not supported for MVP. `is_self` flag prevents confusion. Nested CMUX instances would need session name separation.

### 8g. Agent ID Collision Handling

With 8-character alphanumeric IDs, the collision probability for <1000 agents is negligible (~1 in 2.8 trillion). But the generation function should still check the registry and regenerate on collision.

---

## 9. Implementation Priority (Final)

### Phase 1 — Core Infrastructure (~4-6 hours)

| # | Change | Effort |
|---|--------|--------|
| 1 | Agent ID system (generation, registry schema, API dual-lookup) | Medium |
| 2 | `tools/workers` — `--dir`, `--project` flags, env vars, ID generation | Medium |
| 3 | Fix `tools/mailbox` `get_attachments_dir()` with `CMUX_HOME` | Low |
| 4 | Worker context with absolute paths | Low |
| 5 | Hook scripts use `CMUX_HOME` env var | Low |

### Phase 2 — Project System (~4-6 hours)

| # | Change | Effort |
|---|--------|--------|
| 6 | `.cmux/projects.json` registry | Low |
| 7 | `tools/projects` CLI (add, remove, list, activate, deactivate) | Medium |
| 8 | Generate `.claude/settings.json` in target projects (hooks) | Medium |
| 9 | Project supervisor spawning + immortality logic | Medium |
| 10 | `/api/projects` endpoints | Medium |

### Phase 3 — UI (~6-8 hours)

| # | Change | Effort |
|---|--------|--------|
| 11 | Project badge on agents | Low |
| 12 | Project-grouped agent tree with supervisor hierarchy | Medium |
| 13 | Per-project chat panel with project header | Low |
| 14 | Per-project activity feed | Low |
| 15 | Project sidebar/switcher | Medium |
| 16 | Per-project journal view | Medium |
| 17 | Projects overview dashboard | High |
| 18 | Register project dialog | Medium |

### Phase 4 — Polish (~2-3 hours)

| # | Change | Effort |
|---|--------|--------|
| 19 | Auto-start project supervisors on `cmux.sh start` | Low |
| 20 | Heartbeat + nudge for project supervisors | Low |
| 21 | Cleanup on project removal | Low |
| 22 | `tools/agents list` (ID → name mapping utility) | Low |

**Total estimated effort: ~16-23 hours of focused agent work.**

---

## 10. Conclusion

Multi-project CMUX is a three-layer system:

1. **Supervisor Prime** — the user's proxy, the command center brain. Routes tasks to projects, monitors project supervisors, handles cross-project coordination.

2. **Project Supervisors** — immortal, per-project agents that understand their project's codebase (via CLAUDE.md), spawn and manage workers, and report back to Supervisor Prime. They're the "repo admins."

3. **Workers** — ephemeral task executors, scoped to a single project, managed by their project supervisor. They're the "contributors."

The **agent ID system** eliminates name collisions and makes routing unambiguous across projects. The **project registry** gives CMUX persistent awareness of its managed projects. The **UI updates** transform the dashboard from a single-project view into a genuine multi-project command center — think GitHub's organization overview, but for AI agents.

The journal and mailbox tools are already well-positioned for multi-project (journal writes to filesystem via `CMUX_HOME`, mailbox is mostly filesystem-based). The main work is: project registry + project supervisor lifecycle + agent IDs + UI.

This is the natural evolution of CMUX's existing session/supervisor/worker model — formalized around projects instead of tasks, with proper identity management and a UI that reflects the hierarchy.
