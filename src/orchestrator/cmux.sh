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
CMUX_COMPACT_INTERVAL="${CMUX_COMPACT_INTERVAL:-15}"
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

    # Start supervisor window
    if ! tmux_window_exists "$CMUX_SESSION" "supervisor"; then
        tmux_create_window "$CMUX_SESSION" "supervisor"
        tmux_send_keys "$CMUX_SESSION" "supervisor" "cd ${CMUX_PROJECT_ROOT} && claude"
        log_status "PENDING" "supervisor agent started"
    fi

    # Start FastAPI server in background
    start_server

    # Start background processes
    start_health_monitor &
    start_router &
    start_compact_scheduler &

    log_status "IN_PROGRESS" "cmux system started"
    log_info "cmux system started successfully"
    log_info "Dashboard: http://${CMUX_HOST}:${CMUX_PORT}"
    log_info "tmux session: tmux attach -t ${CMUX_SESSION}"
}

cmd_stop() {
    log_info "Stopping cmux system..."

    # Stop background processes
    pkill -f "cmux-health" 2>/dev/null || true
    pkill -f "cmux-router" 2>/dev/null || true
    pkill -f "cmux-compact" 2>/dev/null || true

    # Stop FastAPI server
    stop_server

    # Kill tmux session
    if tmux_session_exists "$CMUX_SESSION"; then
        tmux kill-session -t "$CMUX_SESSION"
        log_status "COMPLETE" "tmux session killed"
    fi

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
    pgrep -f "cmux-health" >/dev/null && echo "  - health monitor: RUNNING" || echo "  - health monitor: STOPPED"
    pgrep -f "cmux-router" >/dev/null && echo "  - message router: RUNNING" || echo "  - message router: STOPPED"
    pgrep -f "cmux-compact" >/dev/null && echo "  - compact scheduler: RUNNING" || echo "  - compact scheduler: STOPPED"
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
start_health_monitor() {
    exec -a "cmux-health" "${SCRIPT_DIR}/health.sh"
}

start_router() {
    exec -a "cmux-router" "${SCRIPT_DIR}/router.sh"
}

start_compact_scheduler() {
    exec -a "cmux-compact" "${SCRIPT_DIR}/compact.sh"
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
