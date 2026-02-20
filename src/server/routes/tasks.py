"""Tasks API routes — read/update tasks from .cmux/tasks.db (shared with tools/tasks CLI)."""

import json
import sqlite3
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from ..config import settings

router = APIRouter()

DB_PATH = settings.cmux_dir / "tasks.db"


# --- Models ---


class TaskResponse(BaseModel):
    id: str
    title: str
    description: str
    project: str
    assigned_to: str
    status: str
    parent_id: str
    resources: list[str]
    created_at: str
    updated_at: str
    completed_at: str
    children: Optional[list["TaskResponse"]] = None


class TaskListResponse(BaseModel):
    tasks: list[TaskResponse]
    total: int


class TaskTreeResponse(BaseModel):
    tasks: list[TaskResponse]
    total: int


class TaskUpdate(BaseModel):
    status: Optional[str] = None
    assigned_to: Optional[str] = None


# --- Database ---


@contextmanager
def _get_connection():
    """Get a database connection with WAL mode and proper cleanup."""
    if not DB_PATH.exists():
        raise HTTPException(status_code=404, detail="tasks.db not found — no tasks created yet")
    conn = sqlite3.connect(str(DB_PATH))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA busy_timeout=5000")
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def _row_to_task(row: sqlite3.Row) -> TaskResponse:
    """Convert a database row to a TaskResponse."""
    resources_raw = row["resources"]
    try:
        resources = json.loads(resources_raw) if resources_raw else []
    except (json.JSONDecodeError, TypeError):
        resources = []

    return TaskResponse(
        id=row["id"],
        title=row["title"],
        description=row["description"] or "",
        project=row["project"] or "",
        assigned_to=row["assigned_to"] or "",
        status=row["status"] or "pending",
        parent_id=row["parent_id"] or "",
        resources=resources,
        created_at=row["created_at"] or "",
        updated_at=row["updated_at"] or "",
        completed_at=row["completed_at"] or "",
    )


# --- Routes ---


@router.get("", response_model=TaskListResponse)
async def list_tasks(
    project: Optional[str] = Query(None, description="Filter by project ID"),
    status: Optional[str] = Query(None, description="Filter by status"),
    assigned_to: Optional[str] = Query(None, description="Filter by assignee"),
    parent_id: Optional[str] = Query(None, description="Filter by parent task ID"),
    include_done: bool = Query(False, description="Include done tasks"),
):
    """List tasks with optional filters."""
    with _get_connection() as conn:
        conditions: list[str] = []
        params: list = []

        if not include_done and status != "done":
            conditions.append("status != 'done'")

        if project is not None:
            conditions.append("project = ?")
            params.append(project)

        if status is not None:
            conditions.append("status = ?")
            params.append(status)

        if assigned_to is not None:
            conditions.append("assigned_to = ?")
            params.append(assigned_to)

        if parent_id is not None:
            conditions.append("parent_id = ?")
            params.append(parent_id)

        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""

        cursor = conn.execute(
            f"SELECT * FROM tasks {where} ORDER BY created_at",
            params,
        )
        rows = cursor.fetchall()
        tasks = [_row_to_task(row) for row in rows]

        return TaskListResponse(tasks=tasks, total=len(tasks))


@router.get("/tree", response_model=TaskTreeResponse)
async def get_task_tree(
    project: Optional[str] = Query(None, description="Filter by project ID"),
    include_done: bool = Query(False, description="Include done tasks"),
):
    """Get hierarchical task tree — top-level tasks with nested children."""
    with _get_connection() as conn:
        conditions: list[str] = []
        params: list = []

        if not include_done:
            conditions.append("status != 'done'")

        if project is not None:
            conditions.append("project = ?")
            params.append(project)

        where = f"WHERE {' AND '.join(conditions)}" if conditions else ""

        cursor = conn.execute(
            f"SELECT * FROM tasks {where} ORDER BY created_at",
            params,
        )
        all_tasks = [_row_to_task(row) for row in cursor.fetchall()]

    # Build tree: index by parent_id
    by_parent: dict[str, list[TaskResponse]] = {}
    task_map: dict[str, TaskResponse] = {}
    for task in all_tasks:
        task_map[task.id] = task
        parent_key = task.parent_id or ""
        if parent_key not in by_parent:
            by_parent[parent_key] = []
        by_parent[parent_key].append(task)

    def _attach_children(task: TaskResponse) -> TaskResponse:
        children = by_parent.get(task.id, [])
        if children:
            task.children = [_attach_children(c) for c in children]
        else:
            task.children = []
        return task

    # Root tasks have empty parent_id
    roots = by_parent.get("", [])
    tree = [_attach_children(t) for t in roots]

    return TaskTreeResponse(tasks=tree, total=len(all_tasks))


@router.get("/{task_id}", response_model=TaskResponse)
async def get_task(task_id: str):
    """Get a single task with its children."""
    with _get_connection() as conn:
        cursor = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,))
        row = cursor.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail=f"Task not found: {task_id}")

        task = _row_to_task(row)

        # Fetch children
        children_cursor = conn.execute(
            "SELECT * FROM tasks WHERE parent_id = ? ORDER BY created_at",
            (task_id,),
        )
        task.children = [_row_to_task(r) for r in children_cursor.fetchall()]

        return task


@router.patch("/{task_id}", response_model=TaskResponse)
async def update_task(task_id: str, update: TaskUpdate):
    """Update a task's status and/or assigned_to."""
    valid_statuses = {"pending", "assigned", "in-progress", "done", "blocked"}

    if update.status is not None and update.status not in valid_statuses:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid status: {update.status}. Valid: {', '.join(sorted(valid_statuses))}",
        )

    with _get_connection() as conn:
        # Verify task exists
        cursor = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,))
        row = cursor.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail=f"Task not found: {task_id}")

        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        updates: list[str] = [f"updated_at = ?"]
        params: list = [now]

        if update.status is not None:
            updates.append("status = ?")
            params.append(update.status)
            if update.status == "done":
                updates.append("completed_at = ?")
                params.append(now)

        if update.assigned_to is not None:
            updates.append("assigned_to = ?")
            params.append(update.assigned_to)
            # Auto-advance from pending to assigned
            current_status = row["status"]
            if current_status == "pending" and update.status is None:
                updates.append("status = ?")
                params.append("assigned")

        params.append(task_id)
        conn.execute(
            f"UPDATE tasks SET {', '.join(updates)} WHERE id = ?",
            params,
        )

        # Fetch updated task
        cursor = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,))
        updated_row = cursor.fetchone()
        task = _row_to_task(updated_row)

        # Fetch children
        children_cursor = conn.execute(
            "SELECT * FROM tasks WHERE parent_id = ? ORDER BY created_at",
            (task_id,),
        )
        task.children = [_row_to_task(r) for r in children_cursor.fetchall()]

        return task
