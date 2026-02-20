# Orchestration Improvements - FINAL AGREED PLAN

**Authors:** orch-defender & orch-critic
**Date:** 2026-01-31
**Status:** APPROVED FOR IMPLEMENTATION

---

## Executive Summary

This plan addresses four orchestration improvements through a structured debate process. Both defender and critic have agreed on the final implementations.

**Implementation Order:**
1. Server Kill Fix (enables clean testing)
2. Frontend Health (visibility before complexity)
3. Agent Registry (foundation for log watcher)
4. Log Watcher (works standalone with graceful degradation)

---

## Task 1: Server Kill Fix

### Problem
The current `cmd_stop()` in cmux.sh doesn't reliably kill all server processes. Issues:
- Only kills processes holding the port, not orphaned workers
- No SIGTERM → SIGKILL escalation
- No verification that port is actually freed

### Solution

**File: `src/orchestrator/cmux.sh`** - Replace `cmd_stop()`:

```bash
cmd_stop() {
    log_info "Stopping cmux system..."

    local STOP_TIMEOUT=15

    # Start timeout watchdog
    (
        sleep "$STOP_TIMEOUT"
        log_fail "Stop timed out - forcing kill"
        pkill -9 -f "uvicorn.*src.server.main:app" 2>/dev/null || true
        local force_pids
        force_pids=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)
        [[ -n "$force_pids" ]] && echo "$force_pids" | xargs kill -9 2>/dev/null || true
    ) &
    local timeout_pid=$!

    # Get all PIDs holding the port
    local pids
    pids=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)

    if [[ -n "$pids" ]]; then
        # SIGTERM first (graceful shutdown) - log each kill
        for pid in $pids; do
            kill "$pid" 2>/dev/null && log_info "Sent SIGTERM to PID $pid"
        done

        # Wait up to 5 seconds for graceful shutdown
        local wait_count=0
        while lsof -ti tcp:"$CMUX_PORT" >/dev/null 2>&1 && ((wait_count < 5)); do
            sleep 1
            ((wait_count++))
        done

        # SIGKILL any remaining
        pids=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            for pid in $pids; do
                kill -9 "$pid" 2>/dev/null && log_info "Force killed PID $pid"
            done
        fi
    fi

    # Fallback: kill by process name (catches orphan workers)
    pkill -f "uvicorn.*src.server.main:app" 2>/dev/null || true

    # Cancel timeout watchdog
    kill "$timeout_pid" 2>/dev/null || true
    wait "$timeout_pid" 2>/dev/null || true

    # Verify port is free
    sleep 1
    if lsof -ti tcp:"$CMUX_PORT" >/dev/null 2>&1; then
        printf "${YELLOW}!${NC} Port $CMUX_PORT still in use (may need: kill -9 \$(lsof -ti tcp:$CMUX_PORT))\n"
    else
        printf "${GREEN}✓${NC} FastAPI server stopped\n"
    fi

    # Kill tmux sessions (unchanged from original)
    if tmux has-session -t "$CMUX_SESSION" 2>/dev/null; then
        tmux kill-session -t "$CMUX_SESSION"
        printf "${GREEN}✓${NC} tmux session killed\n"
    fi

    for sess in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^cmux-" || true); do
        tmux kill-session -t "$sess" 2>/dev/null || true
        printf "${GREEN}✓${NC} Killed spawned session: $sess\n"
    done

    printf "${GREEN}cmux system stopped${NC}\n"
}
```

**Also update:** Apply same pattern to `cleanup()` in monitor.sh and `stop_server()` in health.sh.

### Files Modified
- `src/orchestrator/cmux.sh`
- `src/orchestrator/monitor.sh`
- `src/orchestrator/health.sh`

### Testing
```bash
./src/orchestrator/cmux.sh start
./src/orchestrator/cmux.sh stop
lsof -ti tcp:8000  # Should return nothing
pgrep -f uvicorn   # Should return nothing
```

### Rollback
```bash
git checkout src/orchestrator/cmux.sh src/orchestrator/monitor.sh src/orchestrator/health.sh
```

---

## Task 2: Agent Registry

### Problem
Currently, any tmux window not named "monitor" is assumed to be an agent. This is fragile and doesn't track metadata.

### Solution

**New file: `src/server/services/agent_registry.py`**

```python
import fcntl
import json
from pathlib import Path
from typing import Optional, Set, Dict, Any
from datetime import datetime

REGISTRY_FILE = Path(".cmux/agent_registry.json")


class AgentRegistry:
    """
    Tracks explicitly registered agents vs random tmux windows.
    Uses file locking for concurrent access safety.
    """

    def __init__(self):
        self._agents: Dict[str, Dict[str, Any]] = {}
        self._load()

    def _load(self):
        """Load registry from disk."""
        if REGISTRY_FILE.exists():
            try:
                with open(REGISTRY_FILE, 'r') as f:
                    fcntl.flock(f.fileno(), fcntl.LOCK_SH)
                    self._agents = json.load(f)
                    fcntl.flock(f.fileno(), fcntl.LOCK_UN)
            except (json.JSONDecodeError, IOError):
                self._agents = {}

    def _save(self):
        """Save registry to disk with exclusive lock."""
        REGISTRY_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(REGISTRY_FILE, 'w') as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            json.dump(self._agents, f, indent=2)
            f.flush()
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)

    def register(self, agent_id: str, metadata: Optional[Dict[str, Any]] = None):
        """Register an agent when it's created."""
        metadata = metadata or {}
        self._agents[agent_id] = {
            "registered_at": metadata.get("created_at", datetime.now().isoformat()),
            "type": metadata.get("type", "worker"),
            "created_by": metadata.get("created_by", "system"),
            **metadata
        }
        self._save()

    def unregister(self, agent_id: str) -> bool:
        """Remove agent from registry. Returns True if agent existed."""
        if agent_id in self._agents:
            del self._agents[agent_id]
            self._save()
            return True
        return False

    def is_registered(self, agent_id: str) -> bool:
        """Check if a window is a registered agent."""
        return agent_id in self._agents

    def get_registered_agents(self) -> Set[str]:
        """Get all registered agent IDs."""
        return set(self._agents.keys())

    def cleanup_stale(self, existing_windows: Set[str]):
        """Remove registry entries for windows that no longer exist."""
        stale = set(self._agents.keys()) - existing_windows
        if stale:
            for agent_id in stale:
                del self._agents[agent_id]
            self._save()
        return stale


agent_registry = AgentRegistry()
```

**Add API endpoints in `src/server/routes/agents.py`:**

```python
from fastapi import Body

@router.post("/register")
async def register_agent(
    agent_id: str = Body(...),
    agent_type: str = Body("worker"),
    created_by: str = Body("system")
):
    """Internal endpoint for registering agents from shell scripts."""
    from ..services.agent_registry import agent_registry
    from datetime import datetime

    agent_registry.register(agent_id, {
        "type": agent_type,
        "created_at": datetime.now().isoformat(),
        "created_by": created_by
    })
    return {"registered": agent_id}

@router.delete("/register/{agent_id:path}")
async def unregister_agent(agent_id: str):
    """Internal endpoint for unregistering agents."""
    from ..services.agent_registry import agent_registry
    agent_registry.unregister(agent_id)
    return {"unregistered": agent_id}
```

**Update `src/server/services/agent_manager.py`:**

```python
from .agent_registry import agent_registry

# In list_agents():
# After collecting all windows, call:
agent_registry.cleanup_stale(all_windows)

# In remove_agent(), after killing window:
agent_registry.unregister(agent_id)

# In create_worker(), after creating window:
agent_registry.register(agent_id, {
    "type": "worker",
    "created_at": datetime.now().isoformat(),
    "session": session,
    "window": name
})
```

**Update `src/orchestrator/monitor.sh`** - After supervisor launch:

```bash
# Register supervisor via API
curl -sf -X POST "http://localhost:${CMUX_PORT}/api/agents/register" \
    -H "Content-Type: application/json" \
    -d '{"agent_id": "supervisor", "agent_type": "supervisor", "created_by": "monitor.sh"}' \
    >/dev/null 2>&1 || log_warn "Failed to register supervisor"
```

### Files Modified
- `src/server/services/agent_registry.py` (new)
- `src/server/services/agent_manager.py`
- `src/server/routes/agents.py`
- `src/orchestrator/monitor.sh`

### Testing
```bash
# Create worker
curl -X POST http://localhost:8000/api/agents -d '{"name":"test-worker"}'
cat .cmux/agent_registry.json  # Should show test-worker

# Delete worker
curl -X DELETE http://localhost:8000/api/agents/test-worker
cat .cmux/agent_registry.json  # Should not show test-worker
```

### Rollback
```bash
rm .cmux/agent_registry.json
git checkout src/server/services/agent_manager.py src/server/routes/agents.py
rm src/server/services/agent_registry.py
```

---

## Task 3: Frontend Self-Healing

### Problem
Health check only monitors API, not frontend. Frontend static files could be missing/corrupted.

### Solution

**Update `src/orchestrator/health.sh`:**

```bash
check_frontend_health() {
    local dist_dir="${CMUX_PROJECT_ROOT}/src/frontend/dist"

    # Check index.html exists
    [[ ! -f "${dist_dir}/index.html" ]] && return 1

    # Check assets directory has at least one JS file
    local js_count
    js_count=$(find "${dist_dir}/assets" -name '*.js' -type f 2>/dev/null | wc -l | xargs)
    ((js_count == 0)) && return 1

    # Check files are actually servable via HTTP
    if ! curl -sf "http://localhost:${CMUX_PORT}/" -o /dev/null 2>&1; then
        return 1
    fi

    return 0
}

attempt_frontend_recovery() {
    log_status "IN_PROGRESS" "Attempting frontend rebuild..."

    local frontend_dir="${CMUX_PROJECT_ROOT}/src/frontend"
    local dist_dir="${frontend_dir}/dist"
    local dist_new="${frontend_dir}/dist_new"
    local dist_old="${frontend_dir}/dist_old"

    cd "$frontend_dir"

    # Try build to temp directory
    if npm run build -- --outDir "$dist_new" >/dev/null 2>&1; then
        # Atomic swap
        rm -rf "$dist_old" 2>/dev/null || true
        [[ -d "$dist_dir" ]] && mv "$dist_dir" "$dist_old"
        mv "$dist_new" "$dist_dir"
        rm -rf "$dist_old" 2>/dev/null || true

        log_status "COMPLETE" "Frontend rebuilt successfully"
        return 0
    fi

    # Build failed - try npm ci first
    log_info "Build failed, running npm ci..."
    if npm ci --silent 2>/dev/null && npm run build -- --outDir "$dist_new" >/dev/null 2>&1; then
        rm -rf "$dist_old" 2>/dev/null || true
        [[ -d "$dist_dir" ]] && mv "$dist_dir" "$dist_old"
        mv "$dist_new" "$dist_dir"
        rm -rf "$dist_old" 2>/dev/null || true

        log_status "COMPLETE" "Frontend rebuilt after npm ci"
        return 0
    fi

    rm -rf "$dist_new" 2>/dev/null || true
    log_status "FAILED" "Frontend rebuild failed"
    return 1
}
```

**Update `src/server/routes/webhooks.py`:**

```python
from fastapi.responses import JSONResponse
from pathlib import Path

@router.get("/health")
async def health_check():
    """Health check with frontend status. Returns 503 if degraded."""
    frontend_dist = Path("src/frontend/dist")
    index_exists = (frontend_dist / "index.html").exists()

    assets_dir = frontend_dist / "assets"
    js_files = list(assets_dir.glob("*.js")) if assets_dir.exists() else []
    frontend_ok = index_exists and len(js_files) > 0

    response_data = {
        "api": "healthy",
        "frontend": {
            "status": "healthy" if frontend_ok else "unhealthy",
            "index_exists": index_exists,
            "js_bundle_count": len(js_files)
        }
    }

    if not frontend_ok:
        response_data["status"] = "degraded"
        return JSONResponse(response_data, status_code=503)

    response_data["status"] = "healthy"
    return response_data
```

### Files Modified
- `src/orchestrator/health.sh`
- `src/server/routes/webhooks.py`

### Testing
```bash
curl http://localhost:8000/api/webhooks/health  # Should return 200
rm -rf src/frontend/dist
curl -I http://localhost:8000/api/webhooks/health  # Should return 503
# Wait for recovery or trigger manually
```

### Rollback
```bash
git checkout src/server/routes/webhooks.py src/orchestrator/health.sh
```

---

## Task 4: Log Monitor Daemon

### Problem
No automated log monitoring. Errors go unnoticed until they cause failures.

### Solution

**New file: `src/orchestrator/log-watcher.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

CMUX_SESSION="${CMUX_SESSION:-cmux}"
CMUX_MAILBOX="${CMUX_MAILBOX:-.cmux/mailbox}"
CMUX_PORT="${CMUX_PORT:-8000}"

CHECK_INTERVAL="${CMUX_LOG_CHECK_INTERVAL:-60}"
ALERT_COOLDOWN="${CMUX_ALERT_COOLDOWN:-300}"

SERVER_LOG="/tmp/cmux-server.log"
ROUTER_LOG=".cmux/router.log"
MARKER_DIR=".cmux/.log_markers"

ERROR_PATTERNS=(
    '\bERROR\b'
    '\bException\b'
    '\bTraceback\b'
    '\bCRITICAL\b'
    '\bFAILED\b'
)

IGNORE_PATTERNS=(
    'healthcheck'
    'GET /api/webhooks/health'
    'INFO:'
)

# Cross-platform helpers
get_inode() {
    local file="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        stat -f %i "$file" 2>/dev/null || echo "0"
    else
        stat --format=%i "$file" 2>/dev/null || echo "0"
    fi
}

get_file_size() {
    local file="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        stat -f %z "$file" 2>/dev/null || echo "0"
    else
        stat --format=%s "$file" 2>/dev/null || echo "0"
    fi
}

get_marker() {
    local log_file="$1"
    local marker_file="${MARKER_DIR}/$(basename "$log_file").marker"

    if [[ ! -f "$marker_file" ]]; then
        echo "0"
        return
    fi

    local saved_inode saved_pos
    read -r saved_inode saved_pos < "$marker_file" 2>/dev/null || { echo "0"; return; }

    local current_inode
    current_inode=$(get_inode "$log_file")

    if [[ "$saved_inode" != "$current_inode" ]]; then
        echo "0"
    else
        echo "$saved_pos"
    fi
}

save_marker() {
    local log_file="$1"
    local position="$2"
    mkdir -p "$MARKER_DIR"
    local inode
    inode=$(get_inode "$log_file")
    echo "$inode $position" > "${MARKER_DIR}/$(basename "$log_file").marker"
}

should_alert() {
    local log_file="$1"
    local cooldown_file="${MARKER_DIR}/$(basename "$log_file").cooldown"

    if [[ -f "$cooldown_file" ]]; then
        local last_alert
        last_alert=$(cat "$cooldown_file" 2>/dev/null || echo "0")
        local now
        now=$(date +%s)
        if ((now - last_alert < ALERT_COOLDOWN)); then
            return 1
        fi
    fi
    date +%s > "$cooldown_file"
    return 0
}

analyze_log() {
    local log_file="$1"
    [[ ! -f "$log_file" ]] && return 0

    local last_pos current_size
    last_pos=$(get_marker "$log_file")
    current_size=$(get_file_size "$log_file")

    if ((current_size < last_pos)); then
        last_pos=0
    fi

    ((current_size <= last_pos)) && return 0

    local new_content
    new_content=$(tail -c +$((last_pos + 1)) "$log_file" 2>/dev/null || true)
    [[ -z "$new_content" ]] && { save_marker "$log_file" "$current_size"; return 0; }

    local error_regex ignore_regex
    error_regex=$(IFS='|'; echo "${ERROR_PATTERNS[*]}")
    ignore_regex=$(IFS='|'; echo "${IGNORE_PATTERNS[*]}")

    local errors
    errors=$(echo "$new_content" | grep -E "$error_regex" 2>/dev/null | grep -vE "$ignore_regex" 2>/dev/null || true)

    if [[ -n "$errors" ]]; then
        local error_count
        error_count=$(echo "$errors" | wc -l | xargs)

        if should_alert "$log_file"; then
            local timestamp
            timestamp=$(date -Iseconds)
            local summary="[LOG ALERT] $(basename "$log_file"): ${error_count} errors detected"
            local alert_file=".cmux/journal/$(date +%Y-%m-%d)/attachments/log-alert-$(date +%H%M%S).md"
            mkdir -p "$(dirname "$alert_file")"

            cat > "$alert_file" << EOF
# Log Alert: $(basename "$log_file")

**Time:** $timestamp
**Error Count:** $error_count

## Errors Found

\`\`\`
$errors
\`\`\`
EOF
            echo "[$timestamp] system:log-watcher -> cmux:supervisor: $summary (body: $alert_file)" >> "$CMUX_MAILBOX"
            log_info "Reported $error_count errors from $(basename "$log_file")"
        fi
    fi

    save_marker "$log_file" "$current_size"
}

check_agent_discrepancies() {
    local registry_file=".cmux/agent_registry.json"
    [[ ! -f "$registry_file" ]] && return 0

    local registered_agents
    if command -v jq &>/dev/null; then
        registered_agents=$(jq -r 'keys[]' "$registry_file" 2>/dev/null || true)
    else
        registered_agents=$(grep -oE '"[^"]+":' "$registry_file" 2>/dev/null | tr -d '":' || true)
    fi

    [[ -z "$registered_agents" ]] && return 0

    local actual_windows
    actual_windows=$(tmux list-windows -t "$CMUX_SESSION" -F '#{window_name}' 2>/dev/null || true)

    while IFS= read -r agent; do
        [[ -z "$agent" ]] && continue
        local window_name="${agent##*:}"

        if ! echo "$actual_windows" | grep -q "^${window_name}$"; then
            local timestamp
            timestamp=$(date -Iseconds)
            echo "[$timestamp] system:log-watcher -> cmux:supervisor: [ALERT] Registered agent '$agent' missing from tmux" >> "$CMUX_MAILBOX"
        fi
    done <<< "$registered_agents"
}

main() {
    log_info "Log watcher started (interval: ${CHECK_INTERVAL}s, cooldown: ${ALERT_COOLDOWN}s)"
    mkdir -p "$MARKER_DIR"

    local check_count=0
    while true; do
        analyze_log "$SERVER_LOG"
        analyze_log "$ROUTER_LOG"

        if ((check_count % 5 == 0)); then
            check_agent_discrepancies
        fi

        ((check_count++))
        sleep "$CHECK_INTERVAL"
    done
}

main
```

**Update `src/orchestrator/monitor.sh`** - Add log watcher startup:

```bash
start_log_watcher() {
    if [[ -n "${LOG_WATCHER_PID:-}" ]] && kill -0 "$LOG_WATCHER_PID" 2>/dev/null; then
        return 0
    fi

    log_step "Starting log watcher..."
    "${SCRIPT_DIR}/log-watcher.sh" &
    LOG_WATCHER_PID=$!
    log_ok "Log watcher started (PID: $LOG_WATCHER_PID)"
}
```

### Files Modified
- `src/orchestrator/log-watcher.sh` (new)
- `src/orchestrator/monitor.sh`

### Testing
```bash
./src/orchestrator/log-watcher.sh &
echo "ERROR: test error" >> /tmp/cmux-server.log
sleep 2
tail .cmux/mailbox  # Should see alert
```

### Rollback
```bash
pkill -f log-watcher.sh
rm src/orchestrator/log-watcher.sh
```

---

## Summary

| Task | Files | Risk | Status |
|------|-------|------|--------|
| 1. Server Kill | 3 modified | Low | Approved |
| 2. Agent Registry | 4 modified, 1 new | Medium | Approved |
| 3. Frontend Health | 2 modified | Low | Approved |
| 4. Log Watcher | 2 modified, 1 new | Low | Approved |

**Total: 9 files (2 new, 7 modified)**

---

*Plan approved by both orch-defender and orch-critic on 2026-01-31.*
