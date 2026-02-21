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
    # Verify the response is actually CMUX, not just any server on the port.
    # A rogue process binding to CMUX_PORT would pass a simple connectivity check.
    curl -sf "http://localhost:${CMUX_PORT}/api/webhooks/health" 2>/dev/null | grep -q '"api":"healthy"'
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
    tmux_send_keys "$CMUX_SESSION" "supervisor" "export CMUX_AGENT=true CMUX_AGENT_NAME=supervisor CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false && cd ${CMUX_PROJECT_ROOT} && claude --dangerously-skip-permissions"

    # Lock window name
    tmux set-option -t "${CMUX_SESSION}:supervisor" allow-rename off 2>/dev/null || true

    # Wait for Claude to initialize (look for the prompt indicator)
    log_step "Waiting for Claude to initialize..."
    local retries=30
    while [[ "$(tmux_pane_state "$CMUX_SESSION" "supervisor")" != "PROMPT" ]]; do
        sleep 1
        ((retries--)) || break
        if ((retries <= 0)); then
            log_warn "Claude startup timeout, sending instructions anyway"
            break
        fi
    done
    sleep 1  # Extra buffer after prompt appears

    # Disable vim mode if enabled (for reliable message delivery)
    if [[ "$(tmux_pane_state "$CMUX_SESSION" "supervisor")" == "VIM" ]]; then
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
    local startup_instruction="Read docs/SUPERVISOR_ROLE.md to understand your role as the CMUX supervisor agent. This file contains your instructions for managing workers, using the journal system, and coordinating tasks. IMPORTANT: Always prefix system-level responses (heartbeat replies, compaction recovery, idle status, status confirmations) with [SYS] so they render as compact notifications in the dashboard."

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

start_compact_daemon() {
    if [[ -n "${COMPACT_PID:-}" ]] && kill -0 "$COMPACT_PID" 2>/dev/null; then
        return 0  # Already running
    fi

    log_step "Starting compact daemon..."
    "${SCRIPT_DIR}/compact.sh" &
    COMPACT_PID=$!
    log_ok "Compact daemon started (PID: $COMPACT_PID)"
}

#───────────────────────────────────────────────────────────────────────────────
# Project Supervisor Management
#───────────────────────────────────────────────────────────────────────────────

# Check if a window name is a project supervisor (sup-*)
is_project_supervisor_name() {
    [[ "$1" == sup-* ]]
}

# Check if a window name is any kind of supervisor (main or project)
is_any_supervisor_name() {
    [[ "$1" == "supervisor" ]] || [[ "$1" == sup-* ]]
}

# Launch project supervisors for all active, non-self projects
launch_project_supervisors() {
    local registry="${CMUX_PROJECT_ROOT}/.cmux/projects.json"
    if [[ ! -f "$registry" ]]; then
        return 0
    fi

    local active_projects
    active_projects=$(jq -r '.projects[] | select(.active == true and .is_self == false) | .id' "$registry" 2>/dev/null || true)

    if [[ -z "$active_projects" ]]; then
        return 0
    fi

    log_step "Starting project supervisors..."
    local count=0

    while IFS= read -r project_id; do
        [[ -z "$project_id" ]] && continue
        local sup_name="sup-${project_id}"

        if tmux_window_exists "$CMUX_SESSION" "$sup_name"; then
            log_ok "Project supervisor '$sup_name' already running"
            continue
        fi

        log_step "Activating project supervisor: $project_id"
        # Use tools/projects activate which handles the full lifecycle
        "${CMUX_PROJECT_ROOT}/tools/projects" activate "$project_id" || {
            log_warn "Failed to activate project: $project_id"
            continue
        }
        ((count++))
    done <<< "$active_projects"

    if ((count > 0)); then
        log_ok "Started $count project supervisor(s)"
    fi
}

# Check heartbeats for all project supervisors
check_project_supervisor_heartbeats() {
    local registry="${CMUX_PROJECT_ROOT}/.cmux/projects.json"
    if [[ ! -f "$registry" ]]; then
        return 0
    fi

    local active_projects
    active_projects=$(jq -r '.projects[] | select(.active == true and .is_self == false) | .id' "$registry" 2>/dev/null || true)

    if [[ -z "$active_projects" ]]; then
        return 0
    fi

    while IFS= read -r project_id; do
        [[ -z "$project_id" ]] && continue
        local sup_name="sup-${project_id}"

        if ! tmux_window_exists "$CMUX_SESSION" "$sup_name"; then
            printf "  %-12s ${RED}●${NC} down — relaunching...\n" "$sup_name:"
            "${CMUX_PROJECT_ROOT}/tools/projects" activate "$project_id" 2>/dev/null || true
            continue
        fi

        local hb_file="${CMUX_PROJECT_ROOT}/.cmux/.${sup_name}-heartbeat"
        if [[ ! -f "$hb_file" ]]; then
            printf "  %-12s ${DIM}●${NC} waiting for first heartbeat\n" "$sup_name:"
            continue
        fi

        local now last_beat staleness
        now=$(date +%s)
        last_beat=$(cat "$hb_file" 2>/dev/null || echo 0)
        if ! [[ "$last_beat" =~ ^[0-9]+$ ]]; then
            printf "  %-12s ${YELLOW}●${NC} invalid heartbeat data\n" "$sup_name:"
            continue
        fi

        staleness=$((now - last_beat))

        if ((staleness < HEARTBEAT_WARN_THRESHOLD)); then
            printf "  %-12s ${GREEN}●${NC} ${staleness}s ago\n" "$sup_name:"
        elif ((staleness < HEARTBEAT_WARN_THRESHOLD * 2)); then
            printf "  %-12s ${YELLOW}●${NC} stale (${staleness}s)\n" "$sup_name:"
        else
            printf "  %-12s ${RED}●${NC} stale (${staleness}s) — consider restarting\n" "$sup_name:"
        fi
    done <<< "$active_projects"
}

#───────────────────────────────────────────────────────────────────────────────
# Supervisor Heartbeat Monitor
#───────────────────────────────────────────────────────────────────────────────

SUPERVISOR_HEARTBEAT_FILE="${CMUX_HEARTBEAT_FILE:-.cmux/.supervisor-heartbeat}"
HEARTBEAT_WARN_THRESHOLD=${CMUX_HEARTBEAT_WARN:-600}     # seconds idle before first nudge
HEARTBEAT_NUDGE_INTERVAL=${CMUX_HEARTBEAT_NUDGE:-120}    # cooldown seconds between nudges
HEARTBEAT_MAX_NUDGES=${CMUX_HEARTBEAT_MAX_NUDGES:-3}     # failed nudges before considering sentry
HEARTBEAT_OBSERVE_TIMEOUT=${CMUX_HEARTBEAT_OBSERVE_TIMEOUT:-1200}  # seconds of FROZEN output before escalating
NUDGE_COUNT=0               # how many consecutive nudges sent without heartbeat response
NUDGE_SENT_AT=0             # timestamp when last nudge was sent (0 = not sent)
TASK_INJECTED=0             # whether a task has been force-injected after nudges failed (0=no, 1=yes)
OBSERVE_STARTED_AT=0        # timestamp when observation mode began (0 = not observing)
OBSERVE_PANE_HASH=""         # md5 hash of last captured pane output during observation
OBSERVE_FROZEN_SINCE=0       # timestamp when pane output last changed (frozen timer starts here)

# Sentry agent state
SENTRY_ACTIVE=${SENTRY_ACTIVE:-false}
SENTRY_ACTIVE_FILE="${SENTRY_ACTIVE_FILE:-.cmux/.sentry-active}"
SENTRY_TIMEOUT=${SENTRY_TIMEOUT:-300}              # seconds before force-killing sentry
SENTRY_STARTED_AT=${SENTRY_STARTED_AT:-0}           # timestamp when sentry was spawned

# Reset all heartbeat escalation state
reset_heartbeat_state() {
    NUDGE_COUNT=0
    NUDGE_SENT_AT=0
    TASK_INJECTED=0
    OBSERVE_STARTED_AT=0
    OBSERVE_PANE_HASH=""
    OBSERVE_FROZEN_SINCE=0
}

# Capture a hash of a pane's last 20 lines for change detection
capture_pane_hash() {
    local session="${1:-$CMUX_SESSION}"
    local window="${2:-supervisor}"
    tmux_capture_pane "$session" "$window" 20 2>/dev/null | md5 -q 2>/dev/null \
        || tmux_capture_pane "$session" "$window" 20 2>/dev/null | md5sum 2>/dev/null | cut -d' ' -f1 \
        || echo ""
}

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

    # If heartbeat updated since we started nudging or observing, supervisor is active — reset
    if ((NUDGE_SENT_AT > 0 && last_beat > NUDGE_SENT_AT)) || \
       ((OBSERVE_STARTED_AT > 0 && last_beat > OBSERVE_STARTED_AT)); then
        reset_heartbeat_state
    fi

    if ((staleness < HEARTBEAT_WARN_THRESHOLD)); then
        # Healthy — active within threshold
        printf "  Heartbeat:  ${GREEN}●${NC} ${staleness}s ago\n"
        reset_heartbeat_state

        # POST healthy heartbeat with rich system stats
        local hb_supervisor="active (${staleness}s idle)"
        local hb_workers hb_mailbox hb_backlog hb_health hb_git
        hb_workers=$(tmux list-windows -t "$CMUX_SESSION" -F '#{window_name}' 2>/dev/null | grep -v -e '^supervisor$' -e '^monitor$' -e '^sup-' -e '^sentry$' | wc -l | xargs)
        hb_mailbox=$(grep -c '"status":"submitted"' "$CMUX_MAILBOX" 2>/dev/null || echo "0")
        hb_backlog=$(sqlite3 "${CMUX_PROJECT_ROOT}/.cmux/tasks.db" "SELECT COUNT(*) FROM tasks WHERE status='backlog';" 2>/dev/null || echo "0")
        hb_health=$(curl -sf --max-time 1 "http://localhost:${CMUX_PORT}/api/webhooks/health" 2>/dev/null | grep -q '"api":"healthy"' && echo "healthy" || echo "degraded")
        hb_git=$(git -C "$CMUX_PROJECT_ROOT" diff --stat HEAD 2>/dev/null | tail -1 | sed 's/^ *//')
        [[ -z "$hb_git" ]] && hb_git="clean"

        local hb_sections
        hb_sections=$(jq -n \
            --arg sup "$hb_supervisor" \
            --arg wrk "${hb_workers} active" \
            --arg mbx "${hb_mailbox} pending" \
            --arg blg "${hb_backlog} items" \
            --arg hlt "$hb_health" \
            --arg gt "$hb_git" \
            '{supervisor: $sup, workers: $wrk, mailbox: $mbx, backlog: $blg, health: $hlt, git: $gt}')

        curl -sf --max-time 2 -X POST "http://localhost:${CMUX_PORT}/api/heartbeat" \
            -H "Content-Type: application/json" \
            -d "{\"timestamp\": ${now}, \"sections\": ${hb_sections}, \"highest_priority\": null, \"all_clear\": true}" \
            >/dev/null 2>&1 || true
        return
    fi

    # ── Past warn threshold — supervisor has been quiet a while ──
    # Branch on whether supervisor is at prompt (idle) or mid-task (busy).

    if ! is_supervisor_at_prompt; then
        # ── MID-TASK PATH ──
        # Supervisor is actively working (not at prompt). Do NOT nudge or
        # interrupt. Enter observation mode and watch for recovery.
        # The timeout is PROGRESS-BASED: only frozen (unchanging) pane
        # output counts toward the timeout. Visible progress resets it.

        local current_hash
        current_hash=$(capture_pane_hash)

        if ((OBSERVE_STARTED_AT == 0)); then
            # Enter observation mode — snapshot initial pane state
            OBSERVE_STARTED_AT=$now
            OBSERVE_PANE_HASH="$current_hash"
            OBSERVE_FROZEN_SINCE=$now
            # Clear any prior nudge state — don't nudge a busy supervisor
            NUDGE_COUNT=0
            NUDGE_SENT_AT=0
            log_status "HEARTBEAT" "Supervisor mid-task (stale ${staleness}s, not at prompt), entering observation mode"
        fi

        # Check if pane output changed since last observation cycle
        if [[ -n "$current_hash" && "$current_hash" != "$OBSERVE_PANE_HASH" ]]; then
            # Output changed — supervisor is making progress, reset frozen timer
            OBSERVE_PANE_HASH="$current_hash"
            OBSERVE_FROZEN_SINCE=$now
            log_status "HEARTBEAT" "Supervisor making progress (pane output changed), resetting observation timer"
        fi

        local frozen_elapsed=$((now - OBSERVE_FROZEN_SINCE))
        local observe_total=$((now - OBSERVE_STARTED_AT))

        if ((frozen_elapsed < HEARTBEAT_OBSERVE_TIMEOUT)); then
            # Pane output still changing or hasn't been frozen long enough
            if ((frozen_elapsed == observe_total)); then
                # No progress detected since observation started
                printf "  Heartbeat:  ${CYAN}●${NC} mid-task (${staleness}s) - observing, frozen (${frozen_elapsed}s/${HEARTBEAT_OBSERVE_TIMEOUT}s)\n"
            else
                # Progress was detected at some point
                printf "  Heartbeat:  ${CYAN}●${NC} mid-task (${staleness}s) - observing (${observe_total}s total, frozen ${frozen_elapsed}s/${HEARTBEAT_OBSERVE_TIMEOUT}s)\n"
            fi
            return
        fi

        # Frozen timeout — pane unchanged for HEARTBEAT_OBSERVE_TIMEOUT seconds
        log_status "HEARTBEAT" "Observation frozen timeout (${frozen_elapsed}s, ${observe_total}s total) — pane unchanged, likely stuck"

        # Final liveness gate before sentry
        if is_supervisor_process_alive; then
            printf "  Heartbeat:  ${RED}●${NC} possibly stuck (${staleness}s, frozen ${frozen_elapsed}s) - no output change or heartbeat\n"
            log_warn "Supervisor possibly stuck: pane frozen ${frozen_elapsed}s, process alive but no heartbeat or output change. Spawning sentry."
        else
            printf "  Heartbeat:  ${RED}●${NC} supervisor dead (${staleness}s) - spawning sentry\n"
            log_warn "Supervisor process dead after ${frozen_elapsed}s frozen observation. Spawning sentry."
        fi

        reset_heartbeat_state
        spawn_sentry
        return
    fi

    # ── IDLE PATH ──
    # Supervisor IS at prompt. If we were observing (mid-task → finished), reset.

    if ((OBSERVE_STARTED_AT > 0)); then
        log_status "HEARTBEAT" "Supervisor returned to prompt after observation, task completed — resetting"
        reset_heartbeat_state
        printf "  Heartbeat:  ${GREEN}●${NC} ${staleness}s ago (task just completed)\n"
        return
    fi

    # Send productivity nudges to idle supervisor (cooldown: HEARTBEAT_NUDGE_INTERVAL)
    local since_nudge=$((now - NUDGE_SENT_AT))

    if ((NUDGE_SENT_AT > 0 && since_nudge < HEARTBEAT_NUDGE_INTERVAL)); then
        # Cooldown — don't send another nudge yet
        printf "  Heartbeat:  ${YELLOW}●${NC} idle (${staleness}s) - nudge cooldown (${since_nudge}s/${HEARTBEAT_NUDGE_INTERVAL}s)\n"
        return
    fi

    if ((NUDGE_COUNT < HEARTBEAT_MAX_NUDGES)); then
        ((NUDGE_COUNT++))
        NUDGE_SENT_AT=$now
        printf "  Heartbeat:  ${YELLOW}●${NC} idle (${staleness}s) - sending autonomy nudge (#${NUDGE_COUNT}/${HEARTBEAT_MAX_NUDGES})\n"
        log_status "HEARTBEAT" "Supervisor idle (${staleness}s), sending autonomy nudge #${NUDGE_COUNT}/${HEARTBEAT_MAX_NUDGES}"

        # Run autonomy-check for rich, structured scan results
        local autonomy_output=""
        local autonomy_tool="${CMUX_PROJECT_ROOT}/tools/autonomy-check"
        if [[ -x "$autonomy_tool" ]] && autonomy_output=$("$autonomy_tool" --summary 2>/dev/null); then
            # Format as a single-line-friendly [HEARTBEAT] message
            # The autonomy-check --summary output has one section per line + priority
            local nudge_msg
            nudge_msg=$(printf '[HEARTBEAT] Autonomy scan results (idle %ds): ' "$staleness")

            # Parse --summary lines into sections dict for API POST
            local hb_sections="{}"
            local hb_priority=""
            local hb_all_clear="false"
            while IFS= read -r scan_line; do
                [[ -z "$scan_line" ]] && continue
                if [[ "$scan_line" == "---" ]]; then
                    nudge_msg="${nudge_msg} | "
                    continue
                fi
                nudge_msg="${nudge_msg}  - ${scan_line}"
                # Parse "Section: value" lines into JSON sections
                if [[ "$scan_line" == *": "* ]]; then
                    local section_key section_val
                    section_key=$(echo "$scan_line" | cut -d: -f1 | tr '[:upper:]' '[:lower:]' | tr ' ' '_')
                    section_val=$(echo "$scan_line" | cut -d: -f2- | sed 's/^ *//')
                    # Escape JSON special chars
                    section_val=$(echo "$section_val" | sed 's/\\/\\\\/g; s/"/\\"/g')
                    hb_sections=$(echo "$hb_sections" | jq --arg k "$section_key" --arg v "$section_val" '. + {($k): $v}' 2>/dev/null || echo "$hb_sections")
                fi
                # Extract highest priority line
                if [[ "$scan_line" == "Highest priority:"* ]]; then
                    hb_priority=$(echo "$scan_line" | sed 's/^Highest priority: *//')
                fi
            done <<< "$autonomy_output"

            nudge_msg="${nudge_msg}  Act on the highest priority item."
            tmux_safe_send "$CMUX_SESSION" "supervisor" "$nudge_msg" --retry 2

            # POST heartbeat data to API (best-effort, 2s timeout)
            local hb_json
            hb_json=$(jq -n \
                --argjson ts "$now" \
                --argjson sections "$hb_sections" \
                --arg priority "$hb_priority" \
                --argjson all_clear "$hb_all_clear" \
                '{timestamp: $ts, sections: $sections, highest_priority: (if $priority == "" then null else $priority end), all_clear: $all_clear}' 2>/dev/null)
            if [[ -n "$hb_json" ]]; then
                curl -sf --max-time 2 -X POST "http://localhost:${CMUX_PORT}/api/heartbeat" \
                    -H "Content-Type: application/json" \
                    -d "$hb_json" >/dev/null 2>&1 || true
            fi
        else
            local today
            today=$(date +%Y-%m-%d)
            local reflection_path=".cmux/journal/${today}/reflection.md"
            tmux_safe_send "$CMUX_SESSION" "supervisor" "[HEARTBEAT] You have been idle for ${staleness}s with no tool activity. Check for pending work — mailbox, worker status, journal TODOs — or find proactive work to do." --retry 2

            # Second message: reference AMBITION.md for self-improvement work
            tmux_safe_send "$CMUX_SESSION" "supervisor" "[AMBITION] Read .cmux/AMBITION.md for your growth agenda. Pick an unchecked short-term goal, spawn a worker to investigate or implement it. Update the file with results. If all short-term goals are done, advance a long-term goal. Never just sit idle — improve something." --retry 2

            # POST all-clear heartbeat to API (best-effort, 2s timeout)
            curl -sf --max-time 2 -X POST "http://localhost:${CMUX_PORT}/api/heartbeat" \
                -H "Content-Type: application/json" \
                -d "{\"timestamp\": ${now}, \"sections\": {}, \"highest_priority\": null, \"all_clear\": true}" \
                >/dev/null 2>&1 || true
        fi
        return
    fi

    # All nudges exhausted — try task injection before sentry.
    # If we haven't injected a task yet, force one in and give another nudge cycle.
    if ((TASK_INJECTED == 0)) && is_supervisor_process_alive; then
        TASK_INJECTED=1
        local inject_msg=""

        # Query backlog for highest-priority pending item
        local backlog_row=""
        backlog_row=$(sqlite3 "${CMUX_PROJECT_ROOT}/.cmux/tasks.db" \
            "SELECT id, title FROM tasks WHERE status IN ('backlog','pending') ORDER BY priority LIMIT 1;" 2>/dev/null || true)

        if [[ -n "$backlog_row" ]]; then
            local task_id task_title
            task_id=$(echo "$backlog_row" | cut -d'|' -f1)
            task_title=$(echo "$backlog_row" | cut -d'|' -f2-)
            inject_msg="[TASK] ${task_title} (from backlog item ${task_id})"
        else
            local today
            today=$(date +%Y-%m-%d)
            inject_msg="[TASK] Read .cmux/journal/${today}/reflection.md and work through the next investigation item."
        fi

        printf "  Heartbeat:  ${YELLOW}●${NC} idle (${staleness}s) - injecting task after ${NUDGE_COUNT} failed nudges\n"
        log_status "HEARTBEAT" "Supervisor ignored ${NUDGE_COUNT} nudges, force-injecting task: ${inject_msg}"
        tmux_safe_send "$CMUX_SESSION" "supervisor" "$inject_msg" --retry 2

        # Reset nudge counter to give supervisor another cycle to respond to injected task
        NUDGE_COUNT=0
        NUDGE_SENT_AT=$now
        return
    fi

    # Task already injected and supervisor still idle — liveness check before sentry.
    if is_supervisor_process_alive; then
        printf "  Heartbeat:  ${YELLOW}●${NC} idle (${staleness}s) - alive at prompt after task injection + ${NUDGE_COUNT} nudges (not stuck)\n"
        log_status "HEARTBEAT" "Supervisor idle (${staleness}s) after task injection + ${NUDGE_COUNT} nudges, but process alive + at prompt — not stuck"
        # Full reset including TASK_INJECTED — start over
        reset_heartbeat_state
        return
    fi

    # Supervisor process is dead while at prompt — spawn sentry as last resort
    printf "  Heartbeat:  ${RED}●${NC} supervisor unresponsive (${staleness}s, ${NUDGE_COUNT} nudges failed, process dead) - spawning sentry\n"
    log_warn "Supervisor unresponsive after ${NUDGE_COUNT} nudges and process not found. Spawning sentry."
    reset_heartbeat_state
    spawn_sentry
}

#───────────────────────────────────────────────────────────────────────────────
# Supervisor Hybrid Liveness Helpers
#───────────────────────────────────────────────────────────────────────────────

# Check if a claude process is running inside the supervisor tmux pane.
# Gets the pane's shell PID, then walks its process tree for a claude process.
# Returns 0 if alive, 1 if dead.
is_supervisor_process_alive() {
    local pane_pid
    pane_pid=$(tmux list-panes -t "${CMUX_SESSION}:supervisor" -F '#{pane_pid}' 2>/dev/null) || return 1
    [[ -z "$pane_pid" ]] && return 1

    # Check if the pane PID or any descendant is a claude process
    # pgrep -P walks child processes; we also check the pane PID itself
    if pgrep -a "claude" -P "$pane_pid" >/dev/null 2>&1; then
        return 0
    fi

    # Also check grandchildren (claude may be a child of the shell which is
    # a child of the pane pid)
    local child_pids
    child_pids=$(pgrep -P "$pane_pid" 2>/dev/null) || return 1
    local cpid
    for cpid in $child_pids; do
        if pgrep -a "claude" -P "$cpid" >/dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

# Check if the supervisor pane is showing an idle prompt.
# Delegates to unified tmux_pane_state(). Returns 0 if at prompt, 1 if busy.
is_supervisor_at_prompt() {
    local state
    state=$(tmux_pane_state "$CMUX_SESSION" "supervisor")
    [[ "$state" == "PROMPT" ]]
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

    # Gather context: backlog items
    local backlog_context=""
    backlog_context=$(sqlite3 "${CMUX_PROJECT_ROOT}/.cmux/tasks.db" \
        "SELECT title FROM tasks WHERE status='backlog' ORDER BY priority LIMIT 3;" 2>/dev/null || echo "(no backlog)")
    [[ -z "$backlog_context" ]] && backlog_context="(no backlog items)"

    # Gather context: recent mailbox subjects
    local mailbox_subjects=""
    if [[ -f "$CMUX_MAILBOX" ]]; then
        mailbox_subjects=$(tail -5 "$CMUX_MAILBOX" 2>/dev/null | grep -o '"subject":"[^"]*"' | sed 's/"subject":"//;s/"$//' || echo "(empty)")
    fi
    [[ -z "$mailbox_subjects" ]] && mailbox_subjects="(no recent messages)"

    # Gather context: today's journal tail
    local today today_journal today_journal_tail today_reflection
    today=$(date +%Y-%m-%d)
    today_journal=".cmux/journal/${today}/journal.md"
    today_reflection=".cmux/journal/${today}/reflection.md"
    today_journal_tail=""
    if [[ -f "$today_journal" ]]; then
        today_journal_tail=$(tail -20 "$today_journal" 2>/dev/null || echo "(empty)")
    else
        today_journal_tail="(no journal entries today)"
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

Write an enriched briefing file and send the supervisor to read it:

\`\`\`bash
cat > .cmux/worker-contexts/sentry-briefing.md << 'BRIEF_EOF'
# Sentry Recovery Briefing

The previous supervisor became unresponsive (heartbeat stale for ${staleness}s at ${timestamp}). A sentry agent performed recovery.

## Pending Backlog (top 3)

${backlog_context}

## Recent Mailbox Messages

${mailbox_subjects}

## Recent Journal (tail of today)

${today_journal_tail}

## Where to Look

- Today's reflection: \`${today_reflection}\`
- Today's journal: \`${today_journal}\`
- Full backlog: run \`./tools/backlog list\`

## Recommended Next Steps

1. Read \`${today_reflection}\` for today's full context
2. Run \`./tools/autonomy-check\` to find highest-priority next action
3. Resume normal operations — check backlog, respond to any pending mailbox messages
BRIEF_EOF
tmux send-keys -t "${CMUX_SESSION}:supervisor" -l "SENTRY RECOVERY: You were relaunched after becoming unresponsive. Read .cmux/worker-contexts/sentry-briefing.md for full context on what was pending, then resume operations."
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
    tmux_send_keys "$CMUX_SESSION" "sentry" "export CMUX_AGENT=true CMUX_AGENT_NAME=sentry CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false && cd ${CMUX_PROJECT_ROOT} && claude --dangerously-skip-permissions"

    # Lock window name
    tmux set-option -t "${CMUX_SESSION}:sentry" allow-rename off 2>/dev/null || true

    # Wait for Claude to initialize
    local retries=30
    while [[ "$(tmux_pane_state "$CMUX_SESSION" "sentry")" != "PROMPT" ]]; do
        sleep 1
        ((retries--)) || break
        if ((retries <= 0)); then
            log_warn "Sentry Claude startup timeout, sending instructions anyway"
            break
        fi
    done
    sleep 1

    # Send the context reference (--force since this is a fresh sentry window)
    tmux_safe_send "$CMUX_SESSION" "sentry" "Read ${context_file} and execute the recovery procedure described in it. Follow every step exactly." --force

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
MAINTENANCE_COUNTER=0
MAINTENANCE_INTERVAL=60  # run every 60 iterations (60 * 5s sleep = 5 minutes)

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
            if ((HEALTH_FAILURES > 0)); then
                mark_healthy
            fi
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
            start_compact_daemon
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

        # Project supervisor heartbeats
        check_project_supervisor_heartbeats

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

        # Sweep all panes for stuck paste buffers (cheap — just capture + grep)
        tmux_sweep_stuck_pastes "$CMUX_SESSION" 2>/dev/null || true

        # Periodic auto-maintenance (every MAINTENANCE_INTERVAL iterations)
        ((MAINTENANCE_COUNTER++)) || true
        if ((MAINTENANCE_COUNTER >= MAINTENANCE_INTERVAL)); then
            MAINTENANCE_COUNTER=0
            local maintenance_tool="${CMUX_PROJECT_ROOT}/tools/auto-maintenance"
            if [[ -x "$maintenance_tool" ]]; then
                "$maintenance_tool" 2>/dev/null || true
            fi
        fi

        sleep 5
    done
}

# Healthy commit tracking (absorbed from former health.sh)
HEALTHY_COMMIT_FILE=".cmux/.last_healthy_commit"
RECOVERY_WAIT=30

mark_healthy() {
    local commit
    commit=$(git rev-parse HEAD 2>/dev/null || echo "")
    if [[ -n "$commit" ]]; then
        echo "$commit" > "$HEALTHY_COMMIT_FILE"
    fi
}

get_last_healthy_commit() {
    if [[ -f "$HEALTHY_COMMIT_FILE" ]]; then
        cat "$HEALTHY_COMMIT_FILE"
    else
        git rev-parse HEAD~1 2>/dev/null || git rev-parse HEAD
    fi
}

# Journal the failure context before rollback
pre_rollback_journal() {
    local error_log="$1"
    local git_status last_commit target_commit
    git_status=$(git status --short 2>/dev/null || echo "Unable to get git status")
    last_commit=$(git log -1 --oneline 2>/dev/null || echo "Unable to get last commit")
    target_commit=$(get_last_healthy_commit)

    curl -sf -X POST "http://localhost:${CMUX_PORT}/api/journal/entry" \
        -H "Content-Type: application/json" \
        -d "{
            \"title\": \"Auto-Rollback Triggered\",
            \"content\": \"## Health Check Failure\\n\\nHealth check failed after ${MAX_FAILURES} consecutive retries. Auto-rollback initiated.\\n\\n### Error Context\\n\\\`\\\`\\\`\\n${error_log}\\n\\\`\\\`\\\`\\n\\n### Git Status\\n\\\`\\\`\\\`\\n${git_status}\\n\\\`\\\`\\\`\\n\\n### Last Commit\\n${last_commit}\\n\\n### Rolling Back To\\n${target_commit}\"
        }" 2>/dev/null || true

    # Also write to local file as backup (API may be down)
    local journal_dir=".cmux/journal/$(date +%Y-%m-%d)"
    mkdir -p "$journal_dir"
    cat > "${journal_dir}/rollback-$(date +%H%M%S).md" << ROLLBACK_EOF
# Auto-Rollback Triggered

**Time:** $(date -Iseconds)

## Health Check Failure

Health check failed after ${MAX_FAILURES} consecutive retries. Auto-rollback initiated.

### Error Context
\`\`\`
${error_log}
\`\`\`

### Git Status
\`\`\`
${git_status}
\`\`\`

### Last Commit
${last_commit}

### Rolling Back To
${target_commit}
ROLLBACK_EOF
}

# Notify supervisor of rollback via mailbox and tmux
notify_supervisor_of_rollback() {
    local error_context="$1"
    local target_commit="$2"
    local message="SYSTEM ALERT: Auto-rollback occurred. The server failed health checks after ${MAX_FAILURES} retries and was rolled back to commit ${target_commit}. Error context: ${error_context}. Check the journal at .cmux/journal/$(date +%Y-%m-%d)/ for full details."

    # Send via mailbox
    local timestamp
    timestamp=$(date -Iseconds)
    echo "[${timestamp}] system:health -> ${CMUX_SESSION}:supervisor: [ERROR] Auto-rollback occurred to ${target_commit}" >> "${CMUX_MAILBOX}" 2>/dev/null || true

    # Also send directly to tmux for immediate attention
    if tmux_window_exists "$CMUX_SESSION" "supervisor"; then
        tmux_safe_send "$CMUX_SESSION" "supervisor" "$message" --force
    fi
}

# Stop the server by killing processes on CMUX_PORT
stop_server() {
    local pids
    pids=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        for pid in $pids; do
            kill "$pid" 2>/dev/null || true
        done
        # Wait for graceful shutdown
        local wait_count=0
        while lsof -ti tcp:"$CMUX_PORT" >/dev/null 2>&1 && ((wait_count < 5)); do
            sleep 1
            ((wait_count++))
        done
        # Force kill remaining
        pids=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            for pid in $pids; do
                kill -9 "$pid" 2>/dev/null || true
            done
        fi
    fi
    pkill -f "uvicorn.*src.server.main:app" 2>/dev/null || true
}

# Rollback to a specific commit, rebuild deps, restart server
rollback_and_restart() {
    local target_commit="$1"
    log_step "Rolling back to commit ${target_commit}"

    cd "$CMUX_PROJECT_ROOT"

    git stash push -m "cmux-auto-rollback-$(date +%s)" 2>/dev/null || true
    git reset --hard "$target_commit" 2>/dev/null || return 1

    # Rebuild dependencies
    uv sync 2>/dev/null || log_warn "uv sync failed, continuing..."
    (cd "${CMUX_PROJECT_ROOT}/src/frontend" && npm ci --silent 2>/dev/null && npm run build 2>/dev/null) || log_warn "Frontend rebuild failed, continuing..."

    stop_server
    start_server
}

attempt_recovery() {
    log_step "Attempting server recovery (multi-stage)..."

    # Capture recent server log for context
    local error_log
    error_log=$(tail -50 /tmp/cmux-server.log 2>/dev/null || echo "No server log available")

    # Stage 1: Simple restart
    log_step "Stage 1: Simple restart..."
    stop_server
    sleep 2
    if start_server && is_server_running; then
        log_ok "Recovery successful (simple restart)"
        mark_healthy
        HEALTH_FAILURES=0
        return
    fi

    # Stage 2: Journal failure and rollback to last healthy commit
    log_step "Stage 2: Rollback to last healthy commit..."
    pre_rollback_journal "$error_log"

    local target_commit
    target_commit=$(get_last_healthy_commit)
    rollback_and_restart "$target_commit"

    sleep "$RECOVERY_WAIT"

    if is_server_running; then
        log_ok "Recovery successful (rollback to $target_commit)"
        notify_supervisor_of_rollback "$error_log" "$target_commit"
        HEALTH_FAILURES=0
        return
    fi

    # Stage 3: Try progressively older commits
    log_step "Stage 3: Trying older commits..."
    local commits
    commits=$(git log --oneline -10 | tail -n +2)

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local commit_hash
        commit_hash=$(echo "$line" | cut -d' ' -f1)

        log_step "Trying rollback to $commit_hash..."
        rollback_and_restart "$commit_hash"

        sleep "$RECOVERY_WAIT"

        if is_server_running; then
            log_ok "Recovery successful (rollback to $commit_hash)"
            notify_supervisor_of_rollback "$error_log" "$commit_hash"
            HEALTH_FAILURES=0
            return
        fi
    done <<< "$commits"

    log_fail "All recovery attempts failed - manual intervention required"
    notify_supervisor_of_rollback "All rollback attempts failed. Manual intervention required." "NONE"
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

    # Phase 2b: Launch project supervisors for active projects
    launch_project_supervisors
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
    start_compact_daemon
    echo ""

    # Phase 7: Run health dashboard (foreground)
    log_ok "Entering dashboard mode..."
    sleep 2
    run_dashboard
}

main
