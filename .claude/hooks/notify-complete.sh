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

# Debug log
DEBUG_LOG="/tmp/cmux_hook_debug.log"

# Exit early if not running as a CMUX-managed agent
[[ "${CMUX_AGENT:-}" != "true" ]] && exit 0

set -euo pipefail

echo "=== $(date) ===" >> "$DEBUG_LOG"
echo "CMUX_AGENT_NAME=$CMUX_AGENT_NAME" >> "$DEBUG_LOG"

# Configuration
CMUX_WEBHOOK_URL="${CMUX_WEBHOOK_URL:-http://localhost:8000/api/agent-events}"
AGENT_NAME="${CMUX_AGENT_NAME:-unknown}"

# Read JSON from stdin
input=$(cat)

# Log raw input from Claude Code
echo "RAW_INPUT=$(echo "$input" | jq -c '.')" >> "$DEBUG_LOG"

# Extract session_id as backup identifier
session_id=$(echo "$input" | jq -r '.session_id // empty')

# Skip if no session_id
if [[ -z "$session_id" ]]; then
    exit 0
fi

# Extract transcript_path and read the agent's response content
transcript_path=$(echo "$input" | jq -r '.transcript_path // empty')

# Small delay to ensure transcript is fully written
sleep 0.2

echo "transcript_path=$transcript_path" >> "$DEBUG_LOG"
echo "file_exists=$(test -f "$transcript_path" && echo yes || echo no)" >> "$DEBUG_LOG"

response_content=""
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
    # Transcript format: each line is JSON with {type, message}
    # type can be "user", "assistant", etc.
    # message.content is an array that may contain text, thinking, or tool_use blocks
    # We want the text from the MOST RECENT assistant entry that has text content
    response_content=$(tail -100 "$transcript_path" | \
        jq -rs '
            # Get all assistant entries, newest last
            [.[] | select(.type == "assistant")] |
            # Reverse so newest is first
            reverse |
            # Find the first entry that has text content
            [.[] |
                # Get text content from this entry
                [.message.content[]? | select(.type == "text") | .text] |
                # Only keep if non-empty
                select(length > 0) |
                # Join multiple text blocks
                join("\n")
            ] |
            # Return first (newest) non-empty text
            if length > 0 then .[0] else "" end
        ' 2>/dev/null || echo "")

    echo "response_content_len=${#response_content}" >> "$DEBUG_LOG"
    echo "response_preview=${response_content:0:80}" >> "$DEBUG_LOG"

    # Also log all text entries found
    tail -50 "$transcript_path" | jq -c 'select(.type == "assistant") | [.message.content[]? | select(.type == "text") | .text[0:40]]' 2>/dev/null | tail -5 >> "$DEBUG_LOG"
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
