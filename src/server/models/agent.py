from pydantic import BaseModel, Field
from datetime import datetime
from enum import Enum
from typing import Optional


class AgentStatus(str, Enum):
    PENDING = "PENDING"
    IN_PROGRESS = "IN_PROGRESS"
    BLOCKED = "BLOCKED"
    TESTING = "TESTING"
    COMPLETE = "COMPLETE"
    FAILED = "FAILED"
    IDLE = "IDLE"


class AgentType(str, Enum):
    SUPERVISOR = "supervisor"
    WORKER = "worker"


class Agent(BaseModel):
    id: str
    name: str
    type: AgentType
    status: AgentStatus = AgentStatus.IDLE
    tmux_window: str
    session: str = "cmux"  # tmux session this agent belongs to
    created_at: datetime = Field(default_factory=datetime.utcnow)
    last_activity: Optional[datetime] = None
    current_task: Optional[str] = None


class AgentList(BaseModel):
    agents: list[Agent]
    total: int


class AgentMessage(BaseModel):
    content: str
    priority: int = Field(default=0, ge=0, le=10)
