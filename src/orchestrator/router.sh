#!/usr/bin/env bash
#===============================================================================
# router.sh - Message Router Daemon
#
# Routes messages from the mailbox to target agents or the user.
# Watches .cmux/mailbox for new JSONL messages and delivers them.
#
# Mailbox Format (one JSON object per line):
#   {"ts":"...","from":"cmux:worker","to":"cmux:supervisor","subject":"...","body":"path"}
#
# Examples:
#   {"ts":"2026-01-31T06:00:00Z","from":"cmux:worker-auth","to":"cmux:supervisor","subject":"[DONE] JWT complete"}
#   {"ts":"2026-01-31T06:00:00Z","from":"cmux:worker","to":"user","subject":"Bug fixed","body":"path/to/file.md"}
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/tmux.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/filelock.sh"

CMUX_SESSION="${CMUX_SESSION:-cmux}"
CMUX_MAILBOX="${CMUX_MAILBOX:-.cmux/mailbox}"
CMUX_PORT="${CMUX_PORT:-8000}"
CMUX_ROUTER_LOG="${CMUX_ROUTER_LOG:-.cmux/router.log}"

POLL_INTERVAL=2
LINE_MARKER=".cmux/.router_line"

#-------------------------------------------------------------------------------
# Logging
#-------------------------------------------------------------------------------

log_route() {
    local status="$1"
    local from="$2"
    local to="$3"
    local details="${4:-}"
    echo "$(date -Iseconds) | $status | $from -> $to | $details" >> "$CMUX_ROUTER_LOG"
}

#-------------------------------------------------------------------------------
# Position Tracking (line-based)
#-------------------------------------------------------------------------------

get_last_line() {
    if [[ -f "$LINE_MARKER" ]]; then
        local val
        val=$(cat "$LINE_MARKER")
        # Validate: must be a non-negative integer
        if [[ "$val" =~ ^[0-9]+$ ]]; then
            echo "$val"
        else
            log_route "WARN" "router" "self" "invalid line marker '$val', resetting to 0"
            echo "0"
        fi
    else
        echo "0"
    fi
}

save_line() {
    echo "$1" > "$LINE_MARKER"
}

#-------------------------------------------------------------------------------
# Session Discovery
#-------------------------------------------------------------------------------

get_cmux_sessions() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -E '^cmux(-|$)' || true
}

#-------------------------------------------------------------------------------
# Message Parsing (JSONL)
#-------------------------------------------------------------------------------

# Parse a single JSONL line and extract fields
# Returns: id|timestamp|from|to|subject|body_path|status
# For status_update records, returns: _status_update|id|status
# Uses jq for reliable JSON parsing - no regex, no ambiguity
parse_line() {
    local line="$1"

    # Skip empty/whitespace-only lines
    [[ -z "${line// /}" ]] && return 1

    # Check if this is a status_update record
    local line_type
    line_type=$(echo "$line" | jq -r '.type // ""' 2>/dev/null)
    if [[ "$line_type" == "status_update" ]]; then
        local update_parsed
        if update_parsed=$(echo "$line" | jq -r '[.id // "", .status // ""] | join("|")' 2>/dev/null); then
            echo "_status_update|$update_parsed"
            return 0
        fi
        return 1
    fi

    # Validate JSON and extract fields in one jq call
    local parsed
    if ! parsed=$(echo "$line" | jq -r '[.id // "", .ts // "", .from // "", .to // "", .subject // "", .body // "", .status // ""] | join("|")' 2>/dev/null); then
        log_route "PARSE_FAIL" "unknown" "unknown" "invalid JSON: ${line:0:60}"
        return 1
    fi

    # Verify we got required fields
    local msg_id timestamp from to subject body_path status
    IFS='|' read -r msg_id timestamp from to subject body_path status <<< "$parsed"

    if [[ -z "$from" ]] || [[ -z "$to" ]] || [[ -z "$subject" ]]; then
        log_route "PARSE_FAIL" "${from:-unknown}" "${to:-unknown}" "missing required fields"
        return 1
    fi

    log_route "PARSED" "$from" "$to" "id=${msg_id:0:8} subject=${subject:0:40}"
    echo "$parsed"
    return 0
}

#-------------------------------------------------------------------------------
# Message Storage & Broadcast
#-------------------------------------------------------------------------------

store_message_via_api() {
    local from="$1"
    local to="$2"
    local content="$3"
    local msg_type="${4:-mailbox}"
    local task_status="${5:-}"

    # Extract agent name from session:agent format
    local from_agent="${from##*:}"
    local to_agent="${to##*:}"
    [[ "$to" == "user" ]] && to_agent="user"

    # Build JSON payload
    local payload
    if [[ -n "$task_status" ]]; then
        payload="{
            \"from_agent\": \"$from_agent\",
            \"to_agent\": \"$to_agent\",
            \"content\": $(echo "$content" | jq -Rs .),
            \"type\": \"$msg_type\",
            \"task_status\": \"$task_status\"
        }"
    else
        payload="{
            \"from_agent\": \"$from_agent\",
            \"to_agent\": \"$to_agent\",
            \"content\": $(echo "$content" | jq -Rs .),
            \"type\": \"$msg_type\"
        }"
    fi

    # Call internal API to store message and broadcast to WebSocket
    curl -sf -X POST "http://localhost:${CMUX_PORT}/api/messages/internal" \
        -H "Content-Type: application/json" \
        -d "$payload" >/dev/null 2>&1 || {
            log_route "WARN" "$from" "$to" "failed to store in DB (API unavailable)"
        }
}

# Update a message's task status via API
update_status_via_api() {
    local msg_id="$1"
    local new_status="$2"

    curl -sf -X PATCH "http://localhost:${CMUX_PORT}/api/messages/${msg_id}/status" \
        -H "Content-Type: application/json" \
        -d "{\"status\": \"$new_status\"}" \
        >/dev/null 2>&1 || {
            log_route "WARN" "router" "api" "failed to update status for $msg_id"
        }
}

#-------------------------------------------------------------------------------
# Message Routing
#-------------------------------------------------------------------------------

route_message() {
    local msg_id="$1"
    local from="$2"
    local to="$3"
    local subject="$4"
    local body_path="$5"
    local status="${6:-}"

    # Build content for storage
    local content="$subject"
    [[ -n "$body_path" ]] && content="$subject (see: $body_path)"

    # Store in DB + broadcast to frontend (with task_status if present)
    store_message_via_api "$from" "$to" "$content" "mailbox" "$status"

    # Route to user via API (handles both "user" and "cmux:user" / "session:user")
    local to_agent_name="${to##*:}"
    if [[ "$to" == "user" ]] || [[ "$to_agent_name" == "user" ]]; then
        local from_agent="${from##*:}"
        curl -sf -X POST "http://localhost:${CMUX_PORT}/api/messages/user" \
            -H "Content-Type: application/json" \
            -d "{\"content\": $(echo "$content" | jq -Rs .), \"from_agent\": \"$from_agent\"}" \
            >/dev/null 2>&1 || true
        log_route "DELIVERED" "$from" "user" "via API"
        return 0
    fi

    # Parse session:window from address
    local session window
    if [[ "$to" == *":"* ]]; then
        session="${to%%:*}"
        window="${to#*:}"
    else
        session="$CMUX_SESSION"
        window="$to"
    fi

    # Check all cmux sessions for the target agent
    local sessions
    sessions=$(get_cmux_sessions)
    local delivered=false

    while IFS= read -r sess; do
        [[ -z "$sess" ]] && continue

        # Try exact session match first
        if [[ "$sess" == "$session" ]] && tmux_window_exists "$sess" "$window"; then
            # Inject notification to target agent's tmux
            tmux_send_keys "$sess" "$window" "[$from] $subject"
            [[ -n "$body_path" ]] && tmux_send_keys "$sess" "$window" "  -> $body_path"
            log_route "DELIVERED" "$from" "$to" "session=$sess"
            delivered=true
            break
        fi
    done <<< "$sessions"

    # If not found in exact session, try any cmux session
    if [[ "$delivered" == "false" ]]; then
        while IFS= read -r sess; do
            [[ -z "$sess" ]] && continue
            if tmux_window_exists "$sess" "$window"; then
                tmux_send_keys "$sess" "$window" "[$from] $subject"
                [[ -n "$body_path" ]] && tmux_send_keys "$sess" "$window" "  -> $body_path"
                log_route "DELIVERED" "$from" "$to" "session=$sess (fallback)"
                delivered=true
                break
            fi
        done <<< "$sessions"
    fi

    if [[ "$delivered" == "false" ]]; then
        log_route "FAILED" "$from" "$to" "window not found"
        return 1
    fi

    # Update task status to "working" after successful delivery
    if [[ -n "$msg_id" ]]; then
        update_status_via_api "$msg_id" "working"
        log_route "STATUS" "$from" "$to" "id=${msg_id:0:8} -> working"
    fi

    return 0
}

#-------------------------------------------------------------------------------
# Mailbox Processing
#-------------------------------------------------------------------------------

process_mailbox() {
    if [[ ! -f "$CMUX_MAILBOX" ]]; then
        return 0
    fi

    # Get current line count
    local last_line current_line
    last_line=$(get_last_line)
    current_line=$(wc -l < "$CMUX_MAILBOX" | xargs)

    # Detect mailbox truncation/recreation: reset marker if file shrunk
    if ((current_line < last_line)); then
        log_route "WARN" "router" "self" "mailbox shrunk (${last_line} -> ${current_line}), resetting position"
        last_line=0
    fi

    if ((current_line <= last_line)); then
        return 0
    fi

    # Lock mailbox during read + line marker update to prevent reading partial writes
    mailbox_lock

    # Re-check line count under lock (may have changed)
    current_line=$(wc -l < "$CMUX_MAILBOX" | xargs)
    if ((current_line <= last_line)); then
        mailbox_unlock
        return 0
    fi

    # Snapshot the new lines while holding the lock
    local line_num=$((last_line + 1))
    local new_lines
    new_lines=$(tail -n +"$line_num" "$CMUX_MAILBOX")
    local lines_processed=0
    lines_processed=$(echo "$new_lines" | wc -l | xargs)

    # Update line marker while still holding lock
    save_line $((last_line + lines_processed))
    mailbox_unlock

    # Process lines outside the lock (routing can take time)
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Parse JSONL line
        local parsed
        if parsed=$(parse_line "$line"); then
            # Check if this is a status_update record
            if [[ "$parsed" == _status_update* ]]; then
                local update_id update_status
                IFS='|' read -r _ update_id update_status <<< "$parsed"
                log_info "Status update: $update_id -> $update_status"
                update_status_via_api "$update_id" "$update_status"
            else
                local msg_id timestamp from to subject body_path status
                IFS='|' read -r msg_id timestamp from to subject body_path status <<< "$parsed"
                log_info "Routing: $from -> $to: $subject"
                route_message "$msg_id" "$from" "$to" "$subject" "$body_path" "$status"
            fi
        else
            log_route "SKIP" "unknown" "unknown" "invalid line: ${line:0:50}..."
        fi
    done <<< "$new_lines"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    log_info "Message router started (JSONL format)"

    # Ensure directories exist
    mkdir -p "$(dirname "$LINE_MARKER")"
    mkdir -p "$(dirname "$CMUX_ROUTER_LOG")"

    # Verify jq is available
    if ! command -v jq &>/dev/null; then
        log_route "FATAL" "router" "self" "jq is required but not installed"
        exit 1
    fi

    # Log startup
    log_route "STARTUP" "router" "all" "Router daemon started (v3 - JSONL format)"

    while true; do
        process_mailbox
        sleep "$POLL_INTERVAL"
    done
}

main
