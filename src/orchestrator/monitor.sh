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

# Initialize supervisor claude
start_supervisor() {
    # Start supervisor window
    if ! tmux_window_exists "$CMUX_SESSION" "supervisor"; then
        tmux_create_window "$CMUX_SESSION" "supervisor"
        # Start Claude with CMUX_AGENT=true and CMUX_AGENT_NAME=supervisor to enable hooks
        # Use --dangerously-skip-permissions for autonomous operation
        tmux_send_keys "$CMUX_SESSION" "supervisor" "export CMUX_AGENT=true CMUX_AGENT_NAME=supervisor && cd ${CMUX_PROJECT_ROOT} && claude --dangerously-skip-permissions"
        log_status "PENDING" "supervisor agent started"

        # Wait for Claude to initialize, then send role instructions
        sleep 8
        tmux_send_keys "$CMUX_SESSION" "supervisor" "Read docs/SUPERVISOR_ROLE.md to understand your role as the CMUX supervisor agent. This file contains your instructions for managing workers, using the journal system, and coordinating tasks."
        log_status "IN_PROGRESS" "supervisor agent received role instructions"
    fi
}

start_server &
start_supervisor &
start_health_monitor &
start_router &
start_compact_scheduler &

wait
