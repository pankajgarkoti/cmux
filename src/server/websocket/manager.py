from fastapi import WebSocket
from typing import Dict
import asyncio
import json
from datetime import datetime, timezone


class ConnectionManager:
    def __init__(self):
        self.active_connections: Dict[str, WebSocket] = {}
        self._lock = asyncio.Lock()

    async def connect(self, websocket: WebSocket, client_id: str):
        await websocket.accept()
        async with self._lock:
            self.active_connections[client_id] = websocket

    async def disconnect(self, client_id: str):
        async with self._lock:
            if client_id in self.active_connections:
                del self.active_connections[client_id]

    async def disconnect_all(self):
        async with self._lock:
            for ws in self.active_connections.values():
                try:
                    await ws.close()
                except Exception:
                    pass
            self.active_connections.clear()

    async def broadcast(self, event: str, data: dict):
        message = json.dumps({
            "event": event,
            "data": data,
            "timestamp": datetime.now(timezone.utc).isoformat()
        })
        async with self._lock:
            disconnected = []
            for client_id, connection in self.active_connections.items():
                try:
                    await connection.send_text(message)
                except Exception:
                    disconnected.append(client_id)
            for client_id in disconnected:
                del self.active_connections[client_id]

    async def send_to(self, client_id: str, event: str, data: dict):
        if client_id in self.active_connections:
            message = json.dumps({
                "event": event,
                "data": data,
                "timestamp": datetime.now(timezone.utc).isoformat()
            })
            try:
                await self.active_connections[client_id].send_text(message)
            except Exception:
                async with self._lock:
                    if client_id in self.active_connections:
                        del self.active_connections[client_id]


ws_manager = ConnectionManager()
