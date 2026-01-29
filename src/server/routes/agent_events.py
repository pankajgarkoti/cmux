from fastapi import APIRouter
from collections import deque
from typing import Any
import uuid

from ..models.agent_event import AgentEvent, AgentEventResponse
from ..websocket.manager import ws_manager
from ..config import settings

router = APIRouter()

# In-memory event buffer per session (limited size)
_event_buffers: dict[str, deque] = {}


def _get_buffer(session_id: str) -> deque:
    """Get or create event buffer for a session."""
    if session_id not in _event_buffers:
        _event_buffers[session_id] = deque(maxlen=settings.event_buffer_size)
    return _event_buffers[session_id]


@router.post("", response_model=AgentEventResponse)
async def receive_agent_event(event: AgentEvent):
    """
    Receive events from Claude Code hooks.

    This endpoint is called by the hook scripts when:
    - PostToolUse: After a tool (Bash, Write, Edit, Read) is executed
    - Stop: When the agent completes a response
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

    # Broadcast to WebSocket clients
    await ws_manager.broadcast("agent_event", event_data)

    return AgentEventResponse(
        success=True,
        event_id=event_id,
        message=f"Event {event.event_type.value} received for agent {display_agent_id}",
    )


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
