---
name: mailbox
description: Send messages to other agents or the user. Use when you need to communicate with supervisor, other workers, or report to user.
allowed-tools: Bash(./tools/mailbox:*)
---

# Mailbox Communication

## You Are An Agent

You are a Claude Code agent running in a tmux window as part of the CMUX multi-agent orchestration system. You are NOT chatting with a human user directly.

**Your context:**
- You are `$CMUX_AGENT_NAME` in session `$CMUX_SESSION`
- Other agents (supervisor, workers) can send you messages
- You can send messages to other agents
- Messages appear in your terminal - respond to them!
- The human user watches via a web dashboard, not this terminal

**When you receive a message like:**
```
[cmux:supervisor] Review the auth implementation
  → .cmux/journal/2026-01-31/attachments/supervisor-1706695200.md
```
This is the supervisor assigning you a task. Read the file, do the work, and respond via mailbox.

---

## Commands

Send messages to other agents or the user via the mailbox.

### Send with body (detailed message)
```bash
./tools/mailbox send <to> "<subject>" "<body>"
```

### Quick notification (no body)
```bash
./tools/mailbox quick <to> "<subject>"
```

### Shortcuts
```bash
./tools/mailbox done "<summary>"      # -> supervisor: [DONE] summary
./tools/mailbox blocked "<issue>"     # -> supervisor: [BLOCKED] issue
./tools/mailbox status "<update>"     # -> supervisor: [STATUS] update
```

### Read recent messages
```bash
./tools/mailbox read [lines]          # Show last N mailbox entries
```

## Recipients

| Recipient | Example |
|-----------|---------|
| Same session agent | `supervisor`, `worker-auth` |
| Other session agent | `cmux-feature:worker-a` |
| Human user (dashboard) | `user` |

## Examples

```bash
# Send detailed analysis
./tools/mailbox send worker-auth "JWT Review" "Found issues in token.py:
- Line 42: expiration logic incorrect
- Line 58: missing refresh token handling"

# Quick status update
./tools/mailbox quick supervisor "Starting auth work"

# Report done
./tools/mailbox done "JWT implementation complete, tests passing"

# Report blocked
./tools/mailbox blocked "Need API credentials from secrets"

# Progress update
./tools/mailbox status "Token refresh logic implemented, running tests"

# Message to user
./tools/mailbox send user "Bug Fixed" "Fixed token.py line 42, see commit abc123"
```

## Mailbox Format

Single-line entries in `.cmux/mailbox`:
```
[timestamp] from -> to: subject (body: path)
```

Example entries:
```
[2026-01-31T06:00:00Z] cmux:worker-auth -> cmux:supervisor: [DONE] JWT complete (body: .cmux/journal/2026-01-31/attachments/worker-auth-1706695200.md)
[2026-01-31T06:05:00Z] cmux:supervisor -> cmux:worker-auth: [TASK] Add refresh tokens
```

## How It Works

1. `send` creates a body file in `.cmux/journal/YYYY-MM-DD/attachments/`
2. Appends single-line entry to `.cmux/mailbox`
3. Router daemon reads mailbox, delivers to target agent's tmux
4. Messages to `user` go directly to dashboard API

## Common Workflow

### When You Start Work
```bash
./tools/mailbox status "Starting on the assigned task"
```

### During Work (if long-running)
```bash
./tools/mailbox status "Halfway done, implementing X"
```

### When You're Blocked
```bash
./tools/mailbox blocked "Cannot find the auth module - need path"
```

### When You're Done
```bash
./tools/mailbox done "Task complete - files: src/auth.py, tests pass"
```

### To Ask Another Agent
```bash
./tools/mailbox send worker-tests "Run auth tests" "Please run pytest tests/test_auth.py and report results"
```
