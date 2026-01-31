from fastapi import APIRouter, Query
from datetime import datetime, timezone
from typing import Optional
import uuid

from ..models.message import Message, MessageList, UserMessage, InternalMessage, MessageType
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
    """Endpoint for agents to send messages to user (displayed in dashboard).

    HOW SUPERVISOR/AGENT REPLIES REACH THE FRONTEND:
    - Agent text output to terminal stays in tmux only (not automatic)
    - To display a message in the dashboard, agents must explicitly use:
        ./tools/mailbox send user "subject" "body"
      or:
        ./tools/mailbox quick user "message"
    - This calls the API directly for user-targeted messages
    - The router.sh daemon also routes "-> user" messages through this endpoint

    This is by design: explicit mailbox communication keeps the dashboard
    focused on intentional agent-to-user messages, not terminal noise.
    """
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


@router.post("/internal")
async def store_internal_message(data: InternalMessage):
    """Store agent-to-agent message from router daemon.

    Called by router.sh when routing messages between agents.
    Stores message in SQLite and broadcasts to frontend via WebSocket.
    """
    msg = Message(
        id=str(uuid.uuid4()),
        timestamp=datetime.now(timezone.utc),
        from_agent=data.from_agent,
        to_agent=data.to_agent,
        content=data.content,
        type=data.type,
        metadata=data.metadata
    )

    # Store in memory + SQLite
    mailbox_service.store_message(msg)

    # Broadcast to frontend
    await ws_manager.broadcast("new_message", msg.model_dump(mode="json"))

    return {"status": "stored", "id": msg.id}
