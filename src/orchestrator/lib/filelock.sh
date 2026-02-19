#!/usr/bin/env bash
#===============================================================================
# filelock.sh - Portable file locking for cross-process mailbox coordination
#
# Provides mailbox_lock() and mailbox_unlock() using flock(2) system call.
# Works on both Linux (flock command) and macOS (python3 fcntl fallback).
#
# All writers to .cmux/mailbox MUST use these functions to prevent JSONL corruption
# from concurrent access by Python (mailbox.py), bash (tools/mailbox), and
# orchestrator scripts (router.sh, health.sh, log-watcher.sh).
#
# Usage:
#   source "path/to/lib/filelock.sh"
#   mailbox_lock
#   echo '{"json":"line"}' >> "$CMUX_MAILBOX"
#   mailbox_unlock
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
