# Ambition Infrastructure Audit — 2026-02-21

Investigator: `ambition-infra-audit` worker
Date: 2026-02-21

---

## 1. VERIFY-DONE COMMITS — Are workers committing when they claim [DONE]?

### Methodology

Read all messages in `.cmux/mailbox` containing `[DONE]` in the subject line. For each, searched for a commit hash pattern (7+ hex chars). For those found, ran `git log --oneline <hash>` to verify the commit exists in the repo.

### Results

| Metric | Count |
|--------|-------|
| Total [DONE] messages in mailbox | 39 |
| [DONE] messages WITH a commit hash | 32 (82%) |
| [DONE] messages WITHOUT a commit hash | 7 (18%) |
| Commit hashes that verified in git | 31 |
| Commit hashes NOT found in git | 1 |

**Verification rate: 31/32 hashes verified (97%).**

### [DONE] Messages Missing Commit Hashes (7)

| # | Agent | Subject Summary | Reasonable? |
|---|-------|----------------|-------------|
| 1 | perm-infra | Verified project-scoped permanent workers | YES — verification task, no code change |
| 2 | delegation-protocol | Added delegation protocol section to docs | NO — doc edit should have a commit |
| 3 | perm-infra | Hook & daemon audit complete (report saved) | YES — investigation/audit, no code change |
| 4 | hero-research | Hero codebase research report (to supervisor) | YES — research task, report is the deliverable |
| 5 | hero-research | Hero codebase research (to squad-lead) | YES — duplicate of above, to different recipient |
| 6 | heroweb-research | Heroweb codebase research report (to supervisor) | YES — research task |
| 7 | heroweb-research | Heroweb research complete (to squad-lead) | YES — duplicate of above |

**Analysis**: Of 7 missing hashes, only 1 is problematic (delegation-protocol edited a file but didn't commit). The other 6 are verification/research tasks where no code was modified. The system is actually performing well here.

### Unverified Commit Hash (1)

| Hash | Agent | Reason |
|------|-------|--------|
| `e47b88e` | heroweb-backend | Commit is in the **heroweb** repo (`/Users/pankajgarkoti/Desktop/code/zonko/heroweb`), not the CMUX repo. `git log` in CMUX can't find it. This is a FALSE NEGATIVE — the commit likely exists in the other repo. |

### Recommended Mechanical Fix

**Post-[DONE] verification hook** — when a worker sends `[DONE]` via mailbox:

1. **Parse the message** for commit hash patterns (`[0-9a-f]{7,40}`)
2. **Run `git log --oneline <hash>`** in the appropriate repo (check agent's `project_id` from registry to determine repo)
3. **If hash found**: tag the message as `[VERIFIED]` in a new field
4. **If hash NOT found AND task involved code changes**: flag to supervisor as `[UNVERIFIED]` with reason
5. **If no hash AND task was code-change type**: flag as `[MISSING-COMMIT]`

**Implementation location**: Could be a post-receive hook in the mailbox router (`router.sh`) or a new verification step in the supervisor's [DONE] handling logic.

**Edge cases to handle**:
- Cross-repo commits (heroweb-backend committing in heroweb repo, not cmux)
- Research/audit tasks where no commit is expected (detect by checking if worker modified any files)
- Duplicate [DONE] messages (same task, different recipients)

---

## 2. COMPACT DAEMON — Is it running?

### Current Status: NOT RUNNING

| Check | Result |
|-------|--------|
| `ps aux \| grep compact` | No process found |
| `pgrep -f compact.sh` | Exit code 1 (not found) |
| tmux windows (`tmux list-windows -t cmux`) | No "compact" window (24 windows listed, none is compact) |
| Status log entries for today (Feb 21) | **ZERO** compact-related entries |
| Last compact daemon start | 2026-02-20T12:48:07 (yesterday) |
| Last successful compaction | 2026-02-20T16:28:45 (worker-mention-routing) |

### Historical Activity (Feb 20)

The compact daemon DID run on Feb 20:

- **7 daemon starts** between 04:02 and 12:48 (restarts via monitor)
- **347 total compact-related log entries**
- Successfully compacted at least 2 agents:
  - `worker-at-mentions` at 16:18
  - `worker-mention-routing` at 16:28
- Many cycles skipped agents due to "no activity since last compaction" (correct behavior)
- `.compact-timestamps` file exists with 11 entries, all from Feb 20

### Root Cause: Monitor Not Restarted After Wiring

The compact daemon was **wired into monitor.sh** via commit `d210784` (today, Feb 21). The code is correct — `start_compact_daemon()` is called in Phase 6 of monitor startup and in the dashboard auto-restart path.

**However**: The currently running `monitor.sh` process was started on Feb 20 (before `d210784` was committed). Since `monitor.sh` is a long-running bash script, it's executing the OLD code from Feb 20 which does NOT include `start_compact_daemon()`. The new code has never been executed.

### Evidence of Compaction Pipeline Working (When Running)

When the daemon was active on Feb 20, it worked correctly:
- Detected idle agents
- Ran pre-compact hooks to save state
- Sent `/compact` command
- Verified compaction via pane output
- Injected recovery messages
- Tracked timestamps to avoid redundant compaction
- Skipped busy and inactive agents

### Impact

With 24 active tmux windows and no compaction since Feb 20, agents that have been active all day (perm-backend, perm-frontend, perm-infra, etc.) are accumulating context without any trimming. If any agent hits its context limit, it will become unresponsive.

### Recommended Fix

**Immediate**: Restart the monitor to pick up the new code:
```bash
# In the monitor tmux window, or:
tmux send-keys -t cmux:monitor C-c
sleep 2
tmux send-keys -t cmux:monitor "./src/orchestrator/monitor.sh" Enter
```

**Structural**: Add a version/hash check to monitor.sh so it can detect when its own code has changed and auto-restart:
```bash
# At top of main loop:
CURRENT_HASH=$(md5 -q "$0")
if [[ -n "${STARTUP_HASH:-}" && "$CURRENT_HASH" != "$STARTUP_HASH" ]]; then
    log_info "monitor.sh code changed, auto-restarting..."
    exec "$0" "$@"
fi
STARTUP_HASH="${STARTUP_HASH:-$CURRENT_HASH}"
```

This would also catch future daemon additions without manual restarts.

---

## Summary

| Investigation | Status | Severity |
|--------------|--------|----------|
| [DONE] commit verification | **82% include hashes, 97% verify** — good but not enforced | LOW — working in practice, could be enforced mechanically |
| Compact daemon | **NOT RUNNING** — dead since Feb 20, monitor needs restart | HIGH — agents accumulating unbounded context |

### Priority Actions

1. **HIGH**: Restart monitor.sh to activate compact daemon (or restart the whole system)
2. **MEDIUM**: Build the post-[DONE] commit verification hook
3. **LOW**: Add self-restart capability to monitor.sh when its code changes
