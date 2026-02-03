# Orchestration Improvements - DEFENDER Initial Plan

**Author:** Orchestration Defender Agent
**Date:** 2026-01-31
**Status:** Initial Draft for Debate

---

## Executive Summary

This plan addresses four orchestration improvements for the CMUX system. Each improvement is grounded in the actual codebase with specific file changes and rationale.

---

## Task 1: Fix cmux.sh Not Killing the Server Properly

### Current State Analysis

**File:** `src/orchestrator/cmux.sh` (lines 92-116)

```bash
cmd_stop() {
    log_info "Stopping cmux system..."

    # Stop FastAPI server
    local pid
    pid=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)
    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
        printf "${GREEN}✓${NC} FastAPI server stopped\n"
    fi
    # ...
}
```

**Problems Identified:**
1. `lsof -ti tcp:$PORT` may return multiple PIDs (parent uvicorn + worker processes)
2. Using `kill` without waiting doesn't ensure clean shutdown
3. No SIGTERM -> SIGKILL escalation for stubborn processes
4. The `cleanup()` function in `monitor.sh` (lines 197-222) has similar issues

### Proposed Solution

**Modify `cmd_stop()` in cmux.sh:**

```bash
cmd_stop() {
    log_info "Stopping cmux system..."

    # Stop FastAPI server (handle multiple PIDs - parent + workers)
    local pids
    pids=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        # SIGTERM first (graceful shutdown)
        echo "$pids" | xargs kill 2>/dev/null || true

        # Wait up to 5 seconds for graceful shutdown
        local wait_count=0
        while lsof -ti tcp:"$CMUX_PORT" >/dev/null 2>&1 && ((wait_count < 5)); do
            sleep 1
            ((wait_count++))
        done

        # SIGKILL any remaining (force kill)
        pids=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            echo "$pids" | xargs kill -9 2>/dev/null || true
        fi
        printf "${GREEN}✓${NC} FastAPI server stopped\n"
    fi

    # Kill main tmux session
    # ... rest unchanged
}
```

**Also update `cleanup()` in monitor.sh with same pattern.**

### Files to Modify
- `src/orchestrator/cmux.sh`: `cmd_stop()` function
- `src/orchestrator/monitor.sh`: `cleanup()` function
- `src/orchestrator/health.sh`: `stop_server()` function (lines 157-163)

### Risk Assessment
- **Low risk**: Changes are defensive and backward compatible
- **Rollback**: Simple - just uses more thorough process killing

---

## Task 2: Track Which tmux Windows Are Actual Agents

### Current State Analysis

**File:** `src/server/config.py` (line 19)

```python
system_windows: list[str] = ["monitor"]
```

**File:** `src/server/services/agent_manager.py` (lines 38-44)

```python
for window in windows:
    # Filter out system windows (like "monitor")
    if window in settings.system_windows:
        continue
    # Assumes everything else is an agent!
```

**Problems Identified:**
1. Any window not named "monitor" is assumed to be an agent
2. User could create manual tmux windows that get picked up as agents
3. No explicit agent registration - purely naming-convention based
4. No persistence of agent metadata (who created it, when, purpose)

### Proposed Solution

Implement **explicit agent registration** with a lightweight metadata store.

**Option A (Recommended): Environment Variable Tagging**

When creating an agent window, set an environment variable:
```bash
# In monitor.sh launch_supervisor():
tmux_send_keys "$CMUX_SESSION" "supervisor" \
    "export CMUX_AGENT=true CMUX_AGENT_NAME=supervisor && cd ${CMUX_PROJECT_ROOT} && claude..."
```

Already exists! But not used for detection. Add detection:

**New file: `src/server/services/agent_registry.py`**

```python
from pathlib import Path
from typing import Optional, Set
import json

REGISTRY_FILE = Path(".cmux/agent_registry.json")

class AgentRegistry:
    """Tracks explicitly registered agents vs random tmux windows."""

    def __init__(self):
        self._agents: dict[str, dict] = {}
        self._load()

    def _load(self):
        if REGISTRY_FILE.exists():
            self._agents = json.loads(REGISTRY_FILE.read_text())

    def _save(self):
        REGISTRY_FILE.parent.mkdir(parents=True, exist_ok=True)
        REGISTRY_FILE.write_text(json.dumps(self._agents, indent=2))

    def register(self, agent_id: str, metadata: dict):
        """Register an agent when it's created."""
        self._agents[agent_id] = {
            "registered_at": metadata.get("created_at"),
            "type": metadata.get("type", "worker"),
            "created_by": metadata.get("created_by", "system"),
            **metadata
        }
        self._save()

    def unregister(self, agent_id: str):
        """Remove agent from registry."""
        if agent_id in self._agents:
            del self._agents[agent_id]
            self._save()

    def is_registered(self, agent_id: str) -> bool:
        """Check if a window is a registered agent."""
        return agent_id in self._agents

    def get_registered_agents(self) -> Set[str]:
        """Get all registered agent IDs."""
        return set(self._agents.keys())

agent_registry = AgentRegistry()
```

**Modify `agent_manager.py`:**

```python
from .agent_registry import agent_registry

async def list_agents(self, session: Optional[str] = None) -> List[Agent]:
    agents = []
    registered = agent_registry.get_registered_agents()

    for sess in sessions:
        windows = await tmux_service.list_windows(sess)

        for window in windows:
            if window in settings.system_windows:
                continue

            agent_id = f"{sess}:{window}" if sess != settings.main_session else window

            # Only include explicitly registered agents
            if agent_id not in registered and window not in registered:
                continue  # Skip unregistered windows

            # ... rest unchanged
```

**Modify `create_worker()`:**

```python
async def create_worker(self, name: str, session: Optional[str] = None) -> Agent:
    session = session or settings.main_session
    await tmux_service.create_window(name, session)

    agent_id = f"{session}:{name}" if session != settings.main_session else name

    # Register the agent
    agent_registry.register(agent_id, {
        "type": "worker",
        "created_at": datetime.now().isoformat(),
        "session": session,
        "window": name
    })

    # ... rest unchanged
```

### Files to Modify
- `src/server/services/agent_registry.py` (new file)
- `src/server/services/agent_manager.py`: Import and use registry
- `src/orchestrator/monitor.sh`: Register supervisor on creation
- `src/server/config.py`: Add `agent_registry_path` setting

### Alternative Considered: tmux Environment Detection

Could check if `CMUX_AGENT=true` env var is set in the pane:
```bash
tmux show-environment -t "cmux:supervisor" CMUX_AGENT
```

**Rejected because:** Environment variables are per-session not per-window, and checking requires subprocess calls for each window.

### Risk Assessment
- **Medium risk**: Changes agent listing behavior
- **Mitigation**: Default to "all windows are agents" if registry is empty (backward compat)
- **Rollback**: Delete registry file to revert to current behavior

---

## Task 3: Self-Healing for Frontend

### Current State Analysis

**File:** `src/orchestrator/health.sh` (lines 21-27)

```bash
check_server_health() {
    if curl -sf "http://localhost:${CMUX_PORT}/api/webhooks/health" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}
```

**Problems Identified:**
1. Only checks API health, not frontend serving
2. Frontend static files could be missing/corrupted
3. React build could have failed silently
4. No detection of JavaScript errors in the frontend

### Proposed Solution

**Multi-layer health checking:**

**Layer 1: Static File Check**
Add to `health.sh`:

```bash
check_frontend_health() {
    # Check if frontend index.html is accessible
    if ! curl -sf "http://localhost:${CMUX_PORT}/" >/dev/null 2>&1; then
        return 1
    fi

    # Check if main JS bundle exists and is served
    # The bundle name changes on rebuild, so check for any .js file in assets
    local index_html
    index_html=$(curl -sf "http://localhost:${CMUX_PORT}/" 2>/dev/null)
    if [[ -z "$index_html" ]]; then
        return 1
    fi

    # Extract JS bundle path from index.html
    local js_path
    js_path=$(echo "$index_html" | grep -oE 'src="/assets/[^"]+\.js"' | head -1 | sed 's/src="//;s/"//')
    if [[ -n "$js_path" ]]; then
        if ! curl -sf "http://localhost:${CMUX_PORT}${js_path}" >/dev/null 2>&1; then
            return 1
        fi
    fi

    return 0
}
```

**Layer 2: API Health Endpoint Enhancement**

Modify `src/server/routes/webhooks.py` to include frontend status:

```python
@router.get("/health")
async def health_check():
    from pathlib import Path

    frontend_dist = Path("src/frontend/dist")
    frontend_ok = (frontend_dist / "index.html").exists()

    # Check for any .js files in assets
    assets_dir = frontend_dist / "assets"
    js_files = list(assets_dir.glob("*.js")) if assets_dir.exists() else []

    return {
        "status": "healthy" if frontend_ok else "degraded",
        "api": "healthy",
        "frontend": {
            "status": "healthy" if frontend_ok and js_files else "unhealthy",
            "index_exists": frontend_ok,
            "js_bundles": len(js_files)
        }
    }
```

**Layer 3: Automatic Frontend Rebuild**

In `health.sh`, add frontend recovery:

```bash
attempt_frontend_recovery() {
    log_status "IN_PROGRESS" "Attempting frontend rebuild..."

    cd "$CMUX_PROJECT_ROOT/src/frontend"

    # Try npm run build
    if npm run build >/dev/null 2>&1; then
        log_status "COMPLETE" "Frontend rebuilt successfully"
        return 0
    fi

    # If build failed, try npm install first
    log_info "Build failed, trying npm install..."
    npm install >/dev/null 2>&1

    if npm run build >/dev/null 2>&1; then
        log_status "COMPLETE" "Frontend rebuilt after npm install"
        return 0
    fi

    log_status "FAILED" "Frontend rebuild failed"
    return 1
}

# In main health loop:
check_combined_health() {
    local api_ok=true
    local frontend_ok=true

    check_server_health || api_ok=false
    check_frontend_health || frontend_ok=false

    if [[ "$api_ok" == "false" ]]; then
        return 1  # API failure is critical
    fi

    if [[ "$frontend_ok" == "false" ]]; then
        log_warn "Frontend unhealthy, attempting recovery..."
        attempt_frontend_recovery
        return 0  # Don't fail overall health for frontend issues
    fi

    return 0
}
```

### Files to Modify
- `src/orchestrator/health.sh`: Add frontend health checks and recovery
- `src/server/routes/webhooks.py`: Enhance health endpoint
- `src/orchestrator/monitor.sh`: Use combined health check

### Risk Assessment
- **Low risk**: Additive changes, doesn't change existing recovery logic
- **Note**: Frontend rebuild during runtime is safe (static files)

---

## Task 4: Log Monitor Agent (Cron-Job Style)

### Current State Analysis

Currently, no automated log monitoring exists. The supervisor agent must manually check logs or receive error reports.

### Proposed Solution

Create a new **log-watcher daemon** that:
1. Monitors key log files for patterns
2. Reports anomalies to supervisor via mailbox
3. Runs on a configurable schedule

**New file: `src/orchestrator/log-watcher.sh`**

```bash
#!/usr/bin/env bash
#===============================================================================
# log-watcher.sh - Cron-Style Log Monitor
#
# Watches log files for error patterns and discrepancies.
# Reports findings to supervisor via mailbox.
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

CMUX_SESSION="${CMUX_SESSION:-cmux}"
CMUX_MAILBOX="${CMUX_MAILBOX:-.cmux/mailbox}"
CMUX_PORT="${CMUX_PORT:-8000}"

# Check interval (seconds)
CHECK_INTERVAL="${CMUX_LOG_CHECK_INTERVAL:-60}"

# Log files to monitor
SERVER_LOG="/tmp/cmux-server.log"
ROUTER_LOG=".cmux/router.log"

# Markers for tracking position
MARKER_DIR=".cmux/.log_markers"

# Error patterns to watch for
ERROR_PATTERNS=(
    "ERROR"
    "Exception"
    "Traceback"
    "CRITICAL"
    "FAILED"
    "Unhandled"
    "Connection refused"
)

# Patterns to ignore (reduce noise)
IGNORE_PATTERNS=(
    "INFO:.*healthcheck"
    "GET /api/webhooks/health"
)

#-------------------------------------------------------------------------------
# Position Tracking
#-------------------------------------------------------------------------------

get_marker() {
    local log_file="$1"
    local marker_file="${MARKER_DIR}/$(basename "$log_file").marker"
    if [[ -f "$marker_file" ]]; then
        cat "$marker_file"
    else
        echo "0"
    fi
}

save_marker() {
    local log_file="$1"
    local position="$2"
    mkdir -p "$MARKER_DIR"
    echo "$position" > "${MARKER_DIR}/$(basename "$log_file").marker"
}

#-------------------------------------------------------------------------------
# Log Analysis
#-------------------------------------------------------------------------------

analyze_log() {
    local log_file="$1"

    [[ ! -f "$log_file" ]] && return 0

    local last_pos current_size
    last_pos=$(get_marker "$log_file")
    current_size=$(wc -c < "$log_file" | xargs)

    # If file was truncated, reset
    if ((current_size < last_pos)); then
        last_pos=0
    fi

    # No new content
    ((current_size <= last_pos)) && return 0

    # Extract new content
    local new_content
    new_content=$(tail -c +$((last_pos + 1)) "$log_file")

    # Build regex for error patterns
    local error_regex
    error_regex=$(IFS='|'; echo "${ERROR_PATTERNS[*]}")

    # Build regex for ignore patterns
    local ignore_regex
    ignore_regex=$(IFS='|'; echo "${IGNORE_PATTERNS[*]}")

    # Find errors (exclude ignored patterns)
    local errors
    errors=$(echo "$new_content" | grep -E "$error_regex" | grep -vE "$ignore_regex" || true)

    if [[ -n "$errors" ]]; then
        local error_count
        error_count=$(echo "$errors" | wc -l | xargs)

        # Report to supervisor
        local timestamp
        timestamp=$(date -Iseconds)
        local summary
        summary="[LOG ALERT] $(basename "$log_file"): ${error_count} errors detected"

        # Write details to attachment
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

## Recommended Actions

1. Check the full log: $log_file
2. Review recent changes: \`git log -5 --oneline\`
3. Check agent status via dashboard
EOF

        # Send to mailbox
        echo "[$timestamp] system:log-watcher -> cmux:supervisor: $summary (body: $alert_file)" >> "$CMUX_MAILBOX"

        log_info "Reported $error_count errors from $(basename "$log_file")"
    fi

    save_marker "$log_file" "$current_size"
}

#-------------------------------------------------------------------------------
# Discrepancy Detection
#-------------------------------------------------------------------------------

check_agent_discrepancies() {
    # Compare expected agents (from registry) with actual tmux windows
    local registry_file=".cmux/agent_registry.json"

    [[ ! -f "$registry_file" ]] && return 0

    local registered_agents
    registered_agents=$(jq -r 'keys[]' "$registry_file" 2>/dev/null || true)

    if [[ -z "$registered_agents" ]]; then
        return 0
    fi

    # Get actual tmux windows
    local actual_windows
    actual_windows=$(tmux list-windows -t "$CMUX_SESSION" -F '#{window_name}' 2>/dev/null || true)

    # Check for missing agents
    while IFS= read -r agent; do
        [[ -z "$agent" ]] && continue
        local window_name="${agent##*:}"

        if ! echo "$actual_windows" | grep -q "^${window_name}$"; then
            local timestamp
            timestamp=$(date -Iseconds)
            echo "[$timestamp] system:log-watcher -> cmux:supervisor: [ALERT] Registered agent '$agent' not found in tmux" >> "$CMUX_MAILBOX"
            log_warn "Agent discrepancy: $agent missing from tmux"
        fi
    done <<< "$registered_agents"
}

#-------------------------------------------------------------------------------
# Health Metrics Collection
#-------------------------------------------------------------------------------

collect_health_metrics() {
    # Collect and log periodic health metrics
    local metrics_file=".cmux/metrics/$(date +%Y-%m-%d).jsonl"
    mkdir -p "$(dirname "$metrics_file")"

    local timestamp cpu_usage mem_usage disk_usage
    timestamp=$(date -Iseconds)
    cpu_usage=$(top -l 1 | grep "CPU usage" | awk '{print $3}' | tr -d '%' || echo "0")
    mem_usage=$(top -l 1 | grep "PhysMem" | awk '{print $2}' | tr -d 'GM' || echo "0")
    disk_usage=$(df -h . | tail -1 | awk '{print $5}' | tr -d '%' || echo "0")

    # Get agent count
    local agent_count
    agent_count=$(tmux list-windows -t "$CMUX_SESSION" 2>/dev/null | wc -l | xargs)

    # Append metrics
    echo "{\"timestamp\":\"$timestamp\",\"cpu\":$cpu_usage,\"memory\":$mem_usage,\"disk\":$disk_usage,\"agents\":$agent_count}" >> "$metrics_file"

    # Alert if resources are high
    if ((disk_usage > 90)); then
        local ts
        ts=$(date -Iseconds)
        echo "[$ts] system:log-watcher -> cmux:supervisor: [ALERT] Disk usage critical: ${disk_usage}%" >> "$CMUX_MAILBOX"
    fi
}

#-------------------------------------------------------------------------------
# Main Loop
#-------------------------------------------------------------------------------

main() {
    log_info "Log watcher daemon started (interval: ${CHECK_INTERVAL}s)"

    mkdir -p "$MARKER_DIR"

    local check_count=0

    while true; do
        # Analyze logs
        analyze_log "$SERVER_LOG"
        analyze_log "$ROUTER_LOG"

        # Check for discrepancies every 5 cycles
        if ((check_count % 5 == 0)); then
            check_agent_discrepancies
            collect_health_metrics
        fi

        ((check_count++))
        sleep "$CHECK_INTERVAL"
    done
}

main
```

**Integration with monitor.sh:**

Add to `monitor.sh` after router start:

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

### Files to Create/Modify
- `src/orchestrator/log-watcher.sh` (new file)
- `src/orchestrator/monitor.sh`: Add log watcher startup
- `src/server/config.py`: Add log watcher settings

### Risk Assessment
- **Low risk**: Separate daemon, doesn't affect core functionality
- **Resource usage**: Minimal (checks every 60s by default)

---

## Implementation Order

1. **Task 1 (Server Kill Fix)** - Immediate, simple, low risk
2. **Task 2 (Agent Registry)** - Important for Task 4 discrepancy detection
3. **Task 3 (Frontend Self-Healing)** - Enhances existing health system
4. **Task 4 (Log Watcher)** - Depends on Task 2 for full functionality

---

## Open Questions for Critic

1. **Agent Registry Persistence:** Should we use JSON file or SQLite for registry?
2. **Log Watcher Alerting:** Should alerts also go to a webhook for external notification?
3. **Frontend Health:** Is checking static files sufficient, or should we add browser-based checks?
4. **Metrics Storage:** Should metrics go in journal or separate metrics directory?

---

## Summary of Changes

| File | Change Type | Risk |
|------|-------------|------|
| `src/orchestrator/cmux.sh` | Modify | Low |
| `src/orchestrator/monitor.sh` | Modify | Low |
| `src/orchestrator/health.sh` | Modify | Low |
| `src/server/services/agent_registry.py` | New | Medium |
| `src/server/services/agent_manager.py` | Modify | Medium |
| `src/server/routes/webhooks.py` | Modify | Low |
| `src/orchestrator/log-watcher.sh` | New | Low |
| `src/server/config.py` | Modify | Low |

**Total Files:** 8 (2 new, 6 modified)

---

*Awaiting critic feedback...*
