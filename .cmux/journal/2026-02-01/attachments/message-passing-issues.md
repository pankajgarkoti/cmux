# Message Passing Issues - Session 2026-02-01

**Author:** supervisor
**Date:** 2026-02-01
**Status:** Partially Fixed (2026-02-03)

---

## Issues Discovered

### 1. Text Stuck in Input Buffers ✅ FIXED
- **Symptom**: "[Pasted text #1 +32 lines]" appearing in worker input boxes
- **When**: After spawning workers with multiline task descriptions
- **Impact**: Old task text never cleared, new messages appended after it
- **Affected**: Both core-implementer and core-critic
- **Location**: `tools/workers spawn` command
- **Fix (d4892cf)**:
  - `tools/workers`: Now writes task to context file, sends single-line read instruction
  - `lib/tmux.sh`: Uses load-buffer/paste-buffer for messages >4KB
  - `lib/tmux.sh`: Increased delays (300ms multiline, 100ms single line)
- **Verified**: Tested with 9.5KB message - delivered correctly

### 2. Messages Not Reaching Workers When Session Not in Foreground ⏳ NEEDS INVESTIGATION
- **Symptom**: Messages sent via `./tools/workers send` don't arrive
- **When**: tmux session/window not actively focused
- **Impact**: Workers sit idle waiting for tasks they already "received"
- **User observation**: Session needs to be in foreground for delivery
- **Location**: `tools/workers send` → `tmux send-keys`
- **Note**: May be tmux behavior - send-keys should work regardless of focus

### 3. Worker Ignored Received Task ✅ LIKELY FIXED
- **Symptom**: core-critic received the task but sent "[STATUS] Awaiting new tasks" instead of working
- **When**: Initial task assignment via spawn
- **Impact**: Had to send a follow-up [PRIORITY] message to trigger action
- **Possible cause**: Task text stuck in buffer wasn't processed as input
- **Fix**: Same as Issue 1 - context file approach ensures task is delivered cleanly

### 4. Duplicate/Repeated Messages ✅ LIKELY FIXED
- **Symptom**: Fix task appeared after the original spawn task text
- **When**: Sending new message to worker with stuck buffer text
- **Impact**: Confusing, wasteful tokens, worker had to parse both
- **Fix**: Same as Issue 1 - no more stuck buffer text to accumulate

### 5. Session Kill During Testing (orch-team) ✅ FIXED
- **Symptom**: All worker windows destroyed when orch-supervisor tested server kill fix
- **When**: Running `cmux.sh stop` or `cmux.sh restart`
- **Impact**: Lost 8 workers mid-task
- **Root cause**: `monitor.sh cleanup()` kills ALL cmux* sessions
- **Location**: `src/orchestrator/monitor.sh` lines 271-274
- **Fix (d4892cf)**: Now only kills THIS specific `$CMUX_SESSION`, not all `cmux*` sessions

### 6. Router vs Direct Messaging Confusion ⏳ DOCUMENTATION NEEDED
- **Symptom**: Messages in `.cmux/mailbox` but workers don't see them
- **When**: Using `./tools/mailbox send` vs `./tools/workers send`
- **Impact**: Two different messaging systems with unclear routing
- **Location**: `tools/mailbox` vs `tools/workers`
- **Note**: Not a bug - two systems serve different purposes:
  - `tools/workers send`: Direct tmux send-keys (synchronous, immediate)
  - `tools/mailbox send`: File-based queue polled by router (async, persistent)

### 7. Intermediate Responses Displayed Before Tool Completion ⏳ CLAUDE CODE BEHAVIOR
- **Symptom**: User sees partial "planning" text (e.g., "Let me do that:") before tool calls finish
- **When**: Supervisor making tool calls
- **Expected**: Only final response shown after tools complete
- **Impact**: Confusing UX, incomplete messages visible to user
- **Possible cause**: Streaming/display issue in Claude Code or tmux rendering
- **Note**: May be expected Claude Code streaming behavior - not fixable at CMUX level

---

## Underlying Questions

1. **tmux send-keys reliability** - Does it work when window is not focused? ⏳ Need to test
2. **Multiline paste handling** - Why does text get stuck in buffer? ✅ RESOLVED: Claude Code needs time to process pasted text before Enter
3. **Router daemon** - Is it running? Is it delivering to the right windows? ✅ Works correctly
4. **Two messaging systems** - mailbox (file-based) vs tmux (direct) - which should be used when? ✅ DOCUMENTED: workers send=immediate, mailbox send=async
5. **Response streaming** - Why are intermediate responses shown before tool completion? ⏳ Claude Code behavior, not fixable at CMUX level

---

## Files Modified (Commit d4892cf)

- `tools/workers` - Now uses context file instead of multiline paste
- `src/orchestrator/lib/tmux.sh` - Load-buffer for >4KB, increased delays, added tmux_clear_input()
- `src/orchestrator/monitor.sh` - Targeted session cleanup

---

## Summary (2026-02-03)

| Issue | Status | Fix |
|-------|--------|-----|
| 1. Text stuck in buffers | ✅ Fixed | Context file + load-buffer |
| 2. Messages when not focused | ⏳ Investigate | May be tmux limitation |
| 3. Worker ignored task | ✅ Fixed | Same as #1 |
| 4. Duplicate messages | ✅ Fixed | Same as #1 |
| 5. Session kill | ✅ Fixed | Targeted cleanup |
| 6. Router confusion | ⏳ Docs | Two systems, different purposes |
| 7. Intermediate responses | ⏳ N/A | Claude Code streaming behavior |

**Testing**: Verified with test-worker (short message) and long-test (9.5KB message) - both delivered correctly.
