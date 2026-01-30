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

    # Wait for Claude to initialize, then send role instructions
    sleep 8
    tmux_send_keys "$CMUX_SESSION" "supervisor" "Read docs/SUPERVISOR_ROLE.md to understand your role as the CMUX supervisor agent. This file contains your instructions for managing workers, using the journal system, and coordinating tasks."

    log_ok "Supervisor agent launched"
}

#───────────────────────────────────────────────────────────────────────────────
# Message Router (runs in background)
#───────────────────────────────────────────────────────────────────────────────

ROUTER_POSITION=0

route_messages() {
    local mailbox="$CMUX_MAILBOX"

    [[ ! -f "$mailbox" ]] && return 0

    local current_size
    current_size=$(wc -c < "$mailbox" | xargs)

    ((current_size <= ROUTER_POSITION)) && return 0

    # Read new content
    local new_content
    new_content=$(tail -c +"$((ROUTER_POSITION + 1))" "$mailbox")

    # Process each message
    local in_message=false
    local current_message=""
    local from="" to=""

    while IFS= read -r line; do
        if [[ "$line" == "--- MESSAGE ---" ]]; then
            if [[ -n "$current_message" && -n "$to" ]]; then
                route_single_message "$from" "$to" "$current_message"
            fi
            current_message=""
            from=""
            to=""
            in_message=true
        elif $in_message; then
            if [[ "$line" =~ ^from:\ *(.+)$ ]]; then
                from="${BASH_REMATCH[1]}"
            elif [[ "$line" =~ ^to:\ *(.+)$ ]]; then
                to="${BASH_REMATCH[1]}"
            fi
            current_message+="$line"$'\n'
        fi
    done <<< "$new_content"

    # Process last message
    if [[ -n "$current_message" && -n "$to" ]]; then
        route_single_message "$from" "$to" "$current_message"
    fi

    ROUTER_POSITION=$current_size
}

route_single_message() {
    local from="$1"
    local to="$2"
    local content="$3"

    echo "$(date -Iseconds) | ROUTE | $from -> $to" >> "$ROUTER_LOG"

    if [[ "$to" == "user" ]]; then
        # Route to API for user display
        curl -sf -X POST "http://localhost:${CMUX_PORT}/api/messages/user" \
            -H "Content-Type: application/json" \
            -d "{\"content\": $(echo "$content" | jq -Rs .), \"from_agent\": \"$from\"}" \
            >/dev/null 2>&1 || true
        return 0
    fi

    # Route to agent window
    if tmux_window_exists "$CMUX_SESSION" "$to"; then
        tmux_send_keys "$CMUX_SESSION" "$to" "$content"
    else
        echo "$(date -Iseconds) | FAILED | $from -> $to | window not found" >> "$ROUTER_LOG"
    fi
}

run_router_loop() {
    echo "$(date -Iseconds) | STARTUP | router ready" >> "$ROUTER_LOG"
    while true; do
        route_messages
        sleep 2
    done
}

#───────────────────────────────────────────────────────────────────────────────
# Health Monitor Dashboard
#───────────────────────────────────────────────────────────────────────────────

HEALTH_FAILURES=0
MAX_FAILURES=3
LAST_CTRL_C=0

handle_exit() {
    local now
    now=$(date +%s)
    if ((now - LAST_CTRL_C < 3)); then
        echo ""
        printf "${RED}Shutting down...${NC}\n"
        [[ -n "${ROUTER_PID:-}" ]] && kill "$ROUTER_PID" 2>/dev/null
        exit 0
    else
        LAST_CTRL_C=$now
        echo ""
        printf "${YELLOW}Press Ctrl+C again within 3s to quit${NC}\n"
        printf "${DIM}Agents keep running. Re-attach: tmux attach -t $CMUX_SESSION${NC}\n"
        sleep 1
    fi
}

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

        # Router status
        if [[ -n "${ROUTER_PID:-}" ]] && kill -0 "$ROUTER_PID" 2>/dev/null; then
            printf "  Router:     ${GREEN}●${NC} running (PID: ${ROUTER_PID})\n"
        else
            printf "  Router:     ${YELLOW}●${NC} restarting...\n"
            run_router_loop &
            ROUTER_PID=$!
        fi

        # Supervisor status
        if tmux_window_exists "$CMUX_SESSION" "supervisor"; then
            printf "  Supervisor: ${GREEN}●${NC} running\n"
        else
            printf "  Supervisor: ${RED}●${NC} not found\n"
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

    print_banner
    print_separator

    # Phase 1: Start server
    start_server || exit 1
    echo ""

    # Phase 2: Launch supervisor
    launch_supervisor
    echo ""

    # Phase 3: Start router in background
    log_step "Starting message router..."
    run_router_loop &
    ROUTER_PID=$!
    log_ok "Message router started (PID: $ROUTER_PID)"
    echo ""

    # Phase 4: Run health dashboard (foreground)
    log_ok "Entering dashboard mode..."
    sleep 2
    run_dashboard
}

main
