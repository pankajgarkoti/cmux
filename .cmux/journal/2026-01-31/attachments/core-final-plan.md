# Core Architecture Improvements - Final Consolidated Plan

**Authors:** core-defender & core-critic
**Date:** 2026-02-01
**Status:** CONVERGED - Ready for Implementation
**Debate Rounds:** 2

---

## Executive Summary

After two rounds of debate, we converged on **7 actionable tasks** (down from 9) with a **unified database architecture**. Two proposals were withdrawn as unnecessary complexity.

| Task | Status | Description |
|------|--------|-------------|
| 1 | REVISED | Simplified Complexity Analyzer |
| 2 | SIMPLIFIED | Team Templates (documentation-only) |
| 3 | REVISED | Learning Store with auto-capture |
| 4 | WITHDRAWN | ~~Terminology aliases~~ |
| 5 | WITHDRAWN | ~~Coordinator Service~~ |
| 6 | SCOPED | Archive Search (backend only) |
| 7 | ACCEPTED | Unique Worker IDs |
| 8 | REVISED | Naming Scheme (flat structure) |
| 9 | REVISED | Artifact Indexing (consolidated) |

**Key Architectural Decision:** Single consolidated SQLite database (`.cmux/cmux.db`) instead of multiple separate databases.

---

## Database Schema

### File: `.cmux/cmux.db`

```sql
-- Consolidated CMUX database schema
-- Replaces: conversations.db, learning.db, artifact_index.db

-- Messages (migrated from conversations.db)
CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,
    from_agent TEXT NOT NULL,
    to_agent TEXT NOT NULL,
    type TEXT NOT NULL,
    content TEXT NOT NULL,
    metadata TEXT
);
CREATE INDEX IF NOT EXISTS idx_messages_from_agent ON messages(from_agent);
CREATE INDEX IF NOT EXISTS idx_messages_to_agent ON messages(to_agent);
CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON messages(timestamp);

-- Agent archives (migrated from conversations.db)
CREATE TABLE IF NOT EXISTS agent_archives (
    id TEXT PRIMARY KEY,
    agent_id TEXT NOT NULL,
    agent_name TEXT NOT NULL,
    agent_type TEXT NOT NULL,
    archived_at TEXT NOT NULL,
    terminal_output TEXT
);
CREATE INDEX IF NOT EXISTS idx_archives_agent_id ON agent_archives(agent_id);
CREATE INDEX IF NOT EXISTS idx_archives_archived_at ON agent_archives(archived_at);

-- Learning/delegation records (new)
CREATE TABLE IF NOT EXISTS delegations (
    id TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,
    task_type TEXT NOT NULL,  -- 'bugfix', 'feature', 'refactor', 'general'
    delegation_type TEXT NOT NULL,  -- 'worker', 'session'
    task_summary TEXT,
    outcome TEXT NOT NULL,  -- 'success', 'blocked', 'failed'
    worker_id TEXT,
    duration_seconds INTEGER,
    created_at TEXT DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_delegations_type ON delegations(task_type, delegation_type);
CREATE INDEX IF NOT EXISTS idx_delegations_outcome ON delegations(outcome);

-- Artifact index (new)
CREATE TABLE IF NOT EXISTS artifacts (
    id TEXT PRIMARY KEY,
    path TEXT UNIQUE NOT NULL,
    filename TEXT NOT NULL,
    artifact_type TEXT NOT NULL,  -- 'attachment', 'artifact', 'archive'
    session TEXT,
    agent TEXT,
    created_at TEXT NOT NULL,
    size_bytes INTEGER,
    content_preview TEXT
);
CREATE INDEX IF NOT EXISTS idx_artifacts_session ON artifacts(session);
CREATE INDEX IF NOT EXISTS idx_artifacts_type ON artifacts(artifact_type);
CREATE INDEX IF NOT EXISTS idx_artifacts_created ON artifacts(created_at);

-- Full-text search for artifacts (new)
CREATE VIRTUAL TABLE IF NOT EXISTS artifacts_fts USING fts5(
    id,
    filename,
    content_preview,
    content='artifacts',
    content_rowid='rowid'
);
```

---

## Task 1: Simplified Complexity Analyzer

### Purpose
Provide advisory recommendations for delegation strategy based on historical data and explicit user signals.

### Files to Create

**`src/server/services/complexity_analyzer.py`**

```python
from dataclasses import dataclass
from typing import Optional
import re

@dataclass
class ComplexityScore:
    score: int  # 0-100
    factors: dict[str, int]
    recommendation: str  # 'worker' | 'session' | 'ask_user'
    rationale: str

class ComplexityAnalyzer:
    """Lightweight complexity estimation using history and explicit signals."""

    # Explicit meta-words only - not domain keywords
    EXPLICIT_SIGNALS = {
        'complex': 40, 'major': 30, 'large': 20,
        'simple': -30, 'small': -20, 'typo': -40, 'quick': -25, 'minor': -20
    }

    def __init__(self, learning_store=None):
        self.learning_store = learning_store

    def analyze(
        self,
        task: str,
        file_count: int = 0
    ) -> ComplexityScore:
        factors = {}
        task_lower = task.lower()

        # 1. Explicit signals only (first match wins)
        for signal, weight in self.EXPLICIT_SIGNALS.items():
            if re.search(rf'\b{signal}\b', task_lower):
                factors['explicit_signal'] = weight
                break

        # 2. Historical success rates from learning store
        if self.learning_store:
            task_type = self._classify_task(task_lower)
            recommendations = self.learning_store.get_recommendations(task_type)
            if recommendations and recommendations[0].get('sample_size', 0) >= 5:
                # Boost recommendation based on history
                best = recommendations[0]
                if best['strategy'] == 'session' and best['success_rate'] > 0.7:
                    factors['historical'] = 15
                elif best['strategy'] == 'worker' and best['success_rate'] > 0.7:
                    factors['historical'] = -15

        # 3. File count (if provided)
        if file_count > 0:
            factors['files'] = min(file_count * 8, 40)

        # 4. Task length (conservative)
        word_count = len(task.split())
        if word_count > 30:
            factors['length'] = min((word_count - 30) // 5, 15)

        # Calculate score (start at neutral 50)
        score = 50 + sum(factors.values())
        score = max(0, min(100, score))

        # Determine recommendation
        if score >= 65:
            recommendation = 'session'
        elif score <= 35:
            recommendation = 'worker'
        else:
            recommendation = 'ask_user'  # Uncertain

        return ComplexityScore(
            score=score,
            factors=factors,
            recommendation=recommendation,
            rationale=f"Score {score}/100 based on {list(factors.keys()) or ['baseline']}"
        )

    def _classify_task(self, task: str) -> str:
        """Simple task type classification for learning store lookup."""
        if any(w in task for w in ['fix', 'bug', 'error', 'issue']):
            return 'bugfix'
        if any(w in task for w in ['add', 'implement', 'feature', 'create']):
            return 'feature'
        if any(w in task for w in ['refactor', 'clean', 'reorganize']):
            return 'refactor'
        return 'general'


# Singleton (initialized with learning_store after imports)
complexity_analyzer: Optional[ComplexityAnalyzer] = None

def init_complexity_analyzer(learning_store):
    global complexity_analyzer
    complexity_analyzer = ComplexityAnalyzer(learning_store)
```

### API Endpoint

**Add to `src/server/routes/`:**

```python
@router.post("/analyze-complexity")
async def analyze_complexity(task: str, file_count: int = 0):
    """Get delegation recommendation for a task."""
    if not complexity_analyzer:
        raise HTTPException(503, "Complexity analyzer not initialized")
    result = complexity_analyzer.analyze(task, file_count)
    return {
        "score": result.score,
        "recommendation": result.recommendation,
        "factors": result.factors,
        "rationale": result.rationale
    }
```

### Documentation Update

Add to `docs/SUPERVISOR_ROLE.md`:
```markdown
## Delegation Guidance (Optional)

The system can provide recommendations for delegation strategy:

```bash
curl -X POST "http://localhost:8000/api/analyze-complexity" \
  -d '{"task": "Refactor the entire authentication system", "file_count": 8}'
```

This returns a recommendation ('worker', 'session', or 'ask_user') based on:
- Explicit complexity signals in the task description
- Historical success rates for similar tasks
- Number of files involved

**Note:** This is advisory only. You make the final decision.
```

---

## Task 2: Team Templates (Documentation-Only)

### Purpose
Document common team patterns for reference. Structured YAML templates deferred until 5+ patterns emerge.

### Files to Create

**`docs/templates/teams/README.md`**

```markdown
# Team Templates

This directory documents common team patterns for CMUX sessions.

## Available Patterns

### Solo Worker
- **When to use:** Simple, focused tasks
- **Agents:** 1 worker
- **Example:** "Fix typo in README"

### Debate Pair
- **When to use:** Design decisions with tradeoffs
- **Agents:** defender, critic
- **Workflow:**
  1. Defender proposes solution
  2. Critic provides critique
  3. Iterate until convergence
  4. Joint recommendation
- **Example:** "Design authentication system"

### Full Feature Team
- **When to use:** Medium-to-large features
- **Agents:** lead (supervisor), backend, frontend, tester
- **Workflow:**
  1. Lead coordinates tasks
  2. Backend/frontend work in parallel
  3. Tester validates
- **Example:** "Implement user settings page"

## Template Validation

```python
from pathlib import Path

def validate_template_exists(template_name: str) -> bool:
    """Check if template documentation exists."""
    return Path(f"docs/templates/{template_name}.md").exists()

def list_available_templates() -> list[str]:
    """List all available template names."""
    return [p.stem for p in Path("docs/templates").glob("*.md")]
```

## Future: Structured Templates

When we have 5+ distinct patterns, we'll add structured YAML templates with:
- Role definitions
- Communication graphs
- Workflow specifications
- Artifact naming conventions
```

---

## Task 3: Learning Store with Auto-Capture

### Purpose
Track delegation outcomes to inform future decisions. Outcomes captured automatically from worker messages.

### Files to Create

**`src/server/services/learning_store.py`**

```python
from dataclasses import dataclass
from datetime import datetime
from typing import List, Optional
import uuid

from .database import cmux_db

@dataclass
class DelegationRecord:
    id: str
    timestamp: datetime
    task_type: str
    delegation_type: str
    task_summary: str
    outcome: str
    worker_id: Optional[str] = None
    duration_seconds: Optional[int] = None

class LearningStore:
    """Tracks delegation outcomes for learning."""

    def __init__(self, db=None):
        self.db = db or cmux_db

    def record(
        self,
        task_type: str,
        delegation_type: str,
        outcome: str,
        task_summary: str = "",
        worker_id: str = None,
        duration_seconds: int = None
    ) -> str:
        """Record a delegation outcome."""
        record_id = str(uuid.uuid4())
        with self.db.get_connection() as conn:
            conn.execute("""
                INSERT INTO delegations
                (id, timestamp, task_type, delegation_type, task_summary,
                 outcome, worker_id, duration_seconds)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                record_id,
                datetime.utcnow().isoformat(),
                task_type,
                delegation_type,
                task_summary[:500],  # Truncate
                outcome,
                worker_id,
                duration_seconds
            ))
        return record_id

    def get_recommendations(
        self,
        task_type: str
    ) -> List[dict]:
        """Get ranked delegation strategies based on history."""
        with self.db.get_connection() as conn:
            results = []
            for strategy in ['worker', 'session']:
                row = conn.execute("""
                    SELECT
                        COUNT(CASE WHEN outcome = 'success' THEN 1 END) as successes,
                        COUNT(*) as total
                    FROM delegations
                    WHERE task_type = ? AND delegation_type = ?
                """, (task_type, strategy)).fetchone()

                total = row['total'] if row else 0
                successes = row['successes'] if row else 0

                results.append({
                    'strategy': strategy,
                    'success_rate': successes / total if total > 0 else 0.5,
                    'sample_size': total
                })

            return sorted(results, key=lambda x: x['success_rate'], reverse=True)


learning_store = LearningStore()
```

### Auto-Capture in Router

**Modify `src/orchestrator/router.sh`:**

```bash
# Add after route_message() function

auto_capture_outcome() {
    local from="$1"
    local subject="$2"

    # Only capture from workers (pattern: worker-*)
    local agent="${from##*:}"
    if [[ ! "$agent" =~ ^worker- ]]; then
        return 0
    fi

    local outcome=""
    if [[ "$subject" =~ ^\[DONE\] ]]; then
        outcome="success"
    elif [[ "$subject" =~ ^\[BLOCKED\] ]]; then
        outcome="blocked"
    else
        return 0
    fi

    # Record to learning store via API
    curl -sf -X POST "http://localhost:${CMUX_PORT}/api/learning/record" \
        -H "Content-Type: application/json" \
        -d "{
            \"worker_id\": \"$agent\",
            \"outcome\": \"$outcome\",
            \"task_summary\": $(echo "$subject" | jq -Rs .)
        }" >/dev/null 2>&1 || true
}

# Call in route_message after successful delivery
auto_capture_outcome "$from" "$subject"
```

### API Endpoint

```python
@router.post("/learning/record")
async def record_outcome(
    worker_id: str,
    outcome: str,
    task_summary: str = "",
    task_type: str = "general",
    delegation_type: str = "worker"
):
    """Record a delegation outcome."""
    record_id = learning_store.record(
        task_type=task_type,
        delegation_type=delegation_type,
        outcome=outcome,
        task_summary=task_summary,
        worker_id=worker_id
    )
    return {"success": True, "record_id": record_id}

@router.get("/learning/recommendations/{task_type}")
async def get_recommendations(task_type: str):
    """Get delegation recommendations for a task type."""
    return learning_store.get_recommendations(task_type)
```

---

## Task 6: Archive Search (Backend Only)

### Purpose
Add search and filter capabilities to archived agents.

### Files to Modify

**`src/server/services/conversation_store.py` (or new database.py):**

```python
def search_archives(
    self,
    query: str = None,
    agent_type: str = None,
    date_from: datetime = None,
    date_to: datetime = None,
    limit: int = 50
) -> List[ArchivedAgentSummary]:
    """Search archived agents with filters."""
    conditions = []
    params = []

    if query:
        conditions.append("(agent_name LIKE ? OR terminal_output LIKE ?)")
        params.extend([f"%{query}%", f"%{query}%"])
    if agent_type:
        conditions.append("agent_type = ?")
        params.append(agent_type)
    if date_from:
        conditions.append("archived_at >= ?")
        params.append(date_from.isoformat())
    if date_to:
        conditions.append("archived_at <= ?")
        params.append(date_to.isoformat())

    where_clause = " AND ".join(conditions) if conditions else "1=1"

    with self.get_connection() as conn:
        cursor = conn.execute(f"""
            SELECT id, agent_id, agent_name, agent_type, archived_at
            FROM agent_archives
            WHERE {where_clause}
            ORDER BY archived_at DESC
            LIMIT ?
        """, params + [limit])

        return [
            ArchivedAgentSummary(
                id=row["id"],
                agent_id=row["agent_id"],
                agent_name=row["agent_name"],
                agent_type=row["agent_type"],
                archived_at=datetime.fromisoformat(row["archived_at"])
            )
            for row in cursor.fetchall()
        ]
```

### API Endpoint

```python
@router.get("/agents/archived/search")
async def search_archived_agents(
    q: str = None,
    agent_type: str = None,
    date_from: str = None,
    date_to: str = None,
    limit: int = 50
):
    """Search archived agents."""
    return cmux_db.search_archives(
        query=q,
        agent_type=agent_type,
        date_from=datetime.fromisoformat(date_from) if date_from else None,
        date_to=datetime.fromisoformat(date_to) if date_to else None,
        limit=limit
    )
```

---

## Task 7: Unique Worker IDs

### Purpose
Prevent name collisions when spawning workers across sessions.

### Files to Modify

**`tools/workers` (spawn function):**

```bash
cmd_spawn() {
    local base_name="${1:-}"
    local task="${2:-}"

    [[ -z "$base_name" ]] && die "usage: workers spawn <name> <task>"
    [[ -z "$task" ]] && die "usage: workers spawn <name> <task>"

    # Sanitize base name
    base_name=$(echo "$base_name" | tr ' ' '-' | tr -cd 'a-zA-Z0-9-_')

    # Generate unique suffix (4 hex chars)
    local suffix=$(head -c 2 /dev/urandom | xxd -p)
    local name="${base_name}-${suffix}"

    # Ensure global uniqueness
    while worker_exists_anywhere "$name"; do
        suffix=$(head -c 2 /dev/urandom | xxd -p)
        name="${base_name}-${suffix}"
    done

    info "Creating worker: $name"
    # ... rest of spawn logic using $name
}

worker_exists_anywhere() {
    local name="$1"
    for sess in $(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -E '^cmux(-|$)'); do
        if tmux list-windows -t "$sess" -F '#{window_name}' 2>/dev/null | grep -qx "$name"; then
            return 0
        fi
    done
    return 1
}
```

**`src/server/services/agent_manager.py`:**

```python
import secrets

async def create_worker(self, base_name: str, session: Optional[str] = None) -> Agent:
    """Create a new worker agent with unique ID."""
    session = session or settings.main_session

    # Sanitize and add unique suffix
    safe_name = re.sub(r'[^\w\-]', '-', base_name)
    suffix = secrets.token_hex(2)  # 4 hex chars
    unique_name = f"{safe_name}-{suffix}"

    # Ensure global uniqueness
    while await self._name_exists_globally(unique_name):
        suffix = secrets.token_hex(2)
        unique_name = f"{safe_name}-{suffix}"

    await tmux_service.create_window(unique_name, session)
    # ... rest of creation

async def _name_exists_globally(self, name: str) -> bool:
    """Check if worker name exists in any session."""
    for sess in await tmux_service.list_sessions():
        windows = await tmux_service.list_windows(sess)
        if name in windows:
            return True
    return False
```

---

## Task 8: Naming Scheme (Flat Structure)

### Purpose
Standardize artifact naming with session prefixes.

### Naming Convention

```
Files:     {session}--{subject}-{timestamp}-{unique}.{ext}
Examples:
  cmux--task-summary-1706947500-a3f2.md
  cmux-auth--plan-initial-1706947600-b4c1.md
```

### Files to Modify

**`src/server/services/mailbox.py`:**

```python
import secrets
import time
import re

def _get_body_path(self, from_agent: str, subject: str) -> Path:
    """Generate organized body file path with flat structure."""
    date_str = datetime.now().strftime("%Y-%m-%d")

    # Extract session from agent address
    if ":" in from_agent:
        session = from_agent.split(":")[0]
    else:
        session = "cmux"

    attachments_dir = settings.cmux_dir / "journal" / date_str / "attachments"
    attachments_dir.mkdir(parents=True, exist_ok=True)

    # Clean subject for filename
    clean_subject = re.sub(r'[^\w\-]', '-', subject[:30]).lower().strip('-')
    timestamp = int(time.time())
    unique = secrets.token_hex(2)

    return attachments_dir / f"{session}--{clean_subject}-{timestamp}-{unique}.md"
```

### Migration Policy

- **Existing files:** Left in place, not migrated
- **New files:** Use new naming scheme
- **No breaking changes:** Old paths continue to work

---

## Task 9: Artifact Indexing

### Purpose
Make artifacts searchable with full-text search.

### Files to Create

**`src/server/services/artifact_index.py`:**

```python
import uuid
import asyncio
from pathlib import Path
from datetime import datetime
from typing import List, Optional
from collections import deque

from .database import cmux_db

class ArtifactIndex:
    """Index artifacts for search."""

    def __init__(self, db=None):
        self.db = db or cmux_db
        self._index_queue = deque()
        self._running = False

    async def index_file(
        self,
        path: Path,
        session: str = None,
        agent: str = None
    ) -> str:
        """Add or update a file in the index."""
        artifact_id = str(uuid.uuid4())

        # Determine type from path
        path_str = str(path)
        if 'attachments' in path_str:
            artifact_type = 'attachment'
        elif 'artifacts' in path_str:
            artifact_type = 'artifact'
        else:
            artifact_type = 'other'

        # Get preview efficiently (limited read)
        preview = None
        if path.suffix in ['.md', '.txt', '.json', '.yaml', '.yml']:
            try:
                with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                    preview = f.read(500)
            except:
                pass

        with self.db.get_connection() as conn:
            conn.execute("""
                INSERT OR REPLACE INTO artifacts
                (id, path, filename, artifact_type, session, agent,
                 created_at, size_bytes, content_preview)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                artifact_id,
                str(path),
                path.name,
                artifact_type,
                session,
                agent,
                datetime.utcnow().isoformat(),
                path.stat().st_size if path.exists() else 0,
                preview
            ))

            # Update FTS
            conn.execute("""
                INSERT OR REPLACE INTO artifacts_fts (id, filename, content_preview)
                VALUES (?, ?, ?)
            """, (artifact_id, path.name, preview or ""))

        return artifact_id

    def queue_for_indexing(self, path: Path, session: str = None, agent: str = None):
        """Queue file for background indexing."""
        self._index_queue.append((path, session, agent))

    async def process_queue(self):
        """Background task to process index queue."""
        while True:
            if self._index_queue:
                path, session, agent = self._index_queue.popleft()
                try:
                    await self.index_file(path, session, agent)
                except Exception as e:
                    pass  # Log and continue
            await asyncio.sleep(0.1)

    async def search(
        self,
        query: str,
        session: str = None,
        limit: int = 50
    ) -> List[dict]:
        """Full-text search across artifacts."""
        with self.db.get_connection() as conn:
            if session:
                cursor = conn.execute("""
                    SELECT a.* FROM artifacts a
                    JOIN artifacts_fts f ON a.id = f.id
                    WHERE artifacts_fts MATCH ? AND a.session = ?
                    ORDER BY a.created_at DESC
                    LIMIT ?
                """, (query, session, limit))
            else:
                cursor = conn.execute("""
                    SELECT a.* FROM artifacts a
                    JOIN artifacts_fts f ON a.id = f.id
                    WHERE artifacts_fts MATCH ?
                    ORDER BY a.created_at DESC
                    LIMIT ?
                """, (query, limit))

            return [dict(row) for row in cursor.fetchall()]

    async def reindex_all(self):
        """Rebuild index from filesystem."""
        journal_path = Path('.cmux/journal')
        if not journal_path.exists():
            return

        for date_dir in journal_path.iterdir():
            if not date_dir.is_dir():
                continue
            for subdir in ['attachments', 'artifacts']:
                subpath = date_dir / subdir
                if subpath.exists():
                    for file in subpath.rglob('*'):
                        if file.is_file():
                            await self.index_file(file)


artifact_index = ArtifactIndex()
```

### API Endpoints

```python
@router.get("/artifacts/search")
async def search_artifacts(
    q: str,
    session: str = None,
    limit: int = 50
):
    """Search indexed artifacts."""
    return await artifact_index.search(q, session, limit)

@router.post("/artifacts/reindex")
async def reindex_artifacts():
    """Rebuild artifact index from filesystem."""
    await artifact_index.reindex_all()
    return {"success": True, "message": "Reindexing complete"}
```

---

## Database Consolidation & Migration

### Files to Create

**`src/server/services/database.py`:**

```python
import sqlite3
from pathlib import Path
from contextlib import contextmanager

from ..config import settings

class CMUXDatabase:
    """Single consolidated SQLite database for all CMUX data."""

    def __init__(self, db_path: Path = None):
        self.db_path = db_path or (settings.cmux_dir / "cmux.db")
        self._ensure_schema()
        self._migrate_if_needed()

    def _ensure_schema(self):
        """Create all tables if they don't exist."""
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        with self.get_connection() as conn:
            conn.executescript("""
                -- [Full schema from above]
            """)

    def _migrate_if_needed(self):
        """Migrate from old conversations.db if exists."""
        old_db = settings.cmux_dir / "conversations.db"
        migrated_marker = settings.cmux_dir / ".migrated"

        if old_db.exists() and not migrated_marker.exists():
            self._migrate_from_conversations_db(old_db)
            migrated_marker.touch()

    def _migrate_from_conversations_db(self, old_db: Path):
        """Copy data from old database."""
        old_conn = sqlite3.connect(str(old_db))
        old_conn.row_factory = sqlite3.Row

        with self.get_connection() as new_conn:
            # Migrate messages
            for row in old_conn.execute("SELECT * FROM messages"):
                new_conn.execute("""
                    INSERT OR IGNORE INTO messages VALUES (?,?,?,?,?,?,?)
                """, tuple(row))

            # Migrate agent_archives
            for row in old_conn.execute("SELECT * FROM agent_archives"):
                new_conn.execute("""
                    INSERT OR IGNORE INTO agent_archives VALUES (?,?,?,?,?,?)
                """, tuple(row))

        old_conn.close()

    @contextmanager
    def get_connection(self):
        """Get a database connection with proper cleanup."""
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        try:
            yield conn
            conn.commit()
        finally:
            conn.close()


cmux_db = CMUXDatabase()
```

---

## Feature Flags

**Add to `src/server/config.py`:**

```python
class Settings(BaseSettings):
    # ... existing settings ...

    # Feature flags for new functionality
    enable_complexity_analyzer: bool = True
    enable_learning_store: bool = True
    enable_artifact_index: bool = True
    learning_min_sample_size: int = 5
```

---

## Implementation Order

### Phase 1: Foundation (Week 1)
1. **Database consolidation** - Create CMUXDatabase, migrate from conversations.db
2. **Unique Worker IDs** - Update tools/workers and agent_manager.py
3. **Naming Scheme** - Update mailbox.py with flat structure

### Phase 2: Memory (Week 2)
4. **Artifact Indexing** - Create artifact_index.py, add API endpoints
5. **Archive Search** - Add search_archives() to database, add API
6. **Learning Store** - Create learning_store.py, add auto-capture to router

### Phase 3: Intelligence (Week 3)
7. **Complexity Analyzer** - Create complexity_analyzer.py, add API
8. **Team Templates** - Document patterns in docs/templates/teams/

---

## Testing Checklist

### Phase 1 Tests
- [ ] Database migration preserves all messages
- [ ] Database migration preserves all archives
- [ ] Unique worker IDs never collide (100 spawns test)
- [ ] New files use flat naming scheme
- [ ] Old files remain accessible

### Phase 2 Tests
- [ ] Artifact search returns relevant results
- [ ] Archive search filters work correctly
- [ ] Auto-capture records [DONE] from workers
- [ ] Auto-capture ignores supervisor messages

### Phase 3 Tests
- [ ] Complexity analyzer returns sensible recommendations
- [ ] Historical data influences recommendations
- [ ] Template validation catches missing files

---

## Summary

This plan consolidates 7 actionable improvements with:
- **Single database architecture** - `.cmux/cmux.db` with all tables
- **Automatic outcome tracking** - Workers' [DONE]/[BLOCKED] captured automatically
- **Full-text search** - Artifacts and archives searchable
- **Unique identifiers** - No more worker name collisions
- **Consistent naming** - Flat structure with session prefixes

Two proposals (terminology aliases, coordinator service) were withdrawn as unnecessary complexity.

---

*Final plan produced by core-defender & core-critic after 2 rounds of debate*
*Status: CONVERGED - Ready for Implementation*
