# Permanent Worker Team — Critic Round 2: Convergence

## I accept the revised plan.

The defender addressed 15 of 18 points substantively and defended 3 convincingly. The revised proposal is significantly stronger than the original. Here's my evaluation of the remaining items.

---

## Evaluation of Defended Points

### Sentry is NOT a permanent worker — ACCEPT defense

I was wrong to conflate these. The sentry is an emergency responder spawned by monitor.sh on supervisor failure — it self-terminates once the supervisor recovers. It exists 1% of the time. A permanent worker exists 99% of the time. These are opposite lifecycle models. My question was useful for documentation purposes (the distinction should be written down), but the defender is correct that sentry should remain as-is.

### Start with 3 (include infra) — ACCEPT defense

The safety argument convinced me. My original objection was about utilization data (2 days is a small sample), but the defender reframed it as a risk argument: infra work has the highest blast radius because it touches the system's recovery mechanisms. A permanent infra worker that understands the coupling between health.sh, monitor.sh, router.sh, and compact.sh is a safety investment, not a utilization optimization. The 12% frequency is enough to keep it engaged, and even during low-infra periods, the knowledge preservation has value.

### Keep audit log — ACCEPT defense

The revised approach is clean: `--force` flag (simple, no reason argument) plus a 3-line silent audit log. Near-zero implementation cost, genuine operational value. This is reasonable.

---

## Evaluation of New Additions

### Pre-compact hook implementation — ACCEPT

The implementation is concrete, uses jq, captures the right state (terminal output, git status, current task from tasks.db). This fixes a real infrastructure gap that exists today. One note: the SQL query uses string interpolation (`WHERE assigned_to='${WINDOW}'`) which is fine for a bash script but should be noted as safe only because window names are sanitized during spawn.

### `workers reset` implementation — ACCEPT

The most important new addition. Key design decisions are sound:
- `/exit` first (graceful) → Ctrl+C fallback → restart in same window
- Task marked as `blocked` before reset, re-assigned after
- Registry counters updated atomically
- Reuses the pre-compact hook for state capture

The shell prompt detection (`grep -qE '^\$|^%|❯'`) is fragile — different shell configs have different prompts. But this is a pragmatic choice for now, and the Ctrl+C fallback covers the failure case.

### Cost analysis — ACCEPT

The honesty is appreciated: pure token math does NOT break even (~162K idle vs ~52K saved). The real justification is accumulated context value, which is qualitative. The quiet hours addition (`PERM_WORKER_QUIET_HOURS`) is a good optimization that brings the numbers closer to parity. This should be included in the initial deployment, not deferred.

### Proactive reset policy — ACCEPT

5 tasks or 3 hours, tracked in registry, checked by supervisor after each task completion and by monitor on time threshold. Deterministic, observable, no subjective judgment required. This is the right approach.

### cleanup_stale fix — ACCEPT

Skipping `permanent: true` entries in cleanup_stale prevents the race condition. Simple and correct.

### stop-gate.sh update — ACCEPT with minor note

The fix allows permanent workers to exit without commit/journal during reset. This is correct because the reset procedure handles state preservation independently. Minor note: the check `[[ "${CMUX_AGENT_NAME}" == perm-* ]]` should also check the registry flag (same pattern as the auto-maintenance fix), but the name-based fast path is fine as a first implementation.

### TASK-CANCEL and preemption — ACCEPT

The preemption policy (cancel low/medium for critical/high, queue same-priority) is sensible and simple enough for the supervisor to implement.

---

## Final Verdict Summary

| Section | Original Verdict | Final Verdict |
|---------|-----------------|---------------|
| 1. Permanent Roles | REVISE | **ACCEPT** (3 roles: frontend, backend, infra; tester ephemeral with template) |
| 2. Task Assignment Protocol | ACCEPT | **ACCEPT** (now with TASK-CANCEL and preemption) |
| 3. Context Reset Mechanism | REVISE | **ACCEPT** (compaction fix as prerequisite, full reset implementation, proactive policy) |
| 4. Perm + Ephemeral Coexistence | ACCEPT | **ACCEPT** |
| 5. Tooling and Code Changes | REVISE | **ACCEPT** (--permanent flag, full reset impl, cleanup_stale fix) |
| 6. Deletion Protection | REVISE | **ACCEPT** (--force + audit log, no retire command) |
| 7. Startup Sequence | ACCEPT | **ACCEPT** (with warning on missing role context) |
| 8. Implementation Priority | REVISE | **ACCEPT** (compaction fix as step 1, cost analysis included, rollback plan specified) |
| 9. Tradeoffs | ACCEPT | **ACCEPT** |

**All sections now at ACCEPT.** The revised plan is ready for synthesis into a final implementation plan.

---

## Remaining Recommendations (non-blocking)

These are suggestions for the synthesis phase, not blocking issues:

1. **Quiet hours should be in the initial deployment**, not deferred — the cost analysis depends on it
2. **The pre-compact hook should be implemented and tested BEFORE any permanent worker code** — it's the foundation
3. **Document the sentry vs permanent worker distinction** in a comment or doc somewhere — future developers will have the same question I did
4. **Consider a `workers status perm-frontend` enhancement** that shows task count, last reset time, and context health — helpful for supervisor decision-making
5. **The shell prompt detection regex in `workers reset` will need tuning** per environment — consider making it configurable or using a more robust detection method (e.g., check if the claude process is still running via `pgrep`)
