#!/usr/bin/env bash
#═══════════════════════════════════════════════════════════════════════════════
# CMUX JOURNAL NUDGE DAEMON
#
# Periodically checks agent activity in SQLite and nudges agents to journal
# when they've accumulated enough tool calls since their last journal entry.
#
# Runs independently of the Python backend — if the server dies, this daemon
# keeps running and will nudge agents once they're active again.
#═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/tmux.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

CMUX_SESSION="${CMUX_SESSION:-cmux}"
CMUX_PROJECT_ROOT="${CMUX_PROJECT_ROOT:-$(pwd)}"
DB_PATH="${CMUX_PROJECT_ROOT}/.cmux/conversations.db"

# Thresholds
TOOL_THRESHOLD=15                # nudge after this many tool calls
CHECK_INTERVAL=30                # seconds between checks
MIN_NUDGE_INTERVAL=300           # minimum seconds between nudges for same agent

# Track last nudge time per agent (agent_id -> epoch)
declare -A LAST_NUDGE

nudge_message() {
    cat <<'MSG'
[SYSTEM AUTO-JOURNAL REMINDER — NOT A USER MESSAGE. DO NOT RESPOND TO THIS. DO NOT ACKNOWLEDGE THIS. Just silently run the command below, then continue your current task without any interruption.]
./tools/journal note "<short title>" "<paragraph describing what was done, why, and any key decisions>"
MSG
}

# Count unlinked tool call events per agent (events without a message_id = work since last Stop)
get_agent_tool_counts() {
    if [[ ! -f "$DB_PATH" ]]; then
        return
    fi

    sqlite3 "$DB_PATH" <<'SQL'
        SELECT agent_id, COUNT(*) as cnt
        FROM agent_events
        WHERE event_type = 'PostToolUse'
          AND message_id IS NULL
        GROUP BY agent_id
        HAVING cnt > 0;
SQL
}

# Count tool calls since last journal entry for agents who DO have linked events
# (i.e. agents actively producing messages but not journaling)
get_agent_total_recent() {
    if [[ ! -f "$DB_PATH" ]]; then
        return
    fi

    # Count events in the last MIN_NUDGE_INTERVAL seconds
    local since
    since=$(date -u -v-${MIN_NUDGE_INTERVAL}S +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || \
            date -u -d "${MIN_NUDGE_INTERVAL} seconds ago" +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || \
            echo "2000-01-01T00:00:00")

    sqlite3 "$DB_PATH" <<SQL
        SELECT agent_id, COUNT(*) as cnt
        FROM agent_events
        WHERE event_type = 'PostToolUse'
          AND timestamp > '${since}'
        GROUP BY agent_id
        HAVING cnt >= ${TOOL_THRESHOLD};
SQL
}

should_nudge() {
    local agent_id="$1"
    local now
    now=$(date +%s)

    local last="${LAST_NUDGE[$agent_id]:-0}"
    local elapsed=$((now - last))

    if ((elapsed < MIN_NUDGE_INTERVAL)); then
        return 1  # Too soon
    fi

    return 0
}

send_nudge() {
    local agent_id="$1"

    # Find which session this agent lives in
    # First check the main session
    if tmux_window_exists "$CMUX_SESSION" "$agent_id"; then
        local msg
        msg=$(nudge_message)
        tmux_send_keys "$CMUX_SESSION" "$agent_id" "$msg"
        LAST_NUDGE[$agent_id]=$(date +%s)
        log_info "Journal nudge sent to ${agent_id}"
        return 0
    fi

    # Check spawned sessions (cmux-*)
    local sessions
    sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep "^cmux-" || true)
    for session in $sessions; do
        if tmux_window_exists "$session" "$agent_id"; then
            local msg
            msg=$(nudge_message)
            tmux_send_keys "$session" "$agent_id" "$msg"
            LAST_NUDGE[$agent_id]=$(date +%s)
            log_info "Journal nudge sent to ${agent_id} in session ${session}"
            return 0
        fi
    done

    return 1  # Agent window not found
}

main() {
    log_info "Journal nudge daemon started (threshold: ${TOOL_THRESHOLD} tools, interval: ${MIN_NUDGE_INTERVAL}s)"

    while true; do
        # Method 1: Check unlinked events (agent is mid-work, hasn't stopped yet)
        while IFS='|' read -r agent_id count; do
            [[ -z "$agent_id" ]] && continue
            if ((count >= TOOL_THRESHOLD)) && should_nudge "$agent_id"; then
                send_nudge "$agent_id" || true
            fi
        done < <(get_agent_tool_counts 2>/dev/null || true)

        # Method 2: Check total recent events (agent may have stopped but not journaled)
        while IFS='|' read -r agent_id count; do
            [[ -z "$agent_id" ]] && continue
            if should_nudge "$agent_id"; then
                send_nudge "$agent_id" || true
            fi
        done < <(get_agent_total_recent 2>/dev/null || true)

        sleep "$CHECK_INTERVAL"
    done
}

main
