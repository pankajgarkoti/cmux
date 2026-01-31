import asyncio
import aiofiles
from datetime import datetime, timezone
from typing import List, Optional
from collections import deque
import json
import uuid

from ..config import settings
from ..models.message import Message, MessageType
from .conversation_store import conversation_store


class MailboxService:
    def __init__(self):
        self.mailbox_path = settings.mailbox_path
        self._lock = asyncio.Lock()
        # In-memory message store for fast access (most recent messages)
        # SQLite provides durability across restarts
        self._messages: deque[Message] = deque(maxlen=200)
        # Load recent messages from SQLite on startup
        self._load_persisted_messages()

    def _load_persisted_messages(self):
        """Load recent messages from SQLite on startup."""
        try:
            messages = conversation_store.get_messages(limit=200)
            # Messages come in reverse order (newest first), reverse to get oldest first
            for msg in reversed(messages):
                self._messages.append(msg)
        except Exception:
            # Database might not exist yet on first run
            pass

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
        """Send a message to the supervisor agent via mailbox.

        Uses single-line format: [timestamp] from -> to: subject (body: path)
        The payload is written to a body file for the full content.
        """
        await self._ensure_mailbox()

        timestamp = datetime.now(timezone.utc).isoformat()
        from_addr = f"webhook:{source}"
        to_addr = "cmux:supervisor"
        subject = f"[WEBHOOK] {source}"

        # Write payload to body file
        date_str = datetime.now().strftime("%Y-%m-%d")
        attachments_dir = settings.cmux_dir / "journal" / date_str / "attachments"
        attachments_dir.mkdir(parents=True, exist_ok=True)
        body_path = attachments_dir / f"webhook-{message_id[:8]}.json"

        async with aiofiles.open(body_path, "w") as f:
            await f.write(json.dumps(payload, indent=2, default=str))

        # Write single-line mailbox entry
        body_rel = str(body_path)
        line = f"[{timestamp}] {from_addr} -> {to_addr}: {subject} (body: {body_rel})"

        async with self._lock:
            async with aiofiles.open(self.mailbox_path, "a") as f:
                await f.write(line + "\n")

    async def send_mailbox_message(
        self,
        from_agent: str,
        to_agent: str,
        subject: str,
        body: str = ""
    ) -> str:
        """Send a message between agents via mailbox.

        Uses single-line format: [timestamp] from -> to: subject (body: path)
        If body is provided, it's written to a file.
        """
        await self._ensure_mailbox()

        message_id = str(uuid.uuid4())
        timestamp = datetime.now(timezone.utc).isoformat()

        # Normalize addresses to session:agent format
        if ":" not in from_agent:
            from_addr = f"cmux:{from_agent}"
        else:
            from_addr = from_agent

        if to_agent == "user":
            to_addr = "user"
        elif ":" not in to_agent:
            to_addr = f"cmux:{to_agent}"
        else:
            to_addr = to_agent

        # Build mailbox line
        if body:
            # Write body to file
            date_str = datetime.now().strftime("%Y-%m-%d")
            attachments_dir = settings.cmux_dir / "journal" / date_str / "attachments"
            attachments_dir.mkdir(parents=True, exist_ok=True)
            body_path = attachments_dir / f"msg-{message_id[:8]}.md"

            async with aiofiles.open(body_path, "w") as f:
                await f.write(f"# {subject}\n\n{body}")

            line = f"[{timestamp}] {from_addr} -> {to_addr}: {subject} (body: {body_path})"
        else:
            line = f"[{timestamp}] {from_addr} -> {to_addr}: {subject}"

        async with self._lock:
            async with aiofiles.open(self.mailbox_path, "a") as f:
                await f.write(line + "\n")

        return message_id

    def store_message(self, message: Message):
        """Store a message in memory and persist to SQLite."""
        self._messages.append(message)
        # Write-through to SQLite for persistence
        conversation_store.store_message(message)

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
