#!/usr/bin/env bash
#═══════════════════════════════════════════════════════════════════════════════
# CMUX MONITOR - Control Center (Window 0)
#
# This script runs inside tmux Window 0 and:
#   1. Starts the FastAPI server
#   2. Launches supervisor agent
#   3. Runs message router in background
#   4. Provides health monitoring dashboard
#═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/tmux.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# Configuration
CMUX_SESSION="${CMUX_SESSION:-cmux}"
CMUX_PORT="${CMUX_PORT:-8000}"
CMUX_HOST="${CMUX_HOST:-0.0.0.0}"
CMUX_MAILBOX="${CMUX_MAILBOX:-.cmux/mailbox}"
CMUX_PROJECT_ROOT="${CMUX_PROJECT_ROOT:-$(pwd)}"
ROUTER_LOG=".cmux/router.log"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

#───────────────────────────────────────────────────────────────────────────────
# Banner & Display
#───────────────────────────────────────────────────────────────────────────────

print_banner() {
    clear
    printf "${CYAN}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════════════╗
    ║                    CMUX CONTROL CENTER                            ║
    ╚═══════════════════════════════════════════════════════════════════╝
EOF
    printf "${NC}"
    echo ""
    printf "  Project: ${BOLD}%s${NC}\n" "$(basename "$CMUX_PROJECT_ROOT")"
    printf "  Path:    ${DIM}%s${NC}\n" "$CMUX_PROJECT_ROOT"
    printf "  Server:  ${DIM}http://${CMUX_HOST}:${CMUX_PORT}${NC}\n"
    echo ""
}

print_separator() {
    printf "${DIM}─────────────────────────────────────────────────────────────────${NC}\n"
}

log_step() {
    printf "${CYAN}▶${NC} $1\n"
}

log_ok() {
    printf "${GREEN}✓${NC} $1\n"
}

log_warn() {
    printf "${YELLOW}!${NC} $1\n"
}

log_fail() {
    printf "${RED}✗${NC} $1\n"
}

#───────────────────────────────────────────────────────────────────────────────
# Server Management
#───────────────────────────────────────────────────────────────────────────────

is_server_running() {
    curl -sf "http://localhost:${CMUX_PORT}/api/webhooks/health" >/dev/null 2>&1
}

start_server() {
    if is_server_running; then
        log_ok "FastAPI server already running (port ${CMUX_PORT})"
        return 0
    fi

    log_step "Starting FastAPI server..."

    # Build frontend if needed
    if [[ ! -d "${CMUX_PROJECT_ROOT}/src/frontend/dist" ]]; then
        log_step "Building frontend..."
        (cd "${CMUX_PROJECT_ROOT}/src/frontend" && npm install && npm run build) || {
            log_fail "Frontend build failed"
            return 1
        }
    fi

    # Start server with nohup
    cd "$CMUX_PROJECT_ROOT"
    nohup uv run uvicorn src.server.main:app \
        --host "$CMUX_HOST" \
        --port "$CMUX_PORT" \
        --ws-ping-interval 30 \
        --ws-ping-timeout 60 \
        > /tmp/cmux-server.log 2>&1 &

    # Wait for server to be ready
    local retries=30
    while ! is_server_running && ((retries-- > 0)); do
        sleep 1
    done

    if is_server_running; then
        log_ok "FastAPI server started (port ${CMUX_PORT})"
        return 0
    else
        log_fail "Failed to start FastAPI server"
        return 1
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Supervisor Agent
#───────────────────────────────────────────────────────────────────────────────

launch_supervisor() {
    if tmux_window_exists "$CMUX_SESSION" "supervisor"; then
        log_ok "Supervisor agent already running"
        return 0
    fi

    log_step "Launching supervisor agent..."

    tmux_create_window "$CMUX_SESSION" "supervisor"
    tmux_send_keys "$CMUX_SESSION" "supervisor" "export CMUX_AGENT=true CMUX_AGENT_NAME=supervisor && cd ${CMUX_PROJECT_ROOT} && claude --dangerously-skip-permissions"

    # Lock window name
    tmux set-option -t "${CMUX_SESSION}:supervisor" allow-rename off 2>/dev/null || true

    # Wait for Claude to initialize (look for the prompt indicator)
    log_step "Waiting for Claude to initialize..."
    local retries=30
    while ! tmux capture-pane -t "${CMUX_SESSION}:supervisor" -p | grep -qE "^❯|bypass permissions"; do
        sleep 1
        ((retries--)) || break
        if ((retries <= 0)); then
            log_warn "Claude startup timeout, sending instructions anyway"
            break
        fi
    done
    sleep 1  # Extra buffer after prompt appears

    # Disable vim mode if enabled (for reliable message delivery)
    if tmux capture-pane -t "${CMUX_SESSION}:supervisor" -p | grep -qE "\-\- (INSERT|NORMAL|VISUAL) \-\-"; then
        log_step "Disabling vim mode..."
        tmux_send_keys "$CMUX_SESSION" "supervisor" "/vim"
        sleep 1
    fi

    # Register supervisor via API
    curl -sf -X POST "http://localhost:${CMUX_PORT}/api/agents/register" \
        -H "Content-Type: application/json" \
        -d '{"agent_id": "supervisor", "agent_type": "supervisor", "created_by": "monitor.sh"}' \
        >/dev/null 2>&1 || log_warn "Failed to register supervisor"

    # Build startup instruction with journal context
    log_step "Sending role instructions..."
    local startup_instruction="Read docs/SUPERVISOR_ROLE.md to understand your role as the CMUX supervisor agent. This file contains your instructions for managing workers, using the journal system, and coordinating tasks."

    # Find the most recent journal and include it for continuity
    local latest_journal=""
    latest_journal=$(find .cmux/journal -name "journal.md" -type f 2>/dev/null | sort -r | head -1)
    if [[ -n "$latest_journal" ]]; then
        local journal_date
        journal_date=$(basename "$(dirname "$latest_journal")")
        startup_instruction="${startup_instruction} Then read ${latest_journal} to catch up on recent activity from ${journal_date}."
    fi

    tmux_send_keys "$CMUX_SESSION" "supervisor" "$startup_instruction"

    log_ok "Supervisor agent launched"
}

#───────────────────────────────────────────────────────────────────────────────
# Message Router (runs in background)
#───────────────────────────────────────────────────────────────────────────────

# Router is now external: src/orchestrator/router.sh
# This function starts the external router daemon

start_router() {
    if [[ -n "${ROUTER_PID:-}" ]] && kill -0 "$ROUTER_PID" 2>/dev/null; then
        return 0  # Already running
    fi

    log_step "Starting message router..."
    "${SCRIPT_DIR}/router.sh" &
    ROUTER_PID=$!
    log_ok "Message router started (PID: $ROUTER_PID)"
}

#───────────────────────────────────────────────────────────────────────────────
# Log Watcher (runs in background)
#───────────────────────────────────────────────────────────────────────────────

start_log_watcher() {
    if [[ -n "${LOG_WATCHER_PID:-}" ]] && kill -0 "$LOG_WATCHER_PID" 2>/dev/null; then
        return 0  # Already running
    fi

    log_step "Starting log watcher..."
    "${SCRIPT_DIR}/log-watcher.sh" &
    LOG_WATCHER_PID=$!
    log_ok "Log watcher started (PID: $LOG_WATCHER_PID)"
}

#───────────────────────────────────────────────────────────────────────────────
# Journal Nudge Daemon (runs in background)
#───────────────────────────────────────────────────────────────────────────────

start_journal_nudge() {
    if [[ -n "${JOURNAL_NUDGE_PID:-}" ]] && kill -0 "$JOURNAL_NUDGE_PID" 2>/dev/null; then
        return 0  # Already running
    fi

    log_step "Starting journal nudge daemon..."
    "${SCRIPT_DIR}/journal-nudge.sh" &
    JOURNAL_NUDGE_PID=$!
    log_ok "Journal nudge daemon started (PID: $JOURNAL_NUDGE_PID)"
}

#───────────────────────────────────────────────────────────────────────────────
# Compact Daemon (runs in background)
#───────────────────────────────────────────────────────────────────────────────

start_compact() {
    if [[ -n "${COMPACT_PID:-}" ]] && kill -0 "$COMPACT_PID" 2>/dev/null; then
        return 0  # Already running
    fi

    log_step "Starting compact daemon..."
    "${SCRIPT_DIR}/compact.sh" &
    COMPACT_PID=$!
    log_ok "Compact daemon started (PID: $COMPACT_PID)"
}

#───────────────────────────────────────────────────────────────────────────────
# Supervisor Heartbeat Monitor
#───────────────────────────────────────────────────────────────────────────────

SUPERVISOR_HEARTBEAT_FILE="${CMUX_HEARTBEAT_FILE:-.cmux/.supervisor-heartbeat}"
HEARTBEAT_WARN_THRESHOLD=${CMUX_HEARTBEAT_WARN:-600}    # seconds before warning (env: CMUX_HEARTBEAT_WARN)
HEARTBEAT_PING_THRESHOLD=${CMUX_HEARTBEAT_PING:-900}    # seconds before sending ping (env: CMUX_HEARTBEAT_PING)
HEARTBEAT_KILL_WAIT=${CMUX_HEARTBEAT_KILL:-300}          # seconds after ping before kill/respawn (env: CMUX_HEARTBEAT_KILL)
HEARTBEAT_PING_SENT_AT=0        # timestamp when ping was sent (0 = not sent)

# Sentry agent state
SENTRY_ACTIVE=${SENTRY_ACTIVE:-false}
SENTRY_ACTIVE_FILE="${SENTRY_ACTIVE_FILE:-.cmux/.sentry-active}"
SENTRY_TIMEOUT=${SENTRY_TIMEOUT:-300}              # seconds before force-killing sentry
SENTRY_STARTED_AT=${SENTRY_STARTED_AT:-0}           # timestamp when sentry was spawned

check_supervisor_heartbeat() {
    # Only check if supervisor window exists
    if ! tmux_window_exists "$CMUX_SESSION" "supervisor"; then
        return
    fi

    # If no heartbeat file yet, supervisor may still be starting up
    if [[ ! -f "$SUPERVISOR_HEARTBEAT_FILE" ]]; then
        printf "  Heartbeat:  ${DIM}●${NC} waiting for first heartbeat\n"
        return
    fi

    local now last_beat staleness
    now=$(date +%s)
    last_beat=$(cat "$SUPERVISOR_HEARTBEAT_FILE" 2>/dev/null || echo 0)

    # Guard against empty or non-numeric content
    if ! [[ "$last_beat" =~ ^[0-9]+$ ]]; then
        printf "  Heartbeat:  ${YELLOW}●${NC} invalid heartbeat data\n"
        return
    fi

    staleness=$((now - last_beat))

    if ((staleness < HEARTBEAT_WARN_THRESHOLD)); then
        # Healthy
        printf "  Heartbeat:  ${GREEN}●${NC} ${staleness}s ago\n"
        HEARTBEAT_PING_SENT_AT=0
        return
    fi

    if ((staleness < HEARTBEAT_PING_THRESHOLD)); then
        # Warning zone
        printf "  Heartbeat:  ${YELLOW}●${NC} stale (${staleness}s ago)\n"
        HEARTBEAT_PING_SENT_AT=0
        return
    fi

    # Past ping threshold
    if ((HEARTBEAT_PING_SENT_AT == 0)); then
        # Send ping to supervisor
        printf "  Heartbeat:  ${RED}●${NC} stale (${staleness}s) - sending ping\n"
        tmux_send_keys "$CMUX_SESSION" "supervisor" "Are you still there? Please respond with a status update."
        HEARTBEAT_PING_SENT_AT=$now
        return
    fi

    # Ping was already sent - check if enough time has passed
    local since_ping=$((now - HEARTBEAT_PING_SENT_AT))
    if ((since_ping < HEARTBEAT_KILL_WAIT)); then
        printf "  Heartbeat:  ${RED}●${NC} stale (${staleness}s) - waiting for ping response (${since_ping}s/${HEARTBEAT_KILL_WAIT}s)\n"
        return
    fi

    # Still no heartbeat after ping + wait - spawn sentry for smart recovery
    printf "  Heartbeat:  ${RED}●${NC} supervisor unresponsive (${staleness}s) - spawning sentry\n"
    log_warn "Supervisor heartbeat expired after ping. Spawning sentry agent..."
    spawn_sentry
}

#───────────────────────────────────────────────────────────────────────────────
# Sentry Agent - Smart Supervisor Recovery
#───────────────────────────────────────────────────────────────────────────────

spawn_sentry() {
    # Prevent double-spawn
    if [[ "$SENTRY_ACTIVE" == "true" ]] || tmux_window_exists "$CMUX_SESSION" "sentry"; then
        log_warn "Sentry already active, skipping spawn"
        return
    fi

    log_step "Spawning sentry agent for supervisor recovery..."

    # Capture supervisor terminal state before anything else
    local supervisor_output=""
    if tmux_window_exists "$CMUX_SESSION" "supervisor"; then
        supervisor_output=$(tmux_capture_pane "$CMUX_SESSION" "supervisor" 100 2>/dev/null || echo "(could not capture)")
    fi

    # Gather context: recent journal
    local journal_context=""
    local latest_journal=""
    latest_journal=$(find .cmux/journal -name "journal.md" -type f 2>/dev/null | sort -r | head -1)
    if [[ -n "$latest_journal" ]]; then
        journal_context=$(tail -50 "$latest_journal" 2>/dev/null || echo "(empty)")
    fi

    # Gather context: recent mailbox
    local mailbox_context=""
    if [[ -f "$CMUX_MAILBOX" ]]; then
        mailbox_context=$(tail -10 "$CMUX_MAILBOX" 2>/dev/null || echo "(empty)")
    fi

    # Timestamps for the report
    local now last_beat staleness
    now=$(date +%s)
    last_beat=$(cat "$SUPERVISOR_HEARTBEAT_FILE" 2>/dev/null || echo 0)
    if [[ "$last_beat" =~ ^[0-9]+$ ]]; then
        staleness=$((now - last_beat))
    else
        staleness="unknown"
    fi
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Write dynamic context file for the sentry agent
    local context_file=".cmux/worker-contexts/sentry-context.md"
    mkdir -p "$(dirname "$context_file")"
    cat > "$context_file" << SENTRY_EOF
# Sentry Agent Context

You are the **sentry** agent. Your mission is to recover a stuck supervisor agent.

## Situation Report

- **Timestamp**: ${timestamp}
- **Heartbeat staleness**: ${staleness}s (threshold was ${HEARTBEAT_PING_THRESHOLD}s + ${HEARTBEAT_KILL_WAIT}s ping wait)
- **Lockfile**: ${SENTRY_ACTIVE_FILE}

## Supervisor Terminal Output (last 100 lines)

\`\`\`
${supervisor_output}
\`\`\`

## Recent Journal (last 50 lines)

\`\`\`
${journal_context}
\`\`\`

## Recent Mailbox (last 10 lines)

\`\`\`
${mailbox_context}
\`\`\`

## Recovery Procedure

Execute these steps in order. Use Bash tool for all commands.

### Step 1: Try /compact on the stuck supervisor

\`\`\`bash
tmux send-keys -t "${CMUX_SESSION}:supervisor" "/compact" Enter
\`\`\`

Then wait 30 seconds:

\`\`\`bash
sleep 30
\`\`\`

### Step 2: Check if heartbeat recovered

\`\`\`bash
now=\$(date +%s)
beat=\$(cat ${SUPERVISOR_HEARTBEAT_FILE} 2>/dev/null || echo 0)
age=\$((now - beat))
echo "Heartbeat age: \${age}s"
\`\`\`

If age < 120, the supervisor recovered! Skip to Step 5.

### Step 3: Kill the stuck supervisor (only if Step 2 shows still stale)

\`\`\`bash
tmux kill-window -t "${CMUX_SESSION}:supervisor" 2>/dev/null || true
rm -f "${SUPERVISOR_HEARTBEAT_FILE}"
echo "awaiting-supervisor" > "${SENTRY_ACTIVE_FILE}"
\`\`\`

### Step 4: Wait for new supervisor

monitor.sh will relaunch the supervisor when it sees "awaiting-supervisor" in the lockfile.
Poll until the new supervisor window exists and has a fresh heartbeat:

\`\`\`bash
for i in \$(seq 1 60); do
    if tmux list-windows -t "${CMUX_SESSION}" -F "#{window_name}" 2>/dev/null | grep -qxF "supervisor"; then
        beat=\$(cat ${SUPERVISOR_HEARTBEAT_FILE} 2>/dev/null || echo 0)
        now=\$(date +%s)
        age=\$((now - beat))
        if [ "\$age" -lt 120 ]; then
            echo "New supervisor is alive (heartbeat \${age}s ago)"
            break
        fi
    fi
    echo "Waiting for new supervisor... (\${i}/60)"
    sleep 5
done
\`\`\`

### Step 5: Brief the new supervisor

Send a message explaining what happened:

\`\`\`bash
tmux send-keys -t "${CMUX_SESSION}:supervisor" -l "SENTRY BRIEFING: The previous supervisor became unresponsive (heartbeat stale for ${staleness}s at ${timestamp}). Recovery was performed. Check the journal for details. Resume normal operations."
sleep 0.2
tmux send-keys -t "${CMUX_SESSION}:supervisor" Enter
\`\`\`

### Step 6: Journal the incident

\`\`\`bash
curl -sf -X POST "http://localhost:${CMUX_PORT}/api/journal/entry" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Sentry: Supervisor recovery at ${timestamp}",
    "content": "## Incident\\nSupervisor heartbeat was stale for ${staleness}s.\\n\\n## Action taken\\nSentry agent performed recovery procedure.\\n\\n## Outcome\\nNew supervisor launched and briefed.",
    "tags": ["sentry", "recovery", "supervisor"]
  }'
\`\`\`

### Step 7: Self-terminate

\`\`\`bash
rm -f "${SENTRY_ACTIVE_FILE}"
tmux kill-window -t "${CMUX_SESSION}:sentry"
\`\`\`

**IMPORTANT**: Execute all steps using the Bash tool. Do NOT skip the self-terminate step.
SENTRY_EOF

    # Create sentry tmux window and start Claude
    tmux_create_window "$CMUX_SESSION" "sentry"
    tmux_send_keys "$CMUX_SESSION" "sentry" "export CMUX_AGENT=true CMUX_AGENT_NAME=sentry && cd ${CMUX_PROJECT_ROOT} && claude --dangerously-skip-permissions"

    # Lock window name
    tmux set-option -t "${CMUX_SESSION}:sentry" allow-rename off 2>/dev/null || true

    # Wait for Claude to initialize
    local retries=30
    while ! tmux capture-pane -t "${CMUX_SESSION}:sentry" -p 2>/dev/null | grep -qE "^❯|bypass permissions"; do
        sleep 1
        ((retries--)) || break
        if ((retries <= 0)); then
            log_warn "Sentry Claude startup timeout, sending instructions anyway"
            break
        fi
    done
    sleep 1

    # Send the context reference
    tmux_send_keys "$CMUX_SESSION" "sentry" "Read ${context_file} and execute the recovery procedure described in it. Follow every step exactly."

    # Write lockfile and update state
    echo "blocking" > "$SENTRY_ACTIVE_FILE"
    SENTRY_ACTIVE=true
    SENTRY_STARTED_AT=$(date +%s)
    HEARTBEAT_PING_SENT_AT=0

    log_ok "Sentry agent spawned"
}

#───────────────────────────────────────────────────────────────────────────────
# Health Monitor Dashboard
#───────────────────────────────────────────────────────────────────────────────

HEALTH_FAILURES=0
MAX_FAILURES=3
LAST_CTRL_C=0
CLEANUP_DONE=false

cleanup() {
    # Prevent running cleanup twice
    [[ "$CLEANUP_DONE" == "true" ]] && return
    CLEANUP_DONE=true

    printf "${RED}Cleaning up...${NC}\n"

    # Kill router background process
    if [[ -n "${ROUTER_PID:-}" ]]; then
        kill "$ROUTER_PID" 2>/dev/null && printf "  ${GREEN}✓${NC} Router stopped\n"
    fi

    # Kill log watcher background process
    if [[ -n "${LOG_WATCHER_PID:-}" ]]; then
        kill "$LOG_WATCHER_PID" 2>/dev/null && printf "  ${GREEN}✓${NC} Log watcher stopped\n"
    fi

    # Kill journal nudge daemon
    if [[ -n "${JOURNAL_NUDGE_PID:-}" ]]; then
        kill "$JOURNAL_NUDGE_PID" 2>/dev/null && printf "  ${GREEN}✓${NC} Journal nudge stopped\n"
    fi

    # Kill compact daemon
    if [[ -n "${COMPACT_PID:-}" ]]; then
        kill "$COMPACT_PID" 2>/dev/null && printf "  ${GREEN}✓${NC} Compact daemon stopped\n"
    fi

    # Kill sentry agent and clean up lockfile
    if tmux_window_exists "$CMUX_SESSION" "sentry" 2>/dev/null; then
        tmux_kill_window "$CMUX_SESSION" "sentry"
        printf "  ${GREEN}✓${NC} Sentry agent stopped\n"
    fi
    rm -f "$SENTRY_ACTIVE_FILE"

    # Kill FastAPI server with SIGTERM → SIGKILL escalation
    local pids
    pids=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        # SIGTERM first
        for pid in $pids; do
            kill "$pid" 2>/dev/null && printf "  ${GREEN}✓${NC} Sent SIGTERM to PID $pid\n"
        done

        # Wait up to 3 seconds for graceful shutdown
        local wait_count=0
        while lsof -ti tcp:"$CMUX_PORT" >/dev/null 2>&1 && ((wait_count < 3)); do
            sleep 1
            ((wait_count++))
        done

        # SIGKILL any remaining
        pids=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            for pid in $pids; do
                kill -9 "$pid" 2>/dev/null && printf "  ${YELLOW}!${NC} Force killed PID $pid\n"
            done
        fi
    fi

    # Fallback: kill by process name
    pkill -f "uvicorn.*src.server.main:app" 2>/dev/null || true

    # Verify port is free
    sleep 1
    if lsof -ti tcp:"$CMUX_PORT" >/dev/null 2>&1; then
        printf "  ${YELLOW}!${NC} Port $CMUX_PORT still in use\n"
    else
        printf "  ${GREEN}✓${NC} FastAPI server stopped\n"
    fi

    # Kill only THIS cmux session (not other cmux-* sessions from different instances)
    # This prevents accidentally destroying workers from parallel cmux runs
    if tmux has-session -t "$CMUX_SESSION" 2>/dev/null; then
        tmux kill-session -t "$CMUX_SESSION" 2>/dev/null && printf "  ${GREEN}✓${NC} Killed session: $CMUX_SESSION\n"
    fi

    printf "${GREEN}Shutdown complete${NC}\n"
}

handle_exit() {
    local now
    now=$(date +%s)
    if ((now - LAST_CTRL_C < 3)); then
        echo ""
        cleanup
        exit 0
    else
        LAST_CTRL_C=$now
        echo ""
        printf "${YELLOW}Press Ctrl+C again within 3s to quit${NC}\n"
        printf "${DIM}Agents keep running. Re-attach: tmux attach -t $CMUX_SESSION${NC}\n"
        sleep 1
    fi
}

# Cleanup on any exit (error, TERM, HUP)
trap cleanup EXIT TERM HUP

run_dashboard() {
    trap handle_exit INT

    while true; do
        print_banner

        printf "${DIM}$(date '+%Y-%m-%d %H:%M:%S')${NC}  "
        printf "${DIM}Ctrl+C twice to quit${NC}\n"
        echo ""

        # Server health
        printf "${BOLD}Services:${NC}\n"
        if is_server_running; then
            printf "  FastAPI:    ${GREEN}●${NC} running (port ${CMUX_PORT})\n"
            HEALTH_FAILURES=0
        else
            ((HEALTH_FAILURES++))
            printf "  FastAPI:    ${RED}●${NC} down (failures: ${HEALTH_FAILURES}/${MAX_FAILURES})\n"

            if ((HEALTH_FAILURES >= MAX_FAILURES)); then
                printf "\n${RED}Server unresponsive, attempting recovery...${NC}\n"
                attempt_recovery
            fi
        fi

        # Router status - restart if dead
        if [[ -n "${ROUTER_PID:-}" ]] && kill -0 "$ROUTER_PID" 2>/dev/null; then
            printf "  Router:     ${GREEN}●${NC} running (PID: ${ROUTER_PID})\n"
        else
            printf "  Router:     ${YELLOW}●${NC} restarting...\n"
            start_router
        fi

        # Journal nudge status - restart if dead
        if [[ -n "${JOURNAL_NUDGE_PID:-}" ]] && kill -0 "$JOURNAL_NUDGE_PID" 2>/dev/null; then
            printf "  J-Nudge:    ${GREEN}●${NC} running (PID: ${JOURNAL_NUDGE_PID})\n"
        else
            printf "  J-Nudge:    ${YELLOW}●${NC} restarting...\n"
            start_journal_nudge
        fi

        # Compact daemon status - restart if dead
        if [[ -n "${COMPACT_PID:-}" ]] && kill -0 "$COMPACT_PID" 2>/dev/null; then
            printf "  Compact:    ${GREEN}●${NC} running (PID: ${COMPACT_PID})\n"
        else
            printf "  Compact:    ${YELLOW}●${NC} restarting...\n"
            start_compact
        fi

        # Sentry status - sync from lockfile before checking
        if [[ -f "$SENTRY_ACTIVE_FILE" ]]; then
            SENTRY_ACTIVE=true
        else
            SENTRY_ACTIVE=false
        fi

        if [[ "$SENTRY_ACTIVE" == "true" ]] || tmux_window_exists "$CMUX_SESSION" "sentry"; then
            if tmux_window_exists "$CMUX_SESSION" "sentry"; then
                local sentry_age=0
                if ((SENTRY_STARTED_AT > 0)); then
                    sentry_age=$(( $(date +%s) - SENTRY_STARTED_AT ))
                fi
                printf "  Sentry:     ${YELLOW}●${NC} active (${sentry_age}s)\n"

                # Timeout safety net
                if ((sentry_age > SENTRY_TIMEOUT)); then
                    log_warn "Sentry timed out after ${SENTRY_TIMEOUT}s, force-killing"
                    tmux_kill_window "$CMUX_SESSION" "sentry"
                    rm -f "$SENTRY_ACTIVE_FILE"
                    SENTRY_ACTIVE=false
                    SENTRY_STARTED_AT=0
                fi
            else
                # Sentry window gone — clear state
                printf "  Sentry:     ${DIM}●${NC} completed\n"
                SENTRY_ACTIVE=false
                SENTRY_STARTED_AT=0
                rm -f "$SENTRY_ACTIVE_FILE"
            fi
        else
            printf "  Sentry:     ${DIM}●${NC} inactive\n"
        fi

        # Supervisor status with sentry-aware auto-relaunch
        if tmux_window_exists "$CMUX_SESSION" "supervisor"; then
            printf "  Supervisor: ${GREEN}●${NC} running\n"
        else
            local lockfile_phase=""
            if [[ -f "$SENTRY_ACTIVE_FILE" ]]; then
                lockfile_phase=$(cat "$SENTRY_ACTIVE_FILE" 2>/dev/null || echo "")
            fi

            if [[ "$lockfile_phase" == "blocking" ]]; then
                printf "  Supervisor: ${YELLOW}●${NC} sentry handling recovery\n"
            else
                printf "  Supervisor: ${YELLOW}●${NC} relaunching...\n"
                launch_supervisor
            fi
        fi

        # Supervisor heartbeat check (skip while sentry is active)
        if [[ "$SENTRY_ACTIVE" != "true" ]]; then
            check_supervisor_heartbeat
        fi

        echo ""

        # Recent mailbox activity
        printf "${BOLD}Recent Messages:${NC}\n"
        if [[ -f "$ROUTER_LOG" ]]; then
            tail -5 "$ROUTER_LOG" 2>/dev/null | while read -r line; do
                printf "  ${DIM}%s${NC}\n" "$line"
            done
        else
            printf "  ${DIM}(none)${NC}\n"
        fi

        echo ""
        print_separator
        printf "${DIM}Dashboard: http://localhost:${CMUX_PORT}${NC}\n"
        printf "${DIM}Ctrl+b n/p: switch windows | Ctrl+b d: detach${NC}\n"

        sleep 5
    done
}

attempt_recovery() {
    log_step "Attempting server restart..."

    # Kill existing server
    local pid
    pid=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null

    sleep 2

    # Try to restart
    if start_server; then
        log_ok "Recovery successful"
        HEALTH_FAILURES=0
    else
        log_fail "Recovery failed"

        # Git rollback if repeated failures
        if ((HEALTH_FAILURES >= MAX_FAILURES * 2)); then
            log_warn "Multiple failures, attempting git rollback..."
            git stash push -m "cmux-recovery-$(date +%s)" 2>/dev/null || true
            git checkout HEAD~1 2>/dev/null || true

            # Rebuild and restart
            (cd "${CMUX_PROJECT_ROOT}/src/frontend" && npm run build) 2>/dev/null || true
            start_server
        fi
    fi
}

#───────────────────────────────────────────────────────────────────────────────
# Main
#───────────────────────────────────────────────────────────────────────────────

main() {
    cd "$CMUX_PROJECT_ROOT"

    # Ensure directories exist
    mkdir -p "$(dirname "$CMUX_MAILBOX")"
    mkdir -p "$(dirname "$ROUTER_LOG")"

    # Clean up stale sentry lockfile (lockfile exists but no sentry window)
    if [[ -f "$SENTRY_ACTIVE_FILE" ]] && ! tmux_window_exists "$CMUX_SESSION" "sentry" 2>/dev/null; then
        rm -f "$SENTRY_ACTIVE_FILE"
    fi

    print_banner
    print_separator

    # Phase 1: Start server
    start_server || exit 1
    echo ""

    # Phase 2: Launch supervisor
    launch_supervisor
    echo ""

    # Phase 3: Start router in background
    start_router
    echo ""

    # Phase 4: Start log watcher in background
    start_log_watcher
    echo ""

    # Phase 5: Start journal nudge daemon
    start_journal_nudge
    echo ""

    # Phase 6: Start compact daemon
    start_compact
    echo ""

    # Phase 7: Run health dashboard (foreground)
    log_ok "Entering dashboard mode..."
    sleep 2
    run_dashboard
}

main
