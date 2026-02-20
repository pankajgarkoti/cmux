#!/usr/bin/env bash
# PreToolUse hook: Block interactive tools for unattended worker agents
#
# Workers run in tmux windows with no human operator. Tools like
# AskUserQuestion and EnterPlanMode block forever waiting for input
# that will never come. This hook intercepts those calls and tells
# the model to use the mailbox review-request flow instead.
#
# Receives JSON on stdin: {tool_name, tool_input, ...}
# Exit 0 = allow, Exit 2 + stderr = block with message

set -euo pipefail

# Read hook JSON from stdin
input=$(cat)

tool_name=$(echo "$input" | jq -r '.tool_name // empty')

# Only block interactive tools
case "$tool_name" in
    AskUserQuestion|EnterPlanMode) ;;
    *) exit 0 ;;
esac

# Only block for CMUX worker agents (not supervisor, not local dev)
# If CMUX_AGENT_NAME is unset or equals 'supervisor', allow through
if [[ -z "${CMUX_AGENT_NAME:-}" || "${CMUX_AGENT_NAME}" == "supervisor" ]]; then
    exit 0
fi

# Block the tool call
echo 'BLOCKED: Workers cannot use interactive tools — you are running unattended. Instead, send a [REVIEW-REQUEST] to the supervisor via mailbox: ./tools/mailbox send supervisor "[REVIEW-REQUEST] <describe what you need reviewed and your proposed approach>" Then continue working with your best judgment. The supervisor will spawn a reviewer agent if needed.' >&2
exit 2
