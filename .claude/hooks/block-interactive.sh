#!/usr/bin/env bash
# PreToolUse hook: Block interactive tools for all unattended CMUX agents
#
# All CMUX agents (supervisor and workers) run in tmux windows with no
# human operator. Tools like AskUserQuestion and EnterPlanMode block
# forever waiting for input that will never come. This hook intercepts
# those calls and directs agents to use mailbox or text output instead.
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

# Only block for CMUX agents (any agent running in the tmux session).
# Non-CMUX agents (local dev, no CMUX_AGENT_NAME set) are allowed through.
if [[ -z "${CMUX_AGENT_NAME:-}" ]]; then
    exit 0
fi

# Block the tool call — tailor the message to agent role
if [[ "${CMUX_AGENT_NAME}" == "supervisor" ]]; then
    echo 'BLOCKED: The supervisor cannot use interactive tools — you are running unattended in tmux. Instead, communicate questions via direct text output or send messages via mailbox: ./tools/mailbox send <recipient> "<message>". Make decisions autonomously and document them in the journal.' >&2
else
    echo 'BLOCKED: Workers cannot use interactive tools — you are running unattended. Instead, send a [REVIEW-REQUEST] to the supervisor via mailbox: ./tools/mailbox send supervisor "[REVIEW-REQUEST] <describe what you need reviewed and your proposed approach>" Then continue working with your best judgment. The supervisor will spawn a reviewer agent if needed.' >&2
fi
exit 2
