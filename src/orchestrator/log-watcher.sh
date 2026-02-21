#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/filelock.sh"

CMUX_SESSION="${CMUX_SESSION:-cmux}"
CMUX_MAILBOX="${CMUX_MAILBOX:-.cmux/mailbox}"
CMUX_PORT="${CMUX_PORT:-8000}"

CHECK_INTERVAL="${CMUX_LOG_CHECK_INTERVAL:-60}"
ALERT_COOLDOWN="${CMUX_ALERT_COOLDOWN:-300}"

SERVER_LOG="/tmp/cmux-server.log"
ROUTER_LOG=".cmux/router.log"
MARKER_DIR=".cmux/.log_markers"

ERROR_PATTERNS=(
    '\bERROR\b'
    '\bException\b'
    '\bTraceback\b'
    '\bCRITICAL\b'
    '\bFAILED\b'
)

IGNORE_PATTERNS=(
    'healthcheck'
    'GET /api/webhooks/health'
    'INFO:'
)

# Cross-platform helpers
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

get_marker() {
    local log_file="$1"
    local marker_file="${MARKER_DIR}/$(basename "$log_file").marker"

    if [[ ! -f "$marker_file" ]]; then
        echo "0"
        return
    fi

    local saved_inode saved_pos
    read -r saved_inode saved_pos < "$marker_file" 2>/dev/null || { echo "0"; return; }

    local current_inode
    current_inode=$(get_inode "$log_file")

    if [[ "$saved_inode" != "$current_inode" ]]; then
        echo "0"
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

should_alert() {
    local log_file="$1"
    local cooldown_file="${MARKER_DIR}/$(basename "$log_file").cooldown"

    if [[ -f "$cooldown_file" ]]; then
        local last_alert
        last_alert=$(cat "$cooldown_file" 2>/dev/null || echo "0")
        local now
        now=$(date +%s)
        if ((now - last_alert < ALERT_COOLDOWN)); then
            return 1
        fi
    fi
    date +%s > "$cooldown_file"
    return 0
}

analyze_log() {
    local log_file="$1"
    [[ ! -f "$log_file" ]] && return 0

    local last_pos current_size
    last_pos=$(get_marker "$log_file")
    current_size=$(get_file_size "$log_file")

    if ((current_size < last_pos)); then
        last_pos=0
    fi

    ((current_size <= last_pos)) && return 0

    local new_content
    new_content=$(tail -c +$((last_pos + 1)) "$log_file" 2>/dev/null || true)
    [[ -z "$new_content" ]] && { save_marker "$log_file" "$current_size"; return 0; }

    local error_regex ignore_regex
    error_regex=$(IFS='|'; echo "${ERROR_PATTERNS[*]}")
    ignore_regex=$(IFS='|'; echo "${IGNORE_PATTERNS[*]}")

    local errors
    errors=$(echo "$new_content" | grep -E "$error_regex" 2>/dev/null | grep -vE "$ignore_regex" 2>/dev/null || true)

    if [[ -n "$errors" ]]; then
        local error_count
        error_count=$(echo "$errors" | wc -l | xargs)

        if should_alert "$log_file"; then
            local timestamp
            timestamp=$(date -Iseconds)
            local summary="[LOG ALERT] $(basename "$log_file"): ${error_count} errors detected"
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
EOF
            mailbox_lock
            jq -cn --arg id "$(uuidgen | tr '[:upper:]' '[:lower:]')" --arg ts "$timestamp" --arg from "system:log-watcher" --arg to "cmux:supervisor" --arg subject "$summary" --arg body "$alert_file" --arg status "submitted" '{id:$id,ts:$ts,from:$from,to:$to,subject:$subject,body:$body,status:$status}' >> "$CMUX_MAILBOX"
            mailbox_unlock
            log_info "Reported $error_count errors from $(basename "$log_file")"
        fi
    fi

    save_marker "$log_file" "$current_size"
}

check_agent_discrepancies() {
    local registry_file=".cmux/agent_registry.json"
    [[ ! -f "$registry_file" ]] && return 0

    local registered_agents
    if command -v jq &>/dev/null; then
        registered_agents=$(jq -r 'keys[]' "$registry_file" 2>/dev/null || true)
    else
        registered_agents=$(grep -oE '"[^"]+":' "$registry_file" 2>/dev/null | tr -d '":' || true)
    fi

    [[ -z "$registered_agents" ]] && return 0

    local actual_windows
    actual_windows=$(tmux list-windows -t "$CMUX_SESSION" -F '#{window_name}' 2>/dev/null || true)

    while IFS= read -r agent; do
        [[ -z "$agent" ]] && continue
        local window_name="${agent##*:}"

        if ! echo "$actual_windows" | grep -q "^${window_name}$"; then
            local timestamp
            timestamp=$(date -Iseconds)
            mailbox_lock
            jq -cn --arg id "$(uuidgen | tr '[:upper:]' '[:lower:]')" --arg ts "$timestamp" --arg from "system:log-watcher" --arg to "cmux:supervisor" --arg subject "[ALERT] Registered agent '$agent' missing from tmux" --arg body "" --arg status "submitted" '{id:$id,ts:$ts,from:$from,to:$to,subject:$subject,body:$body,status:$status}' >> "$CMUX_MAILBOX"
            mailbox_unlock
        fi
    done <<< "$registered_agents"
}

main() {
    log_info "Log watcher started (interval: ${CHECK_INTERVAL}s, cooldown: ${ALERT_COOLDOWN}s)"
    mkdir -p "$MARKER_DIR"

    local check_count=0
    while true; do
        analyze_log "$SERVER_LOG"
        analyze_log "$ROUTER_LOG"

        if ((check_count % 5 == 0)); then
            check_agent_discrepancies
        fi

        ((check_count++))
        sleep "$CHECK_INTERVAL"
    done
}

main
