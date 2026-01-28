from pydantic import BaseModel, Field
from datetime import datetime
from enum import Enum
from typing import Optional


class MessageType(str, Enum):
    TASK = "task"
    STATUS = "status"
    RESPONSE = "response"
    ERROR = "error"
    USER = "user"


class Message(BaseModel):
    id: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    from_agent: str
    to_agent: str
    type: MessageType
    content: str
    metadata: Optional[dict] = None


class MessageList(BaseModel):
    messages: list[Message]
    total: int


class UserMessage(BaseModel):
    content: str
    from_agent: str = "supervisor"
