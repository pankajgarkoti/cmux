#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/tmux.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

CMUX_PORT="${CMUX_PORT:-8000}"
CMUX_SESSION="${CMUX_SESSION:-cmux}"
CMUX_RECOVERY_WAIT="${CMUX_RECOVERY_WAIT:-30}"
CMUX_PROJECT_ROOT="${CMUX_PROJECT_ROOT:-$(pwd)}"

# Healthy commit tracking
HEALTHY_COMMIT_FILE=".cmux/.last_healthy_commit"

CHECK_INTERVAL=10
MAX_FAILURES=3
failure_count=0

# Timeout constants (seconds)
TIMEOUT_GIT_RESET=30
TIMEOUT_CMD=120          # Per-command timeout for npm ci, uv sync, npm run build
TIMEOUT_ROLLBACK=300     # Overall rollback timeout (5 minutes)

# Portable timeout wrapper (macOS lacks GNU 'timeout')
# Returns 0 on success, 124 on timeout, or the command's exit code on failure
run_with_timeout() {
    local timeout_secs="$1"
    shift

    "$@" &
    local cmd_pid=$!

    ( sleep "$timeout_secs" && kill -TERM "$cmd_pid" 2>/dev/null ) &
    local watchdog_pid=$!

    local exit_code=0
    wait "$cmd_pid" 2>/dev/null || exit_code=$?

    # Clean up watchdog
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true

    # 143 = 128 + 15 (SIGTERM) means the watchdog killed the process
    if ((exit_code == 143)); then
        return 124
    fi

    return "$exit_code"
}

check_server_health() {
    if curl -sf "http://localhost:${CMUX_PORT}/api/webhooks/health" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

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

    # Build failed - try npm ci first
    log_info "Build failed, running npm ci..."
    if npm ci --silent 2>/dev/null && npm run build -- --outDir "$dist_new" >/dev/null 2>&1; then
        rm -rf "$dist_old" 2>/dev/null || true
        [[ -d "$dist_dir" ]] && mv "$dist_dir" "$dist_old"
        mv "$dist_new" "$dist_dir"
        rm -rf "$dist_old" 2>/dev/null || true

        log_status "COMPLETE" "Frontend rebuilt after npm ci"
        return 0
    fi

    rm -rf "$dist_new" 2>/dev/null || true
    log_status "FAILED" "Frontend rebuild failed"
    return 1
}

# Mark current commit as healthy
mark_healthy() {
    local commit
    commit=$(git rev-parse HEAD 2>/dev/null || echo "")
    if [[ -n "$commit" ]]; then
        echo "$commit" > "$HEALTHY_COMMIT_FILE"
        log_info "Marked commit $commit as healthy"
    fi
}

# Get last known healthy commit
get_last_healthy_commit() {
    if [[ -f "$HEALTHY_COMMIT_FILE" ]]; then
        cat "$HEALTHY_COMMIT_FILE"
    else
        # Fallback: use previous commit
        git rev-parse HEAD~1 2>/dev/null || git rev-parse HEAD
    fi
}

# Journal the failure context before rollback
pre_rollback_journal() {
    local error_log="$1"
    local git_status
    local last_commit
    local target_commit

    git_status=$(git status --short 2>/dev/null || echo "Unable to get git status")
    last_commit=$(git log -1 --oneline 2>/dev/null || echo "Unable to get last commit")
    target_commit=$(get_last_healthy_commit)

    # Try to post to journal API (may fail if server is down)
    curl -sf -X POST "http://localhost:${CMUX_PORT}/api/journal/entry" \
        -H "Content-Type: application/json" \
        -d "{
            \"title\": \"Auto-Rollback Triggered\",
            \"content\": \"## Health Check Failure\\n\\nHealth check failed after 3 consecutive retries. Auto-rollback initiated.\\n\\n### Error Context\\n\\\`\\\`\\\`\\n${error_log}\\n\\\`\\\`\\\`\\n\\n### Git Status\\n\\\`\\\`\\\`\\n${git_status}\\n\\\`\\\`\\\`\\n\\n### Last Commit\\n${last_commit}\\n\\n### Rolling Back To\\n${target_commit}\"
        }" 2>/dev/null || true

    # Also write to local file as backup
    local journal_dir=".cmux/journal/$(date +%Y-%m-%d)"
    mkdir -p "$journal_dir"
    cat > "${journal_dir}/rollback-$(date +%H%M%S).md" << EOF
# Auto-Rollback Triggered

**Time:** $(date -Iseconds)

## Health Check Failure

Health check failed after 3 consecutive retries. Auto-rollback initiated.

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
EOF

    log_info "Rollback context journaled"
}

# Notify supervisor of rollback via mailbox and tmux
notify_supervisor_of_rollback() {
    local error_context="$1"
    local target_commit="$2"

    local message="SYSTEM ALERT: Auto-rollback occurred. The server failed health checks after 3 retries and was rolled back to commit ${target_commit}. Error context: ${error_context}. Please check the journal at .cmux/journal/$(date +%Y-%m-%d)/ for full details and investigate what caused the failure. Your changes were stashed and can be recovered with 'git stash list'."

    # Send via mailbox (single-line format)
    local timestamp
    timestamp=$(date -Iseconds)
    local attachments_dir
    attachments_dir=".cmux/journal/$(date +%Y-%m-%d)/attachments"
    mkdir -p "$attachments_dir"
    local body_path
    body_path="${attachments_dir}/rollback-$(date +%s).md"
    cat > "$body_path" << EOF
# Auto-Rollback Alert

${message}
EOF
    echo "[${timestamp}] system:health -> ${CMUX_SESSION}:supervisor: [ERROR] Auto-rollback occurred (body: ${body_path})" >> .cmux/mailbox

    # Also send directly to tmux for immediate attention
    if tmux_window_exists "$CMUX_SESSION" "supervisor"; then
        # Use tmux_send_keys function for proper two-step send
        tmux_send_keys "$CMUX_SESSION" "supervisor" "$message"
    fi

    log_info "Supervisor notified of rollback"
}

# Rebuild dependencies with per-command timeouts
# Returns 0 if all succeeded, 1 if any step failed/timed out
rebuild_deps() {
    local had_failure=0

    # Python dependencies (timeout 120s)
    log_info "Running uv sync (timeout ${TIMEOUT_CMD}s)..."
    if ! run_with_timeout "$TIMEOUT_CMD" uv sync; then
        local uv_exit=$?
        if ((uv_exit == 124)); then
            log_status "BLOCKED" "uv sync timed out after ${TIMEOUT_CMD}s, skipping..."
        else
            log_status "BLOCKED" "uv sync failed (exit $uv_exit), skipping..."
        fi
        had_failure=1
    fi

    # Frontend: install dependencies (timeout 120s)
    log_info "Running npm ci (timeout ${TIMEOUT_CMD}s)..."
    if ! run_with_timeout "$TIMEOUT_CMD" bash -c "cd '${CMUX_PROJECT_ROOT}/src/frontend' && npm ci"; then
        local npm_exit=$?
        if ((npm_exit == 124)); then
            log_status "BLOCKED" "npm ci timed out after ${TIMEOUT_CMD}s, skipping..."
        else
            log_status "BLOCKED" "npm ci failed (exit $npm_exit), skipping..."
        fi
        had_failure=1
    fi

    # Frontend: build (timeout 120s)
    log_info "Running npm run build (timeout ${TIMEOUT_CMD}s)..."
    if ! run_with_timeout "$TIMEOUT_CMD" bash -c "cd '${CMUX_PROJECT_ROOT}/src/frontend' && npm run build"; then
        local build_exit=$?
        if ((build_exit == 124)); then
            log_status "BLOCKED" "npm run build timed out after ${TIMEOUT_CMD}s, skipping..."
        else
            log_status "BLOCKED" "npm run build failed (exit $build_exit), skipping..."
        fi
        had_failure=1
    fi

    return "$had_failure"
}

rollback_and_restart() {
    local target_commit="$1"
    log_status "IN_PROGRESS" "Rolling back to commit ${target_commit}"

    cd "$CMUX_PROJECT_ROOT"

    # Stash any changes (preserves work for later recovery)
    git stash push -m "cmux-auto-rollback-$(date +%s)" 2>/dev/null || true

    # Reset to target commit (timeout 30s)
    log_info "Running git reset --hard (timeout ${TIMEOUT_GIT_RESET}s)..."
    if ! run_with_timeout "$TIMEOUT_GIT_RESET" git reset --hard "$target_commit"; then
        local git_exit=$?
        if ((git_exit == 124)); then
            log_status "FAILED" "git reset --hard timed out after ${TIMEOUT_GIT_RESET}s"
        else
            log_status "FAILED" "git reset --hard failed (exit $git_exit)"
        fi
        return 1
    fi

    # Rebuild dependencies with timeouts
    log_info "Rebuilding after rollback..."
    rebuild_deps || log_status "BLOCKED" "Some rebuild steps failed, continuing with restart..."

    # Restart server only (keep tmux sessions alive!)
    stop_server
    start_server

    log_status "COMPLETE" "Rollback to ${target_commit} complete"
}

# Wrapper that enforces an overall timeout on rollback_and_restart
# If the entire operation exceeds TIMEOUT_ROLLBACK, logs CRITICAL and notifies supervisor
rollback_and_restart_timed() {
    local target_commit="$1"

    rollback_and_restart "$target_commit" &
    local func_pid=$!

    ( sleep "$TIMEOUT_ROLLBACK" && kill -TERM "$func_pid" 2>/dev/null ) &
    local watchdog_pid=$!

    local exit_code=0
    wait "$func_pid" 2>/dev/null || exit_code=$?

    # Clean up watchdog
    kill "$watchdog_pid" 2>/dev/null || true
    wait "$watchdog_pid" 2>/dev/null || true

    if ((exit_code == 143)); then
        log_status "FAILED" "CRITICAL: rollback_and_restart exceeded ${TIMEOUT_ROLLBACK}s timeout"
        local timestamp
        timestamp=$(date -Iseconds)
        echo "[${timestamp}] system:health -> ${CMUX_SESSION}:supervisor: [ERROR] CRITICAL: Rollback to ${target_commit} timed out after ${TIMEOUT_ROLLBACK}s. Manual intervention required." >> .cmux/mailbox
        return 1
    fi

    return "$exit_code"
}

stop_server() {
    local pids
    pids=$(lsof -ti tcp:"$CMUX_PORT" 2>/dev/null || true)

    if [[ -n "$pids" ]]; then
        # SIGTERM first (graceful shutdown)
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

    # Fallback: kill by process name
    pkill -f "uvicorn.*src.server.main:app" 2>/dev/null || true
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

    # Capture recent server log for context
    local error_log
    error_log=$(tail -50 /tmp/cmux-server.log 2>/dev/null || echo "No server log available")

    # First, try simple restart
    stop_server
    sleep 2
    start_server

    sleep "$CMUX_RECOVERY_WAIT"

    if check_server_health; then
        log_status "COMPLETE" "Server recovered with simple restart"
        mark_healthy
        return 0
    fi

    # If restart didn't work, journal the failure and try rollback
    log_status "IN_PROGRESS" "Simple restart failed, attempting git rollback..."

    # Journal the failure context
    pre_rollback_journal "$error_log"

    # Get the last known healthy commit
    local target_commit
    target_commit=$(get_last_healthy_commit)

    # Rollback to healthy commit
    log_info "Rolling back to last healthy commit: $target_commit"
    rollback_and_restart_timed "$target_commit"

    sleep "$CMUX_RECOVERY_WAIT"

    if check_server_health; then
        log_status "COMPLETE" "Server recovered after rollback to $target_commit"
        # Notify supervisor
        notify_supervisor_of_rollback "$error_log" "$target_commit"
        return 0
    fi

    # If that didn't work, try rolling back further
    log_status "IN_PROGRESS" "Healthy commit rollback failed, trying previous commits..."

    local commits
    commits=$(git log --oneline -10 | tail -n +2)

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local commit_hash
        commit_hash=$(echo "$line" | cut -d' ' -f1)

        log_info "Trying rollback to $commit_hash..."
        rollback_and_restart_timed "$commit_hash"

        sleep "$CMUX_RECOVERY_WAIT"

        if check_server_health; then
            log_status "COMPLETE" "Server recovered after rollback to $commit_hash"
            notify_supervisor_of_rollback "$error_log" "$commit_hash"
            return 0
        fi
    done <<< "$commits"

    log_status "FAILED" "Recovery failed - manual intervention required"
    notify_supervisor_of_rollback "All rollback attempts failed. Manual intervention required." "NONE"
    return 1
}

main() {
    log_info "Health monitor started"

    # Ensure directories exist
    mkdir -p "$(dirname "$HEALTHY_COMMIT_FILE")"

    while true; do
        if check_server_health; then
            if ((failure_count > 0)); then
                # Just recovered from a failure, mark as healthy
                mark_healthy
            fi
            failure_count=0

            # Server is up — also verify frontend is healthy
            if ! check_frontend_health; then
                log_status "BLOCKED" "Frontend health check failed, attempting recovery..."
                attempt_frontend_recovery || log_status "FAILED" "Frontend recovery failed"
            fi
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
