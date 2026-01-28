from fastapi import APIRouter, Query
from datetime import datetime, timezone
from typing import Optional
import uuid

from ..models.message import Message, MessageList, UserMessage, MessageType
from ..services.mailbox import mailbox_service
from ..websocket.manager import ws_manager

router = APIRouter()


@router.get("", response_model=MessageList)
async def get_messages(
    limit: int = Query(default=50, le=200),
    offset: int = Query(default=0, ge=0),
    agent_id: Optional[str] = None
):
    """Get message history with optional filtering."""
    messages = await mailbox_service.get_messages(
        limit=limit,
        offset=offset,
        agent_id=agent_id
    )
    return MessageList(messages=messages, total=len(messages))


@router.post("/user")
async def send_to_user(message: UserMessage):
    """Endpoint for supervisor to send message to user (displayed in dashboard)."""
    msg = Message(
        id=str(uuid.uuid4()),
        timestamp=datetime.now(timezone.utc),
        from_agent=message.from_agent,
        to_agent="user",
        type=MessageType.USER,
        content=message.content
    )

    await ws_manager.broadcast("user_message", msg.model_dump(mode="json"))
    return {"success": True, "message_id": msg.id}
