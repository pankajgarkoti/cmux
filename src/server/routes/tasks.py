"""Tasks API routes — read/update tasks from .cmux/tasks.db (shared with tools/tasks CLI)."""

import json
import random
import sqlite3
import string
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel

from ..config import settings

router = APIRouter()

DB_PATH = settings.cmux_dir / "tasks.db"

VALID_STATUSES = {"backlog", "pending", "assigned", "in-progress", "review", "done", "blocked", "failed"}
VALID_PRIORITIES = {"critical", "high", "medium", "low"}
VALID_SOURCES = {"user", "backlog", "self-generated", "worker-escalation", "system"}


# --- Models ---


class TaskResponse(BaseModel):
    id: str
    title: str
    description: str
    project: str
    assigned_to: str
    status: str
    priority: str
    source: str
    linked_workers: str
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


class TaskCreate(BaseModel):
    title: str
    description: Optional[str] = ""
    project: Optional[str] = ""
    priority: Optional[str] = "medium"
    source: Optional[str] = "system"
    parent_id: Optional[str] = ""
    assigned_to: Optional[str] = ""
    resources: Optional[list[str]] = []


class TaskUpdate(BaseModel):
    status: Optional[str] = None
    assigned_to: Optional[str] = None
    priority: Optional[str] = None
    source: Optional[str] = None


class TaskStatsResponse(BaseModel):
    total: int
    by_status: dict[str, int]
    by_priority: dict[str, int]
    by_assignee: dict[str, int]
    needs_attention: list[TaskResponse]


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


def _gen_id() -> str:
    """Generate a task ID matching the CLI format: t_ + 8 alphanumeric chars."""
    chars = string.ascii_lowercase + string.digits
    return "t_" + "".join(random.choice(chars) for _ in range(8))


def _row_to_task(row: sqlite3.Row) -> TaskResponse:
    """Convert a database row to a TaskResponse."""
    resources_raw = row["resources"]
    try:
        resources = json.loads(resources_raw) if resources_raw else []
    except (json.JSONDecodeError, TypeError):
        resources = []

    # Safely read columns that may not exist in older schemas
    keys = row.keys()

    return TaskResponse(
        id=row["id"],
        title=row["title"],
        description=row["description"] or "",
        project=row["project"] or "",
        assigned_to=row["assigned_to"] or "",
        status=row["status"] or "pending",
        priority=(row["priority"] or "medium") if "priority" in keys else "medium",
        source=(row["source"] or "system") if "source" in keys else "system",
        linked_workers=(row["linked_workers"] or "") if "linked_workers" in keys else "",
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


@router.get("/stats", response_model=TaskStatsResponse)
async def get_task_stats():
    """Dashboard stats: counts by status, priority, assignee, plus attention items."""
    with _get_connection() as conn:
        total = conn.execute("SELECT COUNT(*) FROM tasks").fetchone()[0]

        # By status
        status_rows = conn.execute(
            "SELECT status, COUNT(*) as cnt FROM tasks GROUP BY status"
        ).fetchall()
        by_status = {row["status"]: row["cnt"] for row in status_rows}

        # By priority (active tasks only)
        priority_rows = conn.execute(
            "SELECT COALESCE(NULLIF(priority,''), 'medium') as pri, COUNT(*) as cnt "
            "FROM tasks WHERE status NOT IN ('done', 'failed') GROUP BY pri"
        ).fetchall()
        by_priority = {row["pri"]: row["cnt"] for row in priority_rows}

        # By assignee (active tasks only)
        assignee_rows = conn.execute(
            "SELECT CASE WHEN assigned_to = '' THEN '(unassigned)' ELSE assigned_to END as agent, "
            "COUNT(*) as cnt FROM tasks WHERE status NOT IN ('done', 'failed') GROUP BY agent"
        ).fetchall()
        by_assignee = {row["agent"]: row["cnt"] for row in assignee_rows}

        # Needs attention: blocked, failed, or critical+pending
        attention_rows = conn.execute(
            "SELECT * FROM tasks WHERE status IN ('blocked', 'failed') "
            "OR (priority = 'critical' AND status NOT IN ('done', 'failed')) "
            "ORDER BY CASE status WHEN 'failed' THEN 1 WHEN 'blocked' THEN 2 ELSE 3 END"
        ).fetchall()
        needs_attention = [_row_to_task(row) for row in attention_rows]

        return TaskStatsResponse(
            total=total,
            by_status=by_status,
            by_priority=by_priority,
            by_assignee=by_assignee,
            needs_attention=needs_attention,
        )


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


@router.post("", response_model=TaskResponse, status_code=201)
async def create_task(body: TaskCreate):
    """Create a new task."""
    if body.priority and body.priority not in VALID_PRIORITIES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid priority: {body.priority}. Valid: {', '.join(sorted(VALID_PRIORITIES))}",
        )
    if body.source and body.source not in VALID_SOURCES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid source: {body.source}. Valid: {', '.join(sorted(VALID_SOURCES))}",
        )

    with _get_connection() as conn:
        # Validate parent exists if given
        if body.parent_id:
            parent_cursor = conn.execute("SELECT id FROM tasks WHERE id = ?", (body.parent_id,))
            if not parent_cursor.fetchone():
                raise HTTPException(status_code=404, detail=f"Parent task not found: {body.parent_id}")

        task_id = _gen_id()
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        status = "assigned" if body.assigned_to else "pending"
        resources_json = json.dumps(body.resources or [])

        conn.execute(
            """INSERT INTO tasks (id, title, description, project, assigned_to, status,
               priority, source, parent_id, resources, created_at, updated_at)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                task_id,
                body.title,
                body.description or "",
                body.project or "",
                body.assigned_to or "",
                status,
                body.priority or "medium",
                body.source or "system",
                body.parent_id or "",
                resources_json,
                now,
                now,
            ),
        )

        # Fetch the created task
        cursor = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,))
        row = cursor.fetchone()
        task = _row_to_task(row)
        task.children = []
        return task


@router.patch("/{task_id}", response_model=TaskResponse)
async def update_task(task_id: str, update: TaskUpdate):
    """Update a task's status, assigned_to, priority, and/or source."""
    if update.status is not None and update.status not in VALID_STATUSES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid status: {update.status}. Valid: {', '.join(sorted(VALID_STATUSES))}",
        )
    if update.priority is not None and update.priority not in VALID_PRIORITIES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid priority: {update.priority}. Valid: {', '.join(sorted(VALID_PRIORITIES))}",
        )
    if update.source is not None and update.source not in VALID_SOURCES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid source: {update.source}. Valid: {', '.join(sorted(VALID_SOURCES))}",
        )

    with _get_connection() as conn:
        # Verify task exists
        cursor = conn.execute("SELECT * FROM tasks WHERE id = ?", (task_id,))
        row = cursor.fetchone()
        if not row:
            raise HTTPException(status_code=404, detail=f"Task not found: {task_id}")

        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        updates: list[str] = ["updated_at = ?"]
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

        if update.priority is not None:
            updates.append("priority = ?")
            params.append(update.priority)

        if update.source is not None:
            updates.append("source = ?")
            params.append(update.source)

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


@router.delete("/{task_id}")
async def delete_task(task_id: str):
    """Delete a task and all its children recursively."""
    with _get_connection() as conn:
        cursor = conn.execute("SELECT id FROM tasks WHERE id = ?", (task_id,))
        if not cursor.fetchone():
            raise HTTPException(status_code=404, detail=f"Task not found: {task_id}")

        def _delete_recursive(conn: sqlite3.Connection, parent_id: str) -> int:
            children = conn.execute(
                "SELECT id FROM tasks WHERE parent_id = ?", (parent_id,)
            ).fetchall()
            count = 0
            for child in children:
                count += _delete_recursive(conn, child["id"])
            conn.execute("DELETE FROM tasks WHERE id = ?", (parent_id,))
            return count + 1

        deleted = _delete_recursive(conn, task_id)
        return {"deleted": deleted, "task_id": task_id}
