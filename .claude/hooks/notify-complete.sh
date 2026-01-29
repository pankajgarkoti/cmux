#!/usr/bin/env bash
# Hook script: POST completion event to FastAPI
# Called by Claude Code Stop hook when response completes
#
# Only runs when CMUX_AGENT=true (set by orchestrator for managed agents)
# Uses CMUX_AGENT_NAME for human-readable agent identification
#
# Receives JSON on stdin with fields:
#   - session_id: identifies the agent
#   - transcript_path: full conversation JSONL file
#   - stop_hook_active: boolean indicating hook is running

# Exit early if not running as a CMUX-managed agent
[[ "${CMUX_AGENT:-}" != "true" ]] && exit 0

set -euo pipefail

# Configuration
CMUX_WEBHOOK_URL="${CMUX_WEBHOOK_URL:-http://localhost:8000/api/agent-events}"
AGENT_NAME="${CMUX_AGENT_NAME:-unknown}"

# Read JSON from stdin
input=$(cat)

# Extract session_id as backup identifier
session_id=$(echo "$input" | jq -r '.session_id // empty')

# Skip if no session_id
if [[ -z "$session_id" ]]; then
    exit 0
fi

# Build event payload - use CMUX_AGENT_NAME for agent_id
payload=$(jq -n \
    --arg event_type "Stop" \
    --arg agent_name "$AGENT_NAME" \
    --argjson hook_data "$input" \
    '{
        event_type: $event_type,
        session_id: $hook_data.session_id,
        agent_id: $agent_name,
        transcript_path: $hook_data.transcript_path
    }')

# POST to FastAPI (non-blocking, ignore errors)
curl -sf -X POST "$CMUX_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    --max-time 5 \
    >/dev/null 2>&1 || true
