#!/usr/bin/env bash
#═══════════════════════════════════════════════════════════════════════════════
# CMUX - Self-Improving Multi-Agent Orchestrator
#
# Creates a tmux session where Window 0 is the control center.
# All setup and agent launching happens visibly from Window 0.
#
# Session Structure:
#   Window 0: Monitor (control center - you are here)
#   Window 1: Supervisor Agent
#   Window 2+: Worker Agents (created as needed)
#═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# Configuration
CMUX_SESSION="${CMUX_SESSION:-cmux}"
CMUX_PORT="${CMUX_PORT:-8000}"
CMUX_HOST="${CMUX_HOST:-0.0.0.0}"
CMUX_PROJECT_ROOT="${CMUX_PROJECT_ROOT:-$(pwd)}"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

#───────────────────────────────────────────────────────────────────────────────
# Commands
#───────────────────────────────────────────────────────────────────────────────

cmd_start() {
    # Check dependencies first
    for cmd in tmux claude git curl uv; do
        if ! command -v $cmd &>/dev/null; then
            printf "${RED}Error: $cmd is required but not installed${NC}\n"
            exit 1
        fi
    done

    # If we're inside the cmux session's monitor window, run orchestration directly
    if [[ -n "${TMUX:-}" ]]; then
        local current_session
        current_session=$(tmux display-message -p '#S')
        if [[ "$current_session" == "$CMUX_SESSION" ]]; then
            exec "${SCRIPT_DIR}/monitor.sh"
        fi
    fi

    # If session already exists, just report it
    if tmux has-session -t "$CMUX_SESSION" 2>/dev/null; then
        printf "${GREEN}Session '$CMUX_SESSION' already running${NC}\n"
        printf "Run '${CYAN}cmux.sh attach${NC}' to attach\n"
        printf "Run '${CYAN}cmux.sh status${NC}' to check status\n"
        exit 0
    fi

    printf "${CYAN}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════════════════════════╗
    ║                    CMUX ORCHESTRATOR                              ║
    ╚═══════════════════════════════════════════════════════════════════╝
EOF
    printf "${NC}\n"

    echo "Project: $(basename "$CMUX_PROJECT_ROOT")"
    echo "Path:    $CMUX_PROJECT_ROOT"
    echo ""

    # Create tmux session with window 0 as the monitor/control center
    printf "${BOLD}Creating tmux session...${NC}\n"

    tmux new-session -d -s "$CMUX_SESSION" -n "monitor" \
        "cd '$CMUX_PROJECT_ROOT' && '$SCRIPT_DIR/monitor.sh'"

    # Lock window name to prevent renaming
    tmux set-option -t "$CMUX_SESSION:monitor" allow-rename off

    printf "${GREEN}✓${NC} Session started: ${CMUX_SESSION}\n"
    printf "${GREEN}✓${NC} Monitor window launched\n"
    echo ""
    printf "Run '${CYAN}cmux.sh attach${NC}' to attach to the session\n"
    printf "Run '${CYAN}cmux.sh status${NC}' to check status\n"
}

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

cmd_restart() {
    cmd_stop
    sleep 2
    cmd_start
}

cmd_status() {
    printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    printf "${BOLD}                    CMUX Status${NC}\n"
    printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
    echo ""

    # tmux session
    if tmux has-session -t "$CMUX_SESSION" 2>/dev/null; then
        printf "tmux session: ${GREEN}$CMUX_SESSION (running)${NC}\n"
        echo ""
        printf "${BOLD}Windows:${NC}\n"
        tmux list-windows -t "$CMUX_SESSION" -F "  #{window_index}: #{window_name}" 2>/dev/null
    else
        printf "tmux session: ${RED}$CMUX_SESSION (not running)${NC}\n"
        echo ""
        echo "Run 'cmux.sh start' to start the system."
        return
    fi
    echo ""

    # FastAPI server
    if curl -sf "http://localhost:${CMUX_PORT}/api/webhooks/health" >/dev/null 2>&1; then
        printf "FastAPI server: ${GREEN}running (port ${CMUX_PORT})${NC}\n"
    else
        printf "FastAPI server: ${RED}stopped${NC}\n"
    fi
    echo ""

    printf "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

cmd_attach() {
    if tmux has-session -t "$CMUX_SESSION" 2>/dev/null; then
        exec tmux attach -t "$CMUX_SESSION"
    else
        printf "${RED}Error: No tmux session found: $CMUX_SESSION${NC}\n"
        echo "Run 'cmux.sh start' to start the system first."
        exit 1
    fi
}

cmd_logs() {
    if [[ -f "/tmp/cmux-server.log" ]]; then
        tail -f /tmp/cmux-server.log
    else
        echo "No server log found. Is the server running?"
        exit 1
    fi
}

cmd_detached_restart() {
    # Pass all arguments to detached-restart.sh
    exec "${SCRIPT_DIR}/detached-restart.sh" "$@"
}

cmd_help() {
    printf "${BOLD}Usage:${NC} cmux.sh <command>\n"
    echo ""
    printf "${BOLD}Commands:${NC}\n"
    printf "  ${CYAN}start${NC}              Start the cmux system (creates tmux session)\n"
    printf "  ${CYAN}stop${NC}               Stop the cmux system\n"
    printf "  ${CYAN}restart${NC}            Restart the cmux system\n"
    printf "  ${CYAN}status${NC}             Show system status\n"
    printf "  ${CYAN}attach${NC}             Attach to tmux session\n"
    printf "  ${CYAN}logs${NC}               Tail the server logs\n"
    printf "  ${CYAN}detached-restart${NC}   Restart server in detached mode (safe for agents)\n"
    printf "  ${CYAN}help${NC}               Show this help\n"
    echo ""
    printf "${BOLD}Detached restart options:${NC}\n"
    printf "  --restart              Restart the FastAPI server only\n"
    printf "  --rollback [commit]    Rollback to commit and restart\n"
    printf "  --detach               Run in background (for agent use)\n"
    echo ""
    printf "${BOLD}tmux shortcuts:${NC}\n"
    printf "  Ctrl+b n/p    Switch between windows\n"
    printf "  Ctrl+b d      Detach from session\n"
    printf "  Ctrl+b [      Enter scroll mode\n"
}

#───────────────────────────────────────────────────────────────────────────────
# Main
#───────────────────────────────────────────────────────────────────────────────

main() {
    case "${1:-start}" in
        start)   cmd_start ;;
        stop)    cmd_stop ;;
        restart) cmd_restart ;;
        status)  cmd_status ;;
        attach)  cmd_attach ;;
        logs)    cmd_logs ;;
        detached-restart) shift; cmd_detached_restart "$@" ;;
        help|-h|--help) cmd_help ;;
        *)
            printf "${RED}Unknown command: %s${NC}\n" "$1"
            echo ""
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
