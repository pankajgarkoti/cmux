"""Telegram bot integration for CMUX.

Uses the raw Telegram Bot API via httpx — no heavy dependencies.
Supports polling mode for receiving messages and sending replies.
"""

import asyncio
import os
import logging
from typing import Optional

import httpx

logger = logging.getLogger(__name__)

TELEGRAM_API = "https://api.telegram.org"


class TelegramBot:
    """Lightweight Telegram bot using the raw Bot API.

    Polls for incoming messages and forwards them to the CMUX mailbox.
    Can send messages back to the user's Telegram chat.
    """

    def __init__(
        self,
        token: Optional[str] = None,
        chat_id: Optional[str] = None,
    ):
        self.token = token or os.getenv("TELEGRAM_BOT_TOKEN")
        self.chat_id = chat_id or os.getenv("TELEGRAM_CHAT_ID")
        self._base_url = f"{TELEGRAM_API}/bot{self.token}" if self.token else None
        self._polling_task: Optional[asyncio.Task] = None
        self._running = False
        self._offset = 0
        self._client: Optional[httpx.AsyncClient] = None
        # Callback for incoming messages — set by the route module
        self.on_message = None

    @property
    def is_configured(self) -> bool:
        return bool(self.token)

    @property
    def is_running(self) -> bool:
        return self._running

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(timeout=httpx.Timeout(35.0))
        return self._client

    async def send_message(self, text: str, chat_id: Optional[str] = None) -> bool:
        """Send a message to a Telegram chat.

        Args:
            text: Message text (supports Markdown).
            chat_id: Target chat. Defaults to configured TELEGRAM_CHAT_ID.

        Returns:
            True if sent successfully.
        """
        target = chat_id or self.chat_id
        if not self._base_url or not target:
            return False

        # Telegram messages max 4096 chars — split if needed
        chunks = [text[i:i + 4096] for i in range(0, len(text), 4096)]
        client = await self._get_client()
        for chunk in chunks:
            try:
                resp = await client.post(
                    f"{self._base_url}/sendMessage",
                    json={"chat_id": target, "text": chunk},
                )
                if resp.status_code != 200:
                    logger.warning(f"Telegram sendMessage failed: {resp.status_code} {resp.text[:200]}")
                    return False
            except Exception:
                logger.warning("Telegram sendMessage error", exc_info=True)
                return False
        return True

    async def get_updates(self) -> list[dict]:
        """Long-poll for new updates from Telegram."""
        if not self._base_url:
            return []

        client = await self._get_client()
        try:
            resp = await client.get(
                f"{self._base_url}/getUpdates",
                params={"offset": self._offset, "timeout": 25},
            )
            if resp.status_code != 200:
                logger.warning(f"Telegram getUpdates failed: {resp.status_code}")
                return []

            data = resp.json()
            updates = data.get("result", [])
            if updates:
                self._offset = updates[-1]["update_id"] + 1
            return updates
        except httpx.TimeoutException:
            return []  # Normal for long-polling
        except Exception:
            logger.warning("Telegram getUpdates error", exc_info=True)
            return []

    async def start_polling(self):
        """Start the background polling loop."""
        if not self.is_configured:
            logger.info("Telegram bot not configured — skipping polling")
            return
        if self._running:
            return

        self._running = True
        self._polling_task = asyncio.create_task(self._poll_loop())
        logger.info("Telegram bot polling started")

    async def _poll_loop(self):
        """Internal polling loop — runs until stop() is called."""
        while self._running:
            try:
                updates = await self.get_updates()
                for update in updates:
                    await self._handle_update(update)
            except asyncio.CancelledError:
                break
            except Exception:
                logger.warning("Telegram poll loop error", exc_info=True)
                await asyncio.sleep(5)

    async def _handle_update(self, update: dict):
        """Process a single Telegram update."""
        message = update.get("message", {})
        text = message.get("text")
        chat_id = str(message.get("chat", {}).get("id", ""))

        if not text:
            return

        # Security: only accept messages from the configured chat
        if self.chat_id and chat_id != str(self.chat_id):
            logger.debug(f"Telegram: ignoring message from chat {chat_id} (expected {self.chat_id})")
            return

        # If no chat_id was configured, use the first sender's chat
        if not self.chat_id:
            self.chat_id = chat_id
            logger.info(f"Telegram: auto-configured chat_id={chat_id}")

        if self.on_message:
            await self.on_message(text, chat_id)

    def reload_config(self, token: Optional[str] = None, chat_id: Optional[str] = None):
        """Re-read credentials from environment and update internal state.

        Call this after dotenv.load_dotenv() to pick up newly-created .env files
        without restarting the server.
        """
        self.token = token or os.getenv("TELEGRAM_BOT_TOKEN")
        self.chat_id = chat_id or os.getenv("TELEGRAM_CHAT_ID")
        self._base_url = f"{TELEGRAM_API}/bot{self.token}" if self.token else None
        # Close stale HTTP client so next call creates a fresh one
        if self._client and not self._client.is_closed:
            # Can't await here (sync method) — mark for recreation
            self._client = None

    async def stop(self):
        """Stop polling and close the HTTP client."""
        self._running = False
        if self._polling_task and not self._polling_task.done():
            self._polling_task.cancel()
            try:
                await self._polling_task
            except asyncio.CancelledError:
                pass
        if self._client and not self._client.is_closed:
            await self._client.aclose()
        logger.info("Telegram bot stopped")


# Singleton — initialized at import, but only active if token is set
telegram_bot = TelegramBot()
