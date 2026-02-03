# Journal - 2026-02-03

## 08:22 - Session Summary: Core Templates + Message Passing Issues
## What was done

1. **Investigated lost workers** - orch-team's server kill fix testing killed all tmux sessions
2. **Continued core-team work** - spawned core-implementer to extract templates from plan
3. **Implementation complete** - 20 files created (7 team templates, 10 role templates, 2 READMEs, supervisor guide update)
4. **Critic review** - core-critic reviewed and approved with 2 minor fixes
5. **Fixes applied** - FEATURE_TEAM.md updated per critic feedback

## Commits
- 2e6af54: feat: add comprehensive team and role templates
- 7f1729b: fix: add role template references to FEATURE_TEAM.md
- 97f606f: docs: add journal entries from multi-team debate

## Issues Discovered

Six message passing issues documented in attachments/message-passing-issues.md:
1. Text stuck in input buffers after multiline paste
2. Messages not reaching workers when session not in foreground
3. Worker ignored received task (needed follow-up message)
4. Duplicate/repeated messages
5. Session cleanup killing all workers
6. Router vs direct messaging confusion

## Next Steps

Investigate and fix message passing issues
