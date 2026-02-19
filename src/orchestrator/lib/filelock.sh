#!/usr/bin/env bash
#===============================================================================
# filelock.sh - Portable file locking for cross-process coordination
#
# Provides locking via flock(2) system call.
# Works on both Linux (flock command) and macOS (python3 fcntl fallback).
#
# Mailbox lock: mailbox_lock() / mailbox_unlock()
#   All writers to .cmux/mailbox MUST use these to prevent JSONL corruption.
#
# Tmux send lock: tmux_send_lock(window) / tmux_send_unlock()
#   All scripts that send-keys to agent tmux windows SHOULD use these to
#   prevent interleaved input (router.sh, journal-nudge.sh, compact.sh).
#
# Usage:
#   source "path/to/lib/filelock.sh"
#   mailbox_lock; echo '{"json":"line"}' >> "$CMUX_MAILBOX"; mailbox_unlock
#   tmux_send_lock "worker-1"; tmux send-keys ...; tmux_send_unlock
#===============================================================================

CMUX_MAILBOX_LOCKFILE="/tmp/cmux-mailbox.lock"
_CMUX_LOCK_FD=9

mailbox_lock() {
    # Open lock file on fd 9
    eval "exec ${_CMUX_LOCK_FD}>\"${CMUX_MAILBOX_LOCKFILE}\""

    if command -v flock &>/dev/null; then
        # Linux: use flock command directly
        flock -x ${_CMUX_LOCK_FD}
    else
        # macOS: use Python's fcntl (same flock(2) syscall, cross-process compatible)
        python3 -c "import fcntl; fcntl.flock(${_CMUX_LOCK_FD}, fcntl.LOCK_EX)"
    fi
}

mailbox_unlock() {
    # Closing the fd releases the flock
    eval "exec ${_CMUX_LOCK_FD}>&-"
}

#-------------------------------------------------------------------------------
# Per-window tmux send locking
# Prevents router, journal-nudge, and compact from interleaving send-keys
#-------------------------------------------------------------------------------

_CMUX_TMX_LOCK_FD=8

tmux_send_lock() {
    local window="$1"
    local lockfile="/tmp/cmux-tmux-send-${window}.lock"

    eval "exec ${_CMUX_TMX_LOCK_FD}>\"${lockfile}\""

    if command -v flock &>/dev/null; then
        flock -x ${_CMUX_TMX_LOCK_FD}
    else
        python3 -c "import fcntl; fcntl.flock(${_CMUX_TMX_LOCK_FD}, fcntl.LOCK_EX)"
    fi
}

tmux_send_unlock() {
    eval "exec ${_CMUX_TMX_LOCK_FD}>&-"
}
