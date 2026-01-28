import asyncio
import aiofiles
from datetime import datetime, timezone
from typing import List, Optional
import json
import uuid

from ..config import settings
from ..models.message import Message, MessageType


class MailboxService:
    def __init__(self):
        self.mailbox_path = settings.mailbox_path
        self._lock = asyncio.Lock()

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

    async def get_messages(
        self,
        limit: int = 50,
        offset: int = 0,
        agent_id: Optional[str] = None
    ) -> List[Message]:
        """Read messages from mailbox (for dashboard display)."""
        await self._ensure_mailbox()

        # This is a simplified implementation
        # Production would use a proper database
        messages: List[Message] = []
        # Parse mailbox file and return messages
        # Implementation depends on specific parsing needs
        return messages[offset:offset + limit]


mailbox_service = MailboxService()
