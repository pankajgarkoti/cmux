#!/usr/bin/env bash
# Pre-compaction state capture hook
#
# Called by compact.sh BEFORE sending /compact to an agent.
# Captures the agent's current state as a structured JSON artifact
# so the agent can recover context after compaction.
#
# Usage: pre-compact.sh <agent_name>
#
# Writes artifact to: .cmux/journal/YYYY-MM-DD/artifacts/compaction-{agent}-{timestamp}.json

set -euo pipefail

AGENT_NAME="${1:-${CMUX_AGENT_NAME:-unknown}}"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CMUX_PORT="${CMUX_PORT:-8000}"

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
    '{
        agent_name: $agent_name,
        timestamp: $timestamp,
        files_modified: ($ARGS.positional // []),
        current_task: $current_task,
        open_questions: [],
        git_branch: $git_branch,
        uncommitted_changes: $uncommitted_changes,
        git_status: $git_status,
        terminal_snapshot: $terminal_snapshot
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
    "terminal_snapshot": ""
}
ENDJSON
fi

echo "$ARTIFACT_FILE"
