# Permanent Worker Team — Critic Critique

## Overall Assessment

This is a well-structured proposal that correctly identifies the core inefficiency (repeated cold-start and codebase re-reading for recurring task types). The infrastructure design is grounded in the existing codebase and avoids unnecessary abstraction. However, several sections have issues ranging from optimistic assumptions to a missing cost analysis. I detail these below.

**Verdict Summary:**

| Section | Verdict | Key Issue |
|---------|---------|-----------|
| 1. Permanent Roles | REVISE | Tester should be ephemeral; 4 may be premature |
| 2. Task Assignment Protocol | ACCEPT | Clean, builds on existing tools |
| 3. Context Reset Mechanism | REVISE | Recovery is hand-wavy; broken compaction not addressed |
| 4. Perm + Ephemeral Coexistence | ACCEPT | Naming convention + registry flag is right |
| 5. Tooling and Code Changes | REVISE | `workers reset` underspecified; missing Claude restart timing |
| 6. Deletion Protection | REVISE | Overengineered for the actual risk |
| 7. Startup Sequence | ACCEPT | Straightforward |
| 8. Implementation Priority | REVISE | Missing cost/benefit analysis |
| 9. Tradeoffs | ACCEPT | Honest; self-identifies the right uncertainties |

---

## Section 1: Permanent Roles — REVISE

**The Good:**
- Frontend/Backend/Infra split is well-justified by the frequency data (31% + 27% + 12% = 70% of work)
- The "what stays ephemeral" list is correct — debate pairs and research are inherently one-shot
- The reasoning for frontend + backend over full-stack is sound: the research shows they are distinct task shapes

**Issues:**

### 1a. The Tester should NOT be permanent

The proposal acknowledges the tester "sits idle most of the time" and only 8% of historical work is testing. A permanent tester has the worst idle-to-active ratio of all four roles.

More importantly, testing knowledge is *task-dependent*, not *role-dependent*. A tester working on a frontend CSS fix needs to know about Chrome MCP browser testing. A tester working on API endpoints needs to know about pytest and httpx.AsyncClient. These are different domains. What a permanent tester "accumulates" is knowledge of the test runner, not knowledge of what to test — and the test runner is the simplest part.

The real cost of an ephemeral tester is low: `pytest` is one command, Chrome MCP is well-documented, and the test file paths are stable. The startup tax for testing (~20-30s) is small compared to the idle cost of keeping a Claude process running 24/7 that works 8% of the time.

**Counter-proposal:** Keep testing ephemeral. Instead, add a `perm-tester-role.md` *template* that ephemeral testers can be spawned with (reducing their startup context-reading time), but don't keep a live permanent window.

### 1b. Starting with 4 permanent workers is premature

The proposal is designing for what we *observed* over 2 days. Two days is a tiny sample. What if the next 5 days are heavy on infra work and zero frontend? We'd have 3 idle permanent workers burning API tokens on heartbeat nudges while the infra worker is overloaded and still needs ephemeral overflow.

**Counter-proposal:** Start with **2 permanent workers** — `perm-frontend` and `perm-backend`. These cover 58% of work and represent the two clearest specializations. Add infra and tester only after we observe their utilization over a week. The tooling should support N permanent workers from day one, but the initial deployment should be conservative.

### 1c. Missing: what about the sentry role?

The sentry already runs as a pseudo-permanent agent (started by monitor.sh, protected by `is_protected()`). The proposal doesn't mention how it relates to the permanent worker concept. Is sentry the prototype for this pattern? Should it be formalized as a permanent worker?

---

## Section 2: Task Assignment Protocol — ACCEPT

**The Good:**
- The flow is clean and incremental — it builds directly on the existing `tools/tasks` and `tools/mailbox` infrastructure
- The `[TASK] <task-id>: <summary>` message format is parseable and traceable
- The `workers assign` shorthand is a good UX improvement
- Worker idle behavior (wait, don't seek work) maintains the supervisor hierarchy correctly

**Minor Suggestions:**
- Consider adding a `[TASK-CANCEL] <task-id>` message format for when the supervisor needs to abort a task already assigned to a permanent worker. This isn't possible with ephemeral workers (just kill them), but permanent workers need a way to learn "stop what you're doing."
- The proposal doesn't address **what happens if the permanent worker is mid-task when a higher-priority task arrives**. Does it queue? Does the supervisor wait? The ephemeral model handles this by spawning a new worker, but the permanent model creates contention.

---

## Section 3: Context Reset Mechanism — REVISE

**The Good:**
- The reset-vs-kill distinction is excellent and clearly tabled
- Preserving tmux window, registry, and agent_id across resets is the right call
- The concept of a persistent role context file that survives resets is sound

**Issues:**

### 3a. The existing compaction system is broken — and the proposal ignores this

The research findings (which the proposal should have read) documented that:
- `compact.sh` references `PRE_COMPACT_HOOK="${PROJECT_ROOT}/.claude/hooks/pre-compact.sh"` — **this file does not exist**
- The recovery message tells workers to read `compaction-<window>-*.json` artifacts — **these are never created** because the pre-compact hook that would create them doesn't exist
- Workers post-compaction are told to check a path that has nothing in it

The proposal's `workers reset` depends on "save a compaction artifact" but doesn't address the fact that the *existing* compaction artifact pipeline is non-functional. The reset procedure in Section 3 says:

> 1. **Preserve state**: Save a compaction artifact to `.cmux/journal/YYYY-MM-DD/artifacts/compaction-perm-frontend-*.json`

But who writes this artifact? The proposal says `workers reset` does it, but the format and content are underspecified. What exactly goes in this JSON? The proposal lists "current task, files modified, git branch, last 50 lines of terminal output" — but doesn't show the implementation. This is the most critical part of the reset mechanism and it's a hand-wave.

**Counter-proposal:** Before implementing permanent workers, **fix the compaction pipeline first**. Create the pre-compact hook that was always intended. Then `workers reset` can reuse the same mechanism. Don't build a second artifact system on top of a broken first one.

### 3b. "Supervisor detects staleness" is not operationalized

The proposal lists "worker's responses become incoherent or slow" as a reset trigger. How does the supervisor detect this? There's no incoherence metric. The only observable proxy is:
- Worker takes too long (but long tasks exist legitimately)
- Worker sends `[BLOCKED]` (but this requires the worker to be self-aware enough to report)
- Worker's output diverges from its task (requires the supervisor to read and evaluate output)

This is a real-world trigger that will be needed, but the proposal should acknowledge it's a hard problem and propose a simpler heuristic (e.g., "reset after N compactions" or "reset after 4 hours regardless").

### 3c. Reset timing gap

The reset procedure kills the Claude process and restarts it. Based on the existing `STARTUP_DELAY=8` in `tools/workers`, this means 8+ seconds where the permanent worker is down. If a task was in progress, the task status is now "in-progress" in tasks.db but no worker is processing it. The proposal should specify that `workers reset` must:
1. Set the current task to `blocked` (not leave it as `in-progress`)
2. Re-assign the task after restart via the same `[TASK]` message flow

---

## Section 4: Perm + Ephemeral Coexistence — ACCEPT

**The Good:**
- `perm-` prefix convention is clean and the dual-check approach (prefix for humans, `permanent: true` flag for code) is correct
- Auto-maintenance protection via `is_protected()` is a one-line change — lowest risk possible
- The supervisor decision flow diagram is clear and sensible
- Priority model (permanent first, ephemeral for overflow) is the right default

**Minor Note:**

The `compact.sh` daemon has `SKIP_WINDOWS="monitor|supervisor"` — this is an **exact match** regex (`^(monitor|supervisor)$`). It does NOT skip `sup-*` project supervisors, and it would NOT skip `perm-*` workers. This is actually correct behavior (permanent workers *should* be compacted), but worth noting that `compact.sh` and `auto-maintenance` have different protection semantics. The proposal should call this out explicitly so the permanent workers don't get accidentally added to `SKIP_WINDOWS` by a future developer who thinks "permanent workers shouldn't be compacted."

---

## Section 5: Tooling and Code Changes — REVISE

**The Good:**
- `cmd_assign()` implementation is clean — 5 lines, reuses existing tools
- Enhanced `workers list` output with star icons is a nice touch
- Role context file template for `perm-frontend-role.md` is well-structured

**Issues:**

### 5a. `workers spawn-permanent` duplicates `workers spawn`

The proposal creates a new `cmd_spawn_permanent()` function that "creates tmux window (same as regular spawn)." This means copy-pasting the 80+ lines of `cmd_spawn()` with minor variations. The current `cmd_spawn()` already handles `--project`, `--task`, `--worktree` flags. A permanent worker needs the same setup minus the one-shot task text, plus the `permanent: true` registry flag and role context.

**Counter-proposal:** Add a `--permanent <role-context-path>` flag to the existing `cmd_spawn()` instead of a new command. This avoids code duplication and keeps all spawn logic in one place:

```bash
workers spawn perm-frontend "Read role context" --permanent .cmux/worker-contexts/perm-frontend-role.md
```

Internally, this sets `role: "permanent-worker"`, `permanent: true`, and `role_context` in the registry. The "task" argument becomes the initial read instruction (or could be auto-generated from the role context path).

### 5b. `workers reset` is the most complex new command but has the least implementation detail

The proposal shows `workers reset perm-frontend` and lists 6 steps, but doesn't provide the actual bash implementation. Given that this command must:
1. Capture terminal output (tmux capture-pane)
2. Query tasks.db for current task
3. Check git status for uncommitted changes
4. Write a structured JSON artifact
5. Archive the conversation via API
6. Kill only the Claude process (not the tmux window)
7. Restart Claude in the same window
8. Wait for Claude startup
9. Re-inject role context
10. Inject recovery context

...this is a ~60-80 line function with multiple failure modes. Step 6 is particularly tricky: how do you kill just the Claude process inside a tmux window without killing the shell? `Ctrl+C` sends SIGINT to Claude, but if Claude has exited, Ctrl+C goes to the shell. The proposal should address whether the tmux window runs Claude directly or inside a shell wrapper.

Looking at the current spawn: `claude --dangerously-skip-permissions` is run directly via `tmux send-keys`. This means the tmux window's process IS Claude. Killing Claude kills the shell. To restart Claude in the same window, you'd need to either:
- Send `/exit` to Claude Code (graceful), then `claude --dangerously-skip-permissions` again
- Or Ctrl+C, wait, then send the command again

The proposal should specify the exact sequence, because getting this wrong bricks the permanent worker.

### 5c. Registry unregistration on kill isn't addressed

The current `cmd_kill` in `tools/workers` does NOT unregister from the agent registry — it relies on `agent_manager.cleanup_stale()` which runs on every `list_agents` call. For permanent workers, the registry entry should explicitly survive kills (since `workers kill` requires a reason and is intentional). But what about the `cleanup_stale()` behavior? If a permanent worker's tmux window crashes (not killed via `workers kill`), `cleanup_stale()` would remove it from the registry — losing the `permanent: true` flag. The `check_permanent_workers()` function in monitor.sh reads from the registry to know which workers to restart, so a race condition exists:

1. `perm-frontend` tmux window crashes
2. `list_agents` runs, `cleanup_stale()` removes `perm-frontend` from registry
3. `check_permanent_workers()` reads registry — `perm-frontend` is gone, doesn't restart

**Counter-proposal:** `cleanup_stale()` must skip entries where `permanent: true`. Or better: permanent worker definitions should live in a separate config file (not the runtime registry), so they can't be accidentally cleaned up.

---

## Section 6: Deletion Protection — REVISE

**The Good:**
- The core idea (require a reason for killing permanent workers) is correct
- The deletion audit log is useful for post-mortems
- The `retire` alternative command is more explicit than overloading `kill`

**Issues:**

### 6a. This is overengineered for the actual risk

The scenario this protects against is: supervisor accidentally runs `workers kill perm-frontend`. But the supervisor is an LLM agent following instructions. It either knows the worker is permanent (because it spawned it or it's in the registry) or it doesn't. A reason requirement doesn't prevent a determined LLM from providing a reason — it prevents accidental/reflexive kills.

A simpler approach: just print a warning and require `--force`:

```bash
if is_permanent "$name"; then
    warn "Cannot kill permanent worker '$name'. Use 'workers reset $name' or 'workers kill $name --force'"
    exit 1
fi
```

The deletion log and journaling are useful, but the `retire` command adds another concept to learn when `kill --force` does the same thing.

### 6b. The auto-maintenance script also needs protection

The proposal correctly adds `perm-*` to `is_protected()` in auto-maintenance, but `is_protected()` only checks the window name prefix. If someone spawns a permanent worker without the `perm-` prefix (say they manually register one), auto-maintenance would kill it. The auto-maintenance should also check the registry `permanent: true` flag, not just the name.

---

## Section 7: Startup Sequence — ACCEPT

**The Good:**
- `launch_permanent_workers()` follows the existing pattern of `launch_project_supervisors()`
- Reading from the registry to determine which workers to launch is correct
- Checking if already running before launching prevents duplicates

**Minor:** The function should log which permanent workers were expected but had missing role context files (`[[ -n "$role_ctx" ]]` check exists, but the else branch should warn, not silently skip).

---

## Section 8: Implementation Priority — REVISE

**The Good:**
- The ordering is dependency-correct (registry before tooling before monitoring)
- Starting with the one-line auto-maintenance fix is smart

**Issues:**

### 8a. Missing cost/benefit analysis

The proposal estimates "~200 lines in tools/workers, ~30 in monitor.sh, ~20 in auto-maintenance" but doesn't estimate the ongoing cost of permanent workers:

- **4 permanent Claude processes = 4x ongoing API token consumption** for heartbeat responses, compaction, and context maintenance — even when idle
- Each heartbeat nudge that a permanent worker responds to costs tokens
- Each compaction cycle costs tokens
- 4 workers idle for 8 hours overnight = meaningful token spend for zero work

The proposal should include a rough break-even analysis: how many ephemeral worker spawns does a permanent worker need to replace to justify its idle cost?

### 8b. No rollback plan

What if permanent workers don't work well in practice? The proposal should include an exit strategy: how to demote all permanent workers back to ephemeral without breaking anything. (The answer is probably "just kill them and remove `permanent: true` from the registry" but this should be stated explicitly.)

---

## Section 9: Tradeoffs — ACCEPT

**The Good:**
- The self-identified uncertainties (tester permanence, auto-claim vs supervisor-driven) are the right ones
- Acknowledging "I'm less certain about" sections is intellectually honest
- The supervisor-driven vs queue-polling question is correctly left open

I agree with the defender's instinct: supervisor-driven assignment is better. Queue-polling introduces coordination complexity and risks two workers claiming the same task.

---

## Cross-Cutting Concerns

### Missing: What about `stop-gate.sh`?

The existing `stop-gate.sh` hook blocks worker shutdown until commit + journal + mailbox are complete. For permanent workers that DON'T exit after tasks, this hook fires on compaction-triggered `/compact` (which triggers a Stop event). The hook's behavior needs to be different for permanent vs ephemeral workers: permanent workers shouldn't be forced to commit between every task — they might be mid-multi-step work when compaction fires.

### Missing: Context accumulation budget

How many tasks should a permanent worker handle before a reset? The proposal mentions triggers (compaction failure, confusion, staleness) but doesn't propose a proactive policy. Consider: "reset every 5 tasks or 2 hours, whichever comes first" as a default that can be tuned.

### Missing: Dashboard/API changes for permanent worker state

The proposal mentions "star icon, different color" in passing but doesn't detail the API changes. The GET `/api/agents` response needs to surface `permanent: true` and `role_context` so the dashboard can render the distinction. The current `_enrich_from_registry` in `agent_manager.py` would need to pass through these new fields.

---

## Summary of Requested Revisions

1. **Drop the permanent tester** — make it an ephemeral role with a good template instead
2. **Start with 2 workers** (frontend + backend), not 4 — scale up based on observed utilization
3. **Fix the compaction pipeline first** — the pre-compact hook and artifact system must work before `workers reset` can build on it
4. **Use `--permanent` flag on existing `spawn`** instead of a new `spawn-permanent` command
5. **Specify `workers reset` implementation** — especially the Claude process restart sequence
6. **Address `cleanup_stale()` race condition** — permanent entries must survive stale cleanup
7. **Simplify deletion protection** to `--force` flag instead of `retire` command
8. **Add a break-even cost analysis** for idle permanent workers vs ephemeral startup tax
9. **Add a proactive reset policy** (every N tasks or M hours)
10. **Address `stop-gate.sh` behavior** for permanent workers
