# Permanent Worker Team — Defender Rebuttal

## Critique Summary and Response Matrix

| # | Critic's Point | Response | Revised? |
|---|---------------|----------|----------|
| 1a | Drop permanent tester | **CONCEDE** | Yes — tester becomes ephemeral with template |
| 1b | Start with 2, not 4 | **PARTIAL CONCEDE** — start with 3 (include infra) | Yes |
| 1c | What about sentry? | **DEFEND** — sentry is NOT a permanent worker | No |
| 2 (minor) | Add TASK-CANCEL, address preemption | **ACCEPT** — incorporated | Yes |
| 3a | Fix compaction pipeline first | **CONCEDE** — prerequisite step added | Yes |
| 3b | "Staleness detection" is hand-wavy | **CONCEDE** — replaced with proactive policy | Yes |
| 3c | Reset timing gap / task status | **ACCEPT** — specified | Yes |
| 4 (minor) | compact.sh vs auto-maintenance semantics | **ACCEPT** — documented | Yes |
| 5a | Use --permanent flag, not new command | **CONCEDE** | Yes |
| 5b | Specify workers reset implementation | **ACCEPT** — full implementation provided | Yes |
| 5c | cleanup_stale race condition | **ACCEPT** — fix specified | Yes |
| 6a | Simplify deletion to --force | **PARTIAL CONCEDE** — --force yes, but keep audit log | Yes |
| 6b | auto-maintenance should check registry too | **ACCEPT** | Yes |
| 7 (minor) | Warn on missing role context | **ACCEPT** | Yes |
| 8a | Add cost analysis | **ACCEPT** — analysis provided | Yes |
| 8b | Add rollback/exit strategy | **ACCEPT** | Yes |
| X1 | stop-gate.sh behavior | **ACCEPT** — addressed | Yes |
| X2 | Context accumulation budget | **ACCEPT** — proactive reset policy added | Yes |
| X3 | Dashboard/API changes | **ACCEPT** — specified | Yes |

**Score: 3 defenses, 15 concessions/acceptances.** The critique substantially improved the proposal.

---

## Detailed Responses

### 1a. Drop the Permanent Tester — CONCEDE

The critic is right. The numbers don't justify it:

- 8% of historical work
- Task-dependent knowledge (frontend testing ≠ API testing)
- Low ephemeral startup cost (pytest is one command, Chrome MCP is documented)
- Worst idle-to-active ratio of all roles

**Revised plan:** Create `perm-tester-role.md` as a *template* for ephemeral testers. The supervisor spawns ephemeral testers with: `workers spawn test-xyz "Test the auth changes" --role-template perm-tester-role.md`. This gives ephemeral testers a fast-start context without the idle cost.

### 1b. Start with 2 or 3 — PARTIAL CONCEDE

I concede that 4 is premature. But I advocate for **3** (frontend + backend + infra) rather than 2, for one critical reason:

**Infra work is the most dangerous category.** The research shows 12% of work touches orchestrator scripts (health.sh, monitor.sh, router.sh, compact.sh). These scripts are the system's immune system — breaking them disables auto-recovery, health monitoring, and message routing. An infra worker that accumulates deep knowledge of these scripts (their interactions, race conditions, timing dependencies) is uniquely valuable because:

1. A new ephemeral worker modifying monitor.sh without understanding the sentry spawn lifecycle could brick the system
2. The health daemon's rollback behavior, the compact daemon's timing, and the router's message delivery are tightly coupled — understanding requires context that's expensive to rebuild
3. The user has already experienced system breakage from infra changes (port 8000 incident documented in WORKER_ROLE.md)

The idle cost of one infra worker is low (see cost analysis below), and the risk mitigation is high.

**Revised plan:** Start with `perm-frontend`, `perm-backend`, `perm-infra`. Add more roles only after observing utilization over a week. The tooling supports N permanent workers from day one.

### 1c. What About Sentry? — DEFEND

The sentry is NOT a permanent worker and should not be formalized as one. The distinction is fundamental:

| Property | Permanent Worker | Sentry |
|----------|-----------------|--------|
| Lifecycle | Always running | Spawned on-demand, self-terminates |
| Purpose | Execute recurring tasks | Emergency supervisor recovery |
| Who manages it | Supervisor | Monitor daemon (no supervisor needed) |
| Identity persistence | Yes (same agent_id across resets) | No (new identity each spawn) |
| When idle | Waits for next task | Doesn't exist |

The sentry is an emergency responder — it exists only when the supervisor is broken. Making it permanent would mean keeping a Claude process running 99% of the time for a role that activates once every few hours (or never). The current spawn-on-demand model is correct for the sentry.

The sentry IS a useful *reference implementation* for "spawn agent, inject context, let it work, self-terminate" — which is exactly the ephemeral pattern. It validates that ephemeral agents with good context files work well.

### 2. TASK-CANCEL and Preemption — ACCEPT

Both are valid gaps. Incorporated into revised protocol:

**TASK-CANCEL format:**
```
[TASK-CANCEL] <task-id>: <reason>
Action: Stop current work, stash changes, mark task as blocked.
```

**Preemption policy:**
When a higher-priority task arrives for a busy permanent worker:
1. If current task is `low` or `medium` priority and new task is `critical` or `high`: supervisor sends `[TASK-CANCEL]` for current task, then `[TASK]` for new task
2. If both are same priority: queue the new task (or spawn ephemeral overflow)
3. The permanent worker, on receiving `[TASK-CANCEL]`, must: stash uncommitted changes, mark task as `blocked` with a note, then acknowledge readiness for the new task

### 3a. Fix Compaction Pipeline First — CONCEDE

The critic identified a real infrastructure gap. I verified:

- `compact.sh` line 29 references `PRE_COMPACT_HOOK="${PROJECT_ROOT}/.claude/hooks/pre-compact.sh"`
- This file **does not exist** (confirmed via glob)
- `compact.sh` lines 146-154 attempt to run the hook and capture an artifact file path
- Lines 186-199 inject a recovery message pointing to `compaction-${window}-*.json` artifacts that are **never created**

This means the entire recovery-after-compaction pipeline is non-functional today. Building `workers reset` on top of this broken foundation would be irresponsible.

**Revised implementation priority:**

1. **Create `.claude/hooks/pre-compact.sh`** — captures agent state (current task, git status, terminal output, files modified) and writes to `.cmux/journal/YYYY-MM-DD/artifacts/compaction-<window>-<timestamp>.json`
2. **Verify compaction recovery works end-to-end** — compact an agent, check that the artifact exists, check that the recovery message points to a real file
3. **Then implement `workers reset`** — which reuses the same artifact format

The pre-compact hook implementation:

```bash
#!/usr/bin/env bash
# .claude/hooks/pre-compact.sh
# Captures agent state before compaction for post-compact recovery.
# Called by compact.sh with window name as $1.
# Outputs the artifact file path on stdout.

set -euo pipefail

WINDOW="${1:-}"
[[ -z "$WINDOW" ]] && exit 0

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
TODAY=$(date +%Y-%m-%d)
TIMESTAMP=$(date +%H%M%S)
ARTIFACT_DIR="${PROJECT_ROOT}/.cmux/journal/${TODAY}/artifacts"
ARTIFACT_FILE="${ARTIFACT_DIR}/compaction-${WINDOW}-${TIMESTAMP}.json"
CMUX_SESSION="${CMUX_SESSION:-cmux}"

mkdir -p "$ARTIFACT_DIR"

# Capture terminal output
terminal_output=$(tmux capture-pane -t "${CMUX_SESSION}:${WINDOW}" -p -S -50 2>/dev/null || echo "")

# Capture git state
git_branch=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo "unknown")
uncommitted=$(git -C "$PROJECT_ROOT" diff --name-only 2>/dev/null || echo "")
staged=$(git -C "$PROJECT_ROOT" diff --cached --name-only 2>/dev/null || echo "")

# Capture current task from tasks.db
current_task=""
DB="${PROJECT_ROOT}/.cmux/tasks.db"
if [[ -f "$DB" ]]; then
    current_task=$(sqlite3 "$DB" \
        "SELECT id || ': ' || title FROM tasks WHERE (assigned_to='${WINDOW}' OR linked_workers LIKE '%${WINDOW}%') AND status IN ('in-progress', 'assigned') LIMIT 1;" \
        2>/dev/null || echo "")
fi

# Write artifact
jq -n \
    --arg window "$WINDOW" \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg terminal "$terminal_output" \
    --arg branch "$git_branch" \
    --arg uncommitted "$uncommitted" \
    --arg staged "$staged" \
    --arg current_task "$current_task" \
    '{
        agent: $window,
        captured_at: $timestamp,
        terminal_snapshot: $terminal,
        git_branch: $branch,
        uncommitted_changes: ($uncommitted | split("\n") | map(select(. != ""))),
        staged_changes: ($staged | split("\n") | map(select(. != ""))),
        current_task: $current_task
    }' > "$ARTIFACT_FILE"

echo "$ARTIFACT_FILE"
```

### 3b. Staleness Detection — CONCEDE

The critic is right that "incoherent responses" is undetectable. Replaced with a proactive policy:

**Proactive reset policy:**
- Reset after **5 completed tasks** (configurable via `PERM_WORKER_RESET_THRESHOLD` env var)
- Reset after **3 hours of continuous operation** (whichever comes first)
- Track completed task count in the registry: `"tasks_since_reset": 0` (incremented when supervisor marks a task done for that worker)
- The supervisor checks this counter after each task completion and triggers reset when threshold is reached

This is deterministic, observable, and doesn't require subjective judgment.

### 3c. Reset Timing Gap — ACCEPT

The critic correctly identified that mid-reset, the task is orphaned. Revised reset procedure includes:

1. Before killing Claude: if worker has an active task, set it to `blocked` with reason "context reset in progress"
2. After restart: re-assign the same task via `[TASK]` message
3. The role context file tells the worker to check for blocked tasks assigned to it on startup

### 4. compact.sh vs auto-maintenance Semantics — ACCEPT

Added explicit documentation:

```
COMPACTION SEMANTICS:
- compact.sh SHOULD compact permanent workers (they accumulate context like anyone)
- auto-maintenance should NOT kill permanent workers (they're long-lived by design)
- These are different concerns: compaction preserves the worker, killing destroys it
- Do NOT add perm-* to compact.sh's SKIP_WINDOWS
```

### 5a. Use --permanent Flag — CONCEDE

The critic is right — a new command duplicates 80+ lines of spawn logic. Revised:

```bash
workers spawn perm-frontend "Permanent frontend specialist" \
    --permanent .cmux/worker-contexts/perm-frontend-role.md
```

Implementation in `cmd_spawn()`:

```bash
# Parse --permanent flag (inside the existing while loop)
--permanent)
    [[ -z "${2:-}" ]] && die "--permanent requires a role context path"
    permanent_role_ctx="$2"
    shift 2
    ;;

# After registry creation, add permanent fields:
if [[ -n "${permanent_role_ctx:-}" ]]; then
    jq_filter='.[$key].permanent = true | .[$key].role = "permanent-worker" | .[$key].role_context = $rctx | .[$key].tasks_since_reset = 0 | .[$key].reset_count = 0'
    jq_args+=(--arg rctx "$permanent_role_ctx")
    jq "${jq_args[@]}" "$jq_filter" "$reg_file" > "$reg_tmp" && mv "$reg_tmp" "$reg_file"
fi

# Override the context file content for permanent workers:
if [[ -n "${permanent_role_ctx:-}" ]]; then
    # Point to role file instead of one-shot task
    task="Read ${permanent_role_ctx} for your permanent role. You are a permanent worker — you persist across tasks and receive work via [TASK] messages with task IDs. Read docs/WORKER_ROLE.md for general guidelines."
fi
```

### 5b. `workers reset` Full Implementation — ACCEPT

Here is the concrete implementation:

```bash
cmd_reset() {
    local name="${1:-}"
    [[ -z "$name" ]] && die "usage: workers reset <name>"

    # Verify it's a permanent worker
    local reg_file="${CMUX_PROJECT_ROOT}/.cmux/agent_registry.json"
    local is_perm
    is_perm=$(jq -r --arg k "$name" '.[$k].permanent // false' "$reg_file" 2>/dev/null)
    [[ "$is_perm" != "true" ]] && die "'$name' is not a permanent worker (use 'workers kill' instead)"

    if ! window_exists "$name"; then
        die "worker '$name' window not found"
    fi

    info "Resetting permanent worker: $name"

    # Step 1: Capture pre-reset state (reuse pre-compact hook)
    local artifact_file=""
    local pre_compact_hook="${CMUX_PROJECT_ROOT}/.claude/hooks/pre-compact.sh"
    if [[ -x "$pre_compact_hook" ]]; then
        artifact_file=$("$pre_compact_hook" "$name" 2>/dev/null) || true
        [[ -n "$artifact_file" ]] && info "State captured: $artifact_file"
    fi

    # Step 2: Mark current task as blocked (if any)
    local db="${CMUX_PROJECT_ROOT}/.cmux/tasks.db"
    if [[ -f "$db" ]]; then
        local active_task
        active_task=$(sqlite3 "$db" \
            "SELECT id FROM tasks WHERE (assigned_to='${name}' OR linked_workers LIKE '%${name}%') AND status='in-progress' LIMIT 1;" \
            2>/dev/null || echo "")
        if [[ -n "$active_task" ]]; then
            sqlite3 "$db" "UPDATE tasks SET status='blocked', updated_at='$(date -u +%Y-%m-%dT%H:%M:%SZ)' WHERE id='${active_task}';"
            warn "Task $active_task marked as blocked during reset"
        fi
    fi

    # Step 3: Archive conversation
    info "Archiving conversation..."
    curl -sX POST "http://localhost:${CMUX_PORT:-8000}/api/agents/${name}/archive" > /dev/null 2>&1 || \
        warn "Failed to archive (server may be down)"

    # Step 4: Gracefully exit Claude, then restart
    # Send /exit to Claude Code (graceful shutdown of the Claude process)
    info "Stopping Claude process..."
    tmux send-keys -t "${CMUX_SESSION}:${name}" -l "/exit"
    sleep 0.1
    tmux send-keys -t "${CMUX_SESSION}:${name}" Enter

    # Wait for Claude to exit (up to 10 seconds)
    local wait=0
    while ((wait < 10)); do
        sleep 1
        ((wait++))
        # Check if we're back at a shell prompt (no claude process)
        local pane_output
        pane_output=$(tmux capture-pane -t "${CMUX_SESSION}:${name}" -p -S -3 2>/dev/null || echo "")
        if echo "$pane_output" | grep -qE '^\$|^%|❯'; then
            break
        fi
    done

    # If /exit didn't work, force with Ctrl+C
    if ((wait >= 10)); then
        warn "/exit timed out, sending Ctrl+C"
        tmux send-keys -t "${CMUX_SESSION}:${name}" C-c
        sleep 2
    fi

    # Step 5: Restart Claude in the same window
    info "Restarting Claude..."
    local agent_id
    agent_id=$(jq -r --arg k "$name" '.[$k].agent_id' "$reg_file")
    local project_id
    project_id=$(jq -r --arg k "$name" '.[$k].project_id // "cmux"' "$reg_file")

    local env_vars="CMUX_AGENT=true CMUX_AGENT_ID=${agent_id} CMUX_AGENT_NAME=${name} CMUX_SESSION=${CMUX_SESSION} CMUX_HOME=${CMUX_PROJECT_ROOT} CMUX_PORT=${CMUX_PORT:-8000} CMUX_SUPERVISOR=${CMUX_AGENT_NAME:-supervisor} CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=false"
    [[ -n "$project_id" && "$project_id" != "null" ]] && env_vars="${env_vars} CMUX_PROJECT_ID=${project_id}"

    tmux send-keys -t "${CMUX_SESSION}:${name}" -l "export ${env_vars} && claude --dangerously-skip-permissions"
    sleep 0.1
    tmux send-keys -t "${CMUX_SESSION}:${name}" Enter

    # Wait for Claude to initialize
    info "Waiting ${STARTUP_DELAY}s for Claude to initialize..."
    sleep "$STARTUP_DELAY"

    # Disable vim mode if needed
    if tmux capture-pane -t "${CMUX_SESSION}:${name}" -p | grep -qE "\-\- (INSERT|NORMAL|VISUAL) \-\-"; then
        tmux send-keys -t "${CMUX_SESSION}:${name}" -l "/vim"
        tmux send-keys -t "${CMUX_SESSION}:${name}" Enter
        sleep 1
    fi

    # Step 6: Re-inject role context
    local role_ctx
    role_ctx=$(jq -r --arg k "$name" '.[$k].role_context // empty' "$reg_file")
    [[ -z "$role_ctx" ]] && die "No role_context found in registry for $name"

    local recovery_instruction="Read ${CMUX_PROJECT_ROOT}/.cmux/worker-contexts/${name}-context.md for your identity. Then read ${role_ctx} for your permanent role."
    if [[ -n "$artifact_file" ]]; then
        recovery_instruction="${recovery_instruction} Then read ${artifact_file} for your pre-reset state — you may have an in-progress task to resume."
    fi

    info "Sending role context..."
    tmux send-keys -t "${CMUX_SESSION}:${name}" -l "$recovery_instruction"
    sleep 0.1
    tmux send-keys -t "${CMUX_SESSION}:${name}" Enter

    # Step 7: Update registry counters
    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local tmp
    tmp=$(mktemp)
    jq --arg k "$name" --arg ts "$now" \
        '.[$k].reset_count = ((.[$k].reset_count // 0) + 1) | .[$k].last_reset_at = $ts | .[$k].tasks_since_reset = 0' \
        "$reg_file" > "$tmp" && mv "$tmp" "$reg_file"

    ok "Permanent worker '$name' reset (reset #$(jq -r --arg k "$name" '.[$k].reset_count' "$reg_file"))"
}
```

Key design decisions:
- Uses `/exit` first (graceful Claude shutdown), falls back to Ctrl+C
- After Claude exits, the tmux window still has a shell — we re-launch Claude in the same shell
- The registry entry is never touched (identity preserved)
- The context file is rewritten with the standard worker preamble

### 5c. cleanup_stale Race Condition — ACCEPT

This is a real bug. Fix:

```python
# In agent_registry.py, modify cleanup_stale():
def cleanup_stale(self, existing_windows: Set[str]):
    """Remove registry entries for windows that no longer exist.

    Skips entries marked as permanent — these persist even when
    their tmux window is temporarily down.
    """
    stale = set()
    for key in self._agents:
        if key not in existing_windows:
            entry = self._agents[key]
            if entry.get("permanent", False):
                continue  # Never clean up permanent workers
            stale.add(key)

    if stale:
        for key in stale:
            del self._agents[key]
        self._save()
    return stale
```

This ensures that even if a permanent worker's tmux window crashes, its registry entry survives so `check_permanent_workers()` in monitor.sh can detect it's missing and restart it.

### 6a. Simplify Deletion to --force — PARTIAL CONCEDE

I accept `--force` over a separate `retire` command. But I keep the audit log — it's 3 lines of jq and provides genuine value for understanding why permanent workers were removed:

```bash
if [[ "$is_perm" == "true" ]]; then
    if [[ "$force_flag" != "true" ]]; then
        die "Cannot kill permanent worker '$name'.\n  Use 'workers reset $name' to reset context, or\n  Use 'workers kill $name --force' to permanently remove."
    fi

    # Audit log (3 lines, near-zero cost)
    local deletion_log="${CMUX_PROJECT_ROOT}/.cmux/permanent-worker-deletions.json"
    [[ -f "$deletion_log" ]] || echo '[]' > "$deletion_log"
    local tmp=$(mktemp)
    jq --arg name "$name" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + [{"worker": $name, "deleted_at": $ts}]' "$deletion_log" > "$tmp" && mv "$tmp" "$deletion_log"

    warn "Permanently removing '$name'"
fi
```

No `retire` command. No reason argument. Just `--force` to prevent accidents, plus a silent audit log.

### 6b. Auto-maintenance Registry Check — ACCEPT

```bash
is_protected() {
    local name="$1"
    [[ "$name" == "supervisor" ]] && return 0
    [[ "$name" == sup-* ]] && return 0
    [[ "$name" == "sentry" ]] && return 0
    [[ "$name" == "monitor" ]] && return 0
    [[ "$name" == perm-* ]] && return 0   # Name-based fast path

    # Also check registry for permanent flag (covers non-standard names)
    local reg_file="${CMUX_PROJECT_ROOT}/.cmux/agent_registry.json"
    if [[ -f "$reg_file" ]]; then
        local is_perm
        is_perm=$(jq -r --arg k "$name" '.[$k].permanent // false' "$reg_file" 2>/dev/null)
        [[ "$is_perm" == "true" ]] && return 0
    fi

    return 1
}
```

### 7. Warn on Missing Role Context — ACCEPT

```bash
if [[ -n "$role_ctx" && -f "$role_ctx" ]]; then
    workers spawn-permanent "$name" "$role_ctx"
else
    log_warn "Permanent worker '$name' has missing role context: ${role_ctx:-<none>}"
    log_warn "Skipping — fix role_context in agent_registry.json"
fi
```

### 8a. Cost/Benefit Analysis — ACCEPT

**Idle cost of a permanent worker:**
- Each heartbeat nudge response: ~500-1000 tokens (input context + short response)
- Heartbeat frequency: every ~10 minutes (600s threshold)
- Per hour idle: ~6 nudge responses × ~750 tokens = ~4,500 tokens/hour
- Per day (8 hours idle overnight): ~36,000 tokens
- 3 permanent workers idle overnight: ~108,000 tokens

**Startup cost of an ephemeral worker:**
- Reading WORKER_ROLE.md: ~2,000 tokens
- Reading task context file: ~500 tokens
- Reading relevant source files for orientation: ~3,000-5,000 tokens
- Total cold start: ~5,500-7,500 tokens per ephemeral spawn

**Break-even calculation:**
- Daily idle cost of 3 permanent workers: ~108,000 tokens (overnight only; during active hours they're working, not idle)
- Daily active-hours idle (assuming 50% utilization): ~3 workers × 8 hours × 50% idle × 4,500 tokens/hour = ~54,000 tokens
- Total daily idle overhead: ~162,000 tokens
- Ephemeral spawns avoided per day: historically ~5-8 workers/day in the permanent role categories
- Savings per avoided spawn: ~6,000 tokens cold start + ~2,000 tokens codebase re-reading = ~8,000 tokens
- Daily savings from permanent workers: ~6.5 spawns × 8,000 = ~52,000 tokens

**Verdict:** The pure token math doesn't break even — permanent workers cost ~162K tokens/day idle vs saving ~52K tokens from avoided spawns. BUT:

1. **The real value isn't tokens — it's accumulated context.** A permanent frontend worker that's handled 5 tasks knows the component tree, the Zustand patterns, the CSS conventions. Ephemeral workers re-discover this every time, making more mistakes and taking longer.
2. **Reduce overnight idle cost:** Permanent workers should be "parked" overnight — not killed, but their heartbeat responses suppressed. Add a quiet hours config: `PERM_WORKER_QUIET_HOURS="00:00-08:00"` where the monitor doesn't send nudges to permanent workers.
3. **With quiet hours, daily idle drops to ~54K tokens** — closer to the 52K savings, and the accumulated context value tips the scale.

### 8b. Rollback/Exit Strategy — ACCEPT

If permanent workers don't work well:

```bash
# Demote all permanent workers to ephemeral (one command)
for name in $(jq -r 'to_entries[] | select(.value.permanent == true) | .key' .cmux/agent_registry.json); do
    workers kill "$name" --force
done
```

Or less destructively — just remove the permanent flag:

```bash
jq 'to_entries | map(if .value.permanent == true then .value.permanent = false | .value.role = "worker" else . end) | from_entries' \
    .cmux/agent_registry.json > /tmp/reg.json && mv /tmp/reg.json .cmux/agent_registry.json
```

This turns them into regular ephemeral workers that auto-maintenance can clean up normally. No code changes needed — the system gracefully degrades.

### X1. stop-gate.sh Behavior — ACCEPT

The current `stop-gate.sh` blocks shutdown unless the agent has committed, journaled, or sent a mailbox message. For permanent workers:

- Compaction triggers `/compact`, not `/exit` — so the Stop hook doesn't fire during compaction (compaction is not a stop event)
- The only time Stop fires for a permanent worker is during `workers reset` (which sends `/exit`)
- During reset, the worker may be mid-task and hasn't committed yet

**Fix:** Add permanent worker awareness to stop-gate.sh:

```bash
# After the supervisor skip, add:
# Skip for permanent workers during reset — their state is captured by the reset procedure
if [[ "${CMUX_AGENT_NAME}" == perm-* ]]; then
    # Check if this is a reset-triggered exit
    local reg_file="${CMUX_HOME:-.}/.cmux/agent_registry.json"
    if [[ -f "$reg_file" ]]; then
        local is_perm
        is_perm=$(jq -r --arg k "${CMUX_AGENT_NAME}" '.[$k].permanent // false' "$reg_file" 2>/dev/null)
        if [[ "$is_perm" == "true" ]]; then
            exit 0  # Allow stop — reset procedure handles state preservation
        fi
    fi
fi
```

### X2. Context Accumulation Budget — ACCEPT

**Policy:** Reset after 5 completed tasks OR 3 hours, whichever comes first.

Tracked in registry:
```json
{
    "tasks_since_reset": 3,
    "last_reset_at": "2026-02-21T04:00:00Z",
    "reset_threshold_tasks": 5,
    "reset_threshold_hours": 3
}
```

The supervisor checks after each task completion:
```bash
# In supervisor's task-done handler:
tasks_since=$(jq -r --arg k "$worker" '.[$k].tasks_since_reset // 0' "$reg_file")
threshold=$(jq -r --arg k "$worker" '.[$k].reset_threshold_tasks // 5' "$reg_file")
if ((tasks_since >= threshold)); then
    workers reset "$worker"
fi
```

And the monitor checks the time threshold in its dashboard loop.

### X3. Dashboard/API Changes — ACCEPT

The `_enrich_from_registry` method in `agent_manager.py` needs to pass through new fields. Add to the Agent model:

```python
class Agent(BaseModel):
    # ... existing fields ...
    permanent: bool = False
    role_context: Optional[str] = None
    reset_count: int = 0
    tasks_since_reset: int = 0
```

In `_enrich_from_registry`:
```python
agent.permanent = meta.get("permanent", False)
agent.role_context = meta.get("role_context")
agent.reset_count = meta.get("reset_count", 0)
agent.tasks_since_reset = meta.get("tasks_since_reset", 0)
```

The GET `/api/agents` response then automatically includes these fields. The dashboard can use `permanent: true` to render a star icon and different color.

---

## Revised Implementation Priority

1. **Fix compaction pipeline** — Create `.claude/hooks/pre-compact.sh`, verify end-to-end
2. **Registry + model changes** — Add `permanent`, `role_context`, `reset_count`, `tasks_since_reset` fields; add `PERMANENT_WORKER` role; fix `cleanup_stale()` to skip permanent entries
3. **Auto-maintenance protection** — Add `perm-*` + registry check to `is_protected()`
4. **`--permanent` flag on `workers spawn`** — Extend existing spawn, no new command
5. **Role context files** — Create `perm-frontend-role.md`, `perm-backend-role.md`, `perm-infra-role.md`, and `perm-tester-role.md` (template for ephemeral testers)
6. **`workers assign`** — Shorthand for task assignment + mailbox
7. **`workers reset`** — Full implementation as specified above
8. **`workers kill --force`** — Deletion protection for permanent workers
9. **stop-gate.sh update** — Allow exit for permanent workers during reset
10. **Monitor integration** — `check_permanent_workers()` for auto-restart; quiet hours support
11. **Dashboard/API** — Surface permanent worker fields

**Prerequisite before any permanent worker deployment:** Step 1 (fix compaction) must be verified working.

---

## Revised Role Count and Startup Plan

| Phase | Workers | When |
|-------|---------|------|
| Phase 1 | `perm-frontend` + `perm-backend` + `perm-infra` | Day 1 |
| Phase 2 | Evaluate utilization after 1 week | Day 7 |
| Phase 3 | Add more permanent roles if justified by data | Day 7+ |

Tester remains ephemeral with the `perm-tester-role.md` template for fast startup.
