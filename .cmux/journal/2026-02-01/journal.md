# Journal - 2026-02-01

## 22:39 - Fixed long message sending from dashboard

## What was done

Fixed bug where long messages from the dashboard would fail to send.

## Root cause

tmux send-keys passes text as command-line argument, hitting ARG_MAX limit (~128KB on macOS). Long messages were silently truncated or failing.

## Solution

Messages >4KB now use tmux load-buffer/paste-buffer via temp file, bypassing command-line length limit.

## Commit

0e896ec - 62 insertions, 13 deletions in tmux_service.py

## 23:03 - Fix: Long message truncation in dashboard

## What was done

Fixed a bug where long multiline messages sent from the dashboard were truncated before reaching agents.

## Root Cause

When pressing Enter to send a message, the `handleKeyDown` handler was reading from React state (`message`). For long messages or pasted content, there was a race condition where the state update from `onChange` might not have fully propagated before the keydown event fired, resulting in truncated content.

## Fix

- ChatInput.tsx: Changed `handleKeyDown` to read from `e.currentTarget.value` instead of state
- ChatInput.tsx: Changed `handleSubmit` to read from `textareaRef.current.value` as fallback
- ChatPanel.tsx: Dispatch input event after clearing textarea to keep React state in sync

## Files Changed

- src/frontend/src/components/chat/ChatInput.tsx
- src/frontend/src/components/chat/ChatPanel.tsx

## Verification

- TypeScript check: passed
- Build: passed
- Commit: 2b19e05

## 23:04 - Fixed long message truncation bug in dashboard

## What was done

Fixed bug where long messages from the dashboard were truncated and never reached agents.

## Root cause

React state race condition in ChatInput.tsx. When Enter was pressed, the handler read from `message` state which may not have received the latest onChange update for long/pasted content.

## Solution

Read directly from DOM element (e.currentTarget.value and textareaRef.current.value) instead of React state.

## Commit

2b19e05 - 21 insertions, 5 deletions across ChatInput.tsx and ChatPanel.tsx

## 23:29 - Fixed long message delivery from Command Center

## What was done

Fixed the bug where long messages (3000+ chars) sent from the Command Center UI were not being delivered to the supervisor agent.

## Root Cause

CommandCenter.tsx was reading from React state (`message`) when sending messages. For long/pasted content, React state updates may lag behind the DOM, causing messages to be truncated or empty.

## Fix

Applied the same DOM-reading pattern used in ChatInput.tsx (commit 2b19e05):

- Added `useRef` for the textarea element
- `handleKeyDown`: reads from `e.currentTarget.value` instead of state
- `handleSubmit`: reads from `textareaRef.current?.value` as fallback

## Verification

- Sent 3500+ character test message through Command Center
- Confirmed delivery to supervisor via tmux (`[Pasted text #2 +1 lines]`)
- TypeScript and build passing

## Commits

- d4acbb7: fix: resolve long message truncation in CommandCenter

## 23:50 - FAILED: Long message fix attempts broke UI completely

## What went wrong

Attempted fixes for long message delivery (commits d4acbb7, 2b19e05, 0e896ec) completely broke the UI:

- Messages became invisible in the interface
- Messages stopped being sent at all
- Text just sat in the input box without submitting

## Root cause of failure

The "fix" changed React controlled components (ChatInput.tsx, CommandCenter.tsx) to read from DOM (`e.currentTarget.value`) instead of React state. This broke the controlled component pattern:

- React state and DOM became desynchronized
- The component stopped functioning as a proper controlled component
- State updates were lost

## What was reverted

- d4acbb7: CommandCenter DOM reading (my fix)
- 2b19e05: ChatInput DOM reading (worker-multiline-fix)
- 0e896ec: tmux buffer for large messages (worker-long-msg-fix)

## What was kept

- 33e3bbc: docs/WORKER_ROLE.md verification protocol (good practice)

## Lessons learned

1. **Never break React patterns**: Controlled components MUST use React state. Reading from DOM instead of state breaks the entire component.

2. **Chrome MCP verification was insufficient**: I "verified" by sending a message and seeing it arrive, but I didn't test that the UI still worked for subsequent messages.

3. **The real bug is still unknown**: The long message issue exists but the approach of bypassing React state is wrong. Need to investigate properly:
   - Is it a React state batching issue?
   - Is it a paste event handling issue?
   - Is there a message size limit somewhere in the API?

4. **Verification must include regression testing**: Not just testing the fix works, but testing that nothing else broke.

## Commits

- 005bee0: revert: undo broken long message fixes

## 23:52 - POSTMORTEM: Failed long message fix attempts

## What happened

Multiple fix attempts for the long message delivery bug completely broke the dashboard UI.

## Failed approaches

1. **Reading from DOM instead of React state** (commits now removed)
   - Changed ChatInput.tsx and CommandCenter.tsx to read `e.currentTarget.value` instead of React state
   - This broke the controlled component pattern
   - Result: Messages invisible, input stopped working entirely

2. **tmux buffer for large messages**
   - Added load-buffer/paste-buffer for messages >4KB
   - Not the root cause - messages were under 4KB

## Why verification failed

- Chrome MCP test only checked if ONE message arrived
- Did not verify the UI still worked for subsequent messages
- Did not test the input field was still functional

## Lessons learned

1. **Never bypass React state in controlled components** - the DOM and React state MUST stay synchronized

2. **Verification must include regression testing** - test that existing functionality still works, not just the fix

3. **The real bug remains unfixed** - need proper investigation:
   - Check network requests in browser DevTools
   - Check if API receives the full message
   - Check tmux delivery logs
   - May be a paste event or React batching issue

## What was kept

- docs/WORKER_ROLE.md verification protocol (776d01e) - good practice, stays

## 00:09 - Fixed user messages visibility bug

## What was done

Fixed critical bug where user messages were invisible in the dashboard chat. Messages existed in DOM but were rendered ~32,000 pixels off-screen.

## Root cause

Radix ScrollArea adds an internal div with `display: table` which expands to fit content when `ml-auto` is used for right-alignment. This caused:

1. Content container expanded to 32,571px wide
2. User messages with `ml-auto` were pushed to the right edge
3. Only visible viewport was ~590px, so messages were off-screen

## Fix applied

1. Added `[&>div]:!block` to ScrollArea viewport class to override Radix internal wrapper
2. Moved scroll-to-bottom button outside ScrollArea using absolute positioning
3. Removed problematic `float-right` from earlier commit

## Key decisions

- Fixed at scroll-area.tsx level so it applies globally to all ScrollArea usages
- Used Tailwind arbitrary selector `[&>div]:!block` for surgical CSS override

## Verification

- Confirmed content width matches viewport width (2004px vs 2004px)
- Screenshot shows user messages now visible on right side
- All scroll areas have display:block instead of display:table

## 13:11 - Orch Task 1: Server Kill Fix Complete
## What was done
Implemented reliable server shutdown with SIGTERM→SIGKILL escalation pattern.

## Files modified
- src/orchestrator/cmux.sh (cmd_stop)
- src/orchestrator/monitor.sh (cleanup)
- src/orchestrator/health.sh (stop_server)

## Key changes
- 15s timeout watchdog to force kill if stuck
- SIGTERM first, wait 5s, then SIGKILL
- Kill by process name to catch orphan workers
- Verify port is freed before success message

## Commit
07c3132

## 13:12 - Orch Task 2: Frontend Self-Healing Complete
## What was done
Added frontend health monitoring and auto-recovery capability.

## Files modified
- src/orchestrator/health.sh (check_frontend_health, attempt_frontend_recovery)
- src/server/routes/webhooks.py (enhanced health endpoint)

## Key features
- Checks index.html and JS bundle existence
- Returns 503 for degraded state
- Atomic directory swap during rebuild
- npm ci fallback if build fails

## Commit
776ca4e

## 13:14 - Orch Task 3: Agent Registry Complete
## What was done
Implemented persistent agent registry with fcntl file locking.

## Files
- src/server/services/agent_registry.py (NEW)
- src/server/services/agent_manager.py (modified)
- src/server/routes/agents.py (modified)
- src/orchestrator/monitor.sh (modified)

## Key features
- JSON registry at .cmux/agent_registry.json
- fcntl locking for concurrent access
- Auto-cleanup of stale entries
- API endpoints for registration from shell

## Commit
73e7609

## 13:16 - Orch Task 4: Log Watcher Daemon Complete
## What was done
Implemented log watcher daemon for automated error monitoring.

## Files
- src/orchestrator/log-watcher.sh (NEW)
- src/orchestrator/monitor.sh (modified)

## Key features
- Monitors server and router logs for ERROR/Exception/Traceback patterns
- Cross-platform stat helpers (macOS/Linux)
- Inode tracking for log rotation
- Alert cooldown to prevent spam
- Checks agent registry for missing agents
- Writes to mailbox and journal

## Commit
d16377e

## 13:37 - Team and Role Templates Implemented
## What was done
Implemented Phase 2 (Templates) from the revised Core Architecture plan:

**Team Templates (7 files):**
- SQUAD_MODEL.md - Cross-functional team with Squad Lead
- FEATURE_TEAM.md - Hierarchical team with Tech Lead
- PLATFORM_TEAM.md - Infrastructure/DevOps team
- TIGER_TEAM.md - Flat urgent response team
- DEBATE_PAIR.md - Simple debate structure
- DEBATE_TO_IMPLEMENTATION.md - Two-phase debate then implement
- SOLO_WORKER.md - Single worker for simple tasks

**Role Templates (10 files):**
- DEBATE_DEFENDER.md, DEBATE_CRITIC.md
- SQUAD_LEAD.md, TECH_LEAD.md, PLATFORM_LEAD.md
- FEATURE_BACKEND.md, FEATURE_FRONTEND.md
- INFRA_WORKER.md, DEVOPS_WORKER.md
- TESTER.md (with Chrome DevTools MCP browser testing guide)

**SUPERVISOR_ROLE.md Updates:**
- Added Complexity Assessment Guide section
- Decision matrix for Worker vs Session vs Debate
- Gut-check questions for delegation
- Links to team templates

## Why
This implements Task 2 (priority) from the revised core architecture plan. Templates provide:
- Standardized agent behavior via role templates
- Clear team structures for common scenarios
- Communication protocols with mailbox examples
- Spawning commands ready to use

## Key decisions
- Each template includes org chart (ASCII), communication graph, and decision authority
- Role templates define mindset, workflow, and what NOT to do
- Tester role includes comprehensive Chrome DevTools MCP testing instructions
- Added README files in both directories for quick reference

## Commit
2e6af54
