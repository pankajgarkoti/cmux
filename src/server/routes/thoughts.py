from fastapi import APIRouter
from pydantic import BaseModel
from datetime import datetime, timezone
from typing import Optional
import logging

from ..websocket.manager import ws_manager

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

    These are ephemeral — broadcast via WebSocket only, no persistence.
    """
    thought_data = {
        "agent_name": event.agent_name,
        "thought_type": event.thought_type,
        "content": event.content,
        "tool_name": event.tool_name,
        "tool_input": _truncate(event.tool_input, 500),
        "tool_response": _truncate(event.tool_response, 500),
        "timestamp": event.timestamp or datetime.now(timezone.utc).isoformat(),
    }

    await ws_manager.broadcast("agent_thought", thought_data)

    return {"success": True}


def _truncate(text: Optional[str], max_length: int) -> Optional[str]:
    if text is None:
        return None
    if len(text) > max_length:
        return text[:max_length] + "..."
    return text
