# Journal - 2026-01-31

## 18:50 - WebSocket Stability Fixes + Documentation Updates
## What was done
- Added server-side ping loop (30s interval) to detect dead WebSocket connections
- Added client pong responses with exponential backoff reconnection (1s-30s)
- Fixed seenIds memory leak in activityStore by rebuilding from current activities
- Created missing docs/WORKER_ROLE.md with worker communication protocol
- Updated supervisor templates to use /workers skill instead of raw tmux commands
- Made cmux.sh start non-interactive (launches system and returns)
- Added uvicorn WS ping settings to monitor.sh

## Why
WebSocket connections were breaking after extended periods due to:
- No keepalive mechanism to detect stale connections
- Fixed 3s reconnect delay causing rapid retries
- seenIds Set growing unboundedly causing memory leaks
- Missing WORKER_ROLE.md documentation referenced in templates

## Key decisions
- 30s ping interval matches uvicorn default
- Exponential backoff caps at 30s to balance recovery time vs server load
- Rebuild seenIds from activities array rather than maintaining separate state

## Issues encountered
None - all tests pass, frontend typecheck clean, system verified working

## 18:55 - Frontend UX Improvements - Markdown & File Viewer
## What was done
- Added @tailwindcss/typography plugin to enable proper markdown rendering (prose classes)
- Added useEffect in ChatPanel to auto-close file viewer when agent is selected

## Why
- Journal markdown files were rendering as plaintext because prose classes had no effect without the typography plugin
- UX friction: clicking a file required manually clicking Close button before viewing an agent

## Key decisions
- Used existing @tailwindcss/typography package (already in node_modules) rather than custom CSS
- useEffect watches selectedAgentId and clears file selection automatically

## Issues encountered
None - straightforward fix

## 18:58 - Fixed File Viewer State Management
## What was done
- Moved file clearing logic from useEffect in ChatPanel to agentStore.selectAgent()
- Removed close button from MemoryViewer
- Simplified ChatPanel by removing unused clearSelectedFile and useEffect

## Why
- Original useEffect approach had race conditions - it ran when selectedFile changed too, immediately clearing files when clicked while an agent was selected
- Moving to store-level action (selectAgent clears file) ensures consistent behavior

## Key decisions
- Used Zustand getState() to access viewerStore from agentStore action
- This cross-store communication is cleaner than effect-based synchronization

## Issues encountered
None

## 19:09 - Toned down activity indicator animations
## What was done
Removed disruptive animations from AgentActivityIndicator component:
- Removed slide-in entrance animation (animate-in fade-in slide-in-from-bottom-2)
- Removed ping radar effect (animate-ping)
- Removed pulsing dots (animate-pulse)
- Simplified component structure

## Why
User reported the conversation animation was annoying and triggered every time. The multiple overlapping animations were visually disruptive.

## Key decisions
Kept only the simple spinner animation (animate-spin) which is standard UX for loading indicators. The 500ms debounce for hiding remains to prevent flicker.

## Issues encountered
None

## 19:23 - Fix disruptive chat scroll animation
## What was done
Changed the chat auto-scroll behavior from `smooth` to `instant` in ChatMessages.tsx.

## Why
When switching between agents, the smooth scroll animation was disruptive. The message list changes (gets filtered differently), triggering the scroll effect each time.

## Key decisions
- Used `behavior: instant` instead of removing the scroll entirely, since scrolling to bottom is still useful for new messages
- Simple one-line fix that preserves functionality while removing the annoyance

## Issues encountered
None

## 19:32 - Add All Agents option to Explorer sidebar
## What was done
Added an "All Agents" button at the top of the Agents section in the Explorer sidebar. When clicked, it clears the selected agent and returns to the Command Center view that shows messages from all agents.

## Why
Previously, once a user clicked on a specific agent, there was no way to return to the overview that shows all agent messages. This created a UX gap where users were stuck viewing a single agent.

## Key decisions
- Placed the "All Agents" item at the top of the agent list (before session groups) for discoverability
- Used the Users icon from lucide-react to visually distinguish it from individual agents
- Added blue accent color and "ALL" badge to make it stand out
- Highlights when selected (selectedAgentId === null)

## Issues encountered
None

## 19:40 - Frontend UX improvements and build process fix
## What was done
- Fixed disruptive activity indicator animations (b471c4d)
- Made chat scroll instant instead of animated when switching agents (d499ef7)
- Added "All Agents" option to return to overview (eb86984)
- Built frontend after changes
- Updated CLAUDE.md to include frontend build in checklist (d662321)

## Why
User reported animations were annoying and there was no way to return to the all-agents group view after selecting a specific agent.

## Key decisions
- Removed slide-in, ping, and pulse animations from activity indicator
- Changed scrollIntoView behavior from smooth to instant
- Added All Agents button at top of agents list in sidebar

## Issues encountered
Supervisor was not building the frontend after changes - added to checklist to prevent future occurrences.

## 21:58 - Message persistence and archived worker conversations
## What was done
- Created SQLite conversation store (conversation_store.py) for persistent message storage
- Integrated write-through caching in mailbox service for message durability
- Added archive endpoints for capturing worker terminal output before kill
- Modified tools/workers script to archive before killing
- Added frontend Archived Workers section in Explorer
- Created ArchivedAgentView component for read-only archive display
- Added agent_archived WebSocket event handling

## Why
Messages were lost on server restart, and killed workers lost all conversation history. This makes debugging and context preservation difficult.

## Key decisions
- SQLite chosen for simplicity and zero config (vs Redis/Postgres)
- Write-through caching keeps in-memory deque for fast reads, SQLite for durability
- Archives stored separately from messages to avoid bloating message queries
- Terminal output captured at 2000 lines by default for comprehensive history

## Issues encountered
None - implementation went smoothly

## 13:17 - Single-Line Mailbox Protocol Implementation
## What was done

1. Created `tools/mailbox` CLI for agent-to-agent communication
   - Commands: send, quick, done, blocked, status, read
   - Automatically creates body files in attachments directory
   - Supports user, supervisor, and worker recipients

2. Created `/mailbox` skill (`.claude/skills/mailbox/SKILL.md`)
   - Explains agent identity to workers
   - Documents mailbox protocol and commands

3. Updated `router.sh` for new single-line format
   - Format: `[timestamp] from -> to: subject (body: path)`
   - Uses line-based tracking instead of byte position
   - Parses session:agent addresses

4. Updated `tools/workers` to inject agent identity context
   - Workers now understand they are autonomous agents
   - Know to use /mailbox skill for communication
   - Reference WORKER_ROLE.md for full guidelines

5. Improved mailbox UI in Explorer
   - Shows message count badge
   - Displays recent message previews
   - From/to with arrow visualization

## Why

The previous multi-line message format was:
- Hard to parse reliably
- Difficult to grep/tail
- Workers were bypassing the mailbox entirely

The new single-line format is:
- Easy to parse with regex
- Works with tail -f and grep
- Clear routing with tmux addresses

## Key decisions

1. Single-line format over multi-line for simplicity
2. Body files in journal/attachments for detailed content
3. tmux addresses (session:window) for explicit routing
4. Agent identity context prepended before task assignment

## Issues encountered

None - implementation went smoothly.
