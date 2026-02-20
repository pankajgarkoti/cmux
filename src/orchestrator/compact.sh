#!/usr/bin/env bash
#═══════════════════════════════════════════════════════════════════════════════
# CMUX COMPACT DAEMON
#
# Periodically compacts agent context windows to prevent agents from hitting
# their context limit and becoming unresponsive ("bricked").
#
# Every COMPACT_INTERVAL seconds, enumerates all agent tmux windows, checks if
# each agent is idle (at prompt), and sends /compact. Verifies compaction
# succeeded by capturing pane output after a delay. Skips the supervisor.
#
# Uses per-window flock to prevent races with router.sh and journal-nudge.sh.
#═══════════════════════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/tmux.sh"
source "${SCRIPT_DIR}/lib/logging.sh"
source "${SCRIPT_DIR}/lib/filelock.sh"

# Configuration
CMUX_SESSION="${CMUX_SESSION:-cmux}"
COMPACT_INTERVAL="${CMUX_COMPACT_INTERVAL:-600}"  # 10 minutes
VERIFY_DELAY=15                                    # seconds to wait after sending /compact
SKIP_WINDOWS="monitor|supervisor"                  # windows to never compact
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
PRE_COMPACT_HOOK="${PROJECT_ROOT}/.claude/hooks/pre-compact.sh"
RECOVERY_DELAY=5                                   # seconds to wait before injecting recovery message
COMPACT_TIMESTAMPS="${PROJECT_ROOT}/.cmux/.compact-timestamps"

# Track state
RUNNING=true

#-------------------------------------------------------------------------------
# Signal handling
#-------------------------------------------------------------------------------

cleanup() {
    RUNNING=false
    log_info "Compact daemon shutting down"
    log_status "COMPACT" "Daemon stopped"
}

trap cleanup EXIT TERM HUP INT

#-------------------------------------------------------------------------------
# Agent idle detection
#-------------------------------------------------------------------------------

# Check if an agent is at prompt (idle) by checking pane state.
# Delegates to unified tmux_pane_state(). Returns 0 if idle, 1 if busy.
is_agent_idle() {
    local session="$1"
    local window="$2"
    local state
    state=$(tmux_pane_state "$session" "$window")
    [[ "$state" == "PROMPT" ]]
}

#-------------------------------------------------------------------------------
# Activity tracking — skip agents with no work since last compaction
#-------------------------------------------------------------------------------

# Get the epoch timestamp of last compaction for a window.
# Returns 0 if never compacted.
get_last_compact_time() {
    local window="$1"
    if [[ -f "$COMPACT_TIMESTAMPS" ]]; then
        local ts
        ts=$(grep "^${window}=" "$COMPACT_TIMESTAMPS" 2>/dev/null | tail -1 | cut -d= -f2)
        echo "${ts:-0}"
    else
        echo "0"
    fi
}

# Record current epoch as last compaction time for a window.
set_last_compact_time() {
    local window="$1"
    local now
    now=$(date +%s)

    # Create file if missing
    touch "$COMPACT_TIMESTAMPS"

    # Remove old entry (if any) and append new one
    if grep -q "^${window}=" "$COMPACT_TIMESTAMPS" 2>/dev/null; then
        # Use a temp file to avoid sed -i portability issues
        grep -v "^${window}=" "$COMPACT_TIMESTAMPS" > "${COMPACT_TIMESTAMPS}.tmp" || true
        mv "${COMPACT_TIMESTAMPS}.tmp" "$COMPACT_TIMESTAMPS"
    fi
    echo "${window}=${now}" >> "$COMPACT_TIMESTAMPS"
}

# Check whether an agent has had activity since its last compaction.
# Looks at heartbeat file mtime, then falls back to context file mtime.
# Returns 0 if there IS activity (should compact), 1 if no activity (skip).
has_activity_since_last_compact() {
    local window="$1"
    local last_compact
    last_compact=$(get_last_compact_time "$window")

    # Never compacted before — always compact
    if [[ "$last_compact" == "0" ]]; then
        return 0
    fi

    # Check heartbeat file first
    local heartbeat_file="${PROJECT_ROOT}/.cmux/.${window}-heartbeat"
    if [[ -f "$heartbeat_file" ]]; then
        local hb_mtime
        hb_mtime=$(stat -f %m "$heartbeat_file" 2>/dev/null || stat -c %Y "$heartbeat_file" 2>/dev/null || echo 0)
        if (( hb_mtime > last_compact )); then
            return 0
        fi
    fi

    # Fall back to context file
    local context_file="${PROJECT_ROOT}/.cmux/worker-contexts/${window}-context.md"
    if [[ -f "$context_file" ]]; then
        local ctx_mtime
        ctx_mtime=$(stat -f %m "$context_file" 2>/dev/null || stat -c %Y "$context_file" 2>/dev/null || echo 0)
        if (( ctx_mtime > last_compact )); then
            return 0
        fi
    fi

    # No activity detected
    return 1
}

#-------------------------------------------------------------------------------
# Compaction
#-------------------------------------------------------------------------------

# Send /compact to an agent and verify it worked.
# Returns 0 on success, 1 on failure.
compact_agent() {
    local session="$1"
    local window="$2"

    # --- Pre-compaction: capture agent state ---
    local artifact_file=""
    if [[ -x "$PRE_COMPACT_HOOK" ]]; then
        artifact_file=$("$PRE_COMPACT_HOOK" "$window" 2>/dev/null) || {
            log_status "COMPACT" "WARN: Pre-compact hook failed for ${window}, continuing anyway"
            artifact_file=""
        }
        if [[ -n "$artifact_file" ]]; then
            log_status "COMPACT" "Pre-compact state saved: ${artifact_file}"
        fi
    fi

    # Send /compact command via safe send with retries
    if ! tmux_safe_send "$session" "$window" "/compact" --retry 5; then
        log_status "COMPACT" "Skipped ${window}: agent not at prompt after retries"
        return 1
    fi

    log_status "COMPACT" "Sent /compact to ${window}, waiting ${VERIFY_DELAY}s for verification"

    # Wait for compaction to complete
    sleep "$VERIFY_DELAY"

    # Verify compaction happened by checking pane output
    local pane_output
    local compaction_ok=false
    pane_output=$(tmux_capture_pane "$session" "$window" 30 2>/dev/null) || {
        log_status "COMPACT" "WARN: Could not capture pane for ${window} verification"
        return 1
    }

    # Look for compaction success indicators
    if echo "$pane_output" | grep -qiE 'compact(ed|ion)|context.*reduc|summariz'; then
        log_status "COMPACT" "Verified: ${window} compaction succeeded"
        compaction_ok=true
    elif is_agent_idle "$session" "$window"; then
        # Agent is back at prompt (compaction may have happened but output scrolled)
        log_status "COMPACT" "OK: ${window} back at prompt after /compact (output not captured)"
        compaction_ok=true
    fi

    # --- Post-compaction: inject recovery message ---
    if $compaction_ok; then
        sleep "$RECOVERY_DELAY"

        local today
        today=$(date +%Y-%m-%d)
        local recovery_msg="You were just compacted. Read your recovery context from .cmux/journal/${today}/artifacts/compaction-${window}-*.json (most recent one). Also check your conversation history via GET /api/agents/${window}/history if anything is unclear."

        if tmux_safe_send "$session" "$window" "$recovery_msg" --retry 3; then
            log_status "COMPACT" "Injected recovery message for ${window}"
        else
            log_status "COMPACT" "WARN: ${window} not idle after compaction, queuing recovery message"
            tmux_safe_send "$session" "$window" "$recovery_msg" --queue || true
        fi

        return 0
    fi

    log_status "COMPACT" "WARN: ${window} compaction unverified (agent may still be processing)"
    return 1
}

#-------------------------------------------------------------------------------
# Main loop
#-------------------------------------------------------------------------------

compact_all_agents() {
    # Enumerate all windows in the cmux session
    local windows
    windows=$(tmux_list_windows "$CMUX_SESSION" 2>/dev/null) || {
        log_status "COMPACT" "WARN: Could not list windows (session $CMUX_SESSION not found?)"
        return
    }

    local compacted=0
    local skipped=0
    local busy=0
    local failed=0

    while IFS= read -r window; do
        [[ -z "$window" ]] && continue

        # Skip monitor and supervisor windows
        if echo "$window" | grep -qE "^(${SKIP_WINDOWS})$"; then
            ((skipped++))
            continue
        fi

        # Check if agent is idle
        if ! is_agent_idle "$CMUX_SESSION" "$window"; then
            ((busy++))
            continue
        fi

        # Skip if no activity since last compaction
        if ! has_activity_since_last_compact "$window"; then
            log_status "COMPACT" "Skipping ${window}: no activity since last compaction"
            ((skipped++))
            continue
        fi

        # Attempt compaction
        if compact_agent "$CMUX_SESSION" "$window"; then
            set_last_compact_time "$window"
            ((compacted++))
        else
            ((failed++))
        fi

    done <<< "$windows"

    log_status "COMPACT" "Cycle complete: compacted=${compacted} busy=${busy} skipped=${skipped} failed=${failed}"
}

main() {
    log_info "Compact daemon started (interval: ${COMPACT_INTERVAL}s, verify delay: ${VERIFY_DELAY}s)"
    log_status "COMPACT" "Daemon started (interval=${COMPACT_INTERVAL}s)"

    while $RUNNING; do
        compact_all_agents

        # Sleep in small increments so we can respond to signals promptly
        local waited=0
        while $RUNNING && ((waited < COMPACT_INTERVAL)); do
            sleep 5
            ((waited += 5))
        done
    done
}

main
