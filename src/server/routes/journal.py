from fastapi import APIRouter, HTTPException, UploadFile, File, Query
from fastapi.responses import Response
from datetime import date
from typing import Optional

from ..models.journal import (
    JournalEntryCreate,
    JournalDayResponse,
    JournalDatesResponse,
    JournalSearchResponse,
)
from ..services.journal import journal_service

router = APIRouter()


@router.get("", response_model=JournalDayResponse)
async def get_journal(
    journal_date: Optional[str] = Query(None, alias="date", description="Date in YYYY-MM-DD format"),
):
    """
    Get journal for a specific date.

    If no date is provided, returns today's journal.
    """
    if journal_date:
        try:
            parsed_date = date.fromisoformat(journal_date)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD.")
    else:
        parsed_date = date.today()

    return await journal_service.get_day(parsed_date)


@router.post("/entry")
async def add_journal_entry(entry: JournalEntryCreate):
    """Add a new entry to today's journal."""
    created = await journal_service.add_entry(
        title=entry.title,
        content=entry.content,
    )
    return {
        "success": True,
        "entry": {
            "title": created.title,
            "timestamp": created.timestamp.isoformat(),
        },
    }


@router.get("/dates", response_model=JournalDatesResponse)
async def list_journal_dates():
    """List all dates that have journal entries."""
    dates = await journal_service.list_dates()
    return JournalDatesResponse(dates=dates)


@router.get("/search", response_model=JournalSearchResponse)
async def search_journals(
    q: str = Query(..., description="Search query"),
    limit: int = Query(20, ge=1, le=100),
):
    """Search across all journal entries."""
    results = await journal_service.search(query=q, limit=limit)
    return JournalSearchResponse(
        query=q,
        results=results,
        total=len(results),
    )


@router.post("/artifact")
async def upload_artifact(
    file: UploadFile = File(...),
    journal_date: Optional[str] = Query(None, alias="date"),
):
    """Upload an artifact file to today's (or specified date's) journal."""
    if journal_date:
        try:
            parsed_date = date.fromisoformat(journal_date)
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD.")
    else:
        parsed_date = date.today()

    if not file.filename:
        raise HTTPException(status_code=400, detail="Filename required")

    content = await file.read()
    path = await journal_service.save_artifact(
        filename=file.filename,
        content=content,
        journal_date=parsed_date,
    )

    return {
        "success": True,
        "filename": file.filename,
        "path": path,
    }


@router.get("/artifact/{filename}")
async def get_artifact(
    filename: str,
    journal_date: str = Query(..., alias="date"),
):
    """Download an artifact file."""
    try:
        parsed_date = date.fromisoformat(journal_date)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid date format. Use YYYY-MM-DD.")

    content = await journal_service.get_artifact(filename, parsed_date)
    if content is None:
        raise HTTPException(status_code=404, detail="Artifact not found")

    # Guess content type from extension
    content_type = "application/octet-stream"
    if filename.endswith(".md"):
        content_type = "text/markdown"
    elif filename.endswith(".json"):
        content_type = "application/json"
    elif filename.endswith(".txt"):
        content_type = "text/plain"
    elif filename.endswith(".png"):
        content_type = "image/png"
    elif filename.endswith(".jpg") or filename.endswith(".jpeg"):
        content_type = "image/jpeg"

    return Response(content=content, media_type=content_type)
