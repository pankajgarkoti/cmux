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
# Returns: timestamp|from|to|subject|body_path
# Uses jq for reliable JSON parsing - no regex, no ambiguity
parse_line() {
    local line="$1"

    # Skip empty/whitespace-only lines
    [[ -z "${line// /}" ]] && return 1

    # Validate JSON and extract fields in one jq call
    local parsed
    if ! parsed=$(echo "$line" | jq -r '[.ts // "", .from // "", .to // "", .subject // "", .body // ""] | join("|")' 2>/dev/null); then
        log_route "PARSE_FAIL" "unknown" "unknown" "invalid JSON: ${line:0:60}"
        return 1
    fi

    # Verify we got required fields
    local timestamp from to subject body_path
    IFS='|' read -r timestamp from to subject body_path <<< "$parsed"

    if [[ -z "$from" ]] || [[ -z "$to" ]] || [[ -z "$subject" ]]; then
        log_route "PARSE_FAIL" "${from:-unknown}" "${to:-unknown}" "missing required fields"
        return 1
    fi

    log_route "PARSED" "$from" "$to" "subject=${subject:0:40}"
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

    # Extract agent name from session:agent format
    local from_agent="${from##*:}"
    local to_agent="${to##*:}"
    [[ "$to" == "user" ]] && to_agent="user"

    # Call internal API to store message and broadcast to WebSocket
    curl -sf -X POST "http://localhost:${CMUX_PORT}/api/messages/internal" \
        -H "Content-Type: application/json" \
        -d "{
            \"from_agent\": \"$from_agent\",
            \"to_agent\": \"$to_agent\",
            \"content\": $(echo "$content" | jq -Rs .),
            \"type\": \"$msg_type\"
        }" >/dev/null 2>&1 || {
            log_route "WARN" "$from" "$to" "failed to store in DB (API unavailable)"
        }
}

#-------------------------------------------------------------------------------
# Message Routing
#-------------------------------------------------------------------------------

route_message() {
    local from="$1"
    local to="$2"
    local subject="$3"
    local body_path="$4"

    # Build content for storage
    local content="$subject"
    [[ -n "$body_path" ]] && content="$subject (see: $body_path)"

    # Store in DB + broadcast to frontend
    store_message_via_api "$from" "$to" "$content" "mailbox"

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
            IFS='|' read -r timestamp from to subject body_path <<< "$parsed"
            log_info "Routing: $from -> $to: $subject"
            route_message "$from" "$to" "$subject" "$body_path"
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
