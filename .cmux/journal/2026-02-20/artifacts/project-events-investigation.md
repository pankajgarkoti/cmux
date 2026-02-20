# Investigation: Why Project Agent Events/Thoughts Don't Show in Dashboard

**Date**: 2026-02-20
**Investigator**: worker-project-events
**Status**: Investigation complete, no fixes applied

## Executive Summary

Project agent events and thoughts ARE being received by the backend, but several issues prevent them from reliably appearing in the frontend dashboard:

1. **Critical**: `ProjectAgentsResponse` type mismatch breaks all project-scoped filtering
2. **Critical**: hello-world project has no hooks installed (missing `.claude/` directory entirely)
3. **Moderate**: Thought content is often `null` for project agents due to transcript extraction issues
4. **Minor**: Historical thought fetching (limit=200) can miss older project agent data when recent agents generate high volume

---

## Detailed Findings

### 1. Hook Installation Status

| Project | Path | Hooks Installed | Notes |
|---------|------|----------------|-------|
| hero | `/Users/pankajgarkoti/Desktop/code/zonko/hero` | YES | All hooks with absolute paths to CMUX |
| heroweb | `/Users/pankajgarkoti/Desktop/code/zonko/heroweb` | YES | All hooks with absolute paths to CMUX |
| hello-world | `/Users/pankajgarkoti/Desktop/code/hello-world` | **NO** | No `.claude/` directory exists at all |

**Root cause for hello-world**: The `tools/projects install-hooks` command was never run for this project, or it failed silently. The `.claude/` directory doesn't exist.

**Evidence**: `ls -la /Users/pankajgarkoti/Desktop/code/hello-world/.claude/` returns "No such file or directory"

### 2. Absolute Paths in Hook Scripts (WORKING)

All hook paths in project `.claude/settings.json` files use absolute paths back to CMUX:
```
/Users/pankajgarkoti/Desktop/code/oss/cmux/.claude/hooks/stream-thought.sh
/Users/pankajgarkoti/Desktop/code/oss/cmux/.claude/hooks/notify-output.sh
/Users/pankajgarkoti/Desktop/code/oss/cmux/.claude/hooks/stream-result.sh
...etc
```

These resolve correctly regardless of the project agent's CWD. **No issue here.**

### 3. Agent Name/ID Sent Correctly (WORKING)

- Project supervisors get `CMUX_AGENT=true` and `CMUX_AGENT_NAME=sup-hero` (set in `tools/projects` line 426)
- Project workers get `CMUX_AGENT=true` and `CMUX_AGENT_NAME=<worker-name>` (set in `tools/workers` line 224)
- Both env vars are correctly passed to hook scripts

**Evidence from database**:
```
GET /api/agent-events?limit=500 — unique agent_ids include: sup-hero, sup-heroweb
GET /api/thoughts?limit=500 — unique agent_names include: sup-hero, sup-heroweb, worker-hello-build
```

**Backend IS receiving events from project agents.** The hooks fire correctly.

### 4. Frontend ProjectAgentsResponse Type Mismatch (CRITICAL BUG)

**Backend returns** (from `GET /api/projects/hero/agents`):
```json
{
  "project_id": "hero",
  "agents": [
    {
      "key": "sup-hero",
      "registered_at": "2026-02-20T12:44:48Z",
      "type": "project-supervisor",
      "agent_id": "ag_gdo9xmu1",
      "display_name": "sup-hero",
      "role": "project-supervisor",
      "project_id": "hero"
    }
  ],
  "total": 1
}
```

**Frontend type expects** (`src/frontend/src/types/project.ts:26-30`):
```typescript
export interface ProjectAgentsResponse {
  project_id: string;
  agents: string[];  // <-- WRONG: should be object[], not string[]
  total: number;
}
```

**Impact**: Every place the frontend creates `new Set(projectAgentsData.agents)` and then checks `.has(someString)` will fail, because the Set contains objects, not strings.

**Affected code**:

1. **`src/frontend/src/hooks/useActivity.ts:18-19`**:
   ```typescript
   const projectAgentIds = new Set(projectAgentsData.agents); // Set of objects
   filtered = filtered.filter((a) => projectAgentIds.has(a.agent_id)); // always false
   ```
   Result: When a project is selected, ALL activities are hidden.

2. **`src/frontend/src/components/chat/ChatPanel.tsx:36-39`**:
   ```typescript
   const projectAgentIds = useMemo(() => {
     if (!selectedProjectId || !projectAgentsData?.agents) return null;
     return new Set(projectAgentsData.agents); // Set of objects
   }, ...);
   ```
   Then at line 49-52:
   ```typescript
   filtered = filtered.filter(
     (m) => projectAgentIds.has(m.from_agent) || projectAgentIds.has(m.to_agent)
   );
   ```
   Result: When a project is selected, ALL messages are hidden.

**Fix needed**: Either:
- Backend should return just agent key strings: `"agents": ["sup-hero"]`
- Or frontend should extract keys: `new Set(projectAgentsData.agents.map(a => a.key))`

### 5. Thought Content Often Null for Project Agents

**Observation**: Many thoughts from project agents have `content: null`:

```
sup-hero: 5 thoughts checked, only 1 had content
sup-heroweb: 5 thoughts checked, only 2 had content
```

Compare with supervisor: 10 out of 10 reasoning thoughts had content.

**Cause**: The `stream-thought.sh` script extracts reasoning from the transcript file using jq:
```bash
thought=$(tail -10 "$transcript_path" | jq -r '...' | tail -1 | head -c 500)
```

This approach is fragile — it only looks at the last 10 lines of the transcript JSONL file. If the transcript is large or the last entries don't have assistant text/thinking blocks, the extraction fails silently and content is null.

**Frontend impact**: The ThoughtStream component filters thoughts to only show those with `thought_type === 'reasoning' && t.content` (ThoughtStream.tsx:40). Null-content thoughts are hidden. So project agents appear to have fewer visible thoughts, making the dashboard look empty for them.

### 6. Historical Thought Limit Can Miss Project Agents

The `useThoughts` hook fetches `api.getThoughts(200)` which returns the 200 most recent thoughts across ALL agents. When a busy agent (like the investigating worker) generates many thoughts, older project agent thoughts get pushed out of the top 200.

**Evidence**: Querying `GET /api/thoughts?limit=200` returned thoughts from supervisor, worker-project-events, worker-tasks-live, worker-hello-build — but NOT from sup-hero or sup-heroweb. Their thoughts exist in the DB (confirmed via agent_name-specific queries) but are outside the top 200.

This is a minor issue since WebSocket delivers thoughts in real-time. It only affects historical data after page refresh or when the dashboard wasn't open during project agent activity.

### 7. AgentEventStore Indexes by session_id (UUID)

The `agentEventStore.ts` indexes events by `session_id` (Claude Code session UUID, e.g., `f20175bc-dbeb-4a70-b2ce-277aa33cbd61`), not by agent name. The `AgentActivityIndicator` has to match by iterating all sessions and checking `event.agent_id === agentId`. This works but is indirect.

The `isAgentActive` check in `AgentActivityIndicator.tsx:28-31` does:
```typescript
const matchesAgent =
  sessionId.toLowerCase().includes(agentId.toLowerCase()) || // UUID never contains agent name
  event.agent_id === agentId; // This is the actual match
```

The first condition (sessionId.includes) is always false since session IDs are UUIDs. Only the fallback `event.agent_id === agentId` works. This is technically correct but fragile.

---

## Summary of Issues (Prioritized)

| # | Severity | Issue | Location | Effect |
|---|----------|-------|----------|--------|
| 1 | **CRITICAL** | ProjectAgentsResponse type mismatch — backend sends dicts, frontend expects strings | `project_service.py:140-149`, `types/project.ts:26-30` | ALL project-scoped filtering (messages + activities) is broken |
| 2 | **CRITICAL** | hello-world has no hooks installed | Missing `.claude/` dir in hello-world project | No events/thoughts generated at all for hello-world |
| 3 | **MODERATE** | Thought content extraction yields null for many project agent thoughts | `.claude/hooks/stream-thought.sh:22-36` | ThoughtStream appears empty/sparse for project agents |
| 4 | **MINOR** | Historical thought API limit (200) can miss older project agents | `useThoughts.ts`, `conversation_store.py:get_thoughts` | Historical thoughts missing after page refresh |
| 5 | **MINOR** | AgentEventStore session_id matching is fragile | `agentEventStore.ts`, `AgentActivityIndicator.tsx:28-31` | First match condition is dead code (UUID never contains agent name) |

## Recommended Fixes

1. **Fix ProjectAgentsResponse**: Either make backend return `["sup-hero", ...]` or update frontend to extract keys: `new Set(agents.map(a => a.key))`
2. **Install hooks for hello-world**: Run `tools/projects install-hooks hello-world`
3. **Improve thought extraction**: Use more lines from transcript, or extract during the Stop event when full response is available
4. **Add per-agent thought querying**: Frontend could query `GET /api/thoughts?agent_name=sup-hero` when a project agent is selected, instead of relying on the global limit=200 query
5. **Clean up dead code**: Remove the `sessionId.includes(agentId)` condition in AgentActivityIndicator
