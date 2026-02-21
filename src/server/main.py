from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import logging
import os
from pathlib import Path

from .config import settings

# --- Laminar observability (optional) ---
# Initialize early, before any Anthropic SDK usage, so it can patch the SDK.
# Gracefully skipped if LMNR_PROJECT_API_KEY is not set.
_lmnr_api_key = os.getenv("LMNR_PROJECT_API_KEY")
if _lmnr_api_key:
    try:
        from lmnr import Laminar, Instruments
        Laminar.initialize(
            project_api_key=_lmnr_api_key,
            instruments={Instruments.ANTHROPIC},
        )
    except Exception:
        logging.getLogger(__name__).warning("Failed to initialize Laminar observability", exc_info=True)
from .routes import (
    webhooks,
    agents,
    messages,
    agent_events,
    journal,
    filesystem,
    sessions,
    thoughts,
    projects,
    tasks,
    heartbeat,
    prefs,
    budget,
    telegram,
)
from .integrations.telegram import telegram_bot
from .websocket.manager import ws_manager

logging.basicConfig(level=getattr(logging, settings.log_level))
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    logger.info("Starting cmux server...")
    ws_manager.start_ping_task()
    if telegram_bot.is_configured:
        await telegram_bot.start_polling()
    yield
    # Shutdown
    if telegram_bot.is_running:
        await telegram_bot.stop()
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
app.include_router(projects.router, prefix="/api/projects", tags=["projects"])
app.include_router(tasks.router, prefix="/api/tasks", tags=["tasks"])
app.include_router(heartbeat.router, prefix="/api/heartbeat", tags=["heartbeat"])
app.include_router(prefs.router, prefix="/api/prefs", tags=["prefs"])
app.include_router(budget.router, prefix="/api/budget", tags=["budget"])
app.include_router(telegram.router, prefix="/api/telegram", tags=["telegram"])

# Static files (frontend) - only mount if directory exists
frontend_dir = Path("src/frontend/dist")
if frontend_dir.exists():
    app.mount("/", StaticFiles(directory=str(frontend_dir), html=True), name="frontend")


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=settings.host, port=settings.port)
