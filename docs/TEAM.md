# Team Architecture

> Living document. Updated whenever permanent workers are added, removed, or restructured.
> Last updated: 2026-02-21

## Overview

CMUX runs a **permanent worker team** — long-lived Claude Code agents that persist across tasks and context resets. Each worker has a fixed identity (name, personality, specialization) and receives work via the supervisor's task system.

The team is designed around the principle that **specialized, adversarial review produces better output than generalist workers**. Builders build, reviewers break — and they're different agents.

## Current Roster

### Builders (3)

| Name | Agent ID | Specialization | Personality | Role File |
|------|----------|---------------|-------------|-----------|
| **Mira** | `perm-frontend` | Frontend / UI — React, TypeScript, Zustand, Tailwind | Meticulous, pixel-perfect, strong aesthetic opinions | `.cmux/worker-contexts/perm-frontend-role.md` |
| **Kai** | `perm-backend` | Backend / API — FastAPI, SQLite, WebSocket, Python | Calm, methodical, thinks in data flows and edge cases | `.cmux/worker-contexts/perm-backend-role.md` |
| **Sol** | `perm-infra` | Infrastructure — shell scripts, tmux, orchestration, health | Cautious, safety-first, thinks about failure modes first | `.cmux/worker-contexts/perm-infra-role.md` |

### Reviewers (2)

| Name | Agent ID | Specialization | Personality | Role File |
|------|----------|---------------|-------------|-----------|
| **Sage** | `perm-ui-review` | Frontend/UI review (adversarial) — visual correctness, a11y, responsive, dark mode | Constructively critical, sharp eye for inconsistency | `.cmux/worker-contexts/perm-ui-review-role.md` |
| **Flint** | `perm-api-review` | Backend/API review (adversarial) — security, validation, race conditions, error handling | Sharp, thorough, assumes if it can break it will | `.cmux/worker-contexts/perm-api-review-role.md` |

### Support (3)

| Name | Agent ID | Specialization | Personality | Role File |
|------|----------|---------------|-------------|-----------|
| **Nova** | `perm-research` | Research — web search, link following, documentation, synthesis | Relentlessly curious, follows threads to their end | `.cmux/worker-contexts/perm-research-role.md` |
| **Bolt** | `perm-devops` | DevOps — CI/CD, automation, git hooks, build pipelines, scripts | Fast, pragmatic, hates manual steps | `.cmux/worker-contexts/perm-devops-role.md` |
| **Echo** | `perm-qa` | QA — pytest, typecheck, browser testing, integration testing | Methodical, relentless, finds the scenarios nobody thought of | `.cmux/worker-contexts/perm-qa-role.md` |

## Team Topology

```
                    ┌──────────────┐
                    │  Supervisor   │
                    └──────┬───────┘
                           │
          ┌────────────────┼────────────────┐
          │                │                │
    ┌─────┴─────┐   ┌─────┴─────┐   ┌─────┴─────┐
    │  Builders  │   │ Reviewers  │   │  Support   │
    ├───────────┤   ├───────────┤   ├───────────┤
    │ Mira (FE) │   │ Sage (UI) │   │ Nova (Res) │
    │ Kai  (BE) │   │ Flint(API)│   │ Bolt (Ops) │
    │ Sol  (Inf)│   │           │   │ Echo (QA)  │
    └───────────┘   └───────────┘   └───────────┘
```

## How It Works

### Lifecycle

All permanent workers are spawned with `--permanent` flag:
```bash
./tools/workers spawn perm-frontend "..." --permanent .cmux/worker-contexts/perm-frontend-role.md
```

This gives them:
- **Deletion protection** — `workers kill` requires `--force` and logs an audit entry
- **Context reset** — `workers reset <name>` gracefully restarts without losing identity
- **Proactive reset policy** — reset after 5 completed tasks or 3 hours (whichever first)
- **Cleanup immunity** — `auto-maintenance` and `cleanup_stale` skip permanent workers

### Task Assignment

```bash
# Create a task, then assign it
./tools/tasks create "Fix the login bug" --assign perm-backend

# Or assign an existing task
./tools/workers assign <task-id> perm-backend
```

Workers receive `[TASK]` messages via the mailbox/router pipeline and report back with `[DONE]`, `[STATUS]`, or `[BLOCKED]`.

### Review Workflow

For code changes, the supervisor routes through the adversarial review layer:

1. Builder (Mira/Kai/Sol) implements the change
2. Reviewer (Sage for frontend, Flint for backend) reviews with structured severity ratings
3. Reviewer gives verdict: **APPROVE** / **REVISE** / **BLOCK**
4. If REVISE: builder addresses feedback, reviewer re-reviews
5. QA (Echo) runs test suite and browser verification

Sage and Echo use Chrome MCP tools for browser-based visual testing — they navigate to `http://localhost:8000`, take screenshots, test interactions, and verify dark mode / responsive behavior.

### Communication

Workers communicate via the mailbox system:
- **Inbound**: `[TASK]`, `[UPDATE]`, `[QUESTION]`, `[PRIORITY]`, `[COMPLETE]`
- **Outbound**: `[STATUS]`, `[DONE]`, `[BLOCKED]`, `[QUESTION]`

Between tasks, workers idle and respond to heartbeat nudges with `[SYS] Idle — awaiting task.`

## Design Rationale

This team structure emerged from an adversarial debate (see `.cmux/journal/2026-02-21/artifacts/04-critic-convergence.md`). Key decisions:

1. **Separate builders and reviewers** — builders should never review their own output. Adversarial review catches what the author misses.
2. **Frontend/backend split in review** — UI review requires visual browser testing (Chrome MCP); API review requires tracing data flows and security analysis. Different skills, different tools.
3. **Permanent over ephemeral for core roles** — the cost of context loading (reading CLAUDE.md, role files, codebase orientation) on every spawn is significant. Permanent workers amortize this cost across many tasks.
4. **Tester as permanent, not ephemeral** — QA benefits from accumulated knowledge of what breaks and where the gaps are. Echo remembers previous test runs (until context reset).
5. **Research as dedicated role** — following links, synthesizing information, and saving artifacts is a distinct workflow that shouldn't interrupt builders.

## Ephemeral Workers

Not everything needs a permanent worker. The supervisor still spawns ephemeral workers for:
- One-off tasks outside any permanent worker's domain
- Parallel execution when permanent workers are busy
- Debate pairs for architectural decisions (see `docs/templates/teams/DEBATE_PAIR.md`)

Ephemeral workers use templates from `docs/templates/roles/` and are killed after task completion.

## Modifying This Document

When adding or removing permanent workers:
1. Create/remove the role context file in `.cmux/worker-contexts/`
2. Spawn/kill the worker with `--permanent` / `--force`
3. Update the roster table and topology diagram above
4. Commit this file with the change
