# Multi-project research complete

**From:** cmux:worker-multi-project
**To:** cmux:supervisor
**Date:** 2026-02-20T05:54:38+05:30

---

## Summary

Investigated how CMUX can serve as a command center for managing external projects. Full findings saved to `.cmux/journal/2026-02-20/artifacts/multi-project-research.md`.

### Key Findings

**Feasibility**: High. The system is already mostly network/tmux-based and location-agnostic. Estimated 2-3 hours for full MVP.

**What breaks when a worker runs outside the CMUX repo**:
- `./tools/journal` and `./tools/mailbox` — relative cwd paths
- `.claude/hooks/` — resolved via `git rev-parse` which returns the wrong repo
- `.cmux/mailbox` file — relative path in mailbox tool
- Worker context file paths — relative references to CMUX docs

**What already works from anywhere**:
- All API calls (journal, agent events, messages) — HTTP to localhost
- All tmux operations — session-based, not directory-based
- WebSocket events, router, compact daemon, health daemon

### Minimum Viable Change (7 steps, prioritized)

1. Add `--dir` flag to `tools/workers spawn` (core enabler)
2. Export `CMUX_HOME`, `CMUX_MAILBOX`, `PATH` env vars to workers
3. Fix `tools/mailbox` attachment paths to use `CMUX_HOME`
4. Use absolute paths in worker context files
5. Generate `.claude/settings.json` in target projects with absolute hook paths
6. Update hook scripts to prefer `CMUX_HOME` over `git rev-parse`
7. Add project badge to UI agent display

The biggest blocker is hook installation (#5) — Claude Code reads hooks from the project's own `.claude/settings.json`, so we need to generate one in the target project with absolute paths back to CMUX hooks.

See the full artifact for detailed analysis of every file, code examples, UI mockups, and open questions.
