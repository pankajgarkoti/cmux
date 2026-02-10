# Journal - 2026-02-03

## 08:22 - Session Summary: Core Templates + Message Passing Issues
## What was done

1. **Investigated lost workers** - orch-team's server kill fix testing killed all tmux sessions
2. **Continued core-team work** - spawned core-implementer to extract templates from plan
3. **Implementation complete** - 20 files created (7 team templates, 10 role templates, 2 READMEs, supervisor guide update)
4. **Critic review** - core-critic reviewed and approved with 2 minor fixes
5. **Fixes applied** - FEATURE_TEAM.md updated per critic feedback

## Commits
- 2e6af54: feat: add comprehensive team and role templates
- 7f1729b: fix: add role template references to FEATURE_TEAM.md
- 97f606f: docs: add journal entries from multi-team debate

## Issues Discovered

Six message passing issues documented in attachments/message-passing-issues.md:
1. Text stuck in input buffers after multiline paste
2. Messages not reaching workers when session not in foreground
3. Worker ignored received task (needed follow-up message)
4. Duplicate/repeated messages
5. Session cleanup killing all workers
6. Router vs direct messaging confusion

## Next Steps

Investigate and fix message passing issues

## 08:37 - Message Passing Fixes Implemented and Verified
## What was done

Fixed 4 out of 7 message passing issues identified in the 2026-02-01 session:

### Issue 1: Text Stuck in Input Buffers ✅
- Changed `tools/workers spawn` to write task to context file instead of multiline paste
- Workers now read from `.cmux/worker-contexts/{name}-context.md`
- Added load-buffer/paste-buffer for messages >4KB in lib/tmux.sh
- Increased delays (300ms multiline, 100ms single) for Claude Code processing

### Issue 5: Monitor Cleanup Kills All Workers ✅
- Changed `monitor.sh cleanup()` to only kill THIS specific `$CMUX_SESSION`
- No longer kills all `cmux*` sessions, preventing accidental worker destruction

### Issues 3 & 4: Worker Ignored Task / Duplicate Messages ✅
- Both were symptoms of Issue 1, now fixed by context file approach

### Issue 2: Messages When Not Focused
- Tested and confirmed working - test message delivered successfully
- Was likely a symptom of Issue 1, not a separate bug

## Testing Performed

1. **Short message test**: Spawned test-worker with simple task - received correctly
2. **Long message test**: Spawned long-test with 9.5KB message (60 lines) - all lines received
3. **Background delivery test**: Sent message to supervisor - delivered successfully

All tests verified via Chrome MCP dashboard screenshots.

## Key Commits

- `d4892cf`: Main fix - tmux.sh, monitor.sh, tools/workers
- `b69201c`: Documentation update with fix status

## Remaining Items

- Issue 6 (Router vs Direct Messaging): Documentation needed, not a bug
- Issue 7 (Intermediate Responses): Claude Code streaming behavior, not fixable at CMUX level

## 13:26 - Onboarding Modal Implementation
## What was done
Implemented a beautiful multi-step onboarding modal for the CMUX frontend that shows on first visit.

## Features
- 6-step wizard covering all CMUX specialties
- Gradient headers with matching icons for each step
- Step indicator dots with clickable navigation
- "Don't show again" checkbox with localStorage persistence
- Smooth animations using tailwindcss-animate

## Steps covered
1. Welcome - Multi-agent orchestration overview
2. Supervisor + Workers - Hierarchical architecture
3. Self-Healing Safety - Automatic rollback protection
4. Real-Time Dashboard - Panel overview
5. Persistent Memory - Journal system
6. Getting Started - How to send tasks

## Files created/modified
- src/frontend/src/stores/onboardingStore.ts (new)
- src/frontend/src/components/onboarding/OnboardingModal.tsx (new)
- src/frontend/src/App.tsx (modified)

## Evidence
- .cmux/journal/2026-02-03/attachments/onboarding-modal-step1.png
- .cmux/journal/2026-02-03/attachments/onboarding-modal-step2.png
- .cmux/journal/2026-02-03/attachments/onboarding-modal-final.png

## 15:22 - Created detached-restart.sh for safe supervisor restarts
## What was done

Created `src/orchestrator/detached-restart.sh` - a shell script that allows the supervisor to safely trigger a restart or rollback without killing itself.

## Why

The supervisor previously ran `./src/orchestrator/cmux.sh restart` which killed the tmux session it was running in, terminating itself. This detached script solves that by:
1. Running fully detached (nohup + disown)
2. Waiting 2 seconds before action so the caller can exit safely
3. Only stopping the FastAPI server (not tmux sessions)

## Features

- `--restart` - Just restart the FastAPI server
- `--rollback [commit]` - Rollback to specified commit (defaults to HEAD~1)
- `--detach` - Run in background
- Logs to `.cmux/detached-restart.log`
- Uses existing lib/common.sh and lib/logging.sh

## Usage

```bash
./src/orchestrator/detached-restart.sh --restart --detach
./src/orchestrator/detached-restart.sh --rollback abc1234 --detach
```

## Commit
48c1ddd
