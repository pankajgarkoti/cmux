from pathlib import Path
from datetime import date, datetime
import aiofiles
import aiofiles.os
import re
from typing import Optional

from ..config import settings
from ..models.journal import (
    JournalEntry,
    JournalDayResponse,
    JournalSearchResult,
)


class JournalService:
    """Service for managing daily journal entries."""

    def __init__(self, base_path: Optional[Path] = None):
        self.base_path = base_path or settings.journal_path

    def _get_day_path(self, journal_date: date) -> Path:
        """Get path to journal directory for a specific date."""
        return self.base_path / journal_date.strftime("%Y-%m-%d")

    def _get_journal_file(self, journal_date: date) -> Path:
        """Get path to journal.md for a specific date."""
        return self._get_day_path(journal_date) / "journal.md"

    def _get_artifacts_dir(self, journal_date: date) -> Path:
        """Get path to artifacts directory for a specific date."""
        return self._get_day_path(journal_date) / "artifacts"

    async def ensure_day_exists(self, journal_date: date) -> None:
        """Ensure journal directory structure exists for a date."""
        day_path = self._get_day_path(journal_date)
        artifacts_path = self._get_artifacts_dir(journal_date)

        await aiofiles.os.makedirs(day_path, exist_ok=True)
        await aiofiles.os.makedirs(artifacts_path, exist_ok=True)

        # Create journal.md if it doesn't exist
        journal_file = self._get_journal_file(journal_date)
        if not journal_file.exists():
            async with aiofiles.open(journal_file, "w") as f:
                await f.write(f"# Journal - {journal_date.strftime('%Y-%m-%d')}\n")

    async def add_entry(self, title: str, content: str, journal_date: Optional[date] = None) -> JournalEntry:
        """Add a new entry to the journal."""
        journal_date = journal_date or date.today()
        await self.ensure_day_exists(journal_date)

        now_local = datetime.now().astimezone()
        entry = JournalEntry(
            title=title,
            content=content,
            timestamp=now_local,
        )

        journal_file = self._get_journal_file(journal_date)
        time_str = now_local.strftime("%H:%M")

        # Only append content body if non-empty (quick logs have no body)
        if content and content.strip():
            entry_text = f"\n## {time_str} - {title}\n{content}\n"
        else:
            entry_text = f"\n## {time_str} - {title}\n"

        async with aiofiles.open(journal_file, "a") as f:
            await f.write(entry_text)

        return entry

    async def get_day(self, journal_date: date) -> JournalDayResponse:
        """Get journal content for a specific date."""
        journal_file = self._get_journal_file(journal_date)
        artifacts_dir = self._get_artifacts_dir(journal_date)

        content = ""
        if journal_file.exists():
            async with aiofiles.open(journal_file, "r") as f:
                content = await f.read()

        artifacts = []
        if artifacts_dir.exists():
            artifacts = [f.name for f in artifacts_dir.iterdir() if f.is_file()]

        return JournalDayResponse(
            date=journal_date.strftime("%Y-%m-%d"),
            content=content,
            artifacts=artifacts,
        )

    async def list_dates(self) -> list[str]:
        """List all dates that have journal entries."""
        if not self.base_path.exists():
            return []

        dates = []
        for item in self.base_path.iterdir():
            if item.is_dir() and re.match(r"\d{4}-\d{2}-\d{2}", item.name):
                journal_file = item / "journal.md"
                if journal_file.exists():
                    dates.append(item.name)

        return sorted(dates, reverse=True)

    async def search(self, query: str, limit: int = 20) -> list[JournalSearchResult]:
        """Search journal entries for a query string."""
        results = []
        query_lower = query.lower()

        dates = await self.list_dates()

        for date_str in dates:
            journal_date = date.fromisoformat(date_str)
            journal_file = self._get_journal_file(journal_date)

            if not journal_file.exists():
                continue

            async with aiofiles.open(journal_file, "r") as f:
                lines = await f.readlines()

            current_title = ""
            for line_num, line in enumerate(lines, 1):
                # Track current section title
                if line.startswith("## "):
                    # Extract title after time (e.g., "## 09:16 - PR Review Task")
                    match = re.match(r"## \d{2}:\d{2} - (.+)", line)
                    if match:
                        current_title = match.group(1).strip()

                if query_lower in line.lower():
                    # Create snippet with context
                    snippet = line.strip()[:200]
                    if len(line.strip()) > 200:
                        snippet += "..."

                    results.append(JournalSearchResult(
                        date=date_str,
                        title=current_title or "Journal",
                        snippet=snippet,
                        line_number=line_num,
                    ))

                    if len(results) >= limit:
                        return results

        return results

    async def save_artifact(
        self,
        filename: str,
        content: bytes,
        journal_date: Optional[date] = None,
    ) -> str:
        """Save an artifact file."""
        journal_date = journal_date or date.today()
        await self.ensure_day_exists(journal_date)

        artifacts_dir = self._get_artifacts_dir(journal_date)
        artifact_path = artifacts_dir / filename

        async with aiofiles.open(artifact_path, "wb") as f:
            await f.write(content)

        return str(artifact_path)

    async def get_artifact(self, filename: str, journal_date: date) -> Optional[bytes]:
        """Get artifact content."""
        artifact_path = self._get_artifacts_dir(journal_date) / filename

        if not artifact_path.exists():
            return None

        async with aiofiles.open(artifact_path, "rb") as f:
            return await f.read()


# Singleton instance
journal_service = JournalService()
