# Core Architecture Improvements - Implementation Plan

**Author:** core-defender (Advocate)
**Date:** 2026-02-01
**Status:** Initial Draft - Awaiting Critique

---

## Executive Summary

This plan addresses 9 core architecture improvements for CMUX. After thorough codebase exploration, I propose incremental, backwards-compatible changes that enhance the system without breaking existing functionality.

**Philosophy:** Each improvement should be independently valuable, testable, and deployable. The system should continue working if any single feature fails.

---

## Task 1: Supervisor Complexity Judgment

**Goal:** Enable the main supervisor to automatically spawn dedicated sessions for complex tasks.

### Current State

- `session_manager.py:83-150` creates sessions via API
- Supervisor must manually decide when to spawn sessions
- No automated complexity assessment

### Proposed Solution

Add a `ComplexityAnalyzer` service that scores tasks and recommends session spawning.

**Files to create:**
- `src/server/services/complexity_analyzer.py`

```python
from dataclasses import dataclass
from typing import Tuple

@dataclass
class ComplexityScore:
    score: int  # 0-100
    factors: dict[str, int]
    recommendation: str  # 'worker' | 'session' | 'debate'
    rationale: str

class ComplexityAnalyzer:
    """Analyzes task descriptions to recommend delegation strategy."""

    # Keywords that suggest complexity
    COMPLEXITY_SIGNALS = {
        'high': ['refactor', 'architecture', 'security', 'authentication', 'migration'],
        'medium': ['feature', 'api', 'database', 'integration'],
        'low': ['fix', 'typo', 'update', 'readme', 'docs']
    }

    FILE_COUNT_THRESHOLDS = {
        'worker': 3,      # <= 3 files = worker
        'session': 10,    # 4-10 files = session
        # > 10 files = session with sub-teams
    }

    def analyze(self, task: str, file_hints: list[str] = None) -> ComplexityScore:
        factors = {}

        # 1. Keyword analysis
        task_lower = task.lower()
        for level, keywords in self.COMPLEXITY_SIGNALS.items():
            for kw in keywords:
                if kw in task_lower:
                    factors['keyword'] = {'high': 30, 'medium': 20, 'low': 10}[level]
                    break

        # 2. Task length (longer = more complex)
        factors['length'] = min(len(task.split()) // 5, 20)

        # 3. Multi-step indicators
        if any(x in task_lower for x in ['and', 'then', 'also', 'plus']):
            factors['multi_step'] = 15

        # 4. File count if provided
        if file_hints:
            factors['file_count'] = min(len(file_hints) * 5, 30)

        score = sum(factors.values())

        # Determine recommendation
        if score >= 50:
            recommendation = 'session'
        elif score >= 30:
            recommendation = 'debate' if 'design' in task_lower else 'worker'
        else:
            recommendation = 'worker'

        return ComplexityScore(
            score=score,
            factors=factors,
            recommendation=recommendation,
            rationale=f"Score {score}/100 based on {list(factors.keys())}"
        )

complexity_analyzer = ComplexityAnalyzer()
```

**Files to modify:**
- `docs/SUPERVISOR_ROLE.md`: Add section on when to use complexity analyzer
- Add optional API endpoint `POST /api/analyze-complexity` for testing

### Integration

The supervisor reads this as a guide but makes the final decision. This preserves human-in-the-loop while providing data-driven recommendations.

---

## Task 2: Templates for Team Architectures

**Goal:** Provide pre-built templates for common team configurations.

### Current State

- Only 2 templates exist: `FEATURE_SUPERVISOR.md`, `BUGFIX_SUPERVISOR.md`
- Templates are documentation-only, not structured data
- No team hierarchy definition

### Proposed Solution

Create structured team templates in `docs/templates/teams/`.

**Files to create:**
- `docs/templates/teams/SOLO_WORKER.yaml`
- `docs/templates/teams/REVIEWER_PAIR.yaml`
- `docs/templates/teams/DEBATE_PAIR.yaml`
- `docs/templates/teams/FULL_FEATURE.yaml`

```yaml
# docs/templates/teams/DEBATE_PAIR.yaml
name: Debate Pair
description: Two agents argue opposing positions to refine a design
when_to_use:
  - Design decisions with tradeoffs
  - Architecture choices
  - Evaluating competing approaches

roles:
  - name: defender
    type: worker
    role_doc: docs/WORKER_ROLE.md
    purpose: Advocates for the proposed solution
    communicates_with: [critic]

  - name: critic
    type: worker
    role_doc: docs/WORKER_ROLE.md
    purpose: Critiques and finds flaws in the proposal
    communicates_with: [defender]

workflow:
  1: defender creates initial proposal
  2: critic provides critique
  3: defender rebuts or revises
  4: repeat 2-3 until convergence
  5: both produce final joint recommendation

artifacts:
  - "{name}-proposal-v{n}.md"
  - "{name}-critique-v{n}.md"
  - "{name}-final.md"
```

```yaml
# docs/templates/teams/FULL_FEATURE.yaml
name: Full Feature Team
description: Complete team for medium-to-large feature development
when_to_use:
  - New features requiring frontend + backend
  - Changes touching 5+ files
  - Features needing dedicated testing

roles:
  - name: lead
    type: supervisor
    role_doc: docs/templates/FEATURE_SUPERVISOR.md
    purpose: Coordinates the team and reviews outputs

  - name: backend
    type: worker
    purpose: Implements backend API and database changes

  - name: frontend
    type: worker
    purpose: Implements UI components and state

  - name: tester
    type: worker
    purpose: Writes and runs tests

communication:
  backend:
    reports_to: lead
    coordinates_with: [frontend]
  frontend:
    reports_to: lead
    coordinates_with: [backend]
  tester:
    reports_to: lead
    tests: [backend, frontend]
```

**Files to modify:**
- `src/server/models/session.py`: Add `team_template` field
- `src/server/services/session_manager.py`: Load team template, spawn workers accordingly

```python
# Addition to session_manager.py
async def create_team_from_template(
    self,
    template_name: str,
    task_description: str,
    name_prefix: str
) -> Session:
    """Create a session with pre-configured team based on template."""
    template = load_team_template(template_name)
    session = await self.create_session(name_prefix, task_description)

    for role in template.roles:
        if role.type == 'worker':
            worker_name = f"{name_prefix}-{role.name}"
            await self._spawn_worker(session.id, worker_name, role)

    return session
```

---

## Task 3: Self-Learning Patterns for Supervisors

**Goal:** Track what delegation strategies work and fail, informing future decisions.

### Current State

- Journal captures outcomes but no structured learning
- No queryable history of what worked
- Each new supervisor starts from scratch

### Proposed Solution

Create a `LearningStore` that records delegation outcomes.

**Files to create:**
- `src/server/services/learning_store.py`

```python
from dataclasses import dataclass
from datetime import datetime
from typing import Literal
import sqlite3
from pathlib import Path

@dataclass
class DelegationRecord:
    id: str
    timestamp: datetime
    task_type: str  # 'bugfix', 'feature', 'refactor', etc.
    delegation_type: str  # 'worker', 'session', 'debate'
    team_template: str | None
    task_summary: str
    outcome: Literal['success', 'partial', 'failed', 'abandoned']
    duration_minutes: int
    worker_count: int
    notes: str

class LearningStore:
    """SQLite store for delegation outcomes."""

    def __init__(self, db_path: Path = Path('.cmux/learning.db')):
        self.db_path = db_path
        self._ensure_db()

    def _ensure_db(self):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS delegations (
                    id TEXT PRIMARY KEY,
                    timestamp TEXT,
                    task_type TEXT,
                    delegation_type TEXT,
                    team_template TEXT,
                    task_summary TEXT,
                    outcome TEXT,
                    duration_minutes INTEGER,
                    worker_count INTEGER,
                    notes TEXT
                )
            """)
            conn.execute("""
                CREATE INDEX IF NOT EXISTS idx_task_type ON delegations(task_type)
            """)

    def record(self, record: DelegationRecord):
        """Store a delegation outcome."""
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT INTO delegations VALUES (?,?,?,?,?,?,?,?,?,?)
            """, (record.id, record.timestamp.isoformat(),
                  record.task_type, record.delegation_type,
                  record.team_template, record.task_summary,
                  record.outcome, record.duration_minutes,
                  record.worker_count, record.notes))

    def get_success_rate(self, task_type: str, delegation_type: str) -> float:
        """Get historical success rate for a delegation strategy."""
        with sqlite3.connect(self.db_path) as conn:
            result = conn.execute("""
                SELECT
                    COUNT(CASE WHEN outcome = 'success' THEN 1 END) as successes,
                    COUNT(*) as total
                FROM delegations
                WHERE task_type = ? AND delegation_type = ?
            """, (task_type, delegation_type)).fetchone()

            if result[1] == 0:
                return 0.5  # No data, assume 50%
            return result[0] / result[1]

    def get_recommendations(self, task_type: str) -> list[dict]:
        """Get ranked delegation strategies based on history."""
        strategies = ['worker', 'session', 'debate']
        results = []

        for strat in strategies:
            rate = self.get_success_rate(task_type, strat)
            results.append({
                'strategy': strat,
                'success_rate': rate,
                'sample_size': self._get_sample_size(task_type, strat)
            })

        return sorted(results, key=lambda x: x['success_rate'], reverse=True)

learning_store = LearningStore()
```

**Files to modify:**
- `docs/SUPERVISOR_ROLE.md`: Add instructions on recording outcomes
- Create API endpoint `POST /api/learning/record` and `GET /api/learning/recommendations`

---

## Task 4: Better Terminology

**Goal:** Clarify naming without breaking backwards compatibility.

### Current Concerns

- "Supervisor" implies employment hierarchy (potentially off-putting)
- "Worker" has similar connotations
- Terms don't clearly convey the technical purpose

### Proposed Solution

**Introduce aliases while maintaining backwards compatibility:**

| Current | Alias (Optional) | Purpose |
|---------|------------------|---------|
| supervisor | coordinator / orchestrator | Delegates tasks, doesn't execute |
| worker | executor / specialist | Performs specific tasks |
| session | team / workspace | Isolated execution environment |

**Files to modify:**
- `src/server/models/agent.py`: Add `role_display_name` field

```python
class AgentType(str, Enum):
    SUPERVISOR = "supervisor"
    WORKER = "worker"

    @property
    def display_name(self) -> str:
        return {
            "supervisor": "Coordinator",
            "worker": "Specialist"
        }.get(self.value, self.value.title())
```

- `src/frontend/src/types/agent.ts`: Add display name handling
- Update frontend components to show display names

**Backwards Compatibility:**
- Keep all existing identifiers (`supervisor`, `worker`)
- Only change display labels in UI
- Documentation can introduce new terms alongside old

---

## Task 5: Inter-Supervisor Communication

**Goal:** Enable supervisors in different sessions to coordinate.

### Current State

- Mailbox supports `session:agent` addressing
- Router can route between sessions
- But no protocol for supervisor-to-supervisor coordination

### Proposed Solution

Define a coordination protocol and add API support.

**Protocol Design:**

```
# Supervisor coordination message format
[timestamp] cmux-auth:supervisor-auth -> cmux:supervisor: [COORD] type: message
```

Coordination types:
- `[COORD] STATUS: <update>` - Progress report
- `[COORD] BLOCK: <issue>` - Blocked, need help
- `[COORD] HANDOFF: <context>` - Transferring responsibility
- `[COORD] COMPLETE: <summary>` - Session work done
- `[COORD] REQUEST: <what-needed>` - Asking for resources/information

**Files to create:**
- `src/server/services/coordinator.py`

```python
from enum import Enum
from dataclasses import dataclass

class CoordMessageType(str, Enum):
    STATUS = "STATUS"
    BLOCK = "BLOCK"
    HANDOFF = "HANDOFF"
    COMPLETE = "COMPLETE"
    REQUEST = "REQUEST"

@dataclass
class CoordinationMessage:
    from_session: str
    from_supervisor: str
    to_session: str
    to_supervisor: str
    type: CoordMessageType
    content: str
    context_path: str | None = None  # Optional path to detailed context

class CoordinatorService:
    async def send_coordination(self, msg: CoordinationMessage):
        """Send coordination message between supervisors."""
        subject = f"[COORD] {msg.type.value}: {msg.content[:50]}"
        from_addr = f"{msg.from_session}:{msg.from_supervisor}"
        to_addr = f"{msg.to_session}:{msg.to_supervisor}"

        await mailbox_service.send_mailbox_message(
            from_agent=from_addr,
            to_agent=to_addr,
            subject=subject,
            body=msg.content if len(msg.content) > 50 else ""
        )

    async def get_active_sessions_supervisors(self) -> list[dict]:
        """List all supervisors across sessions for coordination."""
        sessions = await session_manager.list_sessions()
        return [{
            'session_id': s.id,
            'supervisor': s.supervisor_agent,
            'status': s.status,
            'task': s.task_description
        } for s in sessions]

coordinator_service = CoordinatorService()
```

**Files to modify:**
- `tools/mailbox`: Add `coord` command for sending coordination messages
- `src/orchestrator/router.sh`: Handle `[COORD]` prefix for priority routing

---

## Task 6: Archived Agent Storage and Display

**Goal:** Improve archived agent UX in frontend.

### Current State

- `conversation_store.py` has archive support (lines 151-228)
- `agents.py` has archive endpoints (lines 108-159)
- Frontend has `archivedAgents` in store but limited UI

### Proposed Improvements

**Backend:**
- Add search/filter to archived agents
- Add tagging for archives
- Add archive compression for old entries

**Files to modify:**
- `src/server/services/conversation_store.py`:

```python
# Add to ConversationStore class
def search_archives(
    self,
    query: str = None,
    agent_type: str = None,
    date_from: datetime = None,
    date_to: datetime = None
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

    with self._get_connection() as conn:
        cursor = conn.execute(f"""
            SELECT id, agent_id, agent_name, agent_type, archived_at
            FROM agent_archives
            WHERE {where_clause}
            ORDER BY archived_at DESC
        """, params)
        return [ArchivedAgentSummary(...) for row in cursor.fetchall()]
```

**Frontend:**
- Add archive browser panel with search
- Show archives in explorer under "History" section
- Add terminal output viewer with syntax highlighting

---

## Task 7: Unique Worker IDs

**Goal:** Prevent name collisions when spawning workers.

### Current State

- Worker names are simple strings (e.g., `auth-worker`)
- Collision check exists in `tools/workers:57` but only per-session
- No global uniqueness

### Proposed Solution

Generate unique IDs while keeping human-readable names.

**ID Format:** `{session}:{name}-{short-uuid}`

Example: `cmux:auth-worker-a3f2`

**Files to modify:**
- `tools/workers` (spawn function):

```bash
cmd_spawn() {
    local name="${1:-}"
    local task="${2:-}"

    # Generate short unique suffix
    local suffix=$(head -c 2 /dev/urandom | xxd -p)
    local unique_name="${name}-${suffix}"

    # Ensure uniqueness across all sessions
    while worker_exists_anywhere "$unique_name"; do
        suffix=$(head -c 2 /dev/urandom | xxd -p)
        unique_name="${name}-${suffix}"
    done

    # ... rest of spawn logic with unique_name
}

worker_exists_anywhere() {
    local name="$1"
    for sess in $(get_cmux_sessions); do
        if tmux list-windows -t "$sess" -F '#{window_name}' | grep -qx "$name"; then
            return 0
        fi
    done
    return 1
}
```

- `src/server/services/agent_manager.py`:

```python
async def create_worker(self, base_name: str, session: Optional[str] = None) -> Agent:
    """Create a new worker agent with unique ID."""
    session = session or settings.main_session

    # Generate unique suffix
    import secrets
    suffix = secrets.token_hex(2)  # 4 hex chars
    unique_name = f"{base_name}-{suffix}"

    # Ensure global uniqueness
    while await self._name_exists_globally(unique_name):
        suffix = secrets.token_hex(2)
        unique_name = f"{base_name}-{suffix}"

    await tmux_service.create_window(unique_name, session)
    # ... rest of creation
```

**Backwards Compatibility:**
- Existing workers keep their names
- Only new workers get unique suffixes
- Display name strips suffix in UI if desired

---

## Task 8: Consistent Naming Scheme

**Goal:** Standardize naming for sessions, teams, workers, and artifacts.

### Proposed Naming Convention

```
Sessions:     cmux-{purpose}           (e.g., cmux-auth, cmux-refactor-api)
Supervisors:  supervisor-{purpose}     (e.g., supervisor-auth)
Workers:      {purpose}-{role}-{id}    (e.g., auth-backend-a3f2, auth-tester-b4c1)
Artifacts:    {session}/{date}/{type}-{name}.{ext}
```

**Artifact Path Convention:**
```
.cmux/journal/
  2026-02-01/
    journal.md                           # Daily summary
    attachments/
      cmux-auth/                         # Session-specific folder
        plan-initial.md
        plan-final.md
        worker-backend-a3f2-output.md
      webhook-abc123.json                # Webhooks
      msg-def456.md                      # General messages
```

**Files to modify:**
- `src/server/services/mailbox.py`: Use session-prefixed attachment paths
- `src/server/services/journal.py`: Add `get_session_artifacts()` method
- Update `tools/mailbox` to organize by session

```python
# mailbox.py modification
def _get_body_path(self, from_agent: str, subject: str) -> Path:
    """Generate organized body file path."""
    date_str = datetime.now().strftime("%Y-%m-%d")

    # Extract session from agent address
    if ":" in from_agent:
        session = from_agent.split(":")[0]
    else:
        session = "cmux"

    attachments_dir = settings.cmux_dir / "journal" / date_str / "attachments" / session
    attachments_dir.mkdir(parents=True, exist_ok=True)

    # Clean subject for filename
    clean_subject = re.sub(r'[^\w\-]', '-', subject[:30]).lower()
    timestamp = int(time.time())

    return attachments_dir / f"{clean_subject}-{timestamp}.md"
```

---

## Task 9: Artifact/Attachment Indexing

**Goal:** Make artifacts searchable and browsable.

### Current State

- Artifacts stored in `artifacts/` subdirectories
- Attachments in `attachments/` under journal
- No index, no search, no metadata

### Proposed Solution

Create an artifact index with SQLite.

**Files to create:**
- `src/server/services/artifact_index.py`

```python
import sqlite3
from pathlib import Path
from datetime import datetime
from dataclasses import dataclass

@dataclass
class IndexedArtifact:
    id: str
    path: str
    filename: str
    artifact_type: str  # 'attachment', 'artifact', 'archive'
    session: str | None
    agent: str | None
    created_at: datetime
    size_bytes: int
    content_preview: str | None  # First 500 chars for text files

class ArtifactIndex:
    def __init__(self, db_path: Path = Path('.cmux/artifact_index.db')):
        self.db_path = db_path
        self._ensure_db()

    def _ensure_db(self):
        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                CREATE TABLE IF NOT EXISTS artifacts (
                    id TEXT PRIMARY KEY,
                    path TEXT UNIQUE,
                    filename TEXT,
                    artifact_type TEXT,
                    session TEXT,
                    agent TEXT,
                    created_at TEXT,
                    size_bytes INTEGER,
                    content_preview TEXT
                )
            """)
            conn.execute("CREATE INDEX IF NOT EXISTS idx_session ON artifacts(session)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_agent ON artifacts(agent)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_type ON artifacts(artifact_type)")
            conn.execute("CREATE INDEX IF NOT EXISTS idx_created ON artifacts(created_at)")
            # FTS for content search
            conn.execute("""
                CREATE VIRTUAL TABLE IF NOT EXISTS artifacts_fts
                USING fts5(id, filename, content_preview)
            """)

    async def index_file(self, path: Path, session: str = None, agent: str = None):
        """Add or update a file in the index."""
        artifact_id = str(uuid.uuid4())

        # Determine type from path
        if 'attachments' in str(path):
            artifact_type = 'attachment'
        elif 'artifacts' in str(path):
            artifact_type = 'artifact'
        else:
            artifact_type = 'other'

        # Get preview for text files
        preview = None
        if path.suffix in ['.md', '.txt', '.json', '.yaml']:
            try:
                preview = path.read_text()[:500]
            except:
                pass

        with sqlite3.connect(self.db_path) as conn:
            conn.execute("""
                INSERT OR REPLACE INTO artifacts
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (
                artifact_id, str(path), path.name, artifact_type,
                session, agent, datetime.now().isoformat(),
                path.stat().st_size, preview
            ))

            # Update FTS
            conn.execute("""
                INSERT OR REPLACE INTO artifacts_fts VALUES (?, ?, ?)
            """, (artifact_id, path.name, preview or ""))

    async def search(self, query: str, session: str = None) -> list[IndexedArtifact]:
        """Full-text search across artifacts."""
        with sqlite3.connect(self.db_path) as conn:
            if session:
                results = conn.execute("""
                    SELECT a.* FROM artifacts a
                    JOIN artifacts_fts f ON a.id = f.id
                    WHERE artifacts_fts MATCH ? AND a.session = ?
                    ORDER BY rank
                    LIMIT 50
                """, (query, session))
            else:
                results = conn.execute("""
                    SELECT a.* FROM artifacts a
                    JOIN artifacts_fts f ON a.id = f.id
                    WHERE artifacts_fts MATCH ?
                    ORDER BY rank
                    LIMIT 50
                """, (query,))

            return [self._row_to_artifact(row) for row in results]

    async def reindex_all(self):
        """Rebuild index from filesystem."""
        journal_path = Path('.cmux/journal')
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

**API Endpoints to add:**
- `GET /api/artifacts?q=query&session=cmux-auth`
- `POST /api/artifacts/reindex`

**Files to modify:**
- `src/server/services/mailbox.py`: Call `artifact_index.index_file()` when creating attachments
- `src/server/services/journal.py`: Call index when saving artifacts

---

## Implementation Phases

### Phase 1: Foundation (Low Risk, High Value)
1. **Task 7**: Unique worker IDs - prevents immediate issues
2. **Task 8**: Naming scheme - enables better organization
3. **Task 4**: Terminology aliases - UI improvement only

### Phase 2: Coordination (Medium Risk)
4. **Task 5**: Inter-supervisor communication - builds on mailbox
5. **Task 2**: Team templates - structured approach to spawning
6. **Task 1**: Complexity analyzer - advisory, not mandatory

### Phase 3: Memory & Learning (Higher Complexity)
7. **Task 3**: Self-learning store - new database
8. **Task 9**: Artifact indexing - new search infrastructure
9. **Task 6**: Archive improvements - UI enhancements

---

## Testing Strategy

Each feature should have:
1. Unit tests for new services
2. Integration tests for API endpoints
3. Manual testing checklist for UI changes

Example test for unique worker IDs:
```python
async def test_unique_worker_ids():
    # Spawn two workers with same base name
    w1 = await agent_manager.create_worker("auth-worker")
    w2 = await agent_manager.create_worker("auth-worker")

    assert w1.name != w2.name
    assert w1.name.startswith("auth-worker-")
    assert w2.name.startswith("auth-worker-")
```

---

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| Breaking existing workflows | All changes are backwards-compatible |
| Database migrations | SQLite handles schema evolution gracefully |
| Performance impact from indexing | Index in background, make it optional |
| Complexity analyzer being wrong | It's advisory only, supervisor decides |

---

## Open Questions

1. Should unique IDs be UUIDs or human-readable suffixes?
2. How much historical data should the learning store retain?
3. Should team templates be YAML or JSON?
4. Should we version artifacts for rollback support?

---

## Summary

This plan provides a comprehensive approach to improving CMUX core architecture. Each improvement is:
- **Incremental**: Can be implemented independently
- **Backwards-compatible**: Won't break existing functionality
- **Testable**: Clear success criteria
- **Valuable**: Addresses real pain points

I look forward to the critic's feedback to refine these proposals.

---

*Plan authored by core-defender*
*Ready for critique from core-critic*
