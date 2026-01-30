"""SQLite-based persistent storage for messages and archived agents.

Provides durability across server restarts and archives worker conversations
before they are killed.
"""

import sqlite3
import json
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import List, Optional
from contextlib import contextmanager

from pydantic import BaseModel

from ..config import settings
from ..models.message import Message, MessageType


class ArchivedAgent(BaseModel):
    """An archived agent with its terminal snapshot."""
    id: str
    agent_id: str
    agent_name: str
    agent_type: str
    archived_at: datetime
    terminal_output: Optional[str] = None


class ArchivedAgentSummary(BaseModel):
    """Summary of an archived agent (without terminal output)."""
    id: str
    agent_id: str
    agent_name: str
    agent_type: str
    archived_at: datetime


class ConversationStore:
    """SQLite-based persistent storage for messages and agent archives."""

    def __init__(self, db_path: Optional[Path] = None):
        self.db_path = db_path or (settings.cmux_dir / "conversations.db")
        self._ensure_db()

    def _ensure_db(self):
        """Create database and tables if they don't exist."""
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        with self._get_connection() as conn:
            conn.executescript("""
                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY,
                    timestamp TEXT NOT NULL,
                    from_agent TEXT NOT NULL,
                    to_agent TEXT NOT NULL,
                    type TEXT NOT NULL,
                    content TEXT NOT NULL,
                    metadata TEXT
                );

                CREATE INDEX IF NOT EXISTS idx_messages_from_agent ON messages(from_agent);
                CREATE INDEX IF NOT EXISTS idx_messages_to_agent ON messages(to_agent);
                CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);

                CREATE TABLE IF NOT EXISTS agent_archives (
                    id TEXT PRIMARY KEY,
                    agent_id TEXT NOT NULL,
                    agent_name TEXT NOT NULL,
                    agent_type TEXT NOT NULL,
                    archived_at TEXT NOT NULL,
                    terminal_output TEXT
                );

                CREATE INDEX IF NOT EXISTS idx_archives_agent_id ON agent_archives(agent_id);
                CREATE INDEX IF NOT EXISTS idx_archives_archived_at ON agent_archives(archived_at);
            """)

    @contextmanager
    def _get_connection(self):
        """Get a database connection with proper cleanup."""
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()

    def store_message(self, message: Message) -> None:
        """Store a message in the database."""
        with self._get_connection() as conn:
            conn.execute(
                """
                INSERT OR REPLACE INTO messages
                (id, timestamp, from_agent, to_agent, type, content, metadata)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    message.id,
                    message.timestamp.isoformat(),
                    message.from_agent,
                    message.to_agent,
                    message.type.value,
                    message.content,
                    json.dumps(message.metadata) if message.metadata else None,
                )
            )

    def get_messages(
        self,
        limit: int = 50,
        offset: int = 0,
        agent_id: Optional[str] = None
    ) -> List[Message]:
        """Retrieve messages from the database."""
        with self._get_connection() as conn:
            if agent_id:
                cursor = conn.execute(
                    """
                    SELECT * FROM messages
                    WHERE from_agent = ? OR to_agent = ?
                    ORDER BY timestamp DESC
                    LIMIT ? OFFSET ?
                    """,
                    (agent_id, agent_id, limit, offset)
                )
            else:
                cursor = conn.execute(
                    """
                    SELECT * FROM messages
                    ORDER BY timestamp DESC
                    LIMIT ? OFFSET ?
                    """,
                    (limit, offset)
                )

            messages = []
            for row in cursor.fetchall():
                messages.append(Message(
                    id=row["id"],
                    timestamp=datetime.fromisoformat(row["timestamp"]),
                    from_agent=row["from_agent"],
                    to_agent=row["to_agent"],
                    type=MessageType(row["type"]),
                    content=row["content"],
                    metadata=json.loads(row["metadata"]) if row["metadata"] else None,
                ))
            return messages

    def archive_agent(
        self,
        agent_id: str,
        agent_name: str,
        agent_type: str,
        terminal_output: Optional[str] = None
    ) -> str:
        """Archive an agent with its terminal snapshot.

        Args:
            agent_id: The agent's unique identifier (usually same as name)
            agent_name: Human-readable name of the agent
            agent_type: 'worker' or 'supervisor'
            terminal_output: Terminal scrollback capture

        Returns:
            Archive ID
        """
        archive_id = str(uuid.uuid4())
        with self._get_connection() as conn:
            conn.execute(
                """
                INSERT INTO agent_archives
                (id, agent_id, agent_name, agent_type, archived_at, terminal_output)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    archive_id,
                    agent_id,
                    agent_name,
                    agent_type,
                    datetime.now(timezone.utc).isoformat(),
                    terminal_output,
                )
            )
        return archive_id

    def get_archived_agents(self) -> List[ArchivedAgentSummary]:
        """Get list of all archived agents (without terminal output)."""
        with self._get_connection() as conn:
            cursor = conn.execute(
                """
                SELECT id, agent_id, agent_name, agent_type, archived_at
                FROM agent_archives
                ORDER BY archived_at DESC
                """
            )
            return [
                ArchivedAgentSummary(
                    id=row["id"],
                    agent_id=row["agent_id"],
                    agent_name=row["agent_name"],
                    agent_type=row["agent_type"],
                    archived_at=datetime.fromisoformat(row["archived_at"]),
                )
                for row in cursor.fetchall()
            ]

    def get_archive(self, archive_id: str) -> Optional[ArchivedAgent]:
        """Get a specific archive by ID (with terminal output)."""
        with self._get_connection() as conn:
            cursor = conn.execute(
                """
                SELECT * FROM agent_archives WHERE id = ?
                """,
                (archive_id,)
            )
            row = cursor.fetchone()
            if not row:
                return None
            return ArchivedAgent(
                id=row["id"],
                agent_id=row["agent_id"],
                agent_name=row["agent_name"],
                agent_type=row["agent_type"],
                archived_at=datetime.fromisoformat(row["archived_at"]),
                terminal_output=row["terminal_output"],
            )

    def get_archive_by_agent_id(self, agent_id: str) -> Optional[ArchivedAgent]:
        """Get the most recent archive for an agent ID."""
        with self._get_connection() as conn:
            cursor = conn.execute(
                """
                SELECT * FROM agent_archives
                WHERE agent_id = ?
                ORDER BY archived_at DESC
                LIMIT 1
                """,
                (agent_id,)
            )
            row = cursor.fetchone()
            if not row:
                return None
            return ArchivedAgent(
                id=row["id"],
                agent_id=row["agent_id"],
                agent_name=row["agent_name"],
                agent_type=row["agent_type"],
                archived_at=datetime.fromisoformat(row["archived_at"]),
                terminal_output=row["terminal_output"],
            )

    def get_messages_for_agent(self, agent_id: str, limit: int = 200) -> List[Message]:
        """Get all messages involving a specific agent."""
        return self.get_messages(limit=limit, agent_id=agent_id)


# Singleton instance
conversation_store = ConversationStore()
