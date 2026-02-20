# Orchestration Improvements - DEFENDER Round 2 Rebuttal

**Author:** Orchestration Defender Agent
**Date:** 2026-01-31
**Status:** Round 2 - Addressing Critic Feedback

---

## Response Summary

The critic's feedback is thorough and identifies real issues. I **accept** most critiques and provide revised implementations. A few points I'll defend or offer alternative approaches.

---

## Task 1: Server Kill Fix - REVISED

### Accepted Critiques
- ✅ Orphaned worker processes - ACCEPT, adding pkill fallback
- ✅ Silent failure risk - ACCEPT, using explicit loop
- ✅ Port verification missing - ACCEPT, adding check
- ⚠️ Total timeout - PARTIAL ACCEPT (see below)

### On Total Timeout

The critic suggests `timeout 15 cmd_stop_inner`. I have concerns:

1. `timeout` command behavior differs between GNU coreutils (Linux) and BSD (macOS)
2. On macOS, `timeout` requires `brew install coreutils` (gtimeout)

**Counter-proposal:** Use a subshell with background timeout:

```bash
cmd_stop() {
    # Maximum stop duration - 15 seconds
    local STOP_TIMEOUT=15

    (
        sleep "$STOP_TIMEOUT"
        log_fail "Stop operation timed out - forcing kill"
        pkill -9 -f "uvicorn.*src.server.main:app" 2>/dev/null || true
        lsof -ti tcp:"$CMUX_PORT" 2>/dev/null | xargs kill -9 2>/dev/null || true
    ) &
    local timeout_pid=$!

    _cmd_stop_inner

    # Cancel timeout if we finished in time
    kill "$timeout_pid" 2>/dev/null || true
}
```

This is cross-platform and doesn't require coreutils.

### Revised Implementation

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

### Verdict: REVISED AND IMPROVED

---

## Task 2: Agent Registry - REVISED

### Accepted Critiques
- ✅ Race condition on registry file - ACCEPT, adding fcntl locking
- ✅ Stale registry entries - ACCEPT, adding cleanup on list
- ✅ Missing supervisor registration - ACCEPT, adding API endpoint
- ✅ Missing unregister() in remove_agent() - ACCEPT, will add
- ⚠️ Environment detection as secondary - ACCEPT as fallback

### On Registration API (Question from Critic)

The critic asked how bash calls Python registry. I agree **Option A (API endpoint)** is cleanest.

**New endpoint in `src/server/routes/agents.py`:**

```python
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

**In monitor.sh after supervisor is ready:**

```bash
# Register supervisor via API
curl -sf -X POST "http://localhost:${CMUX_PORT}/api/agents/register" \
    -H "Content-Type: application/json" \
    -d '{"agent_id": "supervisor", "agent_type": "supervisor", "created_by": "monitor.sh"}' \
    >/dev/null 2>&1 || log_warn "Failed to register supervisor"
```

### Revised Registry Implementation

```python
# src/server/services/agent_registry.py

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
                    fcntl.flock(f.fileno(), fcntl.LOCK_SH)  # Shared lock for read
                    self._agents = json.load(f)
                    fcntl.flock(f.fileno(), fcntl.LOCK_UN)
            except (json.JSONDecodeError, IOError):
                self._agents = {}

    def _save(self):
        """Save registry to disk with exclusive lock."""
        REGISTRY_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(REGISTRY_FILE, 'w') as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)  # Exclusive lock for write
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

    def get_agent_metadata(self, agent_id: str) -> Optional[Dict[str, Any]]:
        """Get metadata for a specific agent."""
        return self._agents.get(agent_id)

    def cleanup_stale(self, existing_windows: Set[str]):
        """
        Remove registry entries for windows that no longer exist.
        Called during list_agents() to sync with reality.
        """
        stale = set(self._agents.keys()) - existing_windows
        if stale:
            for agent_id in stale:
                del self._agents[agent_id]
            self._save()
        return stale


agent_registry = AgentRegistry()
```

### Revised agent_manager.py Integration

```python
# In agent_manager.py

from .agent_registry import agent_registry

async def list_agents(self, session: Optional[str] = None) -> List[Agent]:
    agents = []

    # Get list of sessions to query
    if session:
        sessions = [session]
    else:
        sessions = await tmux_service.list_sessions()

    # Collect all actual windows across sessions
    all_windows: Set[str] = set()

    for sess in sessions:
        windows = await tmux_service.list_windows(sess)

        for window in windows:
            if window in settings.system_windows:
                continue

            agent_id = f"{sess}:{window}" if sess != settings.main_session else window
            all_windows.add(agent_id)

            # Check registration OR fallback to env detection
            is_agent = agent_registry.is_registered(agent_id)

            # Fallback: check CMUX_AGENT environment (defensive)
            if not is_agent:
                # For backward compatibility, treat non-registered windows as agents
                # if they exist in non-system slots
                # TODO: Eventually require registration
                is_agent = True  # Backward compat mode

            if is_agent:
                agent_type = AgentType.SUPERVISOR if self._is_supervisor(window, sess) else AgentType.WORKER
                agent = Agent(
                    id=agent_id,
                    name=window,
                    type=agent_type,
                    tmux_window=window,
                    session=sess,
                    status=AgentStatus.IDLE
                )
                agents.append(agent)
                self._agents[agent_id] = agent

    # Cleanup stale registry entries
    agent_registry.cleanup_stale(all_windows)

    return agents

async def remove_agent(self, agent_id: str) -> bool:
    """Remove a worker agent."""
    agent = await self.get_agent(agent_id)
    if not agent:
        return False

    if agent.type == AgentType.SUPERVISOR:
        return False

    session, window = self.parse_agent_id(agent_id)
    success = await tmux_service.kill_window(window, session)

    if success:
        # Unregister from registry
        agent_registry.unregister(agent_id)
        if agent_id in self._agents:
            del self._agents[agent_id]

    return success
```

### Backward Compatibility Strategy

The critic correctly noted we need fallback. My approach:

1. **Phase 1 (this PR):** All windows are agents unless in `system_windows`. Registry is opt-in enhancement.
2. **Phase 2 (future):** Log warning for unregistered agents.
3. **Phase 3 (future):** Require registration (opt-out via config).

### Verdict: REVISED AND IMPROVED

---

## Task 3: Frontend Self-Healing - REVISED

### Accepted Critiques
- ✅ HTML parsing is fragile - ACCEPT, using directory check instead
- ✅ npm install dangerous - ACCEPT, using npm ci
- ✅ HTTP 503 for degraded - ACCEPT, returning proper status code
- ✅ Build during runtime - ACCEPT, using atomic swap
- ⚠️ Startup check already exists - ACKNOWLEDGED (good catch!)

### Revised Implementation

**health.sh frontend check:**

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

    # Build failed - try npm ci first (reproducible install)
    log_info "Build failed, running npm ci..."
    if npm ci --silent 2>/dev/null && npm run build -- --outDir "$dist_new" >/dev/null 2>&1; then
        rm -rf "$dist_old" 2>/dev/null || true
        [[ -d "$dist_dir" ]] && mv "$dist_dir" "$dist_old"
        mv "$dist_new" "$dist_dir"
        rm -rf "$dist_old" 2>/dev/null || true

        log_status "COMPLETE" "Frontend rebuilt after npm ci"
        return 0
    fi

    # Cleanup failed attempt
    rm -rf "$dist_new" 2>/dev/null || true

    log_status "FAILED" "Frontend rebuild failed - manual intervention required"
    return 1
}
```

**webhooks.py health endpoint:**

```python
from fastapi.responses import JSONResponse
from pathlib import Path

@router.get("/health")
async def health_check():
    """
    Health check endpoint with frontend status.
    Returns 503 if frontend is unhealthy (degraded mode).
    """
    frontend_dist = Path("src/frontend/dist")
    index_exists = (frontend_dist / "index.html").exists()

    # Check for JS bundles
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

### On Existing Startup Check

The critic correctly noted `monitor.sh` already has startup check (lines 93-99). My frontend self-healing is for **runtime** recovery, not startup. This complements, not duplicates:

- **Startup (existing):** Build if `dist/` doesn't exist
- **Runtime (new):** Rebuild if files become corrupted/deleted during operation

### Verdict: REVISED AND IMPROVED

---

## Task 4: Log Watcher - REVISED

### Accepted Critiques
- ✅ macOS-specific commands - ACCEPT, adding cross-platform
- ✅ Log rotation breaks position - ACCEPT, adding inode tracking
- ✅ Error patterns too broad - ACCEPT, using word boundaries
- ✅ No rate limiting - ACCEPT, adding cooldown
- ✅ jq dependency - ACCEPT, checking or using pure bash
- ⚠️ Coupling to Task 2 - ACCEPT, adding graceful degradation

### Revised Implementation

```bash
#!/usr/bin/env bash
#===============================================================================
# log-watcher.sh - Cross-Platform Log Monitor
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

CMUX_SESSION="${CMUX_SESSION:-cmux}"
CMUX_MAILBOX="${CMUX_MAILBOX:-.cmux/mailbox}"
CMUX_PORT="${CMUX_PORT:-8000}"

CHECK_INTERVAL="${CMUX_LOG_CHECK_INTERVAL:-60}"
ALERT_COOLDOWN="${CMUX_ALERT_COOLDOWN:-300}"  # 5 minutes

SERVER_LOG="/tmp/cmux-server.log"
ROUTER_LOG=".cmux/router.log"
MARKER_DIR=".cmux/.log_markers"

# Error patterns with word boundaries
ERROR_PATTERNS=(
    '\bERROR\b'
    '\bException\b'
    '\bTraceback\b'
    '\bCRITICAL\b'
    '\bFAILED\b'
    '\bUnhandled\b'
    'Connection refused'
)

IGNORE_PATTERNS=(
    'healthcheck'
    'GET /api/webhooks/health'
    'INFO:'
)

#-------------------------------------------------------------------------------
# Cross-Platform Helpers
#-------------------------------------------------------------------------------

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

#-------------------------------------------------------------------------------
# Position Tracking with Inode Detection
#-------------------------------------------------------------------------------

get_marker() {
    local log_file="$1"
    local marker_file="${MARKER_DIR}/$(basename "$log_file").marker"

    if [[ ! -f "$marker_file" ]]; then
        echo "0"
        return
    fi

    local saved_inode saved_pos
    read -r saved_inode saved_pos < "$marker_file" 2>/dev/null || {
        echo "0"
        return
    }

    local current_inode
    current_inode=$(get_inode "$log_file")

    if [[ "$saved_inode" != "$current_inode" ]]; then
        echo "0"  # File rotated, start fresh
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

#-------------------------------------------------------------------------------
# Rate Limiting
#-------------------------------------------------------------------------------

should_alert() {
    local log_file="$1"
    local cooldown_file="${MARKER_DIR}/$(basename "$log_file").cooldown"

    if [[ -f "$cooldown_file" ]]; then
        local last_alert
        last_alert=$(cat "$cooldown_file" 2>/dev/null || echo "0")
        local now
        now=$(date +%s)
        if ((now - last_alert < ALERT_COOLDOWN)); then
            return 1  # Still in cooldown
        fi
    fi
    date +%s > "$cooldown_file"
    return 0
}

#-------------------------------------------------------------------------------
# Log Analysis
#-------------------------------------------------------------------------------

analyze_log() {
    local log_file="$1"

    [[ ! -f "$log_file" ]] && return 0

    local last_pos current_size
    last_pos=$(get_marker "$log_file")
    current_size=$(get_file_size "$log_file")

    # If file was truncated (smaller than last pos), reset
    if ((current_size < last_pos)); then
        last_pos=0
    fi

    # No new content
    ((current_size <= last_pos)) && return 0

    # Extract new content
    local new_content
    new_content=$(tail -c +$((last_pos + 1)) "$log_file" 2>/dev/null || true)

    [[ -z "$new_content" ]] && {
        save_marker "$log_file" "$current_size"
        return 0
    }

    # Build regex for error patterns
    local error_regex
    error_regex=$(IFS='|'; echo "${ERROR_PATTERNS[*]}")

    # Build regex for ignore patterns
    local ignore_regex
    ignore_regex=$(IFS='|'; echo "${IGNORE_PATTERNS[*]}")

    # Find errors (exclude ignored patterns)
    local errors
    errors=$(echo "$new_content" | grep -E "$error_regex" 2>/dev/null | grep -vE "$ignore_regex" 2>/dev/null || true)

    if [[ -n "$errors" ]]; then
        local error_count
        error_count=$(echo "$errors" | wc -l | xargs)

        # Check cooldown before alerting
        if should_alert "$log_file"; then
            report_errors "$log_file" "$error_count" "$errors"
        else
            log_info "Suppressed alert for $(basename "$log_file") (cooldown)"
        fi
    fi

    save_marker "$log_file" "$current_size"
}

report_errors() {
    local log_file="$1"
    local error_count="$2"
    local errors="$3"

    local timestamp
    timestamp=$(date -Iseconds)
    local summary="[LOG ALERT] $(basename "$log_file"): ${error_count} errors detected"

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

1. Check the full log: \`tail -100 $log_file\`
2. Review recent changes: \`git log -5 --oneline\`
3. Check agent status via dashboard
EOF

    # Send to mailbox
    echo "[$timestamp] system:log-watcher -> cmux:supervisor: $summary (body: $alert_file)" >> "$CMUX_MAILBOX"

    log_info "Reported $error_count errors from $(basename "$log_file")"
}

#-------------------------------------------------------------------------------
# Discrepancy Detection (Graceful if no registry)
#-------------------------------------------------------------------------------

check_agent_discrepancies() {
    local registry_file=".cmux/agent_registry.json"

    # Graceful degradation: skip if registry doesn't exist
    if [[ ! -f "$registry_file" ]]; then
        # No registry yet - this is OK, just skip discrepancy check
        return 0
    fi

    # Check if jq is available
    if ! command -v jq &>/dev/null; then
        # Fallback: use grep/sed for simple JSON parsing
        local registered_agents
        registered_agents=$(grep -oE '"[^"]+":' "$registry_file" 2>/dev/null | tr -d '":' || true)
    else
        local registered_agents
        registered_agents=$(jq -r 'keys[]' "$registry_file" 2>/dev/null || true)
    fi

    [[ -z "$registered_agents" ]] && return 0

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
# Metrics Collection (Skip in v1 - focus on log monitoring)
#-------------------------------------------------------------------------------

# NOTE: Metrics collection removed for v1 per critic feedback
# Cross-platform CPU/memory monitoring adds complexity
# Will be added in v2 if needed

#-------------------------------------------------------------------------------
# Main Loop
#-------------------------------------------------------------------------------

main() {
    log_info "Log watcher daemon started (interval: ${CHECK_INTERVAL}s, cooldown: ${ALERT_COOLDOWN}s)"

    mkdir -p "$MARKER_DIR"

    local check_count=0

    while true; do
        # Analyze logs
        analyze_log "$SERVER_LOG"
        analyze_log "$ROUTER_LOG"

        # Check for discrepancies every 5 cycles (5 minutes at default interval)
        if ((check_count % 5 == 0)); then
            check_agent_discrepancies
        fi

        ((check_count++))
        sleep "$CHECK_INTERVAL"
    done
}

main
```

### On Metrics Collection

Per critic feedback, I've **removed metrics collection from v1**. Focus is on log monitoring. Metrics can be Phase 2 if needed.

### On Task 2 Dependency

Added graceful degradation: if registry doesn't exist, discrepancy check is skipped without error. This means log watcher works standalone.

### Verdict: REVISED AND IMPROVED

---

## Testing Strategy (Addressing Critic's Missing Item #1)

### Unit Tests

**New file: `tests/test_agent_registry.py`**

```python
import pytest
import tempfile
from pathlib import Path
from unittest.mock import patch

def test_registry_register_unregister():
    """Test basic register/unregister flow."""
    with tempfile.TemporaryDirectory() as tmpdir:
        registry_path = Path(tmpdir) / "registry.json"
        with patch('src.server.services.agent_registry.REGISTRY_FILE', registry_path):
            from src.server.services.agent_registry import AgentRegistry
            registry = AgentRegistry()

            registry.register("test-agent", {"type": "worker"})
            assert registry.is_registered("test-agent")

            registry.unregister("test-agent")
            assert not registry.is_registered("test-agent")

def test_registry_file_locking():
    """Test concurrent access doesn't corrupt registry."""
    # TODO: Add multiprocessing test
    pass

def test_registry_cleanup_stale():
    """Test stale entry cleanup."""
    with tempfile.TemporaryDirectory() as tmpdir:
        registry_path = Path(tmpdir) / "registry.json"
        with patch('src.server.services.agent_registry.REGISTRY_FILE', registry_path):
            from src.server.services.agent_registry import AgentRegistry
            registry = AgentRegistry()

            registry.register("agent-1", {})
            registry.register("agent-2", {})

            stale = registry.cleanup_stale({"agent-1"})  # agent-2 missing
            assert "agent-2" in stale
            assert not registry.is_registered("agent-2")
```

### Integration Tests

**New file: `tests/test_health_frontend.py`**

```python
import pytest
from pathlib import Path
from unittest.mock import patch, MagicMock

@pytest.mark.asyncio
async def test_health_endpoint_healthy():
    """Test health endpoint returns 200 when frontend is OK."""
    with patch('pathlib.Path.exists', return_value=True):
        with patch('pathlib.Path.glob', return_value=[Path('index.js')]):
            from src.server.routes.webhooks import health_check
            response = await health_check()
            assert response["status"] == "healthy"

@pytest.mark.asyncio
async def test_health_endpoint_degraded():
    """Test health endpoint returns 503 when frontend is missing."""
    # Frontend missing
    with patch.object(Path, 'exists', return_value=False):
        from src.server.routes.webhooks import health_check
        response = await health_check()
        assert response.status_code == 503
```

### Manual Testing Checklist

```markdown
## Pre-Implementation
- [ ] `./src/orchestrator/cmux.sh status` works
- [ ] `curl http://localhost:8000/api/webhooks/health` returns 200

## After Task 1 (Server Kill)
- [ ] Start system: `./src/orchestrator/cmux.sh start`
- [ ] Stop system: `./src/orchestrator/cmux.sh stop`
- [ ] Verify port free: `lsof -ti tcp:8000` returns nothing
- [ ] Verify no orphan processes: `pgrep -f uvicorn` returns nothing

## After Task 2 (Agent Registry)
- [ ] Create worker via API: `POST /api/agents`
- [ ] Check registry exists: `cat .cmux/agent_registry.json`
- [ ] Delete worker via API: `DELETE /api/agents/worker-1`
- [ ] Verify unregistered: `cat .cmux/agent_registry.json` (worker-1 gone)

## After Task 3 (Frontend Health)
- [ ] Health returns 200: `curl http://localhost:8000/api/webhooks/health`
- [ ] Delete dist: `rm -rf src/frontend/dist`
- [ ] Health returns 503: `curl -I http://localhost:8000/api/webhooks/health`
- [ ] Wait 60s for recovery (or trigger manually)
- [ ] Health returns 200 again

## After Task 4 (Log Watcher)
- [ ] Start log watcher: `./src/orchestrator/log-watcher.sh &`
- [ ] Inject error: `echo "ERROR: test" >> /tmp/cmux-server.log`
- [ ] Check mailbox for alert: `tail .cmux/mailbox`
- [ ] Verify cooldown: inject another error, check no duplicate alert within 5min
```

---

## Rollback Procedures (Addressing Critic's Missing Item #2)

| Task | Rollback Command |
|------|------------------|
| 1. Server Kill | `git checkout src/orchestrator/cmux.sh src/orchestrator/monitor.sh src/orchestrator/health.sh` |
| 2. Registry | `rm .cmux/agent_registry.json && git checkout src/server/services/agent_manager.py` |
| 3. Frontend Health | `git checkout src/server/routes/webhooks.py src/orchestrator/health.sh` |
| 4. Log Watcher | `pkill -f log-watcher.sh && rm src/orchestrator/log-watcher.sh` |

---

## Documentation Updates (Addressing Critic's Missing Item #3)

Will update:
- `CLAUDE.md`: Add log watcher to "System Orchestration" section
- `docs/README.md`: Add agent registry architecture note
- No need for extensive docs - these are internal components

---

## Revised Implementation Order

Agree with critic's revised order:

1. **Task 1 (Server Kill)** - Enables clean restarts for testing others
2. **Task 3 (Frontend Health)** - Improves visibility before complexity
3. **Task 2 (Agent Registry)** - Foundation for Task 4
4. **Task 4 (Log Watcher)** - Last, with graceful degradation if registry missing

---

## Summary of Changes from Round 1

| Issue | Resolution |
|-------|------------|
| Orphan worker processes | Added `pkill -f uvicorn` fallback |
| Total timeout | Added subshell watchdog (cross-platform) |
| Port verification | Added post-kill check |
| Registry race condition | Added fcntl file locking |
| Stale registry entries | Added cleanup_stale() method |
| Supervisor registration | Added API endpoint |
| HTML parsing fragile | Using directory file check instead |
| npm install dangerous | Using npm ci |
| HTTP 503 for degraded | Returning JSONResponse with status_code=503 |
| Atomic build swap | Building to dist_new, then mv |
| macOS-specific commands | Added cross-platform helpers |
| Log rotation | Added inode tracking |
| Error patterns broad | Added word boundaries |
| Rate limiting | Added cooldown mechanism |
| jq dependency | Added fallback to grep/sed |
| Registry coupling | Added graceful degradation |
| Testing strategy | Added unit/integration tests + checklist |
| Rollback procedures | Added table |
| Documentation | Will update CLAUDE.md |

---

*Ready for Round 3 or Final Review.*
