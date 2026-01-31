#!/usr/bin/env bash
#===============================================================================
# router.sh - Message Router Daemon
#
# Routes messages from the mailbox to target agents or the user.
# Watches .cmux/mailbox for new single-line messages and delivers them.
#
# Mailbox Format (single line):
#   [timestamp] from -> to: subject (body: path)
#
# Examples:
#   [2026-01-31T06:00:00Z] cmux:worker-auth -> cmux:supervisor: [DONE] JWT complete
#   [2026-01-31T06:00:00Z] cmux:worker -> user: Bug fixed (body: path/to/file.md)
#===============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/tmux.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

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
        cat "$LINE_MARKER"
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
# Message Parsing (Single-Line Format)
#-------------------------------------------------------------------------------

# Parse: [timestamp] from -> to: subject (body: path)
parse_line() {
    local line="$1"

    # Regex: [timestamp] from -> to: subject (body: path)?
    # Note on address format: supports "agent" or "session:agent" (one colon max)
    # The "to" field uses alternation: ([^\ :]+:[^\ :]+|[^\ :]+)
    #   - Either: session:agent (two parts separated by colon, neither contains space/colon)
    #   - Or: just agent (single part with no colon)
    # This ensures we match "cmux:supervisor" correctly, not just "cmux"
    if [[ "$line" =~ ^\[([^\]]+)\]\ ([^\ ]+)\ -\>\ ([^\ :]+:[^\ :]+|[^\ :]+):\ (.+)$ ]]; then
        local timestamp="${BASH_REMATCH[1]}"
        local from="${BASH_REMATCH[2]}"
        local to="${BASH_REMATCH[3]}"
        local rest="${BASH_REMATCH[4]}"

        # Extract body path if present: (body: path)
        local subject body_path
        if [[ "$rest" =~ \(body:\ (.+)\)$ ]]; then
            body_path="${BASH_REMATCH[1]}"
            # Remove (body: path) from subject
            subject="${rest% (body:*}"
        else
            subject="$rest"
            body_path=""
        fi

        # Log successful parse for debugging
        log_route "PARSED" "$from" "$to" "subject=${subject:0:40}"

        # Output: timestamp|from|to|subject|body_path
        echo "$timestamp|$from|$to|$subject|$body_path"
        return 0
    fi

    # Log parse failure for debugging
    log_route "PARSE_FAIL" "unknown" "unknown" "line=${line:0:60}"

    # No match
    return 1
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

    # Route to user via API (already handled by store, but also send direct)
    if [[ "$to" == "user" ]]; then
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

    if ((current_line <= last_line)); then
        return 0
    fi

    # Process each new line
    local line_num=$((last_line + 1))
    tail -n +"$line_num" "$CMUX_MAILBOX" | while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Parse the single-line format
        local parsed
        if parsed=$(parse_line "$line"); then
            IFS='|' read -r timestamp from to subject body_path <<< "$parsed"
            log_info "Routing: $from -> $to: $subject"
            route_message "$from" "$to" "$subject" "$body_path"
        else
            log_route "SKIP" "unknown" "unknown" "invalid format: ${line:0:50}..."
        fi
    done

    save_line "$current_line"
}

#-------------------------------------------------------------------------------
# Main
#-------------------------------------------------------------------------------

main() {
    log_info "Message router started (single-line format)"

    # Ensure directories exist
    mkdir -p "$(dirname "$LINE_MARKER")"
    mkdir -p "$(dirname "$CMUX_ROUTER_LOG")"

    # Log startup
    log_route "STARTUP" "router" "all" "Router daemon started (v2 - single-line format)"

    while true; do
        process_mailbox
        sleep "$POLL_INTERVAL"
    done
}

main
