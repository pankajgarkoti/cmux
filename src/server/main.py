from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging
from pathlib import Path

from .config import settings
from .routes import (
    webhooks,
    agents,
    messages,
    agent_events,
    journal,
    filesystem,
    sessions,
    thoughts,
)
from .websocket.manager import ws_manager

logging.basicConfig(level=getattr(logging, settings.log_level))
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("Starting cmux server...")
    ws_manager.start_ping_task()
    yield
    # Shutdown
    await ws_manager.stop_ping_task()
    await ws_manager.disconnect_all()
    logger.info("Shutting down cmux server...")


app = FastAPI(
    title="cmux",
    description="Self-improving multi-agent AI orchestration",
    version="0.1.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routes
app.include_router(webhooks.router, prefix="/api/webhooks", tags=["webhooks"])
app.include_router(agents.router, prefix="/api/agents", tags=["agents"])
app.include_router(sessions.router, prefix="/api/sessions", tags=["sessions"])
app.include_router(messages.router, prefix="/api/messages", tags=["messages"])
app.include_router(
    agent_events.router, prefix="/api/agent-events", tags=["agent-events"]
)
app.include_router(journal.router, prefix="/api/journal", tags=["journal"])
app.include_router(filesystem.router, prefix="/api/filesystem", tags=["filesystem"])
app.include_router(thoughts.router, prefix="/api/thoughts", tags=["thoughts"])

# Static files (frontend) - only mount if directory exists
frontend_dir = Path("src/frontend/dist")
if frontend_dir.exists():
    app.mount("/", StaticFiles(directory=str(frontend_dir), html=True), name="frontend")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=settings.host, port=settings.port)
