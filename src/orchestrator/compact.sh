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

# Check if an agent is at prompt (idle) by capturing the last lines of its pane.
# Returns 0 if idle, 1 if busy.
is_agent_idle() {
    local session="$1"
    local window="$2"

    local pane_output
    pane_output=$(tmux_capture_pane "$session" "$window" 20 2>/dev/null) || return 1

    # Look for Claude Code prompt indicators:
    # - "❯" prompt character
    # - "bypass permissions" (dangerously-skip-permissions mode prompt)
    # - "> " at start of line (basic prompt)
    if echo "$pane_output" | grep -qE '❯|bypass permissions|^> '; then
        return 0
    fi

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

    # Acquire per-window lock to prevent races with router/journal-nudge
    tmux_send_lock "$window"

    # Re-check idle under lock (state may have changed)
    if ! is_agent_idle "$session" "$window"; then
        tmux_send_unlock
        log_status "COMPACT" "Skipped ${window}: agent became busy before send"
        return 1
    fi

    # Send /compact command
    tmux send-keys -t "${session}:${window}" -l "/compact"
    sleep 0.1
    tmux send-keys -t "${session}:${window}" Enter

    tmux_send_unlock

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

        # Wait for agent to be idle again before injecting recovery message
        if is_agent_idle "$session" "$window"; then
            local today
            today=$(date +%Y-%m-%d)
            local recovery_msg="You were just compacted. Read your recovery context from .cmux/journal/${today}/artifacts/compaction-${window}-*.json (most recent one). Also check your conversation history via GET /api/agents/${window}/history if anything is unclear."

            tmux_send_lock "$window"
            tmux send-keys -t "${session}:${window}" -l "$recovery_msg"
            sleep 0.1
            tmux send-keys -t "${session}:${window}" Enter
            tmux_send_unlock

            log_status "COMPACT" "Injected recovery message for ${window}"
        else
            log_status "COMPACT" "WARN: ${window} not idle after compaction, skipping recovery message"
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

        # Attempt compaction
        if compact_agent "$CMUX_SESSION" "$window"; then
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
