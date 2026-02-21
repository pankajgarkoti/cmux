"""Telegram integration routes.

Provides:
- POST /api/telegram/webhook — receives Telegram webhook updates (future use)
- GET /api/telegram/status — check if bot is configured and running
- POST /api/telegram/send — internal endpoint for agents to send messages to Telegram
"""

from fastapi import APIRouter
from pydantic import BaseModel
from typing import Optional
import logging

from ..integrations.telegram import telegram_bot
from ..services.mailbox import mailbox_service
from ..websocket.manager import ws_manager

logger = logging.getLogger(__name__)

router = APIRouter()


class TelegramSendRequest(BaseModel):
    text: str
    chat_id: Optional[str] = None


class TelegramWebhookUpdate(BaseModel):
    """Minimal Telegram webhook update — pass-through to bot handler."""
    update_id: int
    message: Optional[dict] = None


@router.get("/status")
async def telegram_status():
    """Check if the Telegram bot is configured and running."""
    return {
        "configured": telegram_bot.is_configured,
        "running": telegram_bot.is_running,
        "chat_id": telegram_bot.chat_id,
    }


@router.post("/send")
async def telegram_send(req: TelegramSendRequest):
    """Send a message to the configured Telegram chat.

    Used internally by agents or the router daemon to forward
    messages to the user via Telegram.
    """
    if not telegram_bot.is_configured:
        return {"success": False, "error": "Telegram bot not configured"}

    sent = await telegram_bot.send_message(req.text, chat_id=req.chat_id)
    return {"success": sent}


@router.post("/reload")
async def telegram_reload():
    """Reload Telegram bot credentials from .env and restart if newly configured.

    Call this after updating .env with TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID
    so the bot picks up the new values without a server restart.
    """
    from dotenv import load_dotenv

    load_dotenv(override=True)
    was_running = telegram_bot.is_running
    telegram_bot.reload_config()

    # Start polling if newly configured and not already running
    if telegram_bot.is_configured and not was_running:
        await telegram_bot.start_polling()

    return {
        "configured": telegram_bot.is_configured,
        "running": telegram_bot.is_running,
        "chat_id": telegram_bot.chat_id,
    }


@router.post("/webhook")
async def telegram_webhook(update: TelegramWebhookUpdate):
    """Receive a Telegram webhook update (for future webhook mode).

    In polling mode this endpoint is unused, but it's ready for when
    a public URL is available.
    """
    if update.message:
        await telegram_bot._handle_update(update.model_dump())
    return {"ok": True}


async def _on_telegram_message(text: str, chat_id: str):
    """Callback: incoming Telegram message → CMUX mailbox.

    Posts the message to the mailbox so the router daemon picks it up
    and delivers it to the supervisor.
    """
    await mailbox_service.send_mailbox_message(
        from_agent="telegram:user",
        to_agent="cmux:supervisor",
        subject=f"[USER] {text[:80]}",
        body=text,
    )

    # Also broadcast to the dashboard
    await ws_manager.broadcast("telegram_message", {
        "from": "telegram:user",
        "text": text,
        "chat_id": chat_id,
    })

    logger.info(f"Telegram message from chat {chat_id} routed to supervisor")


# Wire up the callback
telegram_bot.on_message = _on_telegram_message
