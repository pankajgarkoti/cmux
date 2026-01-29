#!/usr/bin/env bash
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
PROCESSED_MARKER=".cmux/.router_position"

# Log a routing event
log_route() {
    local status="$1"
    local from="$2"
    local to="$3"
    local details="${4:-}"
    echo "$(date -Iseconds) | $status | $from → $to | $details" >> "$CMUX_ROUTER_LOG"
}

# Get list of all cmux sessions
get_cmux_sessions() {
    tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -E '^cmux(-|$)' || true
}

get_last_position() {
    if [[ -f "$PROCESSED_MARKER" ]]; then
        cat "$PROCESSED_MARKER"
    else
        echo "0"
    fi
}

save_position() {
    echo "$1" > "$PROCESSED_MARKER"
}

parse_message() {
    local content="$1"

    # Extract fields from message format
    local timestamp from to msg_type msg_id body

    timestamp=$(echo "$content" | grep "^timestamp:" | cut -d: -f2- | xargs)
    from=$(echo "$content" | grep "^from:" | cut -d: -f2- | xargs)
    to=$(echo "$content" | grep "^to:" | cut -d: -f2- | xargs)
    msg_type=$(echo "$content" | grep "^type:" | cut -d: -f2- | xargs)
    msg_id=$(echo "$content" | grep "^id:" | cut -d: -f2- | xargs)

    # Body is everything after the second ---
    body=$(echo "$content" | sed -n '/^---$/,/^---$/!p' | tail -n +2)

    echo "$from|$to|$msg_type|$msg_id|$body"
}

route_to_agent() {
    local to="$1"
    local content="$2"
    local from="${3:-unknown}"

    if [[ "$to" == "user" ]]; then
        # Route to FastAPI server endpoint for user display
        if curl -sf -X POST "http://localhost:${CMUX_PORT}/api/messages/user" \
            -H "Content-Type: application/json" \
            -d "{\"content\": $(echo "$content" | jq -Rs .), \"from_agent\": \"supervisor\"}" \
            >/dev/null 2>&1; then
            log_route "DELIVERED" "$from" "user" "via API"
            log_info "Routed message to user via API"
        else
            log_route "FAILED" "$from" "user" "API error"
        fi
        return 0
    fi

    # Check all cmux sessions for the target agent
    local sessions
    sessions=$(get_cmux_sessions)

    while IFS= read -r session; do
        [[ -z "$session" ]] && continue

        if tmux_window_exists "$session" "$to"; then
            tmux_send_keys "$session" "$to" "$content"
            log_route "DELIVERED" "$from" "$to" "session=$session"
            log_info "Routed message to agent: $to in session: $session"
            return 0
        fi
    done <<< "$sessions"

    # Agent not found in any session
    log_route "FAILED" "$from" "$to" "agent not found"
    log_status "BLOCKED" "Cannot route to unknown agent: $to"
    return 1
}

process_mailbox() {
    if [[ ! -f "$CMUX_MAILBOX" ]]; then
        return 0
    fi

    local last_pos current_pos
    last_pos=$(get_last_position)
    current_pos=$(wc -c < "$CMUX_MAILBOX" | xargs)

    if ((current_pos <= last_pos)); then
        return 0
    fi

    # Read new content
    local new_content
    new_content=$(tail -c +"$((last_pos + 1))" "$CMUX_MAILBOX")

    # Process each message (separated by "--- MESSAGE ---")
    local in_message=false
    local current_message=""

    while IFS= read -r line; do
        if [[ "$line" == "--- MESSAGE ---" ]]; then
            if [[ -n "$current_message" ]]; then
                # Process previous message
                local parsed
                parsed=$(parse_message "$current_message")

                local to
                to=$(echo "$parsed" | cut -d'|' -f2)

                if [[ -n "$to" ]]; then
                    local from_agent
                    from_agent=$(echo "$parsed" | cut -d'|' -f1)
                    route_to_agent "$to" "$current_message" "$from_agent"
                fi
            fi
            current_message=""
            in_message=true
        elif $in_message; then
            current_message+="$line"$'\n'
        fi
    done <<< "$new_content"

    # Process last message if any
    if [[ -n "$current_message" ]]; then
        local parsed
        parsed=$(parse_message "$current_message")
        local to from_agent
        to=$(echo "$parsed" | cut -d'|' -f2)
        from_agent=$(echo "$parsed" | cut -d'|' -f1)
        if [[ -n "$to" ]]; then
            route_to_agent "$to" "$current_message" "$from_agent"
        fi
    fi

    save_position "$current_pos"
}

main() {
    log_info "Message router started"

    # Ensure directories exist
    mkdir -p "$(dirname "$PROCESSED_MARKER")"
    mkdir -p "$(dirname "$CMUX_ROUTER_LOG")"

    # Log startup
    log_route "STARTUP" "router" "all" "Router daemon started"

    while true; do
        process_mailbox
        sleep "$POLL_INTERVAL"
    done
}

main
