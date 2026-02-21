from fastapi import APIRouter
from pydantic import BaseModel
from datetime import datetime, timezone
from typing import Dict, Optional
import logging

from ..websocket.manager import ws_manager

logger = logging.getLogger(__name__)

router = APIRouter()


class HeartbeatData(BaseModel):
    timestamp: float
    sections: Dict[str, str] = {}
    highest_priority: Optional[str] = None
    all_clear: bool = False


class HeartbeatResponse(BaseModel):
    timestamp: float
    sections: Dict[str, str]
    highest_priority: Optional[str]
    all_clear: bool
    received_at: str


# In-memory latest heartbeat
_latest_heartbeat: Optional[HeartbeatResponse] = None


@router.post("")
async def post_heartbeat(data: HeartbeatData):
    """Accept heartbeat scan data from monitor and broadcast via WebSocket."""
    global _latest_heartbeat

    _latest_heartbeat = HeartbeatResponse(
        timestamp=data.timestamp,
        sections=data.sections,
        highest_priority=data.highest_priority,
        all_clear=data.all_clear,
        received_at=datetime.now(timezone.utc).isoformat(),
    )

    await ws_manager.broadcast("heartbeat_update", _latest_heartbeat.model_dump())

    return {"success": True}


@router.get("")
async def get_heartbeat():
    """Return latest heartbeat data."""
    if _latest_heartbeat is None:
        return {"status": "no_data", "message": "No heartbeat received yet"}
    return _latest_heartbeat.model_dump()
