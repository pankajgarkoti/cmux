from fastapi import APIRouter, BackgroundTasks
from datetime import datetime, timezone
import uuid

from ..models.webhook import WebhookPayload, WebhookResponse
from ..services.mailbox import mailbox_service
from ..websocket.manager import ws_manager

router = APIRouter()


@router.post("/{source}", response_model=WebhookResponse)
async def receive_webhook(
    source: str,
    payload: WebhookPayload,
    background_tasks: BackgroundTasks
):
    """Receive and process webhook from external source."""
    message_id = str(uuid.uuid4())

    # Queue message for supervisor
    await mailbox_service.send_to_supervisor(
        message_id=message_id,
        source=source,
        payload=payload.model_dump()
    )

    # Broadcast to dashboard
    background_tasks.add_task(
        ws_manager.broadcast,
        "webhook_received",
        {"source": source, "message_id": message_id}
    )

    return WebhookResponse(
        success=True,
        message_id=message_id,
        queued_at=datetime.now(timezone.utc)
    )


@router.get("/health")
async def webhook_health():
    """Health check for webhook receiver."""
    return {"status": "healthy", "timestamp": datetime.now(timezone.utc).isoformat()}
