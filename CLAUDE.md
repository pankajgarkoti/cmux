# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

CMUX is a **self-improving** multi-agent AI orchestration system. The core goal: once the base system is running, it can safely add features to itself through coordinated Claude agents.

The architecture enables safe self-modification through:
- **Isolated execution** - Worker agents run in separate tmux windows, containing blast radius
- **Automatic rollback** - Health daemon detects failures and rolls back to last working git commit
- **Supervisor coordination** - Single supervisor delegates tasks, reviews changes before integration
- **Persistent memory** - Journal system maintains context across sessions for informed decisions

Agents modify the codebase, the health monitor validates changes work, and failures trigger automatic recovery.

## Development Commands

### Python Backend
```bash
uv sync                                    # Install dependencies
uv sync --extra dev                        # Install with dev dependencies
uv run pytest                              # Run all tests
uv run pytest tests/test_agents.py -v      # Run specific test file
uv run pytest -k "test_name" -v            # Run single test by name
uv run uvicorn src.server.main:app --reload --host 0.0.0.0 --port 8000  # Dev server
```

### Frontend
```bash
cd src/frontend
npm install                   # Install dependencies
npm run dev                   # Dev server (port 5173, proxies to :8000)
npm run build                 # Production build
npm run lint                  # ESLint
npm run typecheck             # TypeScript check
```

### System Orchestration
```bash
./src/orchestrator/cmux.sh start    # Start full system (server + supervisor + daemons)
./src/orchestrator/cmux.sh stop     # Stop everything
./src/orchestrator/cmux.sh status   # Check status
./src/orchestrator/cmux.sh logs     # View status logs
tmux attach -t cmux                 # Attach to tmux session
```

## Architecture

### System Flow
```
Webhooks/User → Mailbox (.cmux/mailbox) → Router daemon → Supervisor agent
                                                              ↓
                                                        Worker agents (tmux)
                                                              ↓
                                                        WebSocket broadcast
                                                              ↓
                                                        React dashboard
```

### Key Components

**Backend (src/server/):**
- `main.py` - FastAPI app with CORS, static files, route mounting
- `services/agent_manager.py` - Agent lifecycle, maps tmux windows to agents
- `services/mailbox.py` - File-based message queue with async locking
- `services/tmux_service.py` - tmux operations (send-keys, capture-pane)
- `services/journal.py` - Daily journal persistence
- `websocket/manager.py` - WebSocket connection pool and broadcast

**Frontend (src/frontend/src/):**
- `stores/` - Zustand state (agentStore, activityStore, connectionStore, layoutStore)
- `hooks/useWebSocket.ts` - WebSocket with auto-reconnect
- `components/explorer/` - File browser and agent tree
- `components/chat/` - Agent interaction panel
- `components/activity/` - Event timeline
- `lib/api.ts` - API client functions

**Orchestration (src/orchestrator/):**
- `cmux.sh` - Main entry point, tmux session management
- `health.sh` - Health monitoring with git rollback recovery
- `router.sh` - Polls mailbox, routes messages to agents
- `compact.sh` - Periodic context compaction scheduler

### Data Models

Agents have statuses: `PENDING`, `IN_PROGRESS`, `BLOCKED`, `TESTING`, `COMPLETE`, `FAILED`, `IDLE`

Messages have types: `TASK`, `STATUS`, `RESPONSE`, `ERROR`, `USER`

Agent events (from Claude Code hooks): `PostToolUse`, `Stop` - tracked in `routes/agent_events.py`

### Runtime Data

`.cmux/` directory (gitignored):
- `mailbox` - Message queue file
- `status.log` - System status log
- `journal/YYYY-MM-DD/` - Daily journals with artifacts

## API Structure

REST endpoints under `/api/`:
- `/agents` - CRUD, messaging, terminal capture
- `/agents/ws` - WebSocket for real-time updates
- `/messages` - History and user message display
- `/agent-events` - Claude Code hook event receiver
- `/journal` - Daily journal CRUD and search
- `/filesystem` - File browser
- `/webhooks/{source}` - External webhook receiver
- `/webhooks/health` - Health check

WebSocket events: `agent_event`, `new_message`, `webhook_received`, `message_sent`

## Testing

Tests use pytest-asyncio with `asyncio_mode = "auto"`. Test files in `tests/`:
- `test_agents.py` - Agent endpoint tests
- `test_messages.py` - Message handling
- `test_webhooks.py` - Webhook receiver
- `test_websocket.py` - WebSocket communication

Use `httpx.AsyncClient` with `ASGITransport` for async endpoint tests.

## Environment Variables

Key settings (in `src/server/config.py`):
- `CMUX_HOST` / `CMUX_PORT` - Server bind (default: 0.0.0.0:8000)
- `CMUX_SESSION` - tmux session name (default: cmux)
- `CMUX_MAILBOX` - Message queue path (default: .cmux/mailbox)

## Self-Improvement Safety Model

The system protects against breaking itself during self-modification:

1. **Health daemon** (`health.sh`) polls `/api/webhooks/health` every 10 seconds
2. After 3 consecutive failures, attempts restart
3. If restart fails, stashes local changes and rolls back to previous git commit
4. Rebuilds dependencies and frontend, then restarts

This means agents can experiment with changes - if something breaks the system, it automatically recovers to a known-good state. The journal preserves context about what was attempted for the next run.
