from fastapi import APIRouter, BackgroundTasks
from fastapi.responses import JSONResponse
from datetime import datetime, timezone
from pathlib import Path
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
    """Health check with frontend status. Returns 503 if degraded."""
    frontend_dist = Path("src/frontend/dist")
    index_exists = (frontend_dist / "index.html").exists()

    assets_dir = frontend_dist / "assets"
    js_files = list(assets_dir.glob("*.js")) if assets_dir.exists() else []
    frontend_ok = index_exists and len(js_files) > 0

    response_data = {
        "api": "healthy",
        "frontend": {
            "status": "healthy" if frontend_ok else "unhealthy",
            "index_exists": index_exists,
            "js_bundle_count": len(js_files)
        },
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

    if not frontend_ok:
        response_data["status"] = "degraded"
        return JSONResponse(response_data, status_code=503)

    response_data["status"] = "healthy"
    return response_data
