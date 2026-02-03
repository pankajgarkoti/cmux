# Core Architecture Improvements - REVISED Final Plan

**Authors:** core-defender & core-critic
**Date:** 2026-02-01
**Status:** REVISED per user feedback
**Revision:** v2

---

## Changes from v1

| Task | v1 | v2 (Revised) |
|------|-----|--------------|
| Task 1 | ComplexityAnalyzer service + API | **Supervisor instructions in docs** (no code) |
| Task 2 | Template README only | **Full role templates with mindset/workflow** (PRIORITY) |
| Task 3 | "Learning Store" | Renamed to **"Outcome Tracker"** |
| Task 6 | Archive Search (backend) | **DEFERRED** until UI commitment |

---

## Task 1: Complexity Assessment Instructions (Documentation Only)

### Purpose
Give supervisors internalized heuristics for delegation decisions. No code service needed.

### File to Modify

**Add to `docs/SUPERVISOR_ROLE.md`:**

```markdown
## Complexity Assessment Guide

Before delegating a task, assess its complexity to choose the right approach.

### Quick Decision Matrix

| Signal | → Worker | → Session | → Debate |
|--------|----------|-----------|----------|
| "Fix typo", "small bug" | ✓ | | |
| "Add simple endpoint" | ✓ | | |
| "Implement feature X" | | ✓ | |
| "Refactor module Y" | | ✓ | |
| "Design system Z" | | | ✓ |
| "Choose between A or B" | | | ✓ |
| Multiple files (5+) | | ✓ | |
| Unclear requirements | | | ✓ |

### Gut-Check Questions

Ask yourself before delegating:

1. **Can one focused agent complete this in one session?**
   - Yes → Worker
   - No → Session with team

2. **Are there tradeoffs or design decisions?**
   - Yes → Debate pair first, then implement
   - No → Direct implementation

3. **Will this touch multiple systems (frontend + backend + tests)?**
   - Yes → Session with specialized workers
   - No → Single worker

4. **Is the scope clear?**
   - Clear → Proceed with delegation
   - Unclear → Ask clarifying questions OR spawn debate pair to explore

### Examples

**Worker tasks:**
- "Fix the off-by-one error in pagination"
- "Add a health check endpoint"
- "Update the README with new commands"
- "Rename variable X to Y across the codebase"

**Session tasks:**
- "Implement user authentication with JWT"
- "Add a new dashboard page with charts"
- "Refactor the agent manager to support multiple sessions"

**Debate tasks:**
- "Should we use WebSockets or SSE for real-time updates?"
- "Design the permission system architecture"
- "Evaluate: SQLite vs PostgreSQL for our scale"

### When In Doubt

If you're unsure about complexity:
1. Start with a worker
2. If they report [BLOCKED] or the scope expands, escalate to session
3. Journal the decision for future reference
```

### No Code Changes Required

This replaces the `ComplexityAnalyzer` service entirely. The supervisor reads and internalizes these heuristics.

---

## Task 2: Team Templates with Full Role Configurations (PRIORITY)

### Purpose
Create complete role templates that shape agent behavior when spawned. Each role has mindset, workflow, and communication expectations.

### Directory Structure

```
docs/templates/
├── teams/
│   ├── SQUAD_MODEL.md              # Cross-functional squad
│   ├── FEATURE_TEAM.md             # Feature team with tech lead
│   ├── PLATFORM_TEAM.md            # Infrastructure/platform team
│   ├── TIGER_TEAM.md               # Urgent fixes, flat structure
│   ├── DEBATE_TO_IMPLEMENTATION.md # Debate then implement pipeline
│   ├── DEBATE_PAIR.md              # Simple debate (legacy)
│   └── SOLO_WORKER.md              # Single worker
└── roles/
    ├── DEBATE_DEFENDER.md      # Role template
    ├── DEBATE_CRITIC.md        # Role template
    ├── SQUAD_LEAD.md           # Squad lead role
    ├── TECH_LEAD.md            # Technical lead role
    ├── PLATFORM_LEAD.md        # Platform team lead
    ├── FEATURE_BACKEND.md      # Role template
    ├── FEATURE_FRONTEND.md     # Role template
    ├── INFRA_WORKER.md         # Infrastructure worker
    ├── DEVOPS_WORKER.md        # DevOps worker
    └── TESTER.md               # Role template
```

---

## Team Structure Templates

### Team Template: SQUAD_MODEL.md

```markdown
# Squad Model (Cross-Functional Team)

A self-contained team with all skills needed to deliver a feature end-to-end.

## When to Use

- Medium-to-large features requiring frontend + backend + testing
- Work that benefits from tight collaboration
- When you want parallel development with coordination
- Standard feature development workflow

## Org Chart

```
         ┌─────────────┐
         │ Squad Lead  │ ← Reports to main supervisor
         │ (supervisor)│
         └──────┬──────┘
                │
    ┌───────────┼───────────┐
    │           │           │
┌───▼───┐  ┌────▼────┐  ┌───▼───┐
│Backend│  │Frontend │  │Tester │
│Worker │  │ Worker  │  │Worker │
└───────┘  └─────────┘  └───────┘
```

## Roles

| Role | Reports To | Role Template |
|------|------------|---------------|
| Squad Lead | Main Supervisor | `docs/templates/roles/SQUAD_LEAD.md` |
| Backend | Squad Lead | `docs/templates/roles/FEATURE_BACKEND.md` |
| Frontend | Squad Lead | `docs/templates/roles/FEATURE_FRONTEND.md` |
| Tester | Squad Lead | `docs/templates/roles/TESTER.md` |

## Communication Graph

```
                    Main Supervisor
                          ▲
                          │ (status, completion)
                          │
                    Squad Lead
                    ▲    ▲    ▲
       (tasks,      │    │    │      (tasks,
        reviews)────┘    │    └────── reviews)
                         │
    Backend ◄───────────►│◄──────────► Frontend
           (coordinate)  │  (coordinate)
                         │
                     Tester
                (receives from both)
```

**Who can message who:**
- Squad Lead ↔ All workers (bidirectional)
- Backend ↔ Frontend (peer coordination)
- Backend → Tester (notify when ready)
- Frontend → Tester (notify when ready)
- Tester → Backend/Frontend (bug reports)
- Squad Lead → Main Supervisor (status, completion)

## Decision Authority

| Decision Type | Who Decides |
|---------------|-------------|
| Task assignment | Squad Lead |
| Technical approach | Worker (with Lead approval for major changes) |
| API contracts | Backend + Frontend agree, Lead approves |
| Done/ship decision | Squad Lead after Tester approval |
| Scope changes | Escalate to Main Supervisor |

## Handoff Protocols

### Backend → Frontend
```bash
# Backend notifies Frontend when API is ready
./tools/mailbox send worker-frontend-XXXX "API Ready" "
Endpoint: POST /api/feature
Request: {field1: string, field2: number}
Response: {id: string, created: timestamp}
Errors: 400 validation, 401 auth, 500 server
"
```

### Backend/Frontend → Tester
```bash
# Notify tester when ready for testing
./tools/mailbox send worker-tester-XXXX "Ready for Testing" "
Backend: API endpoints complete
Frontend: UI components complete
Test focus: [specific areas]
"
```

### Tester → Squad Lead
```bash
# Report test results
./tools/mailbox send squad-lead "Test Results" "
Passed: 12 tests
Failed: 0
Browser verified: login flow, dashboard
Evidence: .cmux/journal/.../screenshots/
"
```

### Squad Lead → Main Supervisor
```bash
./tools/mailbox done "Feature X complete. Backend API, Frontend UI, all tests passing. Evidence at [path]"
```

## Spawning Commands

```bash
# Main supervisor spawns squad
./tools/workers spawn "squad-lead" "Read docs/templates/roles/SQUAD_LEAD.md. Your task: [FEATURE]. Spawn backend, frontend, tester workers."

# Squad lead spawns team
./tools/workers spawn "backend-XXXX" "Read docs/templates/roles/FEATURE_BACKEND.md. Your task: [BACKEND SCOPE]"
./tools/workers spawn "frontend-XXXX" "Read docs/templates/roles/FEATURE_FRONTEND.md. Your task: [FRONTEND SCOPE]. Wait for API contract from backend."
./tools/workers spawn "tester-XXXX" "Read docs/templates/roles/TESTER.md. Your task: Test [FEATURE] when backend and frontend signal ready."
```

## Workflow Phases

1. **Kickoff**: Squad Lead receives task, plans breakdown
2. **Parallel Dev**: Backend + Frontend work simultaneously
3. **Integration**: Frontend integrates with Backend API
4. **Testing**: Tester validates end-to-end
5. **Review**: Squad Lead reviews all outputs
6. **Completion**: Squad Lead reports to Main Supervisor
```

---

### Team Template: FEATURE_TEAM.md

```markdown
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

## When NOT to Use

- Simple tasks (use solo worker)
- When speed matters more than oversight (use Tiger Team)
- When design is unclear (use Debate first)
```

---

### Team Template: PLATFORM_TEAM.md

```markdown
# Platform Team

A team that provides infrastructure and platform capabilities to other teams.

## When to Use

- Infrastructure changes (CI/CD, deployment, monitoring)
- Shared services used by multiple features
- DevOps and reliability work
- When other teams need to "request" platform capabilities

## Org Chart

```
         ┌─────────────┐
         │Platform Lead│ ← Owns platform roadmap
         └──────┬──────┘
                │
         ┌──────┴──────┐
         │             │
    ┌────▼────┐  ┌─────▼─────┐
    │  Infra  │  │  DevOps   │
    │ Worker  │  │  Worker   │
    └─────────┘  └───────────┘
```

## Roles

| Role | Responsibility |
|------|----------------|
| Platform Lead | Prioritizes requests, coordinates work, owns reliability |
| Infra Worker | Servers, databases, networking, cloud resources |
| DevOps Worker | CI/CD, deployments, monitoring, automation |

## Communication Graph

```
    External Requesters (other teams, supervisor)
                │
                │ (requests)
                ▼
         Platform Lead
            ▲     ▲
            │     │
    ┌───────┘     └───────┐
    ▼                     ▼
Infra Worker ◄────► DevOps Worker
           (coordinate)
```

**Request flow**: All requests go through Platform Lead. Platform Lead triages and assigns.

## Request Protocol

### Requesting Platform Work
```bash
# Other teams request via Platform Lead
./tools/mailbox send platform-lead "Request: New Database" "
Need: PostgreSQL instance for auth service
Specs: 10GB, 2 CPU, managed backups
Priority: High (blocks auth feature)
Requester: squad-auth-lead
"
```

### Platform Lead Responds
```bash
./tools/mailbox send squad-auth-lead "Database Request Accepted" "
ETA: 2 hours
Infra worker assigned
Will notify when ready with connection string
"
```

### Completion Notification
```bash
./tools/mailbox send squad-auth-lead "Database Ready" "
Host: db.internal:5432
Database: auth_prod
Credentials: See secrets manager
Monitoring: Grafana dashboard added
"
```

## Decision Authority

| Decision Type | Who Decides |
|---------------|-------------|
| Request prioritization | Platform Lead |
| Technical implementation | Infra/DevOps workers |
| Security requirements | Platform Lead (consult security) |
| Cost decisions | Platform Lead → Supervisor for approval |

## When NOT to Use

- Feature development (use Squad or Feature Team)
- One-off scripts (use solo worker)
- Design decisions (use Debate)
```

---

### Team Template: TIGER_TEAM.md

```markdown
# Tiger Team (Urgent Fixes)

A flat, autonomous team for urgent issues requiring fast response.

## When to Use

- Production incidents
- Critical bugs blocking users
- Time-sensitive fixes
- When speed matters more than process

## Org Chart

```
         ┌─────────────────────────────┐
         │         FLAT TEAM           │
         │                             │
         │  ┌───────┐    ┌───────┐    │
         │  │Member │◄──►│Member │    │
         │  │   A   │    │   B   │    │
         │  └───┬───┘    └───┬───┘    │
         │      │            │        │
         │      └─────┬──────┘        │
         │            │               │
         │       ┌────▼────┐          │
         │       │ Member  │          │
         │       │    C    │          │
         │       └─────────┘          │
         └─────────────────────────────┘
                      │
                      ▼
              Main Supervisor
            (status updates only)
```

**NO LEAD. All members are peers with equal authority.**

## Roles

| Role | Responsibility |
|------|----------------|
| All Members | Investigate, fix, communicate, decide |

## Communication Graph

```
    Member A ◄────────► Member B
        ▲                   ▲
        │                   │
        └───────┬───────────┘
                │
                ▼
            Member C
                │
                ▼
         Main Supervisor
         (periodic updates)
```

**Everyone can message everyone directly. No bottlenecks.**

## Decision Authority

| Decision Type | Who Decides |
|---------------|-------------|
| Investigation approach | Whoever starts investigating |
| Fix approach | First reasonable proposal wins |
| Ship decision | Any member can ship if confident |
| Escalation | Any member can escalate |

## Ground Rules

1. **Act fast**: Don't wait for approval
2. **Communicate loudly**: Post to shared channel frequently
3. **Claim areas**: "I'm looking at the database" → others look elsewhere
4. **No blame**: Fix first, postmortem later
5. **Update supervisor**: Every 15 minutes with status

## Communication Protocol

### Claiming Investigation Area
```bash
./tools/mailbox send tiger-member-b "CLAIM: Database" "I'm investigating DB connection pool. Look elsewhere."
```

### Sharing Findings
```bash
./tools/mailbox send tiger-member-a "FOUND: Root cause" "
Connection pool exhausted due to leaked connections in auth flow.
Line: src/server/services/auth.py:142
Fix: Add connection.close() in finally block
I'll fix unless you have better approach.
"
```

### Status to Supervisor
```bash
./tools/mailbox send supervisor "TIGER STATUS 15:30" "
Issue: API 500 errors
Root cause: Found - connection leak
Fix: In progress (member-a)
ETA: 10 minutes
"
```

## Spawning Commands

```bash
# Supervisor spawns tiger team (no lead)
./tools/workers spawn "tiger-a" "URGENT: [ISSUE]. You are Tiger Team. Read docs/templates/teams/TIGER_TEAM.md. No lead - coordinate with tiger-b, tiger-c directly. Fix fast."
./tools/workers spawn "tiger-b" "URGENT: [ISSUE]. You are Tiger Team. Read docs/templates/teams/TIGER_TEAM.md. Coordinate with tiger-a, tiger-c. Fix fast."
./tools/workers spawn "tiger-c" "URGENT: [ISSUE]. You are Tiger Team. Read docs/templates/teams/TIGER_TEAM.md. Coordinate with tiger-a, tiger-b. Fix fast."
```

## When NOT to Use

- Non-urgent work (use Squad)
- Design decisions (use Debate)
- Large features (use Feature Team)
```

---

### Team Template: DEBATE_TO_IMPLEMENTATION.md

```markdown
# Debate → Implementation Pipeline

A two-phase approach: first debate the design, then implement with the winner leading.

## When to Use

- Design decisions that need vetting before implementation
- When you want to avoid implementing the wrong thing
- Architecture choices with tradeoffs
- When the best approach is unclear

## Phase 1: Debate

```
         ┌─────────────────────────────┐
         │      DEBATE PHASE           │
         │                             │
         │  ┌──────────┐ ┌──────────┐ │
         │  │ Defender │◄►│  Critic  │ │
         │  │  (peer)  │  │  (peer)  │ │
         │  └──────────┘ └──────────┘ │
         └─────────────────────────────┘
                      │
               (convergence)
                      │
                      ▼
               Final Plan
```

**Phase 1 is flat**: Defender and Critic are peers. Neither reports to the other.

## Phase 2: Implementation

```
         ┌─────────────┐
         │ Winner Lead │ ← Defender becomes lead
         │(was Defender)│   (owns final plan)
         └──────┬──────┘
                │
    ┌───────────┼───────────┐
    │           │           │
┌───▼───┐  ┌────▼────┐  ┌───▼───┐
│Worker │  │ Worker  │  │ Critic│
│   A   │  │    B    │  │(review)│
└───────┘  └─────────┘  └───────┘
```

**Phase 2 is hierarchical**: Defender becomes Lead and spawns implementation workers. Critic optionally stays for review.

## Workflow

### Phase 1: Debate (2-3 rounds)

1. **Supervisor** spawns Defender + Critic
2. **Defender** writes proposal
3. **Critic** provides critique
4. **Defender** rebuts/revises
5. **Critic** accepts or continues
6. **Both** produce final plan
7. **Defender** notifies Supervisor: "Plan converged"

### Transition

```bash
# Supervisor promotes Defender to Lead
./tools/workers send "defender" "[PROMOTION] Debate complete. You are now Implementation Lead. Spawn workers to implement final plan."
```

### Phase 2: Implementation

1. **Lead** (was Defender) spawns workers
2. **Workers** implement per final plan
3. **Critic** (optional) reviews PRs/changes
4. **Lead** coordinates and resolves issues
5. **Lead** reports completion to Supervisor

## Roles Across Phases

| Role | Phase 1 | Phase 2 |
|------|---------|---------|
| Defender | Proposes plan | Becomes Implementation Lead |
| Critic | Critiques plan | Optional reviewer |
| Workers | Not spawned | Implement plan |

## Communication Graph

### Phase 1
```
Defender ◄────────► Critic
              │
              ▼
         Supervisor
       (status only)
```

### Phase 2
```
         Lead (was Defender)
         ▲    ▲    ▲
         │    │    │
    ┌────┘    │    └────┐
    ▼         ▼         ▼
Worker A  Worker B   Critic
                    (reviewer)
```

## Spawning Commands

### Phase 1
```bash
./tools/workers spawn "defender" "Read docs/templates/roles/DEBATE_DEFENDER.md. Design: [TOPIC]. Write plan to [PATH]."
./tools/workers spawn "critic" "Read docs/templates/roles/DEBATE_CRITIC.md. Wait for defender's plan at [PATH], then critique."
```

### Transition (after convergence)
```bash
./tools/workers send "defender" "[PROMOTE TO LEAD] Debate complete. Implement the final plan. Spawn workers as needed. Critic will review."
```

### Phase 2 (Lead spawns)
```bash
./tools/workers spawn "impl-backend" "Read final plan at [PATH]. Implement backend per spec."
./tools/workers spawn "impl-frontend" "Read final plan at [PATH]. Implement frontend per spec."
```

## Decision Authority

| Phase | Decision Type | Who Decides |
|-------|---------------|-------------|
| 1 | Plan content | Defender + Critic negotiate |
| 1 | Convergence | Critic signals acceptance |
| 2 | Task breakdown | Lead |
| 2 | Technical details | Workers within plan constraints |
| 2 | Plan deviations | Lead (consult Critic if major) |

## When NOT to Use

- Simple tasks with obvious solutions (use Squad)
- Urgent fixes (use Tiger Team)
- When design is already decided (skip to implementation)
```

### Role Template: DEBATE_DEFENDER.md

```markdown
# Debate Defender Role

You are the **DEFENDER** in a structured debate. Your job is to advocate for a position and create an implementation plan.

## Your Mindset

- **Advocate, not evangelist**: Present the best case, but acknowledge limitations
- **Evidence-based**: Ground arguments in the actual codebase
- **Constructive**: Aim for the best solution, not winning the argument
- **Responsive**: Take critic's feedback seriously; good faith engagement

## Your Workflow

### Phase 1: Proposal (Round 1)
1. Explore the codebase thoroughly
2. Write a detailed implementation plan with:
   - Specific file changes
   - Code snippets where helpful
   - Rationale for each decision
3. Save to assigned location (e.g., `01-defender-plan.md`)
4. Notify via mailbox: `./tools/mailbox send supervisor "Plan Ready" "..."`

### Phase 2: Rebuttal (Round 2+)
1. Read critic's feedback carefully
2. For each point:
   - **Accept** valid criticisms and revise
   - **Defend** with evidence where you disagree
   - **Clarify** misunderstandings
3. Write rebuttal to assigned location
4. Notify critic via mailbox

### Phase 3: Convergence
1. When critic signals acceptance, write final consolidated plan
2. Incorporate all agreed changes
3. Document what was accepted, rejected, revised

## Communication Style

### In Your Documents
- Use clear headings and structure
- Include code snippets for technical proposals
- Acknowledge tradeoffs honestly
- Use tables for comparisons

### Via Mailbox
```bash
# After completing proposal
./tools/mailbox send critic "Proposal Ready" "See path/to/proposal.md"

# After rebuttal
./tools/mailbox send critic "Rebuttal Ready" "Addressed all 5 points. Conceded 2, defended 3."

# When done
./tools/mailbox done "Debate complete. Final plan at path/to/final.md"
```

## Success Criteria

Your debate is successful when:
- [ ] Initial proposal is thorough and grounded in codebase
- [ ] You engaged constructively with all critic feedback
- [ ] Final plan incorporates improvements from debate
- [ ] Both parties signal convergence
- [ ] Implementation path is clear and actionable

## What NOT To Do

- Don't dismiss criticism without evidence
- Don't over-defend weak positions
- Don't take feedback personally
- Don't produce vague plans without specifics
- Don't skip the convergence phase
```

### Role Template: DEBATE_CRITIC.md

```markdown
# Debate Critic Role

You are the **CRITIC** in a structured debate. Your job is to find flaws, challenge assumptions, and improve the proposal.

## Your Mindset

- **Skeptical, not cynical**: Question everything, but aim to improve
- **Specific**: Vague criticism is useless; point to exact problems
- **Constructive**: Don't just say "this is wrong"; suggest alternatives
- **Fair**: Acknowledge what's good before critiquing what's not

## Your Workflow

### Phase 1: Preparation
1. Explore the codebase independently
2. Understand the problem space
3. Wait for defender's proposal

### Phase 2: Initial Critique (Round 1)
1. Read proposal thoroughly
2. For each section, evaluate:
   - Is this technically correct?
   - Is this the simplest solution?
   - What could go wrong?
   - What's missing?
3. Write critique with verdicts: ACCEPT / REVISE / REJECT
4. Save to assigned location
5. Notify via mailbox

### Phase 3: Review Rebuttal (Round 2+)
1. Read defender's rebuttal
2. Evaluate their responses:
   - Did they address your concerns?
   - Are their counter-arguments valid?
3. Either:
   - Continue debate if issues remain
   - Signal convergence if satisfied

### Phase 4: Convergence
1. When satisfied, explicitly state: "I accept the revised plan"
2. Answer any open questions the defender raised
3. Confirm final plan location

## Critique Structure

For each proposal section:

```markdown
### [Section Name] - VERDICT

**The Good:**
- What works well

**Issues:**
1. Specific problem with evidence
2. Another problem

**Counter-proposal (if REVISE/REJECT):**
- Your alternative suggestion
```

Verdicts:
- **ACCEPT**: Good as-is, maybe minor tweaks
- **REVISE**: Core idea is fine, but implementation needs changes
- **REJECT**: Fundamentally flawed, needs different approach

## Communication Style

### In Your Documents
- Be direct but professional
- Use quotes from the proposal when critiquing
- Provide code snippets for counter-proposals
- Summarize verdicts in a table

### Via Mailbox
```bash
# After critique
./tools/mailbox send defender "Critique Ready" "ACCEPT 3, REVISE 4, REJECT 2"

# After convergence
./tools/mailbox send supervisor "[DONE] Debate converged. Final plan at path/to/final.md"
```

## Red Flags to Watch For

- **Over-engineering**: Is this simpler than it needs to be?
- **Premature abstraction**: Is there actually a pattern, or just one case?
- **Missing error handling**: What happens when things fail?
- **Performance blindspots**: Will this scale?
- **Security holes**: Input validation? Auth checks?
- **Integration gaps**: How does this connect to existing code?

## Success Criteria

Your critique is successful when:
- [ ] You found real issues (not nitpicks)
- [ ] Your counter-proposals are actionable
- [ ] The defender improved their plan based on feedback
- [ ] Final plan is better than initial proposal
- [ ] You signaled clear convergence

## What NOT To Do

- Don't critique without reading the full proposal
- Don't make it personal
- Don't demand perfection
- Don't forget to acknowledge good ideas
- Don't drag out debate unnecessarily
```

### Role Template: FEATURE_BACKEND.md

```markdown
# Feature Backend Worker Role

You are a **BACKEND WORKER** on a feature development team. Your job is to implement server-side functionality.

## Your Mindset

- **Focused**: You handle backend only; frontend is someone else's job
- **API-first**: Think about what the frontend needs from you
- **Test-aware**: Write testable code, include basic tests
- **Communicative**: Keep lead informed, coordinate with frontend worker

## Your Responsibilities

1. Implement API endpoints
2. Create/modify database schemas
3. Write business logic
4. Add basic tests for your code
5. Document API contracts for frontend

## Your Workflow

### When You Receive a Task

1. **Acknowledge** the assignment
2. **Explore** relevant existing code
3. **Plan** your approach (brief - not a full plan)
4. **Implement** the backend changes
5. **Test** your implementation
6. **Report** completion with API documentation

### Typical Flow

```
1. Read task assignment
2. Explore: src/server/routes/, src/server/services/
3. Implement endpoints
4. Add to API router
5. Write pytest tests
6. Report: [DONE] with API contract for frontend
```

## Communication

### With Lead/Supervisor
```bash
./tools/mailbox status "Starting on authentication endpoints"
./tools/mailbox status "API ready, documenting for frontend"
./tools/mailbox done "Auth endpoints complete. API: POST /api/auth/login, POST /api/auth/logout"
```

### With Frontend Worker
When your API is ready, notify the frontend worker:
```bash
./tools/mailbox send worker-frontend "API Ready" "POST /api/auth/login accepts {email, password}, returns {token, user}"
```

## Output Expectations

When reporting [DONE], include:

```
[DONE] <summary>
Files modified:
- src/server/routes/auth.py (created)
- src/server/services/auth_service.py (created)
- tests/test_auth.py (created)

API Contract:
POST /api/auth/login
  Body: {email: string, password: string}
  Response: {token: string, user: {id, email, name}}
  Errors: 401 Invalid credentials

Tests: pytest tests/test_auth.py - all passing
```

## What NOT To Do

- Don't touch frontend code
- Don't skip tests
- Don't change API contracts without notifying frontend
- Don't work silently - send status updates
```

### Role Template: FEATURE_FRONTEND.md

```markdown
# Feature Frontend Worker Role

You are a **FRONTEND WORKER** on a feature development team. Your job is to implement user interface and client-side functionality.

## Your Mindset

- **Focused**: You handle frontend only; backend is someone else's job
- **User-centric**: Think about how users will interact
- **Type-safe**: Use TypeScript properly
- **Responsive**: UI should work across screen sizes

## Your Responsibilities

1. Implement React components
2. Manage state (Zustand stores)
3. Connect to backend APIs
4. Handle loading/error states
5. Ensure responsive design

## Your Workflow

### When You Receive a Task

1. **Acknowledge** the assignment
2. **Wait for API contract** from backend worker (if not provided)
3. **Explore** relevant existing components
4. **Implement** UI components
5. **Test** with typecheck and build
6. **Report** completion

### Typical Flow

```
1. Read task assignment
2. Get API contract from backend worker
3. Explore: src/frontend/src/components/, stores/
4. Implement components
5. Connect to API via lib/api.ts
6. Run: npm run typecheck && npm run build
7. Report [DONE]
```

## Communication

### With Lead/Supervisor
```bash
./tools/mailbox status "Waiting for backend API contract"
./tools/mailbox status "Building login form component"
./tools/mailbox done "Login UI complete, connected to /api/auth/login"
```

### With Backend Worker
If you need API clarification:
```bash
./tools/mailbox send worker-backend "API Question" "What error format does /api/auth/login return for validation errors?"
```

## Output Expectations

When reporting [DONE], include:

```
[DONE] <summary>
Files modified:
- src/frontend/src/components/auth/LoginForm.tsx (created)
- src/frontend/src/stores/authStore.ts (created)
- src/frontend/src/lib/api.ts (modified - added auth endpoints)

Verified:
- npm run typecheck: passed
- npm run build: passed
- Manual test: login flow works
```

## What NOT To Do

- Don't touch backend code
- Don't skip typecheck
- Don't hardcode API URLs (use lib/constants.ts)
- Don't ignore loading/error states
```

### Role Template: TESTER.md

```markdown
# Tester Worker Role

You are a **TESTER** on a feature development team. Your job is to validate that implementations work correctly.

## Your Mindset

- **Skeptical**: Assume things are broken until proven working
- **Thorough**: Test edge cases, not just happy path
- **Clear**: Report issues with reproduction steps
- **Collaborative**: Help fix issues, don't just report them

## Your Responsibilities

1. Write integration tests
2. Run existing test suites
3. Perform manual testing
4. Report issues with clear reproduction steps
5. Verify fixes

## Your Workflow

### When You Receive a Task

1. **Wait** for implementation to be ready
2. **Review** what was implemented
3. **Write** additional tests if needed
4. **Run** all relevant tests
5. **Report** results

### Testing Commands

```bash
# Backend tests
uv run pytest tests/ -v

# Frontend checks
cd src/frontend && npm run typecheck
cd src/frontend && npm run build
cd src/frontend && npm run lint

# Specific test file
uv run pytest tests/test_auth.py -v
```

## Issue Reporting Format

When you find issues:

```
[ISSUE] <brief description>

**Steps to Reproduce:**
1. Do X
2. Then Y
3. Observe Z

**Expected:** What should happen
**Actual:** What actually happens

**Evidence:** Log output, screenshot path, or test failure

**Severity:** Critical / High / Medium / Low
```

## Communication

```bash
# Starting testing
./tools/mailbox status "Running test suite for auth feature"

# Found issues
./tools/mailbox send worker-backend "Bug Found" "POST /api/auth/login returns 500 on empty password instead of 400"

# All clear
./tools/mailbox done "Auth feature tested. 12 tests passing, no issues found"
```

## Browser Testing (Chrome DevTools MCP)

For frontend changes, **you MUST verify in the browser**, not just check that code compiles. Use Chrome DevTools MCP tools to test the actual UI.

### Setup
1. Ensure Chrome is running with the dashboard open
2. Use `mcp__chrome-devtools__list_pages` to find the dashboard page
3. Use `mcp__chrome-devtools__select_page` to target it

### Testing Workflow

```
1. Navigate to the feature
2. Take snapshot to verify elements exist
3. Interact with UI elements
4. Take screenshots as evidence
5. Save evidence to journal attachments
```

### Essential Commands

**Navigate to dashboard:**
```
mcp__chrome-devtools__navigate_page
  url: "http://localhost:8000"
```

**Take accessibility snapshot (verify elements exist):**
```
mcp__chrome-devtools__take_snapshot
# Returns element tree with uid identifiers
# Look for expected elements: buttons, inputs, text
```

**Click elements to test interactions:**
```
mcp__chrome-devtools__click
  uid: "<element-uid-from-snapshot>"
# Use uid from take_snapshot results
```

**Fill form inputs:**
```
mcp__chrome-devtools__fill
  uid: "<input-uid>"
  value: "test input"
```

**Take screenshot as evidence:**
```
mcp__chrome-devtools__take_screenshot
  filePath: ".cmux/journal/2026-02-01/attachments/test-evidence-login.png"
```

**Wait for async operations:**
```
mcp__chrome-devtools__wait_for
  text: "Success"
  timeout: 5000
```

### Example: Testing Login Flow

```
# 1. Navigate to login page
mcp__chrome-devtools__navigate_page url="http://localhost:8000/login"

# 2. Snapshot to find form elements
mcp__chrome-devtools__take_snapshot
# Look for: email input, password input, submit button

# 3. Fill email
mcp__chrome-devtools__fill uid="email-input-uid" value="test@example.com"

# 4. Fill password
mcp__chrome-devtools__fill uid="password-input-uid" value="password123"

# 5. Click submit
mcp__chrome-devtools__click uid="submit-button-uid"

# 6. Wait for redirect/success
mcp__chrome-devtools__wait_for text="Dashboard" timeout=5000

# 7. Screenshot as evidence
mcp__chrome-devtools__take_screenshot filePath=".cmux/journal/2026-02-01/attachments/login-success.png"
```

### Example: Verifying UI Component Exists

```
# 1. Navigate to page with new component
mcp__chrome-devtools__navigate_page url="http://localhost:8000"

# 2. Take snapshot
mcp__chrome-devtools__take_snapshot

# 3. Search snapshot output for expected elements:
#    - Look for button text: "New Feature"
#    - Look for component structure
#    - Verify accessibility attributes

# 4. If element missing, report [ISSUE]
# 5. If element present, take screenshot as evidence
```

### Evidence Requirements

For frontend testing, your [DONE] message MUST include:
- Screenshot paths showing the feature works
- Snapshot confirmation that elements exist
- Any interactions you tested

```
[DONE] Login feature tested in browser
Evidence:
- .cmux/journal/2026-02-01/attachments/login-form-snapshot.txt
- .cmux/journal/2026-02-01/attachments/login-success.png
- Tested: form submission, error states, redirect
```

### Common Issues

**Chrome MCP unavailable:**
```
[BLOCKED] Chrome DevTools MCP unavailable - browser profile in use
Need: Restart Chrome or use isolated profile
```

**Element not found in snapshot:**
- Component may not have rendered yet → use wait_for
- Wrong page → check current URL
- Element hidden → check for conditional rendering

## What NOT To Do

- Don't test half-finished work
- Don't report vague issues ("it doesn't work")
- Don't skip edge cases
- Don't approve without actually testing
- **Don't skip browser testing for frontend changes**
- **Don't say "build passes" as proof UI works**
```

### Team Template: DEBATE_PAIR.md (Updated)

```markdown
# Debate Pair Team Template

Use this template when you need to evaluate tradeoffs, make design decisions, or refine proposals through structured argument.

## When to Use

- Design decisions with multiple valid approaches
- Architecture choices that need vetting
- Evaluating competing implementation strategies
- Any task where "should we do X or Y?" is unclear

## Team Composition

| Role | Template | Purpose |
|------|----------|---------|
| Defender | `docs/templates/roles/DEBATE_DEFENDER.md` | Proposes and advocates |
| Critic | `docs/templates/roles/DEBATE_CRITIC.md` | Critiques and improves |

## Spawning Commands

```bash
# Spawn defender
./tools/workers spawn "defender" "Read docs/templates/roles/DEBATE_DEFENDER.md for your role. Your task: [TASK DESCRIPTION]. Write proposal to [OUTPUT PATH]."

# Spawn critic
./tools/workers spawn "critic" "Read docs/templates/roles/DEBATE_CRITIC.md for your role. Wait for defender's proposal at [PATH], then critique."
```

## Expected Artifacts

```
.cmux/journal/YYYY-MM-DD/attachments/
├── 01-defender-proposal.md
├── 02-critic-critique.md
├── 03-defender-rebuttal.md
├── 04-critic-round2.md (if needed)
└── final-plan.md
```

## Workflow

```
Round 1:
  Defender → writes proposal → notifies Critic
  Critic → reads, critiques → notifies Defender

Round 2:
  Defender → responds to critique → notifies Critic
  Critic → reviews response → signals convergence OR continues

Final:
  Defender → writes consolidated plan
  Both → confirm completion to Supervisor
```

## Success Criteria

- [ ] Proposal grounded in actual codebase
- [ ] Critique found substantive issues
- [ ] Revisions improved the proposal
- [ ] Both parties reached convergence
- [ ] Final plan is actionable
```

---

## Task 3: Outcome Tracker (Renamed from Learning Store)

### Name Change Rationale
"Learning Store" implies AI/ML. "Outcome Tracker" clearly describes what it does: tracks delegation outcomes.

### Files to Create

Rename all references:
- `learning_store.py` → `outcome_tracker.py`
- `LearningStore` class → `OutcomeTracker` class
- `/api/learning/` → `/api/outcomes/`

```python
# src/server/services/outcome_tracker.py

class OutcomeTracker:
    """Tracks delegation outcomes for historical analysis."""

    def record_outcome(
        self,
        worker_id: str,
        outcome: str,  # 'success', 'blocked', 'failed'
        task_summary: str = "",
        task_type: str = "general"
    ) -> str:
        """Record an outcome from a worker's completion message."""
        # ... implementation unchanged from v1
```

### Auto-Capture (Unchanged)
Router still auto-captures [DONE] and [BLOCKED] from workers.

---

## Task 6: Archive Search - DEFERRED

### Decision
Defer archive search until we commit to a full feature with UI. Backend-only search provides limited value without a way for users to access it.

### Future Work
When ready to implement:
1. Design archive browser UI component
2. Implement backend search API
3. Add filtering (by date, type, agent)
4. Consider compression for old archives

---

## Revised Implementation Order

### Phase 1: Foundation
1. **Database consolidation** - Single `.cmux/cmux.db`
2. **Unique Worker IDs** - Task 7 (unchanged)
3. **Naming Scheme** - Task 8 (unchanged)

### Phase 2: Templates (PRIORITY)
4. **Role Templates** - Create all role template files
5. **Team Templates** - Update team template files to reference roles
6. **Supervisor Guide** - Add complexity assessment section

### Phase 3: Memory
7. **Outcome Tracker** - Task 3 with new name
8. **Artifact Indexing** - Task 9 (unchanged)

### Deferred
- Archive Search (Task 6) - Until UI commitment

---

## Summary of v2 Changes

| Change | Impact |
|--------|--------|
| Task 1 → Documentation | Removed ~150 lines of Python, added ~100 lines of docs |
| Task 2 → Full role templates | Added 5 detailed role template files |
| Task 3 → Renamed | "Outcome Tracker" is clearer |
| Task 6 → Deferred | Reduces scope, focuses effort |

**Files to Create (Task 2):**
- `docs/templates/roles/DEBATE_DEFENDER.md`
- `docs/templates/roles/DEBATE_CRITIC.md`
- `docs/templates/roles/FEATURE_LEAD.md`
- `docs/templates/roles/FEATURE_BACKEND.md`
- `docs/templates/roles/FEATURE_FRONTEND.md`
- `docs/templates/roles/TESTER.md`

**Files to Modify:**
- `docs/SUPERVISOR_ROLE.md` - Add complexity assessment guide
- `docs/templates/teams/DEBATE_PAIR.md` - Reference role templates

---

*Revised plan incorporating user feedback*
*v2 - 2026-02-01*
