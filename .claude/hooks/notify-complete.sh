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

# Extract transcript_path and read the agent's response content
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

response_content=""
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    # Transcript format: each line is JSON with {type, message}
    # type can be "user", "assistant", etc.
    # message is either a string or object with content[0].text
    response_content=$(tail -100 "$transcript_path" | \
        jq -rs '
            [.[] | select(.type == "assistant")] | last |
            if . == null then ""
            elif .message | type == "string" then .message
            elif .message.content then
                [.message.content[] | select(.type == "text") | .text] | join("")
            else ""
            end
        ' 2>/dev/null || echo "")
fi

# Build event payload - use CMUX_AGENT_NAME for agent_id
payload=$(jq -n \
    --arg event_type "Stop" \
    --arg agent_name "$AGENT_NAME" \
    --arg response_content "$response_content" \
    --argjson hook_data "$input" \
    '{
        event_type: $event_type,
        session_id: $hook_data.session_id,
        agent_id: $agent_name,
        transcript_path: $hook_data.transcript_path,
        response_content: (if $response_content == "" then null else $response_content end)
    }')

# POST to FastAPI (non-blocking, ignore errors)
curl -sf -X POST "$CMUX_WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    --max-time 5 \
    >/dev/null 2>&1 || true
