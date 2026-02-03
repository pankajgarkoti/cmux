# Message Passing Issues - Session 2026-02-01

**Author:** supervisor
**Date:** 2026-02-01
**Status:** Investigation needed

---

## Issues Discovered

### 1. Text Stuck in Input Buffers
- **Symptom**: "[Pasted text #1 +32 lines]" appearing in worker input boxes
- **When**: After spawning workers with multiline task descriptions
- **Impact**: Old task text never cleared, new messages appended after it
- **Affected**: Both core-implementer and core-critic
- **Location**: `tools/workers spawn` command

### 2. Messages Not Reaching Workers When Session Not in Foreground
- **Symptom**: Messages sent via `./tools/workers send` don't arrive
- **When**: tmux session/window not actively focused
- **Impact**: Workers sit idle waiting for tasks they already "received"
- **User observation**: Session needs to be in foreground for delivery
- **Location**: `tools/workers send` → `tmux send-keys`

### 3. Worker Ignored Received Task
- **Symptom**: core-critic received the task but sent "[STATUS] Awaiting new tasks" instead of working
- **When**: Initial task assignment via spawn
- **Impact**: Had to send a follow-up [PRIORITY] message to trigger action
- **Possible cause**: Task text stuck in buffer wasn't processed as input

### 4. Duplicate/Repeated Messages
- **Symptom**: Fix task appeared after the original spawn task text
- **When**: Sending new message to worker with stuck buffer text
- **Impact**: Confusing, wasteful tokens, worker had to parse both

### 5. Session Kill During Testing (orch-team)
- **Symptom**: All worker windows destroyed when orch-supervisor tested server kill fix
- **When**: Running `cmux.sh stop` or `cmux.sh restart`
- **Impact**: Lost 8 workers mid-task
- **Root cause**: `monitor.sh cleanup()` kills ALL cmux* sessions
- **Location**: `src/orchestrator/monitor.sh` lines 271-274

### 6. Router vs Direct Messaging Confusion
- **Symptom**: Messages in `.cmux/mailbox` but workers don't see them
- **When**: Using `./tools/mailbox send` vs `./tools/workers send`
- **Impact**: Two different messaging systems with unclear routing
- **Location**: `tools/mailbox` vs `tools/workers`

---

## Underlying Questions

1. **tmux send-keys reliability** - Does it work when window is not focused?
2. **Multiline paste handling** - Why does text get stuck in buffer?
3. **Router daemon** - Is it running? Is it delivering to the right windows?
4. **Two messaging systems** - mailbox (file-based) vs tmux (direct) - which should be used when?

---

## Files to Investigate

- `tools/workers` - spawn and send commands
- `tools/mailbox` - file-based messaging
- `src/orchestrator/router.sh` - message routing daemon
- `src/orchestrator/lib/tmux.sh` - tmux helper functions
- `src/orchestrator/monitor.sh` - cleanup function

---

## Next Steps

1. Investigate root causes in codebase
2. Create a plan to fix
3. Implement fixes
4. Test message passing end-to-end
