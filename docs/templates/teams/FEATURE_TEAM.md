# Feature Team with Tech Lead

A hierarchical team where a Tech Lead makes technical decisions and workers implement.

## When to Use

- Features requiring strong technical direction
- When architectural decisions need a single authority
- Complex implementations needing design oversight
- When you want technical review before merging

## Org Chart

```
         ┌─────────────┐
         │ Supervisor  │ ← Owns outcome
         └──────┬──────┘
                │
         ┌──────▼──────┐
         │  Tech Lead  │ ← Makes technical decisions
         └──────┬──────┘
                │
    ┌───────────┼───────────┐
    │           │           │
┌───▼───┐  ┌────▼────┐  ┌───▼───┐
│Worker │  │ Worker  │  │Worker │
│   A   │  │    B    │  │   C   │
└───────┘  └─────────┘  └───────┘
```

## Roles

| Role | Reports To | Responsibility |
|------|------------|----------------|
| Supervisor | User | Outcome owner, delegates to Tech Lead |
| Tech Lead | Supervisor | Technical decisions, code review, worker coordination |
| Workers | Tech Lead | Implementation |

## Communication Graph

```
    Supervisor
        ▲
        │ (progress, blockers, completion)
        │
    Tech Lead
    ▲   ▲   ▲
    │   │   │
    │   │   │ (tasks, reviews, approvals)
    ▼   ▼   ▼
Worker A  Worker B  Worker C
    └───────┴───────┘
     (no direct peer
      communication)
```

**Key difference from Squad Model**: Workers do NOT coordinate directly. All communication goes through Tech Lead.

## Decision Authority

| Decision Type | Who Decides |
|---------------|-------------|
| Task breakdown | Tech Lead |
| Technical approach | Tech Lead |
| Code approval | Tech Lead reviews all changes |
| Architecture changes | Tech Lead (may consult Supervisor) |
| Done decision | Tech Lead → Supervisor approves |

## Handoff Protocols

### Tech Lead → Workers
```bash
./tools/workers send "worker-a-XXXX" "[TASK] Implement the database schema per spec. Do not proceed to API until I review."
```

### Workers → Tech Lead
```bash
./tools/mailbox send tech-lead "Schema Complete" "
Created tables: users, sessions, tokens
Files: src/server/models/auth.py
Ready for review before proceeding.
"
```

### Tech Lead → Supervisor
```bash
./tools/mailbox send supervisor "[DONE] Auth feature complete" "
Reviewed: All worker implementations
Tests: Passing
Architecture: Clean, follows patterns
Ready for final approval.
"
```

## Spawning Commands

```bash
# Supervisor spawns tech lead
./tools/workers spawn "tech-lead" "Read docs/templates/roles/TECH_LEAD.md. Your task: [FEATURE]. You own technical decisions. Spawn workers as needed."

# Tech lead spawns workers
./tools/workers spawn "worker-schema" "Your task: [SPECIFIC TASK]. Report to me when complete. Do not proceed without my review."
./tools/workers spawn "worker-api" "Your task: [SPECIFIC TASK]. Wait for schema worker to complete."
```

## When NOT to Use

- Simple tasks (use solo worker)
- When speed matters more than oversight (use Tiger Team)
- When design is unclear (use Debate first)
