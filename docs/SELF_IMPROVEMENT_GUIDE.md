# CMUX Self-Improvement Guide

This document provides guidelines for agents modifying the CMUX system itself. The system is designed for safe self-improvement through automated monitoring and recovery.

## The Safety Model

CMUX protects against breaking itself during self-modification:

1. **Health Monitoring**: The health daemon (`health.sh`) checks server health every 10 seconds
2. **Automatic Recovery**: After 3 consecutive failures, attempts simple restart
3. **Git Rollback**: If restart fails, rolls back to last known healthy commit
4. **Session Preservation**: tmux sessions are kept alive during rollback (agents survive)
5. **Journal Persistence**: Failure context is logged for post-mortem analysis
6. **Supervisor Notification**: After rollback, supervisor receives error details

### What This Means for You

- **You can experiment**: If your changes break the server, the system auto-recovers
- **Your work is preserved**: Changes are stashed, not deleted
- **Context is maintained**: The journal records what was attempted
- **You stay alive**: tmux sessions survive rollbacks

## What You CAN Modify (Safe)

These components have low risk of breaking the system:

### Frontend (`src/frontend/`)

- React components
- Styling and CSS
- State management (stores)
- API client functions
- Types and interfaces

### API Routes (`src/server/routes/`)

- Adding new endpoints
- Modifying response formats
- Adding validation
- New route files

### Data Models (`src/server/models/`)

- Adding new models
- Adding fields to existing models
- Pydantic validation rules

### Tests (`tests/`)

- New test files
- Test fixtures
- Test utilities

### Documentation (`docs/`)

- Guides and tutorials
- Template files
- README updates

## What Requires Care

These components are more sensitive:

### Services (`src/server/services/`)

- `agent_manager.py` - Agent lifecycle management
- `session_manager.py` - Session creation and termination
- `tmux_service.py` - tmux operations
- `mailbox.py` - Message queue

**Risk**: Breaking services can cause server startup failure.

**Mitigation**:

1. Test changes locally before applying
2. Make incremental changes
3. Ensure health endpoint remains accessible

### WebSocket Manager (`src/server/websocket/`)

- Connection handling
- Broadcast logic

**Risk**: Breaking WebSocket can prevent frontend updates.

**Mitigation**:

1. Keep the basic broadcast interface stable
2. Test connection and disconnect handling

### Configuration (`src/server/config.py`)

- Settings and defaults

**Risk**: Invalid config can prevent server startup.

**Mitigation**:

1. Provide sensible defaults
2. Validate values at startup

## FORBIDDEN Without Approval

These components are critical for recovery:

### `src/orchestrator/health.sh`

The recovery system itself. Breaking this removes the safety net.

### `src/orchestrator/cmux.sh`

System startup. Breaking this prevents system from starting.

### `.cmux/` Directory Structure

Runtime data paths. Changing structure can break multiple components.

### Changes to Health Endpoint

`/api/webhooks/health` must always respond to health checks.

## Required Validation Checklist

Before considering a change complete:

```bash
# 1. Run tests
uv run pytest

# 2. Check health endpoint works
curl http://localhost:8000/api/webhooks/health

# 3. Build frontend (if frontend changes)
cd src/frontend && npm run build

# 4. Check for TypeScript errors
cd src/frontend && npm run typecheck

# 5. Manual smoke test of changed feature
# (verify the change works as expected)
```

## If Something Breaks

### Server Won't Start

1. Check `/tmp/cmux-server.log` for error details
2. The health daemon will attempt recovery automatically
3. After recovery, check the journal for what went wrong

### Health Check Fails

1. Wait for auto-recovery (up to 3 retries)
2. If rollback occurs, check `.cmux/journal/$(date +%Y-%m-%d)/`
3. Your changes are stashed: `git stash list`
4. To restore: `git stash pop` (after fixing the issue)

### tmux Sessions Broken

1. Check if session exists: `tmux has-session -t cmux`
2. Restart system: `./src/orchestrator/cmux.sh restart`
3. Agent context preserved in journal

## Best Practices for Self-Improvement

### 1. Make Small, Incremental Changes

- One logical change at a time
- Easier to isolate issues if something breaks

### 2. Test Before Committing

- Run the validation checklist
- Verify behavior manually

### 3. Document What You're Changing

- Add journal entry before making changes
- Explain the rationale

### 4. Keep the Health Endpoint Sacred

- Never modify `/api/webhooks/health` to not respond
- If you must change it, ensure it still returns 200

### 5. Preserve Session Compatibility

- Don't change session naming conventions mid-operation
- Gracefully handle missing fields in models

### 6. Use the Journal

- Record decisions and their rationale
- Log errors and how you fixed them
- Future agents (including you after compaction) benefit

### 7. Verify Integration, Not Just Existence

Creating a new component is not enough — you MUST verify it's actually wired into the system. Dead code that exists but never runs is worse than no code at all, because it creates a false sense of safety.

> **Lesson learned (2026-02-21):** `health.sh` contained full multi-stage recovery logic (restart → rollback → progressive rollback) but was never started by `cmux.sh` or any other startup script. When the system crashed, the recovery logic didn't fire because nothing ever invoked it. The daemon was dead code for the entire life of the system.

**After creating any new component, verify:**

| Component type | Verification |
|---------------|-------------|
| Shell script/daemon | Is it started by `cmux.sh` or `monitor.sh`? Check the startup flow. |
| API route | Is it mounted in `main.py`? Can you `curl` it? |
| Frontend component | Is it imported and rendered somewhere? Does `npm run build` include it? |
| Service/module | Is it imported by a route or startup code? |
| Config value | Is it read by the code that needs it? |
| Cron/scheduled task | Is the scheduler running? Is the task registered? |

**The test:** If you deleted the new file, would anything break? If the answer is "no", it's not integrated.

## Recovery from Bad State

### Recovering Stashed Changes

```bash
# List stashed changes
git stash list

# Show what's in a stash
git stash show -p stash@{0}

# Apply stash (keeps it in list)
git stash apply stash@{0}

# Pop stash (removes from list)
git stash pop
```

### Manual Rollback

```bash
# See recent commits
git log --oneline -10

# Reset to specific commit
git reset --hard <commit-hash>

# Rebuild
uv sync
cd src/frontend && npm install && npm run build

# Restart server
./src/orchestrator/cmux.sh restart
```

### Checking System State

```bash
# Check if server is running
curl -s http://localhost:8000/api/webhooks/health

# Check tmux sessions
tmux list-sessions

# Check agents
curl -s http://localhost:8000/api/agents | jq '.agents[].name'

# Check recent status
tail -20 .cmux/status.log
```

## Example Self-Improvement Workflow

```
1. Identify what needs to change
2. Journal: "Planning to modify X because Y"
3. Read the relevant code
4. Plan the changes
5. Make small incremental changes
6. After each change:
   - Run tests
   - Check health endpoint
   - Build frontend (if applicable)
7. Journal: "Completed change to X, tested successfully"
8. If something breaks:
   - Wait for auto-recovery
   - Check journal for error context
   - Fix the issue
   - Try again
```

---

Remember: The system is designed to recover from your mistakes. Don't be afraid to experiment, but do validate your changes. The journal preserves context for you and future agents.
