"""Filesystem API routes for exploring .cmux directory."""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from pathlib import Path
from typing import Optional

from ..config import settings

router = APIRouter()


class FilesystemItem(BaseModel):
    name: str
    path: str
    type: str  # 'file' or 'directory'
    children: Optional[list["FilesystemItem"]] = None
    size: Optional[int] = None
    modified: Optional[str] = None


class FilesystemResponse(BaseModel):
    items: list[FilesystemItem]
    path: str


class FileContentResponse(BaseModel):
    content: str
    path: str


def get_cmux_dir() -> Path:
    """Get the .cmux directory path."""
    return Path(settings.cmux_dir)


def build_tree(path: Path, max_depth: int = 3, current_depth: int = 0) -> list[FilesystemItem]:
    """Recursively build a file tree from a directory."""
    items = []

    if not path.exists() or not path.is_dir():
        return items

    try:
        entries = sorted(path.iterdir(), key=lambda x: (not x.is_dir(), x.name.lower()))

        for entry in entries:
            # Skip hidden files except for specific allowed ones
            if entry.name.startswith('.') and entry.name not in ['.cmux']:
                continue

            item = FilesystemItem(
                name=entry.name,
                path=str(entry.relative_to(get_cmux_dir().parent)),
                type='directory' if entry.is_dir() else 'file',
            )

            if entry.is_file():
                try:
                    stat = entry.stat()
                    item.size = stat.st_size
                    item.modified = str(stat.st_mtime)
                except OSError:
                    pass

            if entry.is_dir() and current_depth < max_depth:
                item.children = build_tree(entry, max_depth, current_depth + 1)

            items.append(item)

    except PermissionError:
        pass

    return items


@router.get("", response_model=FilesystemResponse)
async def get_filesystem(
    path: Optional[str] = Query(None, description="Relative path within .cmux directory")
) -> FilesystemResponse:
    """Get the filesystem tree for the .cmux directory."""
    cmux_dir = get_cmux_dir()

    if not cmux_dir.exists():
        return FilesystemResponse(items=[], path=str(cmux_dir))

    if path:
        target_path = cmux_dir / path
        # Security: ensure we're not escaping the cmux directory
        try:
            target_path.resolve().relative_to(cmux_dir.resolve())
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid path")
    else:
        target_path = cmux_dir

    items = build_tree(target_path)

    return FilesystemResponse(items=items, path=str(target_path))


@router.get("/content", response_model=FileContentResponse)
async def get_file_content(
    path: str = Query(..., description="Relative path to file within .cmux directory")
) -> FileContentResponse:
    """Get the content of a file within .cmux directory."""
    cmux_dir = get_cmux_dir()
    file_path = cmux_dir.parent / path

    # Security: ensure we're not escaping the cmux directory
    try:
        file_path.resolve().relative_to(cmux_dir.resolve())
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid path: must be within .cmux directory")

    if not file_path.exists():
        raise HTTPException(status_code=404, detail="File not found")

    if not file_path.is_file():
        raise HTTPException(status_code=400, detail="Path is not a file")

    # Limit file size to prevent memory issues
    max_size = 1024 * 1024  # 1MB
    if file_path.stat().st_size > max_size:
        raise HTTPException(status_code=413, detail="File too large")

    try:
        content = file_path.read_text(encoding='utf-8', errors='replace')
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error reading file: {str(e)}")

    return FileContentResponse(content=content, path=str(path))
