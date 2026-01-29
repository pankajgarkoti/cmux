import asyncio
from typing import List

from ..config import settings


class TmuxService:
    def __init__(self):
        self.session = settings.tmux_session

    async def _run_command(self, cmd: List[str]) -> tuple[str, str]:
        """Run tmux command and return stdout, stderr."""
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()
        return stdout.decode(), stderr.decode()

    async def list_windows(self) -> List[str]:
        """List all windows in the session."""
        stdout, _ = await self._run_command([
            "tmux", "list-windows", "-t", self.session, "-F", "#{window_name}"
        ])
        return [w.strip() for w in stdout.strip().split("\n") if w.strip()]

    async def send_input(self, window: str, text: str):
        """Send text input to a tmux window."""
        # Send text literally, then Enter separately
        await self._run_command([
            "tmux", "send-keys", "-t", f"{self.session}:{window}", "-l", text
        ])
        await self._run_command([
            "tmux", "send-keys", "-t", f"{self.session}:{window}", "Enter"
        ])

    async def send_interrupt(self, window: str):
        """Send Ctrl+C to a tmux window."""
        await self._run_command([
            "tmux", "send-keys", "-t", f"{self.session}:{window}", "C-c"
        ])

    async def capture_pane(self, window: str, lines: int = 100) -> str:
        """Capture recent output from a tmux pane."""
        stdout, _ = await self._run_command([
            "tmux", "capture-pane", "-t", f"{self.session}:{window}",
            "-p", "-S", f"-{lines}"
        ])
        return stdout

    async def create_window(self, name: str) -> bool:
        """Create a new tmux window."""
        _, stderr = await self._run_command([
            "tmux", "new-window", "-t", self.session, "-n", name
        ])
        return not stderr

    async def kill_window(self, name: str) -> bool:
        """Kill a tmux window."""
        _, stderr = await self._run_command([
            "tmux", "kill-window", "-t", f"{self.session}:{name}"
        ])
        return not stderr


tmux_service = TmuxService()
