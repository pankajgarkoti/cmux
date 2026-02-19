from fastapi import APIRouter, Query
from pydantic import BaseModel
from datetime import datetime, timezone
from typing import Optional
import logging
import uuid

from ..websocket.manager import ws_manager
from ..services.conversation_store import conversation_store

logger = logging.getLogger(__name__)

router = APIRouter()


class ThoughtEvent(BaseModel):
    agent_name: str
    thought_type: str  # 'reasoning' or 'tool_result'
    content: Optional[str] = None
    tool_name: Optional[str] = None
    tool_input: Optional[str] = None
    tool_response: Optional[str] = None
    timestamp: Optional[str] = None


@router.post("")
async def receive_thought(event: ThoughtEvent):
    """
    Receive a live thought/reasoning event from a Claude Code hook.

    Persists to SQLite and broadcasts via WebSocket.
    """
    thought_id = str(uuid.uuid4())[:8]
    thought_data = {
        "id": thought_id,
        "agent_name": event.agent_name,
        "thought_type": event.thought_type,
        "content": event.content,
        "tool_name": event.tool_name,
        "tool_input": _truncate(event.tool_input, 500),
        "tool_response": _truncate(event.tool_response, 500),
        "timestamp": event.timestamp or datetime.now(timezone.utc).isoformat(),
    }

    conversation_store.store_thought(thought_data)
    await ws_manager.broadcast("agent_thought", thought_data)

    return {"success": True, "thought_id": thought_id}


@router.get("")
async def get_thoughts(
    agent_name: Optional[str] = Query(None, description="Filter by agent name"),
    limit: int = Query(50, ge=1, le=500, description="Max number of thoughts to return"),
):
    """Retrieve persisted thoughts, optionally filtered by agent name."""
    thoughts = conversation_store.get_thoughts(agent_name=agent_name, limit=limit)
    return {"thoughts": thoughts, "count": len(thoughts)}


def _truncate(text: Optional[str], max_length: int) -> Optional[str]:
    if text is None:
        return None
    if len(text) > max_length:
        return text[:max_length] + "..."
    return text
