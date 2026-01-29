#!/usr/bin/env bash
set -euo pipefail

# Source common libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/tmux.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

# Configuration (from environment or defaults)
CMUX_SESSION="${CMUX_SESSION:-cmux}"
CMUX_PORT="${CMUX_PORT:-8000}"
CMUX_HOST="${CMUX_HOST:-0.0.0.0}"
CMUX_MAILBOX="${CMUX_MAILBOX:-.cmux/mailbox}"
CMUX_STATUS_LOG="${CMUX_STATUS_LOG:-.cmux/status.log}"
CMUX_RECOVERY_WAIT="${CMUX_RECOVERY_WAIT:-30}"
CMUX_PROJECT_ROOT="${CMUX_PROJECT_ROOT:-$(pwd)}"

# Commands
cmd_start() {
    log_info "Starting cmux system..."

    # Ensure directories exist
    mkdir -p "$(dirname "$CMUX_MAILBOX")"
    mkdir -p "$(dirname "$CMUX_STATUS_LOG")"

    # Start tmux session if not exists
    if ! tmux_session_exists "$CMUX_SESSION"; then
        tmux_create_session "$CMUX_SESSION"
        log_status "PENDING" "tmux session created"
    fi

    # Start supervisor window with CMUX agent environment
    if ! tmux_window_exists "$CMUX_SESSION" "supervisor"; then
        tmux_create_window "$CMUX_SESSION" "supervisor"
        # Start Claude with CMUX_AGENT=true to enable hooks, and --dangerously-skip-permissions for autonomous operation
        tmux_send_keys "$CMUX_SESSION" "supervisor" "export CMUX_AGENT=true CMUX_AGENT_NAME=supervisor && cd ${CMUX_PROJECT_ROOT} && claude --dangerously-skip-permissions"
        log_status "PENDING" "supervisor agent started"

        # Wait for Claude to initialize, then send role instructions
        sleep 8
        tmux_send_keys "$CMUX_SESSION" "supervisor" "Read docs/SUPERVISOR_ROLE.md to understand your role as the CMUX supervisor agent. This file contains your instructions for managing workers, using the journal system, and coordinating tasks."
        log_status "IN_PROGRESS" "supervisor agent received role instructions"
    fi

    # Start FastAPI server in background
    start_server

    # Start health monitor INSIDE the tmux monitor window
    tmux_send_keys "$CMUX_SESSION" "monitor" "cd ${CMUX_PROJECT_ROOT} && ${SCRIPT_DIR}/health.sh"
    log_status "IN_PROGRESS" "health monitor started in tmux"

    # Start router daemon in background
    start_router &

    log_status "IN_PROGRESS" "cmux system started"
    log_info "cmux system started successfully"
    log_info "Dashboard: http://${CMUX_HOST}:${CMUX_PORT}"
    log_info "tmux session: tmux attach -t ${CMUX_SESSION}"
}

cmd_stop() {
    log_info "Stopping cmux system..."

    # Stop router daemon (runs as background process)
    pkill -f "cmux-router" 2>/dev/null || true

    # Stop FastAPI server
    stop_server

    # Kill main tmux session (this also stops health monitor running inside it)
    if tmux_session_exists "$CMUX_SESSION"; then
        tmux kill-session -t "$CMUX_SESSION"
        log_status "COMPLETE" "tmux session killed"
    fi

    # Kill any spawned sessions
    for sess in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep "^cmux-" || true); do
        tmux kill-session -t "$sess" 2>/dev/null || true
        log_info "Killed spawned session: $sess"
    done

    log_status "COMPLETE" "cmux system stopped"
    log_info "cmux system stopped"
}

cmd_restart() {
    cmd_stop
    sleep 2
    cmd_start
}

cmd_status() {
    echo "=== cmux Status ==="
    echo ""

    # tmux session
    if tmux_session_exists "$CMUX_SESSION"; then
        echo "tmux session: RUNNING"
        echo "Windows:"
        tmux list-windows -t "$CMUX_SESSION" -F "  - #{window_name}: #{window_activity}"
    else
        echo "tmux session: STOPPED"
    fi
    echo ""

    # FastAPI server
    if is_server_running; then
        echo "FastAPI server: RUNNING (port ${CMUX_PORT})"
    else
        echo "FastAPI server: STOPPED"
    fi
    echo ""

    # Background processes
    echo "Background processes:"
    # Health monitor runs inside tmux monitor window
    if tmux_session_exists "$CMUX_SESSION" && tmux_window_exists "$CMUX_SESSION" "monitor"; then
        local monitor_cmd
        monitor_cmd=$(tmux list-panes -t "$CMUX_SESSION:monitor" -F '#{pane_current_command}' 2>/dev/null | head -1)
        if [[ "$monitor_cmd" == "bash" || "$monitor_cmd" == "health.sh" ]]; then
            echo "  - health monitor: RUNNING (in tmux)"
        else
            echo "  - health monitor: STOPPED (window exists but script not running)"
        fi
    else
        echo "  - health monitor: STOPPED"
    fi
    pgrep -f "cmux-router" >/dev/null && echo "  - message router: RUNNING" || echo "  - message router: STOPPED"
}

cmd_logs() {
    tail -f "$CMUX_STATUS_LOG"
}

# Server management
start_server() {
    if is_server_running; then
        log_info "Server already running"
        return 0
    fi

    log_info "Starting FastAPI server..."
    cd "$CMUX_PROJECT_ROOT"

    # Build frontend if needed
    if [[ ! -d "src/frontend/dist" ]]; then
        log_info "Building frontend..."
        (cd src/frontend && npm install && npm run build)
    fi

    # Start server with nohup
    nohup uv run uvicorn src.server.main:app \
        --host "$CMUX_HOST" \
        --port "$CMUX_PORT" \
        > /tmp/cmux-server.log 2>&1 &

    # Wait for server to be ready
    local retries=30
    while ! is_server_running && ((retries-- > 0)); do
        sleep 1
    done

    if is_server_running; then
        log_status "IN_PROGRESS" "FastAPI server started"
        return 0
    else
        log_status "FAILED" "Failed to start FastAPI server"
        return 1
    fi
}

stop_server() {
    local pid
    pid=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)
    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
        log_status "COMPLETE" "FastAPI server stopped"
    fi
}

is_server_running() {
    curl -sf "http://localhost:${CMUX_PORT}/api/webhooks/health" >/dev/null 2>&1
}

# Background process starters
start_router() {
    exec -a "cmux-router" "${SCRIPT_DIR}/router.sh"
}

# Main entry point
main() {
    case "${1:-}" in
        start)   cmd_start ;;
        stop)    cmd_stop ;;
        restart) cmd_restart ;;
        status)  cmd_status ;;
        logs)    cmd_logs ;;
        *)
            echo "Usage: $0 {start|stop|restart|status|logs}"
            exit 1
            ;;
    esac
}

main "$@"
