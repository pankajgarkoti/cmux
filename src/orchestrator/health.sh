#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

CMUX_PORT="${CMUX_PORT:-8000}"
CMUX_RECOVERY_WAIT="${CMUX_RECOVERY_WAIT:-30}"
CMUX_PROJECT_ROOT="${CMUX_PROJECT_ROOT:-$(pwd)}"

CHECK_INTERVAL=10
MAX_FAILURES=3
failure_count=0

check_server_health() {
    if curl -sf "http://localhost:${CMUX_PORT}/api/webhooks/health" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

get_last_working_commit() {
    # Find last commit where server was known to work
    # This could be stored in a marker file or use git bisect logic
    git log --oneline -20 | head -1 | cut -d' ' -f1
}

rollback_and_restart() {
    local target_commit="$1"
    log_status "IN_PROGRESS" "Rolling back to commit ${target_commit}"

    cd "$CMUX_PROJECT_ROOT"

    # Stash any changes
    git stash push -m "cmux-auto-rollback-$(date +%s)" 2>/dev/null || true

    # Reset to target commit
    git reset --hard "$target_commit"

    # Rebuild and restart
    log_info "Rebuilding after rollback..."

    # Reinstall Python dependencies
    uv sync

    # Rebuild frontend
    (cd src/frontend && npm install && npm run build)

    # Restart server
    stop_server
    start_server

    log_status "COMPLETE" "Rollback to ${target_commit} complete"
}

stop_server() {
    local pid
    pid=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)
    if [[ -n "$pid" ]]; then
        kill "$pid" 2>/dev/null || true
    fi
}

start_server() {
    cd "$CMUX_PROJECT_ROOT"
    nohup uv run uvicorn src.server.main:app \
        --host "0.0.0.0" \
        --port "$CMUX_PORT" \
        > /tmp/cmux-server.log 2>&1 &

    sleep 5
}

attempt_recovery() {
    log_status "IN_PROGRESS" "Attempting server recovery..."

    # First, try simple restart
    stop_server
    sleep 2
    start_server

    sleep "$CMUX_RECOVERY_WAIT"

    if check_server_health; then
        log_status "COMPLETE" "Server recovered with simple restart"
        return 0
    fi

    # If restart didn't work, try rolling back commits
    log_status "IN_PROGRESS" "Simple restart failed, attempting git rollback..."

    local commits
    commits=$(git log --oneline -10 | tail -n +2)

    while IFS= read -r line; do
        local commit_hash
        commit_hash=$(echo "$line" | cut -d' ' -f1)

        log_info "Trying rollback to $commit_hash..."
        rollback_and_restart "$commit_hash"

        sleep "$CMUX_RECOVERY_WAIT"

        if check_server_health; then
            log_status "COMPLETE" "Server recovered after rollback to $commit_hash"
            return 0
        fi
    done <<< "$commits"

    log_status "FAILED" "Recovery failed - manual intervention required"
    return 1
}

main() {
    log_info "Health monitor started"

    while true; do
        if check_server_health; then
            failure_count=0
        else
            ((failure_count++))
            log_status "BLOCKED" "Server health check failed (${failure_count}/${MAX_FAILURES})"

            if ((failure_count >= MAX_FAILURES)); then
                attempt_recovery
                failure_count=0
            fi
        fi

        sleep "$CHECK_INTERVAL"
    done
}

main
