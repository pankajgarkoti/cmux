#!/usr/bin/env bash
# Post-compaction context recovery hook (SessionStart, matcher: compact)
#
# When Claude Code resumes a session after compaction, this hook fires
# and injects the pre-compaction state artifact into the agent's context.
#
# Receives JSON on stdin from Claude Code with session info.
# Outputs to stdout — Claude Code injects this as context automatically.

set -euo pipefail

AGENT_NAME="${CMUX_AGENT_NAME:-}"
# Prefer CMUX_HOME for workers in external directories
PROJECT_ROOT="${CMUX_HOME:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Read stdin (required by hook protocol) but we primarily use env vars
cat > /dev/null 2>&1 || true

# If no agent name, we can't find the artifact
if [[ -z "$AGENT_NAME" ]]; then
    echo "Session resumed after compaction. No CMUX_AGENT_NAME set — check the journal for recent context:"
    echo "  ./tools/journal read"
    exit 0
fi

TODAY=$(date +%Y-%m-%d)
ARTIFACT_DIR="${PROJECT_ROOT}/.cmux/journal/${TODAY}/artifacts"

# Find the most recent compaction artifact for this agent
LATEST_ARTIFACT=""
if [[ -d "$ARTIFACT_DIR" ]]; then
    LATEST_ARTIFACT=$(ls -t "${ARTIFACT_DIR}/compaction-${AGENT_NAME}-"*.json 2>/dev/null | head -1 || true)
fi

# Also check yesterday in case compaction happened near midnight
if [[ -z "$LATEST_ARTIFACT" ]]; then
    YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d 2>/dev/null || true)
    if [[ -n "$YESTERDAY" ]]; then
        YESTERDAY_DIR="${PROJECT_ROOT}/.cmux/journal/${YESTERDAY}/artifacts"
        if [[ -d "$YESTERDAY_DIR" ]]; then
            LATEST_ARTIFACT=$(ls -t "${YESTERDAY_DIR}/compaction-${AGENT_NAME}-"*.json 2>/dev/null | head -1 || true)
        fi
    fi
fi

if [[ -n "$LATEST_ARTIFACT" && -s "$LATEST_ARTIFACT" ]]; then
    echo "=== PRE-COMPACTION STATE FOR ${AGENT_NAME} ==="
    echo ""
    cat "$LATEST_ARTIFACT"
    echo ""
    echo "=== END PRE-COMPACTION STATE ==="
    echo ""
    echo "You were just compacted. Above is your pre-compaction state. Check the journal and your conversation history if anything is unclear."
    echo ""
    echo "Recovery steps:"
    echo "  1. Review the artifact above for your task, git state, and recent activity"
    echo "  2. Read recent journal: ./tools/journal read"
    echo "  3. Check your worker context: cat ${PROJECT_ROOT}/.cmux/worker-contexts/worker-${AGENT_NAME}-context.md"
else
    echo "You were just compacted but no compaction artifact was found for agent '${AGENT_NAME}'."
    echo ""
    echo "Recovery steps:"
    echo "  1. Read the journal for recent context: ./tools/journal read"
    echo "  2. Check your worker context: cat ${PROJECT_ROOT}/.cmux/worker-contexts/worker-${AGENT_NAME}-context.md"
    echo "  3. Check conversation history: curl -s http://localhost:8000/api/agents/${AGENT_NAME}/history?limit=20 | jq '.messages'"
fi
