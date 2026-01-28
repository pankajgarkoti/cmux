from pydantic_settings import BaseSettings
from pathlib import Path


class Settings(BaseSettings):
    host: str = "0.0.0.0"
    port: int = 8000
    log_level: str = "INFO"
    tmux_session: str = "cmux"
    mailbox_path: Path = Path(".cmux/mailbox")
    recovery_wait_seconds: int = 30
    compact_interval_minutes: int = 15

    model_config = {
        "env_prefix": "CMUX_",
        "env_file": ".env",
    }


settings = Settings()
