#!/usr/bin/env bash
# tmux helper functions for cmux orchestrator

# Check if a tmux session exists
tmux_session_exists() {
    local session="$1"
    tmux has-session -t "$session" 2>/dev/null
}

# Create a new tmux session
tmux_create_session() {
    local session="$1"
    tmux new-session -d -s "$session" -n "monitor"
}

# Check if a tmux window exists
tmux_window_exists() {
    local session="$1"
    local window="$2"
    # Use -xF for exact fixed-string match (prevents regex injection via window names)
    tmux list-windows -t "$session" -F "#{window_name}" 2>/dev/null | grep -qxF "$window"
}

# Create a new tmux window
tmux_create_window() {
    local session="$1"
    local name="$2"
    # Use session: syntax to append window without specifying index
    tmux new-window -t "${session}:" -n "$name"
}

# Send keys to a tmux window
# For long messages (>4KB), uses tmux load-buffer/paste-buffer for reliability
# WARNING: Multiline content may cause "[Pasted text]" buffer issues in Claude Code
# For worker tasks, prefer writing to a file and sending a read instruction
tmux_send_keys() {
    local session="$1"
    local window="$2"
    shift 2
    local keys="$*"
    local msg_len=${#keys}

    # Warn about multiline content (can cause paste buffer issues in Claude Code)
    if [[ "$keys" == *$'\n'* ]] && [[ $msg_len -lt 4096 ]]; then
        # Log warning for debugging but don't fail
        : # Can uncomment for debugging: echo "[tmux.sh] NOTE: Sending multiline text" >&2
    fi

    # For long messages (>4KB), use buffer-based approach
    # This avoids issues with send-keys -l on large text
    if [[ $msg_len -gt 4096 ]]; then
        local tmpfile
        tmpfile=$(mktemp)
        printf '%s' "$keys" > "$tmpfile"

        # Load into named buffer and paste
        tmux load-buffer -b cmux-msg "$tmpfile"
        tmux paste-buffer -t "${session}:${window}" -b cmux-msg -d
        rm -f "$tmpfile"

        # Longer delay for large messages - Claude needs time to process
        sleep 0.5
    else
        # Send text literally for shorter messages
        tmux send-keys -t "${session}:${window}" -l "$keys"

        # Delay for paste to be processed by Claude Code
        # Claude shows "[Pasted text #N +X lines]" and needs time before Enter
        if [[ "$keys" == *$'\n'* ]]; then
            sleep 0.3  # 300ms delay for multiline (was 150ms - too short)
        else
            sleep 0.1  # 100ms for single line (was 50ms)
        fi
    fi

    tmux send-keys -t "${session}:${window}" Enter
}

# Send interrupt (Ctrl+C) to a tmux window
tmux_send_interrupt() {
    local session="$1"
    local window="$2"
    tmux send-keys -t "${session}:${window}" C-c
}

# Capture pane content
tmux_capture_pane() {
    local session="$1"
    local window="$2"
    local lines="${3:-100}"
    tmux capture-pane -t "${session}:${window}" -p -S "-${lines}"
}

# Kill a tmux window
tmux_kill_window() {
    local session="$1"
    local window="$2"
    tmux kill-window -t "${session}:${window}" 2>/dev/null || true
}

# List all windows in a session
tmux_list_windows() {
    local session="$1"
    tmux list-windows -t "$session" -F "#{window_name}" 2>/dev/null || true
}

# Clear any text stuck in tmux input buffer
# Use this to recover from "[Pasted text]" situations where input is stuck
tmux_clear_input() {
    local session="$1"
    local window="$2"
    # Send Ctrl+U to clear the current line
    tmux send-keys -t "${session}:${window}" C-u
    # Send Escape to exit any special mode (like vim mode in Claude)
    tmux send-keys -t "${session}:${window}" Escape
    sleep 0.1
}
