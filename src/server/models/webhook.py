from pydantic import BaseModel, Field
from datetime import datetime
from typing import Any, Optional


class WebhookPayload(BaseModel):
    source: str
    event_type: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    data: dict[str, Any]
    signature: Optional[str] = None


class WebhookResponse(BaseModel):
    success: bool
    message_id: str
    queued_at: datetime
