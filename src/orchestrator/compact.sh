#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/tmux.sh"
source "${SCRIPT_DIR}/lib/logging.sh"

CMUX_SESSION="${CMUX_SESSION:-cmux}"
CMUX_COMPACT_INTERVAL="${CMUX_COMPACT_INTERVAL:-15}"

compact_all_agents() {
    log_info "Running periodic /compact on all agents..."

    local windows
    windows=$(tmux list-windows -t "$CMUX_SESSION" -F "#{window_name}" 2>/dev/null || true)

    while IFS= read -r window; do
        if [[ -n "$window" ]]; then
            log_info "Compacting agent: $window"
            tmux_send_keys "$CMUX_SESSION" "$window" "/compact"
            sleep 2  # Small delay between compacts
        fi
    done <<< "$windows"

    log_status "COMPLETE" "Periodic compact completed"
}

main() {
    log_info "Compact scheduler started (interval: ${CMUX_COMPACT_INTERVAL}m)"

    while true; do
        # Sleep for the interval (in minutes)
        sleep "$((CMUX_COMPACT_INTERVAL * 60))"
        compact_all_agents
    done
}

main
