import asyncio
import aiofiles
from datetime import datetime, timezone
from typing import List, Optional
from collections import deque
import json
import uuid

from ..config import settings
from ..models.message import Message, MessageType


class MailboxService:
    def __init__(self):
        self.mailbox_path = settings.mailbox_path
        self._lock = asyncio.Lock()
        # In-memory message store for dashboard display (most recent messages)
        self._messages: deque[Message] = deque(maxlen=200)

    async def _ensure_mailbox(self):
        """Ensure mailbox file exists."""
        self.mailbox_path.parent.mkdir(parents=True, exist_ok=True)
        if not self.mailbox_path.exists():
            self.mailbox_path.touch()

    async def send_to_supervisor(
        self,
        message_id: str,
        source: str,
        payload: dict
    ):
        """Send a message to the supervisor agent via mailbox."""
        await self._ensure_mailbox()

        message = f"""--- MESSAGE ---
timestamp: {datetime.now(timezone.utc).isoformat()}
from: webhook:{source}
to: supervisor
type: task
id: {message_id}
---
{json.dumps(payload, indent=2, default=str)}
"""
        async with self._lock:
            async with aiofiles.open(self.mailbox_path, "a") as f:
                await f.write(message + "\n")

    async def send_message(
        self,
        from_agent: str,
        to_agent: str,
        content: str,
        msg_type: MessageType = MessageType.TASK
    ) -> str:
        """Send a message between agents."""
        await self._ensure_mailbox()

        message_id = str(uuid.uuid4())
        message = f"""--- MESSAGE ---
timestamp: {datetime.now(timezone.utc).isoformat()}
from: {from_agent}
to: {to_agent}
type: {msg_type.value}
id: {message_id}
---
{content}
"""
        async with self._lock:
            async with aiofiles.open(self.mailbox_path, "a") as f:
                await f.write(message + "\n")

        return message_id

    def store_message(self, message: Message):
        """Store a message in memory for dashboard display."""
        self._messages.append(message)

    async def get_messages(
        self,
        limit: int = 50,
        offset: int = 0,
        agent_id: Optional[str] = None
    ) -> List[Message]:
        """Read messages from in-memory store for dashboard display."""
        messages = list(self._messages)

        # Filter by agent if specified
        if agent_id:
            messages = [m for m in messages
                       if m.from_agent == agent_id or m.to_agent == agent_id]

        # Return in reverse order (newest first) with pagination
        messages = list(reversed(messages))
        return messages[offset:offset + limit]


mailbox_service = MailboxService()
