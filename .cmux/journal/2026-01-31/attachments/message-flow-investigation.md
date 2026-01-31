# Message Flow Investigation: Dashboard Display Issues

**Investigator**: worker-investigator
**Date**: 2026-01-31
**Status**: ROOT CAUSE IDENTIFIED

---

## Executive Summary

**Some supervisor messages fail to appear in the dashboard because of a regex bug in the router daemon that rejects addresses containing colons (e.g., `cmux:supervisor`).**

Messages to simple addresses like `user` work correctly. Messages to fully-qualified addresses like `cmux:worker-name` fail.

---

## Root Cause

### The Bug: `router.sh` line 77

```bash
if [[ "$line" =~ ^\[([^\]]+)\]\ ([^\ ]+)\ -\>\ ([^:]+):\ (.+)$ ]]; then
```

**Problem**: The "to" field pattern `([^:]+)` cannot handle addresses that contain colons.

- `[^:]+` means "one or more characters that are NOT colons"
- Address `cmux:worker-proposer` contains a colon
- Regex only matches `cmux`, then expects `: ` (colon-space)
- But actual text is `:worker-proposer:` - NO MATCH, message SKIPPED

### Proof from Router Log

```
2026-01-31T18:54:01+05:30 | SKIP | unknown -> unknown | invalid format: [2026-01-31T18:54:00+05:30] cmux:worker-critic -> ...
2026-01-31T18:54:55+05:30 | SKIP | unknown -> unknown | invalid format: [2026-01-31T18:54:55+05:30] cmux:worker-proposer -...
2026-01-31T20:17:11+05:30 | SKIP | unknown -> unknown | invalid format: [2026-01-31T20:17:10+05:30] cmux:worker-investigat...
```

ALL recent messages are SKIPPED due to this regex issue.

### Verification Test

```bash
# Original regex - FAILS
test_line="[2026-01-31T18:54:00+05:30] cmux:worker-critic -> cmux:worker-proposer: Critic Ready"
[[ "$test_line" =~ ^\[([^\]]+)\]\ ([^\ ]+)\ "->"\ ([^:]+):\ (.+)$ ]]
# Result: NO MATCH

# Fixed regex - WORKS
[[ "$test_line" =~ ^\[([^\]]+)\]\ ([^\ ]+)\ "->"\ ([^\ ]+):\ (.+)$ ]]
# Result: MATCH, to=cmux:worker-proposer

# Simple address (no colon) - WORKS with original
test_simple="[2026-01-31T18:54:00+05:30] cmux:worker -> user: Hello"
[[ "$test_simple" =~ ^\[([^\]]+)\]\ ([^\ ]+)\ "->"\ ([^:]+):\ (.+)$ ]]
# Result: MATCH, to=user
```

---

## Conditions: Messages That Appear vs Don't Appear

### Messages That APPEAR in Dashboard

| Condition | Example | Reason |
|-----------|---------|--------|
| Direct API calls to `/api/messages/user` | `./tools/mailbox send user "Hello"` | Bypasses router, goes direct to API |
| Messages to `user` via router | When router regex works | `user` has no colon |
| Messages sent via `POST /api/agents/{id}/message` | User sending to agent | Direct API, no router |
| Old multi-line messages already in mailbox | Historical messages | May have been routed before format change |

### Messages That DON'T APPEAR in Dashboard

| Condition | Example | Reason |
|-----------|---------|--------|
| Messages with session:agent addresses | `cmux:supervisor`, `cmux:worker-auth` | Colon in "to" breaks regex |
| Agent-to-agent messages | worker-a -> worker-b | Both use session:window format |
| Status/Done/Blocked to supervisor | `./tools/mailbox done "message"` | Supervisor address is `cmux:supervisor` |

---

## Message Flow Analysis

### Path 1: Mailbox -> Router -> Dashboard (BROKEN for session:agent)

```
Agent calls ./tools/mailbox
    └── Writes single-line to .cmux/mailbox
        └── router.sh polls mailbox
            └── parse_line() regex FAILS for session:agent addresses
                └── Message SKIPPED (never reaches API)
```

### Path 2: Direct to User API (WORKS)

```
Agent calls ./tools/mailbox send user "message"
    └── mailbox tool detects "user" as recipient
        └── Calls POST /api/messages/user directly
            └── WebSocket broadcasts "user_message" event
                └── Frontend displays message
```

### Path 3: User Message to Agent (WORKS)

```
User clicks Send in dashboard
    └── Frontend calls POST /api/agents/{id}/message
        └── stores message + broadcasts "new_message"
            └── Also sends to tmux via send-keys
```

---

## Fix Required

### Change in `src/orchestrator/router.sh` line 77:

**Before** (broken):
```bash
if [[ "$line" =~ ^\[([^\]]+)\]\ ([^\ ]+)\ -\>\ ([^:]+):\ (.+)$ ]]; then
```

**After** (fixed):
```bash
if [[ "$line" =~ ^\[([^\]]+)\]\ ([^\ ]+)\ -\>\ ([^\ ]+):\ (.+)$ ]]; then
```

**Change**: `([^:]+)` -> `([^\ ]+)` for the "to" field

This allows colons in the address while still correctly separating the "to" field from the subject (which follows `: `).

---

## Secondary Finding: Old Multi-Line Format in Mailbox

The mailbox contains old multi-line messages (lines 1-894) in this format:

```
--- MESSAGE ---
timestamp: 2026-01-31T02:00:00Z
from: worker-auth-advocate
to: worker-auth-critic
type: USER
id: advocate-opening-001
---
# Opening Defense...
```

These are ALSO skipped by the router because they don't match the single-line format at all. This is expected behavior - the router was designed for the new single-line format.

However, the `mailbox_service.py` still has methods that write this old format (`send_to_supervisor`, `send_message`). These should be updated or removed to avoid confusion.

---

## Files Analyzed

| File | Purpose | Finding |
|------|---------|---------|
| `src/orchestrator/router.sh:77` | Message routing | **BUG**: regex `[^:]+` for "to" field |
| `tools/mailbox` | Agent messaging tool | Works correctly, produces valid format |
| `src/server/routes/messages.py` | Message API endpoints | Works correctly |
| `src/server/websocket/manager.py` | WebSocket broadcast | Works correctly |
| `src/frontend/src/hooks/useWebSocket.ts` | Frontend message handling | Works correctly |
| `src/server/services/mailbox.py` | Message storage | Has old multi-line format methods (unused?) |

---

## Recommendations

1. **Immediate**: Fix the regex in `router.sh` line 77
2. **Short-term**: Add integration test for message routing with session:agent addresses
3. **Cleanup**: Remove or update old multi-line format methods in `mailbox_service.py`
4. **Monitoring**: Add metric for SKIP vs DELIVERED in router logs

---

## Investigation Complete

The root cause is a single-character regex issue. Changing `[^:]` to `[^\ ]` in the "to" field pattern will fix all message routing.
