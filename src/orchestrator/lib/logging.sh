#!/usr/bin/env bash
# Logging utilities for cmux orchestrator

CMUX_STATUS_LOG="${CMUX_STATUS_LOG:-.multiclaude/status.log}"
CMUX_IMPL_LOG="${CMUX_IMPL_LOG:-.multiclaude/implementation.log}"

# Ensure log directory exists
_ensure_log_dir() {
    mkdir -p "$(dirname "$CMUX_STATUS_LOG")"
    mkdir -p "$(dirname "$CMUX_IMPL_LOG")"
}

# Log a status message (for status.log)
log_status() {
    _ensure_log_dir
    local status="$1"
    shift
    local message="$*"
    echo "$(date -Iseconds) [${status}] ${message}" >> "$CMUX_STATUS_LOG"
}

# Log an implementation detail (for implementation.log)
log_impl() {
    _ensure_log_dir
    local message="$*"
    echo "$(date -Iseconds) ${message}" >> "$CMUX_IMPL_LOG"
}

# Log to stdout with color
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}
