#!/usr/bin/env bash
# Pre-compaction state capture hook
#
# Can be called two ways:
#   1. By compact.sh directly:  pre-compact.sh <agent_name>
#   2. As a Claude Code PreCompact hook: receives JSON on stdin with transcript_path
#
# Captures the agent's current state as a structured JSON artifact
# so the agent can recover context after compaction.
#
# Writes artifact to: .cmux/journal/YYYY-MM-DD/artifacts/compaction-{agent}-{timestamp}.json

set -euo pipefail

# Prefer CMUX_HOME for workers in external directories
PROJECT_ROOT="${CMUX_HOME:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
CMUX_PORT="${CMUX_PORT:-8000}"

# --- Determine invocation mode and read stdin if available ---
STDIN_JSON=""
TRANSCRIPT_PATH=""

# Try to read JSON from stdin (non-blocking)
if [[ ! -t 0 ]]; then
    STDIN_JSON=$(cat 2>/dev/null || true)
    if [[ -n "$STDIN_JSON" ]]; then
        TRANSCRIPT_PATH=$(echo "$STDIN_JSON" | jq -r '.transcript_path // empty' 2>/dev/null || true)
    fi
fi

# Agent name: $1 > stdin session_id > env var > unknown
if [[ -n "${1:-}" ]]; then
    AGENT_NAME="$1"
elif [[ -n "$STDIN_JSON" ]]; then
    AGENT_NAME=$(echo "$STDIN_JSON" | jq -r '.session_id // empty' 2>/dev/null || true)
    AGENT_NAME="${AGENT_NAME:-${CMUX_AGENT_NAME:-unknown}}"
else
    AGENT_NAME="${CMUX_AGENT_NAME:-unknown}"
fi

# Paths
TODAY=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%H%M%S)
ARTIFACT_DIR="${PROJECT_ROOT}/.cmux/journal/${TODAY}/artifacts"
ARTIFACT_FILE="${ARTIFACT_DIR}/compaction-${AGENT_NAME}-${TIMESTAMP}.json"

# Ensure artifact directory exists
mkdir -p "$ARTIFACT_DIR"

# --- Capture git state ---
GIT_BRANCH=$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
GIT_DIFF_NAMES=$(git -C "$PROJECT_ROOT" diff --name-only 2>/dev/null || echo "")
GIT_STAGED_NAMES=$(git -C "$PROJECT_ROOT" diff --cached --name-only 2>/dev/null || echo "")
GIT_STATUS=$(git -C "$PROJECT_ROOT" status --short 2>/dev/null || echo "")
UNCOMMITTED=$([ -n "$GIT_STATUS" ] && echo "true" || echo "false")

# Combine modified files (both staged and unstaged)
ALL_MODIFIED=$(printf '%s\n%s' "$GIT_DIFF_NAMES" "$GIT_STAGED_NAMES" | sort -u | sed '/^$/d')

# --- Capture terminal output via API ---
TERMINAL_OUTPUT=""
if curl -sf "http://localhost:${CMUX_PORT}/api/agents/${AGENT_NAME}/terminal?lines=50" >/dev/null 2>&1; then
    TERMINAL_OUTPUT=$(curl -sf "http://localhost:${CMUX_PORT}/api/agents/${AGENT_NAME}/terminal?lines=50" | jq -r '.output // ""' 2>/dev/null || echo "")
fi

# --- Extract recent reasoning from transcript JSONL ---
RECENT_REASONING=""
if [[ -n "$TRANSCRIPT_PATH" && -f "$TRANSCRIPT_PATH" ]]; then
    # Read last 100 lines of JSONL transcript, extract assistant messages and tool calls
    RECENT_REASONING=$(tail -100 "$TRANSCRIPT_PATH" 2>/dev/null | jq -r '
        select(.type == "assistant" or .type == "tool_result" or .type == "tool_use") |
        if .type == "assistant" then
            "ASSISTANT: " + (
                if (.message.content | type) == "array" then
                    [.message.content[] | select(.type == "text") | .text] | join("\n")
                elif (.message.content | type) == "string" then
                    .message.content
                else
                    "(non-text content)"
                end
            )
        elif .type == "tool_use" then
            "TOOL_USE: " + (.name // "unknown") + " -> " + ((.input | tostring)[:200] // "")
        elif .type == "tool_result" then
            "TOOL_RESULT: " + ((.content // "")[:200])
        else empty end
    ' 2>/dev/null | tail -50 || true)
fi

# --- Try to extract current task from last mailbox message ---
CURRENT_TASK=""
if [ -f "${PROJECT_ROOT}/.cmux/mailbox" ]; then
    # Find the last message addressed to this agent
    CURRENT_TASK=$(grep -A 5 "to: ${AGENT_NAME}" "${PROJECT_ROOT}/.cmux/mailbox" 2>/dev/null | tail -1 || echo "")
fi

# --- Build JSON artifact ---
# Use jq to construct proper JSON (handles escaping)
jq -n \
    --arg agent_name "$AGENT_NAME" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg git_branch "$GIT_BRANCH" \
    --argjson uncommitted_changes "$UNCOMMITTED" \
    --arg current_task "$CURRENT_TASK" \
    --arg terminal_snapshot "$TERMINAL_OUTPUT" \
    --arg git_status "$GIT_STATUS" \
    --arg recent_reasoning "$RECENT_REASONING" \
    --arg transcript_path "${TRANSCRIPT_PATH:-}" \
    '{
        agent_name: $agent_name,
        timestamp: $timestamp,
        files_modified: ($ARGS.positional // []),
        current_task: $current_task,
        open_questions: [],
        git_branch: $git_branch,
        uncommitted_changes: $uncommitted_changes,
        git_status: $git_status,
        terminal_snapshot: $terminal_snapshot,
        recent_reasoning: $recent_reasoning,
        transcript_path: $transcript_path
    }' \
    --args -- $(echo "$ALL_MODIFIED" | tr '\n' ' ') \
    > "$ARTIFACT_FILE" 2>/dev/null

# If jq failed or produced empty file, write a minimal artifact
if [ ! -s "$ARTIFACT_FILE" ]; then
    cat > "$ARTIFACT_FILE" << ENDJSON
{
    "agent_name": "${AGENT_NAME}",
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "files_modified": [],
    "current_task": "",
    "open_questions": [],
    "git_branch": "${GIT_BRANCH}",
    "uncommitted_changes": ${UNCOMMITTED},
    "git_status": "",
    "terminal_snapshot": "",
    "recent_reasoning": "",
    "transcript_path": ""
}
ENDJSON
fi

echo "$ARTIFACT_FILE"
