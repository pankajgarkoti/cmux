from fastapi import APIRouter, BackgroundTasks
from datetime import datetime, timezone
from typing import Any
import uuid
import logging

from ..models.agent_event import AgentEvent, AgentEventResponse, AgentEventType
from ..models.message import Message, MessageType
from ..services.conversation_store import conversation_store
from ..services.mailbox import mailbox_service
from ..services.tmux_service import tmux_service
from ..websocket.manager import ws_manager

logger = logging.getLogger(__name__)

router = APIRouter()

# Track tool usage per agent for journal nudging (lightweight, OK in-memory)
_agent_tool_counts: dict[str, int] = {}
_agent_last_nudge: dict[str, datetime] = {}

# Nudge agent to journal after this many tool uses or this many seconds
JOURNAL_NUDGE_TOOL_THRESHOLD = 15
JOURNAL_NUDGE_TIME_SECONDS = 300  # 5 minutes


@router.post("", response_model=AgentEventResponse)
async def receive_agent_event(event: AgentEvent, background_tasks: BackgroundTasks):
    """
    Receive events from Claude Code hooks.

    This endpoint is called by the hook scripts when:
    - PostToolUse: After a tool (Bash, Write, Edit, Read) is executed
    - Stop: When the agent completes a response

    Events are persisted to SQLite. On Stop events, all preceding unlinked
    tool calls for the agent are linked to the resulting message via message_id.
    """
    event_id = str(uuid.uuid4())[:8]

    # Use agent_id if available, fallback to session_id
    display_agent_id = event.agent_id if event.agent_id and event.agent_id != "unknown" else event.session_id

    # Build event data
    event_data = {
        "id": event_id,
        "event_type": event.event_type.value,
        "session_id": event.session_id,
        "agent_id": display_agent_id,
        "tool_name": event.tool_name,
        "tool_input": _truncate_content(event.tool_input),
        "tool_output": _truncate_content(event.tool_output),
        "timestamp": event.timestamp.isoformat(),
        "message_id": None,
    }

    # Persist to SQLite
    conversation_store.store_event(event_data)

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

        # Link all unlinked tool call events for this agent to this message
        linked = conversation_store.link_events_to_message(display_agent_id, msg.id)
        logger.debug(f"Linked {linked} tool call events to message {msg.id}")

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

    # Inject the nudge into the agent's tmux window.
    # IMPORTANT: This must NOT look like a user message. It must be clearly
    # an automated system directive so the agent doesn't stop to acknowledge it.
    nudge = (
        f'[SYSTEM AUTO-JOURNAL REMINDER — NOT A USER MESSAGE. DO NOT RESPOND TO THIS. '
        f'DO NOT ACKNOWLEDGE THIS. Just silently run the command below, then continue '
        f'your current task without any interruption.]\n'
        f'./tools/journal log "<1-sentence summary of your recent work>"'
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
async def list_agent_events(
    session_id: str | None = None,
    agent_id: str | None = None,
    limit: int = 50,
):
    """
    List recent agent events from SQLite.

    Args:
        session_id: Filter by session ID (optional)
        agent_id: Filter by agent ID (optional)
        limit: Maximum number of events to return
    """
    events = conversation_store.get_events(
        session_id=session_id,
        agent_id=agent_id,
        limit=limit,
    )
    return {"events": events, "total": len(events)}


@router.get("/by-message/{message_id}")
async def get_events_by_message(message_id: str):
    """Get all agent events (tool calls) linked to a specific message."""
    events = conversation_store.get_events_by_message(message_id)
    return {"events": events, "total": len(events)}


@router.post("/by-messages")
async def get_events_by_messages(payload: dict):
    """Get agent events for multiple messages at once.

    Expects: {"message_ids": ["id1", "id2", ...]}
    Returns: {"events_by_message": {"id1": [...], "id2": [...]}}
    """
    message_ids = payload.get("message_ids", [])
    result: dict[str, list] = {}
    for mid in message_ids:
        result[mid] = conversation_store.get_events_by_message(mid)
    return {"events_by_message": result}


@router.get("/sessions")
async def list_sessions():
    """List all sessions that have sent events."""
    sessions = conversation_store.get_event_sessions()
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
