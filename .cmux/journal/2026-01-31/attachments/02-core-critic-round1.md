# Core Architecture Improvements - Round 1 Critique

**Author:** core-critic
**Date:** 2026-02-01
**Status:** Initial Critique

---

## Executive Summary

The defender presents a thoughtful plan with genuine improvements, but several proposals suffer from **over-engineering**, **unclear integration paths**, and **database proliferation**. I identify critical issues requiring revision before implementation.

**Key Concerns:**
1. Three new SQLite databases is excessive - consolidate to one
2. Complexity analyzer uses brittle heuristics with no feedback loop
3. Several "features" are thin wrappers adding layers without value
4. Missing integration details on how supervisors actually consume these services

---

## Task 1: Complexity Analyzer - MAJOR CONCERNS

### The Good
- Acknowledging the need for delegation guidance is correct
- Advisory-only approach (supervisor decides) is wise

### Critical Issues

**1. Keyword-based heuristics are brittle and naive**

```python
COMPLEXITY_SIGNALS = {
    'high': ['refactor', 'architecture', 'security', 'authentication', 'migration'],
    # ...
}
```

This will misfire constantly:
- "Fix authentication typo" scores high (contains 'authentication')
- "Rewrite the entire billing system" scores low (no keywords)
- "Add a small security header" triggers 'security' flag

**Counter-proposal:** Use task length + explicit user hints instead of keyword matching. If the user says "this is complex", believe them.

**2. No connection to Task 3 (Learning Store)**

The analyzer has hardcoded thresholds but ignores historical data. Why build a learning store if the analyzer doesn't learn?

**Counter-proposal:** Feed learning store success rates INTO the complexity analyzer:
```python
def analyze(self, task: str) -> ComplexityScore:
    # Get historical data for similar task types
    history = learning_store.get_recommendations(self._classify_task_type(task))
    # Adjust recommendation based on what worked before
```

**3. Multi-step detection is laughable**

```python
if any(x in task_lower for x in ['and', 'then', 'also', 'plus']):
    factors['multi_step'] = 15
```

"Fix the readme and commit" would trigger this. So would "then we're done" as a suffix. False positives everywhere.

**Verdict: Revise or defer.** The core idea has merit but this implementation will frustrate users with bad recommendations.

---

## Task 2: Team Templates - ACCEPTABLE WITH MODIFICATIONS

### The Good
- Structured team configurations are genuinely useful
- YAML format is readable and version-controllable
- Example templates (DEBATE_PAIR, FULL_FEATURE) are practical

### Issues

**1. Missing template discovery and validation**

How does `load_team_template()` work? Where does it look? What if template is malformed?

**Required additions:**
- Template schema validation (use Pydantic or JSON Schema)
- Error messages when templates are invalid
- List available templates API endpoint

**2. Over-specified for current scale**

CMUX has existed for ~2 days of active development. We have 2 templates. Adding infrastructure for template hierarchies and communication graphs is premature.

**Counter-proposal:** Start with documentation-only templates (current approach), add structured YAML only when we have 5+ distinct patterns worth encoding.

**3. Session naming collision risk**

`create_team_from_template` uses `name_prefix` but doesn't check if session already exists.

**Verdict: Accept with simplification.** Drop the complex communication graph (`communicates_with`, `coordinates_with`). Keep roles and workflow definition.

---

## Task 3: Self-Learning Store - SIGNIFICANT REDESIGN NEEDED

### The Good
- Tracking delegation outcomes is valuable
- Success rate queries are practical
- SQLite is appropriate for this use case

### Critical Issues

**1. Database proliferation**

This plan introduces THREE separate SQLite databases:
- `learning.db` (Task 3)
- `artifact_index.db` (Task 9)
- Existing `conversations.db`

This is poor architecture. SQLite is single-writer - multiple DBs mean multiple lock domains, backup complexity, and cognitive overhead.

**Counter-proposal:** ONE database (`.cmux/cmux.db`) with multiple tables:
- `delegations` (learning data)
- `artifacts` (index)
- `agent_archives` (move from conversations.db)

**2. How does the supervisor record outcomes?**

The plan says "Add instructions on recording outcomes" but doesn't specify:
- When does recording happen?
- Is it manual or automatic?
- What determines 'success' vs 'partial' vs 'failed'?

Without automated outcome capture, this becomes another manual step supervisors will forget.

**Counter-proposal:** Auto-record based on worker [DONE]/[BLOCKED] messages:
```python
# In router.sh or mailbox processing
if message matches "[DONE]":
    learning_store.record(outcome='success', ...)
elif message matches "[BLOCKED]":
    learning_store.record(outcome='failed', ...)
```

**3. Cold start problem**

With no data, `get_success_rate` returns 0.5. This provides no guidance until you have significant history.

**Verdict: Accept with database consolidation and automatic outcome capture.**

---

## Task 4: Terminology Aliases - UNNECESSARY COMPLEXITY

### The Problem This Solves... Doesn't Exist

"Supervisor" and "Worker" are standard industry terms used by:
- Erlang/OTP supervisors
- Celery workers
- Kubernetes
- Every process management system

The claim they're "off-putting" is unsubstantiated.

### Issues

**1. Display name divergence causes confusion**

If the UI shows "Coordinator" but logs show "supervisor", users will be confused when debugging.

**2. Marginal benefit for real cost**

Adding `role_display_name` field, frontend handling, and documentation updates for... what? A different label?

**3. "Specialist" is arguably worse**

"Worker" is clear: it does work. "Specialist" implies domain expertise the agent may not have.

**Counter-proposal:** Drop this entirely. If terminology must change, do a full rename (breaking change) rather than maintaining parallel naming systems.

**Verdict: REJECT. Unnecessary complexity for zero demonstrable benefit.**

---

## Task 5: Inter-Supervisor Communication - REDUNDANT ABSTRACTION

### Current State Analysis

The mailbox ALREADY supports supervisor-to-supervisor communication:
```
[2026-02-01T10:00:00] cmux-auth:supervisor-auth -> cmux:supervisor: [STATUS] JWT complete
```

The router already routes between sessions. What problem does `[COORD]` prefix solve?

### Issues

**1. CoordinatorService is a thin wrapper**

```python
async def send_coordination(self, msg: CoordinationMessage):
    subject = f"[COORD] {msg.type.value}: {msg.content[:50]}"
    await mailbox_service.send_mailbox_message(...)
```

This adds a class, dataclass, and enum to... prepend a string to messages? Over-abstraction.

**2. [COORD] prefix creates parsing ambiguity**

We already have `[STATUS]`, `[DONE]`, `[BLOCKED]`, `[QUESTION]`. Now we add `[COORD] STATUS`, `[COORD] BLOCK`?

This creates confusion: Is `[COORD] STATUS` different from `[STATUS]`? The answer should be "no" - it's the same semantics.

**Counter-proposal:** Don't add new prefixes. Supervisor-to-supervisor messages are already handled by existing mailbox. If we need priority routing, add a priority field to the message format, not a prefix.

**Verdict: REJECT. The existing mailbox handles this. Adding a wrapper adds complexity without functionality.**

---

## Task 6: Archived Agent Improvements - GOOD BUT UNDERSPECIFIED

### The Good
- Search/filter for archives is valuable
- Tagging is useful for categorization
- Code additions are reasonable

### Issues

**1. Compression is mentioned but not detailed**

> Add archive compression for old entries

How? When? What format? What triggers it? This is vague.

**2. Frontend changes not specified**

> Add archive browser panel with search

What component? Where does it live? This needs design.

**Counter-proposal:** Focus on backend search first (3 has code), defer frontend and compression to future iteration.

**Verdict: Accept search/filter, defer compression and frontend.**

---

## Task 7: Unique Worker IDs - ACCEPT

### This Is Well Designed

- Addresses real collision problem
- 4-character hex suffix is reasonable
- Backwards compatible
- Global uniqueness check is correct

### Minor Issues

**1. Display name consideration**

Should UI show `auth-worker-a3f2` or strip to `auth-worker`? Needs explicit decision.

**Counter-proposal:** Keep full name everywhere for clarity. Users will learn the pattern.

**2. Collision check performance**

`worker_exists_anywhere()` queries all sessions. At scale (10+ sessions, 50+ workers), this gets slow.

**Counter-proposal:** Accept for now, add index if performance becomes issue.

**Verdict: ACCEPT. Solid, practical improvement.**

---

## Task 8: Consistent Naming Scheme - ACCEPT WITH CAUTION

### The Good
- Standardization is valuable
- Session-prefixed artifact paths make sense
- Pattern is clear and learnable

### Issues

**1. Migration risk for existing artifacts**

What happens to existing files in `attachments/`? Are they moved? Left in place? Orphaned?

**Required addition:** Migration plan or decision to grandfather existing artifacts.

**2. Path length concerns**

`.cmux/journal/2026-02-01/attachments/cmux-auth-feature-token-refresh/plan-initial.md`

This is getting long. Consider if deep nesting is worth it.

**Counter-proposal:** Flatten to session prefix in filename:
```
.cmux/journal/2026-02-01/attachments/cmux-auth--plan-initial.md
```

**Verdict: Accept with migration plan.**

---

## Task 9: Artifact Indexing - ACCEPT WITH CONSOLIDATION

### The Good
- Full-text search with FTS5 is the right choice
- Reindex capability is necessary
- Schema is appropriate

### Issues

**1. Another SQLite database**

Already addressed in Task 3 critique. Consolidate.

**2. Index maintenance overhead**

Calling `index_file()` on every mailbox attachment adds latency. Consider background indexing.

**3. Preview extraction for large files**

```python
preview = path.read_text()[:500]
```

What if file is 100MB? Read 100MB to get 500 chars?

**Fix:** Read with limit:
```python
with open(path, 'r') as f:
    preview = f.read(500)
```

**Verdict: Accept with database consolidation and performance fixes.**

---

## Cross-Cutting Concerns

### 1. Database Consolidation Is Non-Negotiable

Proposed: 3 databases (`learning.db`, `artifact_index.db`, `conversations.db`)

Required: 1 database (`.cmux/cmux.db`) with proper schema:
```sql
-- Single database with all tables
CREATE TABLE delegations (...);
CREATE TABLE artifacts (...);
CREATE TABLE agent_archives (...);
-- Keep conversations table too
```

### 2. Feature Flags Missing

Several features should be toggleable:
- Complexity analyzer recommendations
- Automatic outcome recording
- Artifact indexing

Add to `config.py`:
```python
enable_complexity_analyzer: bool = True
enable_learning_store: bool = True
enable_artifact_index: bool = True
```

### 3. Integration Path Unclear

Many features create services but don't explain:
- How does supervisor discover complexity recommendations?
- Where are learning store stats displayed?
- How does search get exposed to users?

Each feature needs an "Integration" section specifying:
- CLI commands (if any)
- API endpoints
- Frontend components (if any)
- Documentation updates

---

## Summary of Verdicts

| Task | Verdict | Action Required |
|------|---------|-----------------|
| 1. Complexity Analyzer | **REVISE** | Remove keyword matching, integrate with learning store |
| 2. Team Templates | **SIMPLIFY** | Drop communication graphs, add validation |
| 3. Learning Store | **REVISE** | Consolidate DB, auto-capture outcomes |
| 4. Terminology | **REJECT** | Unnecessary complexity |
| 5. Inter-Supervisor Comm | **REJECT** | Redundant abstraction over mailbox |
| 6. Archive Improvements | **PARTIAL** | Accept search, defer compression/frontend |
| 7. Unique Worker IDs | **ACCEPT** | Good as-is |
| 8. Naming Scheme | **ACCEPT** | Need migration plan |
| 9. Artifact Indexing | **ACCEPT** | Consolidate DB, fix performance |

---

## Priority Reordering

If we accept my revisions, implementation order should be:

**Phase 1: Foundation**
1. Unique Worker IDs (Task 7) - immediate value
2. Naming Scheme (Task 8) - enables better organization
3. Database Consolidation - prerequisite for 3, 6, 9

**Phase 2: Memory**
4. Artifact Indexing (Task 9) - with consolidation
5. Archive Search (Task 6) - leverages same DB
6. Learning Store (Task 3) - with auto-capture

**Phase 3: Intelligence**
7. Team Templates (Task 2) - simplified version
8. Complexity Analyzer (Task 1) - integrated with learning store

**Dropped:**
- Task 4 (Terminology) - rejected
- Task 5 (Coordinator Service) - rejected

---

## Final Position

The defender has done solid analysis of real problems. However, approximately 30% of the proposed solutions are over-engineered or redundant. I recommend:

1. **Consolidate databases** - one SQLite file, multiple tables
2. **Drop Tasks 4 and 5** - complexity without benefit
3. **Simplify Task 1** - remove keyword matching
4. **Auto-capture outcomes** - make Task 3 actually useful

I await the defender's rebuttal.

---

*Critique authored by core-critic*
*Round 1 complete - awaiting defender response*
