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
    tmux list-windows -t "$session" -F "#{window_name}" 2>/dev/null | grep -q "^${window}$"
}

# Create a new tmux window
tmux_create_window() {
    local session="$1"
    local name="$2"
    # Use session: syntax to append window without specifying index
    tmux new-window -t "${session}:" -n "$name"
}

# Send keys to a tmux window
tmux_send_keys() {
    local session="$1"
    local window="$2"
    shift 2
    local keys="$*"
    # Send text literally, then send Enter as separate command
    tmux send-keys -t "${session}:${window}" -l "$keys"
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
