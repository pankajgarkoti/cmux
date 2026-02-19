from fastapi import APIRouter, BackgroundTasks
from collections import deque
from datetime import datetime, timezone
from typing import Any
import uuid
import logging

from ..models.agent_event import AgentEvent, AgentEventResponse, AgentEventType
from ..models.message import Message, MessageType
from ..services.mailbox import mailbox_service
from ..services.tmux_service import tmux_service
from ..websocket.manager import ws_manager
from ..config import settings

logger = logging.getLogger(__name__)

router = APIRouter()

# In-memory event buffer per session (limited size)
_event_buffers: dict[str, deque] = {}

# Track tool usage per agent for journal nudging
_agent_tool_counts: dict[str, int] = {}
_agent_last_nudge: dict[str, datetime] = {}

# Nudge agent to journal after this many tool uses or this many seconds
JOURNAL_NUDGE_TOOL_THRESHOLD = 15
JOURNAL_NUDGE_TIME_SECONDS = 300  # 5 minutes


def _get_buffer(session_id: str) -> deque:
    """Get or create event buffer for a session."""
    if session_id not in _event_buffers:
        _event_buffers[session_id] = deque(maxlen=settings.event_buffer_size)
    return _event_buffers[session_id]


@router.post("", response_model=AgentEventResponse)
async def receive_agent_event(event: AgentEvent, background_tasks: BackgroundTasks):
    """
    Receive events from Claude Code hooks.

    This endpoint is called by the hook scripts when:
    - PostToolUse: After a tool (Bash, Write, Edit, Read) is executed
    - Stop: When the agent completes a response

    Auto-journals agent activity based on tool usage frequency and time thresholds.
    """
    event_id = str(uuid.uuid4())[:8]

    # Use agent_id if available, fallback to session_id
    display_agent_id = event.agent_id if event.agent_id and event.agent_id != "unknown" else event.session_id

    # Store in buffer
    buffer = _get_buffer(event.session_id)
    event_data = {
        "id": event_id,
        "event_type": event.event_type.value,
        "session_id": event.session_id,
        "agent_id": display_agent_id,
        "tool_name": event.tool_name,
        "tool_input": _truncate_content(event.tool_input),
        "tool_output": _truncate_content(event.tool_output),
        "timestamp": event.timestamp.isoformat(),
    }
    buffer.append(event_data)

    # Broadcast agent_event to WebSocket clients
    await ws_manager.broadcast("agent_event", event_data)

    # Track tool usage for journal nudging
    if event.event_type == AgentEventType.POST_TOOL_USE and event.tool_name:
        _agent_tool_counts[display_agent_id] = _agent_tool_counts.get(display_agent_id, 0) + 1

    # For Stop events with response_content, create a message and broadcast it
    if event.event_type == AgentEventType.STOP and event.response_content:
        msg = Message(
            id=str(uuid.uuid4()),
            timestamp=datetime.now(timezone.utc),
            from_agent=display_agent_id,
            to_agent="user",
            type=MessageType.RESPONSE,
            content=event.response_content,
        )
        # Store in mailbox service for retrieval via /api/messages
        mailbox_service.store_message(msg)
        # Broadcast to frontend so it appears in the chat
        await ws_manager.broadcast("new_message", msg.model_dump(mode="json"))

        # Nudge agent to journal if enough activity has accumulated
        background_tasks.add_task(
            _maybe_nudge_journal, display_agent_id
        )

    return AgentEventResponse(
        success=True,
        event_id=event_id,
        message=f"Event {event.event_type.value} received for agent {display_agent_id}",
    )


async def _maybe_nudge_journal(agent_id: str):
    """Nudge an agent to write a journal entry if activity thresholds are met.

    Instead of the server writing a mechanical summary, we inject a prompt
    into the agent's tmux window. The agent - with full conversation context -
    writes a real, meaningful journal entry.
    """
    now = datetime.now(timezone.utc)
    total_tools = _agent_tool_counts.get(agent_id, 0)
    last_nudge = _agent_last_nudge.get(agent_id)

    # Check thresholds
    time_met = (
        last_nudge is None
        or (now - last_nudge).total_seconds() >= JOURNAL_NUDGE_TIME_SECONDS
    )
    tools_met = total_tools >= JOURNAL_NUDGE_TOOL_THRESHOLD

    if not (time_met or tools_met):
        return

    # Don't nudge if the agent's window doesn't exist
    try:
        if not await tmux_service.window_exists(agent_id):
            return
    except Exception:
        return

    # Inject the nudge into the agent's tmux window
    nudge = (
        f'Write a journal entry about your recent work using: '
        f'./tools/journal log "<brief summary of what you just did and why>"'
    )
    try:
        await tmux_service.send_input(agent_id, nudge)
        logger.info(f"Journal nudge sent to {agent_id} (tools: {total_tools})")
    except Exception:
        logger.debug(f"Failed to nudge {agent_id} for journaling")
        return

    # Reset counters
    _agent_tool_counts[agent_id] = 0
    _agent_last_nudge[agent_id] = now


@router.get("")
async def list_agent_events(session_id: str | None = None, limit: int = 50):
    """
    List recent agent events.

    Args:
        session_id: Filter by session ID (optional)
        limit: Maximum number of events to return
    """
    if session_id:
        buffer = _get_buffer(session_id)
        events = list(buffer)[-limit:]
    else:
        # Combine all buffers
        all_events = []
        for buf in _event_buffers.values():
            all_events.extend(buf)
        # Sort by timestamp descending
        all_events.sort(key=lambda e: e["timestamp"], reverse=True)
        events = all_events[:limit]

    return {"events": events, "total": len(events)}


@router.get("/sessions")
async def list_sessions():
    """List all sessions that have sent events."""
    sessions = []
    for session_id, buffer in _event_buffers.items():
        if buffer:
            latest = buffer[-1]
            sessions.append({
                "session_id": session_id,
                "event_count": len(buffer),
                "last_event": latest["timestamp"],
                "last_event_type": latest["event_type"],
            })
    return {"sessions": sessions}


def _truncate_content(content: Any, max_length: int = 1000) -> Any:
    """Truncate content for storage/display."""
    if content is None:
        return None
    if isinstance(content, str):
        if len(content) > max_length:
            return content[:max_length] + "... [truncated]"
        return content
    if isinstance(content, dict):
        # Recursively truncate dict values
        return {k: _truncate_content(v, max_length) for k, v in content.items()}
    if isinstance(content, list):
        return [_truncate_content(item, max_length) for item in content[:10]]
    return content
