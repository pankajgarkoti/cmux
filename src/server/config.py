from pydantic_settings import BaseSettings
from pathlib import Path


class Settings(BaseSettings):
    host: str = "0.0.0.0"
    port: int = 8000
    log_level: str = "INFO"
    tmux_session: str = "cmux"
    cmux_dir: Path = Path(".cmux")
    mailbox_path: Path = Path(".cmux/mailbox")
    recovery_wait_seconds: int = 30
    event_buffer_size: int = 100
    journal_path: Path = Path(".cmux/journal")
    router_log_path: Path = Path(".cmux/router.log")
    healthy_commit_path: Path = Path(".cmux/.last_healthy_commit")

    # System windows that should be hidden from agent listings
    system_windows: list[str] = ["monitor"]

    # Main session name (immortal - cannot be killed)
    main_session: str = "cmux"

    # Session prefix for spawned sessions
    session_prefix: str = "cmux-"

    # Startup delay for Claude to initialize (seconds)
    claude_startup_delay: int = 8

    model_config = {
        "env_prefix": "CMUX_",
        "env_file": ".env",
        "extra": "ignore",
    }


settings = Settings()
