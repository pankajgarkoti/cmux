# CMUX

A self-improving multi-agent AI orchestration system that manages and coordinates Claude AI agents running in parallel. CMUX provides a unified dashboard for monitoring, controlling, and communicating with multiple AI agents working collaboratively.

## Features

- **Multi-Agent Orchestration** - Supervisor agent delegates tasks to worker agents running in isolated tmux windows
- **Real-time Dashboard** - React UI with WebSocket updates for live monitoring
- **Webhook Integration** - Receive events from external sources (GitHub, etc.)
- **Message Queue** - File-based mailbox for async inter-agent communication
- **Health Monitoring** - Automatic restart with git rollback recovery on failures
- **Intelligent Routing** - Messages routed to appropriate agents or UI endpoints
- **Process Management** - tmux-based terminal multiplexing for agent isolation
- **Periodic Maintenance** - Auto-compaction to maintain agent context windows

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         CMUX System                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │   Webhook    │───▶│   Mailbox    │───▶│    Router    │       │
│  │   Endpoint   │    │ (.cmux/mail) │    │   (daemon)   │       │
│  └──────────────┘    └──────────────┘    └──────┬───────┘       │
│                                                  │               │
│                           ┌──────────────────────┼───────┐       │
│                           ▼                      ▼       ▼       │
│                    ┌────────────┐         ┌──────────────────┐  │
│                    │ Supervisor │         │  Worker Agents   │  │
│                    │   Agent    │────────▶│  (tmux windows)  │  │
│                    └────────────┘         └──────────────────┘  │
│                           │                      │               │
│                           └──────────┬───────────┘               │
│                                      ▼                           │
│                           ┌──────────────────┐                   │
│                           │    WebSocket     │                   │
│                           │    Broadcast     │                   │
│                           └────────┬─────────┘                   │
│                                    ▼                             │
│                           ┌──────────────────┐                   │
│                           │  React Dashboard │                   │
│                           │   (Real-time)    │                   │
│                           └──────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
```

## Tech Stack

### Backend
- **Python 3.11+** with FastAPI
- **Uvicorn** ASGI server
- **Pydantic** for data validation
- **WebSockets** for real-time communication
- **aiofiles** for async file operations

### Frontend
- **React 18** with TypeScript
- **Vite** build tool
- **Tailwind CSS** for styling
- **React Query** for data fetching
- **Zustand** for state management
- **Radix UI** component primitives

### Orchestration
- **Bash** shell scripts
- **tmux** for terminal multiplexing
- **curl** for health checks

## Prerequisites

- Python 3.11+
- Node.js 18+
- tmux
- git
- [uv](https://github.com/astral-sh/uv) (Python package manager)

## Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/cmux.git
   cd cmux
   ```

2. **Install Python dependencies**
   ```bash
   uv sync
   ```

3. **Install frontend dependencies**
   ```bash
   cd src/frontend
   npm install
   cd ../..
   ```

4. **Build the frontend**
   ```bash
   cd src/frontend
   npm run build
   cd ../..
   ```

## Usage

### Start CMUX

```bash
./src/orchestrator/cmux.sh start
```

This will:
- Create a tmux session named `cmux`
- Start the FastAPI server on port 8000
- Launch the supervisor agent
- Start health monitoring, message routing, and compaction daemons

### Stop CMUX

```bash
./src/orchestrator/cmux.sh stop
```

### Restart CMUX

```bash
./src/orchestrator/cmux.sh restart
```

### Check Status

```bash
./src/orchestrator/cmux.sh status
```

### View Logs

```bash
./src/orchestrator/cmux.sh logs
```

### Attach to tmux Session

```bash
tmux attach -t cmux
```

## Configuration

Configuration is managed via environment variables. Create a `.env` file or export variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `CMUX_HOST` | `0.0.0.0` | Server bind address |
| `CMUX_PORT` | `8000` | Server port |
| `CMUX_SESSION` | `cmux` | tmux session name |
| `CMUX_MAILBOX` | `.cmux/mailbox` | Mailbox file path |
| `CMUX_STATUS_LOG` | `.cmux/status.log` | Status log path |
| `CMUX_RECOVERY_WAIT` | `30` | Recovery wait time (seconds) |
| `CMUX_COMPACT_INTERVAL` | `15` | Compaction interval (minutes) |

## API Endpoints

### Agents

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/agents` | List all agents |
| `GET` | `/api/agents/{id}` | Get agent details |
| `POST` | `/api/agents` | Create new agent |
| `DELETE` | `/api/agents/{id}` | Remove agent |
| `POST` | `/api/agents/{id}/interrupt` | Interrupt agent |
| `POST` | `/api/agents/{id}/compact` | Compact agent context |
| `WS` | `/api/agents/ws` | WebSocket for real-time updates |

### Messages

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/messages` | Get message history |
| `POST` | `/api/messages/user` | Display user message |

### Webhooks

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/api/webhooks/{source}` | Receive webhook from external source |

### Health

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/health` | Server health check |

## Development

### Run Backend in Development Mode

```bash
cd src/server
uv run uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Run Frontend in Development Mode

```bash
cd src/frontend
npm run dev
```

The frontend dev server proxies API requests to `localhost:8000`.

### Run Tests

```bash
uv run pytest
```

### Project Structure

```
cmux/
├── src/
│   ├── server/                 # FastAPI backend
│   │   ├── models/             # Pydantic models
│   │   │   ├── agent.py        # Agent types & statuses
│   │   │   ├── message.py      # Message types & routing
│   │   │   └── webhook.py      # Webhook payloads
│   │   ├── routes/             # API endpoints
│   │   │   ├── agents.py       # Agent CRUD & WebSocket
│   │   │   ├── messages.py     # Message history
│   │   │   └── webhooks.py     # Webhook receiver
│   │   ├── services/           # Business logic
│   │   │   ├── agent_manager.py    # Agent lifecycle
│   │   │   ├── mailbox.py          # Message queue
│   │   │   └── tmux_service.py     # tmux wrapper
│   │   ├── websocket/          # Real-time communication
│   │   │   └── manager.py      # Connection manager
│   │   ├── config.py           # Settings
│   │   └── main.py             # App entry point
│   │
│   ├── frontend/               # React dashboard
│   │   ├── src/
│   │   │   ├── components/     # UI components
│   │   │   │   ├── agents/     # Agent management
│   │   │   │   ├── activity/   # Activity feed
│   │   │   │   ├── messages/   # Messaging UI
│   │   │   │   ├── layout/     # Page layout
│   │   │   │   ├── status/     # Status indicators
│   │   │   │   └── ui/         # Reusable primitives
│   │   │   ├── hooks/          # Custom React hooks
│   │   │   ├── stores/         # Zustand state stores
│   │   │   ├── lib/            # Utilities & API client
│   │   │   └── main.tsx        # App entry point
│   │   ├── package.json
│   │   └── vite.config.ts
│   │
│   └── orchestrator/           # Bash scripts
│       ├── cmux.sh             # Main entry point
│       ├── monitor.sh          # Master orchestrator
│       ├── health.sh           # Health monitoring
│       ├── router.sh           # Message routing
│       ├── compact.sh          # Periodic compaction
│       └── lib/                # Shell libraries
│           ├── tmux.sh         # tmux helpers
│           ├── logging.sh      # Logging utilities
│           └── common.sh       # Common functions
│
├── tests/                      # Python tests
│   ├── test_agents.py
│   ├── test_messages.py
│   ├── test_webhooks.py
│   ├── test_websocket.py
│   └── conftest.py
│
├── .cmux/                      # Runtime data (gitignored)
│   ├── mailbox                 # Message queue file
│   ├── status.log              # Status log
│   └── implementation.log      # Implementation log
│
├── pyproject.toml              # Python dependencies
├── CLAUDE.md                   # Claude Code instructions
└── README.md                   # This file
```

## Agent Statuses

| Status | Description |
|--------|-------------|
| `PENDING` | Task received, not yet started |
| `IN_PROGRESS` | Actively working on task |
| `BLOCKED` | Waiting on external dependency |
| `TESTING` | Running tests/validation |
| `COMPLETE` | Task finished successfully |
| `FAILED` | Task failed |
| `IDLE` | No active task |

## Message Types

| Type | Description |
|------|-------------|
| `TASK` | New task assignment |
| `STATUS` | Status update |
| `RESPONSE` | Task response/result |
| `ERROR` | Error notification |
| `USER` | User-initiated message |

## Health Monitoring

The health daemon (`health.sh`) provides automatic recovery:

1. Checks server health every 10 seconds
2. After 3 consecutive failures, attempts restart
3. If restart fails, performs git rollback to previous commit
4. Rebuilds dependencies and frontend after rollback
5. Restarts the system

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Follow the workflow in `CLAUDE.md` for status logging
4. Write tests for new functionality
5. Commit changes (`git commit -m 'Add amazing feature'`)
6. Push to branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

MIT License - see LICENSE file for details.
