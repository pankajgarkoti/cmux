# Project Supervisor Chat Visibility Investigation

**Date:** 2026-02-20
**Investigator:** worker-sup-chat-visibility

## Problem Statement

Project supervisor agents (sup-hello-world, sup-hero, sup-heroweb) show empty or near-empty chat panels in the dashboard. The main supervisor has 133 messages visible; project supervisors have 0-2 visible messages each despite being active.

## Message Flow Analysis

### How the main supervisor's messages work (133+ visible)

1. **User → Supervisor (UI chat):**
   - User types in ChatPanel → `POST /api/agents/supervisor/message` (`agents.py:86`)
   - This stores `Message(from_agent="user", to_agent="supervisor")` in DB
   - Then sends content via tmux to the supervisor window

2. **Supervisor → User (Stop hook):**
   - Every time the supervisor produces output, `notify-complete.sh` fires
   - Posts to `/api/agent-events` which calls `agent_events.py:55-81`
   - Creates `Message(from_agent="supervisor", to_agent="user")` and stores in DB
   - This is how supervisor responses appear in the chat

3. **Frontend filter (ChatPanel.tsx:55-60):**
   ```tsx
   filtered = filtered.filter(
     (m) =>
       (m.from_agent === selectedAgentId && m.to_agent === 'user') ||
       (m.from_agent === 'user' && m.to_agent === selectedAgentId)
   );
   ```
   Only shows messages where one party is `"user"`. Works for main supervisor.

### Why project supervisors show empty

#### Root Cause 1: Task assignments via `tools/workers send` are never stored

When Supervisor Prime sends work to a project supervisor, it uses `tools/workers send`:
```bash
# tools/workers, cmd_send() line 412:
tmux send-keys -t "${CMUX_SESSION}:${name}" -l "$message"
```

This is **raw tmux** — no API call, no DB storage. The message appears in the tmux pane but is never recorded in the messages database. Compare with the UI chat path (`POST /api/agents/{id}/message`) which stores the message AND sends via tmux.

**Impact:** Task assignments to project supervisors are invisible. There's no `from_agent="supervisor", to_agent="sup-hero"` message stored.

#### Root Cause 2: Stop hook hardcodes `to_agent="user"` for ALL agents

In `agent_events.py:65-69`:
```python
msg = Message(
    id=str(uuid.uuid4()),
    timestamp=datetime.now(timezone.utc),
    from_agent=display_agent_id,
    to_agent="user",          # ← hardcoded
    type=msg_type,
    content=response_content,
)
```

When `sup-hero` produces output, the message is stored as `from_agent="sup-hero", to_agent="user"`. This technically makes it show up in the filter, but:
- It's semantically wrong (project supervisors report to their parent supervisor, not the user)
- Only `[SYS]`-tagged or final responses trigger this — intermediate work doesn't

#### Root Cause 3: ChatPanel filter excludes inter-agent messages

The frontend filter (`ChatPanel.tsx:55-60`) requires one party to be `"user"`. Messages that DO exist in the DB but are filtered out:

| Message | Stored? | Shown? | Why hidden |
|---------|---------|--------|------------|
| supervisor → sup-hero (task) | **NO** (tmux only) | N/A | Not stored |
| sup-hero → supervisor (mailbox [DONE]) | YES | **NO** | Neither party is "user" |
| sup-hero → user (Stop hook) | YES | YES | Matches filter (2 msgs) |
| worker-hello-apply → sup-hello-world | YES | **NO** | Neither party is "user" |

**Current message counts from DB:**
- Main supervisor with user filter: **133 messages**
- sup-hero with user filter: **2 messages** (both [SYS] idle messages from Stop hook)
- sup-hero total (any involvement): **3 messages**
- sup-heroweb total: **3 messages**
- sup-hello-world total: **2 messages**

## Proposed Solution

### Fix 1: Expand ChatPanel filter (Frontend — Required)

Change `ChatPanel.tsx` to show ALL messages involving the selected agent, not just user<->agent pairs. The current filter is designed for the supervisor-user conversation model, but project supervisors and workers communicate with other agents.

**Proposed change (`ChatPanel.tsx:44-64`):**
```tsx
const messages = useMemo(() => {
  let filtered = allMessages;

  // Filter by project (if selected)
  if (projectAgentIds) {
    filtered = filtered.filter(
      (m) => projectAgentIds.has(m.from_agent) || projectAgentIds.has(m.to_agent)
    );
  }

  // Filter by specific agent (if selected)
  if (selectedAgentId) {
    if (selectedAgentId === 'supervisor') {
      // Main supervisor: keep user<->supervisor filter (established pattern)
      filtered = filtered.filter(
        (m) =>
          (m.from_agent === selectedAgentId && m.to_agent === 'user') ||
          (m.from_agent === 'user' && m.to_agent === selectedAgentId)
      );
    } else {
      // All other agents: show all messages involving this agent
      filtered = filtered.filter(
        (m) => m.from_agent === selectedAgentId || m.to_agent === selectedAgentId
      );
    }
  }

  return filtered;
}, [allMessages, selectedAgentId, projectAgentIds]);
```

**Benefit:** Immediately shows all stored inter-agent messages (mailbox [DONE], [STATUS], worker reports to supervisors).

### Fix 2: Store messages from `tools/workers send` (Backend — Required)

Add an API call in `tools/workers` `cmd_send()` to persist the message:

**Proposed change (`tools/workers`, after line 414):**
```bash
cmd_send() {
    local name="${1:-}"
    local message="${2:-}"

    [[ -z "$name" ]] && die "usage: workers send <name> <message>"
    [[ -z "$message" ]] && die "usage: workers send <name> <message>"

    if ! window_exists "$name"; then
        die "worker '$name' not found"
    fi

    info "Sending message to: $name"

    # Store message in DB so it appears in dashboard chat
    local from_agent="${CMUX_AGENT_NAME:-supervisor}"
    curl -sf -X POST "http://localhost:${CMUX_PORT}/api/messages/internal" \
        -H "Content-Type: application/json" \
        -d "{\"from_agent\": $(printf '%s' "$from_agent" | jq -Rs .), \"to_agent\": $(printf '%s' "$name" | jq -Rs .), \"content\": $(printf '%s' "$message" | jq -Rs .), \"type\": \"task\"}" \
        >/dev/null 2>&1 || true

    # Send message using literal flag then Enter
    tmux send-keys -t "${CMUX_SESSION}:${name}" -l "$message"
    sleep 0.1
    tmux send-keys -t "${CMUX_SESSION}:${name}" Enter

    ok "Message sent to '$name'"
}
```

**Benefit:** Task assignments from any supervisor to any agent are now recorded and visible.

### Fix 3 (Optional): Fix Stop hook to_agent for non-supervisor agents

In `agent_events.py`, instead of always setting `to_agent="user"`, look up the agent's supervisor from the registry:

```python
# Determine the correct recipient for Stop hook messages
to_agent = "user"  # default for main supervisor
if display_agent_id != "supervisor":
    # For project supervisors and workers, address to their supervisor
    entry = agent_registry.get_entry(display_agent_id)
    if entry:
        # Use created_by or infer from hierarchy
        to_agent = entry.get("created_by_agent", "supervisor")
```

**Benefit:** Data model accuracy. Project supervisor responses are correctly attributed to their parent supervisor. Combined with Fix 1, this makes the chat show a coherent conversation.

**Risk:** This changes existing behavior where agent responses show as "→ user" messages. The main supervisor's Stop hook messages need to continue going to "user" for backward compatibility. Recommend as a follow-up improvement, not part of the initial fix.

## Recommended Implementation Order

1. **Fix 1 (Frontend filter)** — Immediate impact, minimal risk. Shows the 8 messages already in the DB for project supervisors.
2. **Fix 2 (Store send messages)** — Records future task assignments. Simple shell script change.
3. **Fix 3 (Stop hook to_agent)** — Optional follow-up for data model accuracy.

## Files to Modify

| File | Change | Priority |
|------|--------|----------|
| `src/frontend/src/components/chat/ChatPanel.tsx` | Expand agent message filter | P0 |
| `tools/workers` | Add API call in `cmd_send()` | P0 |
| `src/server/routes/agent_events.py` | Smart `to_agent` on Stop events | P1 (follow-up) |

## Testing Plan

1. Apply Fix 1, rebuild frontend, verify sup-hero/sup-heroweb chat panels show existing messages
2. Apply Fix 2, use `./tools/workers send sup-hero "test message"`, verify it appears in sup-hero's chat
3. Send a mailbox message from a project supervisor, verify it shows in chat
4. Verify main supervisor chat still works correctly (only shows user<->supervisor)
