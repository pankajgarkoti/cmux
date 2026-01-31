# Message System Issues - Fix Required

**Date**: 2026-01-31
**Status**: Needs fixing

---

## Issues to Fix

### Issue 1: Router Regex Too Fragile

**File**: `src/orchestrator/router.sh:77`

**Current regex**:
```bash
^\[([^\]]+)\]\ ([^\ ]+)\ -\>\ ([^:]+):\ (.+)$
```

**Problems**:
1. `([^:]+)` for "to" field breaks on addresses with colons (`cmux:supervisor`)
2. Regex is brittle - any unexpected character breaks parsing
3. Escaping `->` may have issues across bash versions

**Requirements for fix**:
- Handle `session:agent` addresses (colons in to/from fields)
- Handle special characters in subject (emojis, brackets, quotes, etc.)
- Make parsing robust - prefer partial match over total failure
- Log what was parsed vs what failed for debugging

---

### Issue 2: Supervisor Replies Not Reaching Frontend

**Symptom**: User reports my (supervisor) responses don't always appear in dashboard, even though tool calls and events update in real-time.

**Observations**:
- Tool use events show up (via agent_events webhook)
- Some messages appear, others don't
- WebSocket connection works (events stream in real-time)

**Hypothesis**:
- Messages routed via mailbox → router → API fail due to regex
- Messages I output to terminal don't automatically reach dashboard
- Only explicit `./tools/mailbox send user "..."` calls work

**To investigate**:
- How should supervisor replies reach the dashboard?
- Is there a missing mechanism for supervisor text output → frontend?
- Check if WebSocket broadcast for "new_message" is being called

---

### Issue 3: Multiline Paste + Enter Timing

**File**: `src/server/services/tmux_service.py:70-85` and `src/orchestrator/lib/tmux.sh:32-40`

**Symptom**: When sending multiline messages to agents via tmux:
1. Text is pasted correctly
2. Claude Code shows `[Pasted text #1 +N lines]`
3. Enter key doesn't register - user must manually press Enter

**Current implementation**:
```python
# Step 1: Send text LITERALLY (no Enter)
await self._run_command(["tmux", "send-keys", "-t", target, "-l", text])
# Step 2: Send Enter SEPARATELY
await self._run_command(["tmux", "send-keys", "-t", target, "Enter"])
```

**Possible causes**:
- Timing issue between paste and Enter
- Claude Code paste mode needs delay before Enter
- Multi-line detection in Claude triggers different input handling

**Fix options**:
- Add small delay between text and Enter
- Send Enter multiple times
- Use different tmux send approach

---

### Issue 4: Old Multi-Line Format in mailbox_service.py

**File**: `src/server/services/mailbox.py`

**Problem**: Methods `send_to_supervisor()` and `send_message()` write old multi-line format:
```
--- MESSAGE ---
timestamp: ...
from: ...
to: ...
---
content
```

But router expects single-line format:
```
[timestamp] from -> to: subject (body: path)
```

**Fix**: Remove or update these methods to use single-line format, or remove them if unused.

---

## Priority Order

1. **Router regex** - Fix immediately, blocks all agent-to-agent communication
2. **Supervisor replies** - Investigate why my replies don't show up
3. **Multiline Enter** - Add delay or fix timing
4. **Old format cleanup** - Remove confusion from codebase

---

## Acceptance Criteria

- [ ] All messages with `session:agent` addresses route correctly
- [ ] Messages with special characters (emojis, brackets, quotes) parse correctly
- [ ] Supervisor responses appear in dashboard consistently
- [ ] Multiline messages to agents don't get stuck waiting for Enter
- [ ] No old multi-line format code remains (or is clearly deprecated)
- [ ] Router logs show DELIVERED not SKIP for valid messages

---

## Test Cases for Router

After fix, these should ALL parse correctly:

```
[2026-01-31T18:54:00+05:30] cmux:worker-a -> cmux:worker-b: Hello
[2026-01-31T18:54:00+05:30] cmux:worker -> user: Task done!
[2026-01-31T18:54:00+05:30] cmux:supervisor -> cmux:worker-auth: [TASK] Fix the bug
[2026-01-31T18:54:00+05:30] worker -> supervisor: [DONE] Completed task
[2026-01-31T18:54:00+05:30] cmux:worker -> user: Here's the result: {"status": "ok"}
[2026-01-31T18:54:00+05:30] cmux:worker -> user: Check file (body: /path/to/file.md)
[2026-01-31T18:54:00+05:30] cmux:worker -> user: Done! 🎉
```
