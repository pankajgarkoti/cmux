# Teams Skill Analysis: Should CMUX Have a `/teams` Tool?

**Author:** worker-teams-skill-review
**Date:** 2026-02-20
**Task:** Research-only review of whether CMUX needs a `/teams` skill and CLI tool

---

## 1. What Would a `/teams` Tool Do?

A `/teams` tool would automate the spawning of pre-configured team structures from the 7 team templates in `docs/templates/teams/`. Example usage:

```bash
# Set up a full squad for a feature
./tools/teams setup SQUAD_MODEL "implement user settings page"
# → Spawns: squad-lead, backend-settings, frontend-settings, tester-settings
# → Each worker gets the correct role template and inter-agent references

# Check team status
./tools/teams status settings
# → Shows all 4 workers, their terminal output summaries, mailbox activity

# Tear down when done
./tools/teams teardown settings

# List active teams
./tools/teams list
```

### Potential Commands

| Command | Description |
|---------|-------------|
| `setup <TEMPLATE> <task> [--name <prefix>]` | Spawn all workers with correct roles, templates, and cross-references |
| `teardown <name>` | Kill all workers in a team |
| `status <name>` | Show all team members and recent terminal output |
| `list` | List active teams and their members |
| `templates` | List available team templates with descriptions |

### What Each Template Would Automate

| Template | Workers Spawned | Complexity of Manual Setup |
|----------|----------------|---------------------------|
| SOLO_WORKER | 1 | Trivial — already just `./tools/workers spawn` |
| SQUAD_MODEL | 4 (lead, backend, frontend, tester) | 4 sequential spawns with role templates, cross-references |
| FEATURE_TEAM | 2-4 (tech lead + workers) | 3-4 spawns, hierarchical communication setup |
| PLATFORM_TEAM | 3 (platform lead, infra, devops) | 3 spawns with specialized roles |
| TIGER_TEAM | 2-3 (flat peers) | 2-3 spawns, each needing names of all other members |
| DEBATE_PAIR | 2 (defender, critic) | 2 spawns with output path coordination |
| DEBATE_TO_IMPL | 2→4+ (debate then implement) | Multi-phase: 2 spawns, then promotion, then N more |

---

## 2. What's the Gap Today?

### Current Workflow (How Supervisor Sets Up Teams)

1. Supervisor receives a task
2. Reads SUPERVISOR_ROLE.md complexity assessment (lines 38-106) to choose team type
3. Reads the relevant team template (e.g., `docs/templates/teams/SQUAD_MODEL.md`)
4. Manually constructs N `./tools/workers spawn` commands, each with:
   - A descriptive worker name
   - Reference to the correct role template (e.g., `docs/templates/roles/FEATURE_BACKEND.md`)
   - The task description scoped to that worker's responsibility
   - Cross-references to other team members' names for communication
5. Executes spawns sequentially (each takes ~8s due to `STARTUP_DELAY`)
6. Optionally sends initial coordination messages

### Pain Points

**Boilerplate intensity:** Setting up a SQUAD_MODEL requires the supervisor to write 4 spawn commands totaling ~400+ characters of template paths and role instructions. Each spawn command contains:
- The role template path (`docs/templates/roles/FEATURE_BACKEND.md`)
- Worker role docs reference (`docs/WORKER_ROLE.md`)
- Task scoping for that specific role
- Names of other team members for coordination

**Error-prone cross-references:** Tiger Team and Squad Model require workers to know each other's names. The supervisor must manually ensure consistency — if it names one worker `tiger-a` but tells another to coordinate with `tiger-1`, communication breaks.

**Time cost:** Each `./tools/workers spawn` takes ~8 seconds (STARTUP_DELAY). A SQUAD_MODEL takes ~32 seconds of sequential spawning. The supervisor must wait and execute each in turn.

**Template path fragility:** Role template paths like `docs/templates/roles/FEATURE_BACKEND.md` are hardcoded in the supervisor's prompt output. If templates move or rename, every spawn command breaks silently.

**No team-level visibility:** There's no way to ask "what teams are running?" — `./tools/workers list` shows a flat list of all workers with no team grouping. The supervisor has to remember which workers belong to which team.

### What Works Fine Today

- **Template selection:** The supervisor's LLM judgment about which template to use is good — the complexity assessment matrix in SUPERVISOR_ROLE.md is clear and well-structured. A tool doesn't improve this.
- **Task scoping:** The supervisor decides how to split work across roles, which requires understanding the task. A tool can't do this — it still needs human/LLM input for task breakdown.
- **Flexibility:** The supervisor can deviate from templates (e.g., skip the tester role for a simple squad, add an extra backend worker). This flexibility is valuable.

---

## 3. What Commands Would It Need?

### Core Commands (Minimum Viable)

```bash
./tools/teams setup <TEMPLATE> "<task description>" [--name <prefix>]
./tools/teams teardown <prefix>
./tools/teams status <prefix>
./tools/teams list
```

### Optional Commands

```bash
./tools/teams templates                  # List available templates with descriptions
./tools/teams add <prefix> <role> "<task>"  # Add a worker to an existing team
./tools/teams promote <worker> "<msg>"   # Transition (for DEBATE_TO_IMPL)
```

### Critical Design Decision: How Much Does `setup` Automate?

**Option A: Full automation** — `setup` spawns all workers with generated task descriptions based on the template's role breakdown. The supervisor provides a single task description and the tool generates per-role tasks.

**Option B: Scaffolding only** — `setup` spawns workers with the correct role templates and naming, but leaves task descriptions generic (e.g., "Your backend task for: implement user settings page"). The supervisor then sends specific task breakdowns via `./tools/workers send`.

**Option C: Interactive recipe** — `setup` outputs the spawn commands that *would* be run (like a dry-run) and the supervisor can edit/confirm them. Doesn't save time, but prevents typos.

**Recommendation: Option B (scaffolding).** Full automation (A) requires the tool to understand task decomposition, which is the supervisor's core value-add. Interactive (C) doesn't save enough time. Scaffolding (B) handles the boilerplate (names, templates, cross-references) while preserving supervisor judgment for task scoping.

---

## 4. Should It Be a CLI Tool, a Skill, or Both?

### Analysis

| Factor | CLI Tool (`tools/teams`) | Skill (`.claude/skills/teams/`) | Both |
|--------|--------------------------|--------------------------------|------|
| Who uses it | Any agent via bash | Claude agents via skill system | Both |
| Permission model | `allowed-tools: Bash(./tools/teams:*)` | Skill-level permissions | Layered |
| Implementation | Bash script (matches workers pattern) | SKILL.md wrapping the bash tool | Natural extension |
| Discoverability | `ls tools/` | Skill system shows in prompts | Maximum |

### Recommendation: Both (matching the existing pattern)

The existing `workers` system uses both:
- `tools/workers` — the bash CLI that does the actual work
- `.claude/skills/workers/SKILL.md` — the skill wrapper that tells Claude agents how to use it

A `/teams` tool should follow the same pattern:
- `tools/teams` — bash script handling spawn orchestration, teardown, status, list
- `.claude/skills/teams/SKILL.md` — skill wrapper with usage instructions

This is consistent with `mailbox` and `journal` which also have both a CLI tool and a skill.

---

## 5. What Are the Risks?

### Risk 1: Over-Automation / Loss of Supervisor Judgment
**Severity: Medium**

The supervisor's primary job is to assess complexity and choose the right team structure. If `./tools/teams setup SQUAD_MODEL` becomes the default, supervisors might reach for SQUAD_MODEL without considering whether a solo worker or debate pair would be better.

**Mitigation:** The tool should NOT include template selection logic. The supervisor still reads the complexity assessment and decides. The tool only handles the spawning mechanics after the decision is made.

### Risk 2: Rigidity
**Severity: Medium-High**

Not every task fits cleanly into a template. A "SQUAD_MODEL" feature might not need a tester. A "FEATURE_TEAM" might need 2 backend workers. If the tool spawns a fixed set of workers, it may create unnecessary agents (wasting resources and context).

**Mitigation:** Option B (scaffolding) helps here. The tool spawns the standard team, but the supervisor can immediately `./tools/workers kill` unnecessary members or `./tools/workers spawn` additional ones. Alternatively, add `--skip <role>` and `--extra <role>` flags.

### Risk 3: Complexity and Maintenance Burden
**Severity: Medium**

A new tool means more code to maintain. The team templates may evolve (new templates, changed roles), and the tool must stay in sync. If templates change but the tool doesn't update, it spawns with stale configuration.

**Mitigation:** The tool should read templates at runtime rather than hardcoding team compositions. It could parse a structured header in each template file to know which roles to spawn.

### Risk 4: Naming Collisions
**Severity: Low**

If the supervisor sets up two squads for different features, worker names could collide (e.g., two `backend-*` workers). The tool needs a prefix/namespace system.

**Mitigation:** The `--name <prefix>` flag and auto-generated prefixes from the task description.

### Risk 5: DEBATE_TO_IMPLEMENTATION Is Multi-Phase
**Severity: Medium**

This template isn't a one-shot setup — it requires a debate phase, convergence detection, a promotion step, then an implementation phase. Automating this end-to-end is significantly more complex than the other templates.

**Mitigation:** Start without DEBATE_TO_IMPLEMENTATION support. The tool handles single-phase team setups. Multi-phase workflows remain manual (or get a separate `teams promote` command later).

---

## 6. Recommendation

### Build a Minimal Version

**Verdict: Build it, but keep it small.**

The gap is real — setting up multi-worker teams is the most boilerplate-heavy operation the supervisor does, and the cross-reference errors are a genuine source of bugs. But the value of a `/teams` tool is in the mechanical spawning, NOT in decision-making or task decomposition.

### What to Build (MVP)

1. **`tools/teams` bash script** with these commands:
   - `setup <TEMPLATE> "<task>" [--name <prefix>]` — spawns workers per template with correct role templates and cross-references
   - `teardown <prefix>` — kills all workers with the given prefix
   - `status <prefix>` — shows all team members' terminal output
   - `list` — shows active teams grouped by prefix
   - `templates` — lists available templates with one-line descriptions

2. **`.claude/skills/teams/SKILL.md`** wrapping the CLI tool

3. **Supported templates in MVP:**
   - SOLO_WORKER (trivial but included for completeness)
   - SQUAD_MODEL
   - FEATURE_TEAM
   - PLATFORM_TEAM
   - TIGER_TEAM
   - DEBATE_PAIR

4. **Deferred to v2:**
   - DEBATE_TO_IMPLEMENTATION (multi-phase)
   - `teams add` / `teams promote` commands
   - Template composition flags (`--skip`, `--extra`)

### What NOT to Build

- **Template selection logic** — the supervisor decides which template; the tool just executes
- **Task decomposition** — the tool doesn't break the task into per-role subtasks; it uses a generic description and the supervisor refines via `./tools/workers send`
- **Convergence detection** — for debate teams, the supervisor still monitors for convergence signals; the tool doesn't automate phase transitions
- **Team state persistence** — no database or state file tracking teams; just use tmux window naming conventions (e.g., all workers prefixed with the team name) and `./tools/workers list` filtering

### Implementation Sketch

The `setup` command would:
1. Read the template file to determine roles needed
2. Generate worker names using the prefix (e.g., `auth-squad-lead`, `auth-backend`, `auth-frontend`, `auth-tester`)
3. For each role, construct the spawn command with the correct role template path
4. Inject cross-references (e.g., Tiger Team members know each other's names)
5. Execute `./tools/workers spawn` for each, sequentially (due to the 8s startup delay)
6. Report the team composition

### Expected Effort

- **tools/teams script:** ~200-300 lines of bash (similar complexity to `tools/workers`)
- **SKILL.md:** ~80 lines (similar to workers skill)
- **Testing:** Manual testing with each template type
- **Timeline:** One focused worker, one session

### Summary Table

| Aspect | Decision |
|--------|----------|
| Build it? | Yes, minimal version |
| CLI tool? | Yes (`tools/teams`) |
| Skill? | Yes (`.claude/skills/teams/SKILL.md`) |
| Templates supported | 6 of 7 (defer DEBATE_TO_IMPL) |
| Task decomposition? | No — supervisor's job |
| Template selection? | No — supervisor's job |
| Team state persistence? | No — use naming conventions |
| Multi-phase automation? | No — manual for now |

---

## Appendix: Current vs. Proposed Workflow

### Current: Supervisor Sets Up a SQUAD_MODEL Manually

```bash
# Step 1: Supervisor reads template docs
# Step 2: Supervisor constructs spawn commands manually

./tools/workers spawn "squad-lead-auth" "Read docs/templates/roles/SQUAD_LEAD.md. Your task: Implement user authentication with JWT. Spawn backend, frontend, tester workers."

# Wait 8s...

./tools/workers spawn "backend-auth" "Read docs/templates/roles/FEATURE_BACKEND.md. Your task: Implement JWT backend in src/server/auth/. Report to squad-lead-auth."

# Wait 8s...

./tools/workers spawn "frontend-auth" "Read docs/templates/roles/FEATURE_FRONTEND.md. Your task: Implement login/logout UI. Wait for API contract from backend-auth. Report to squad-lead-auth."

# Wait 8s...

./tools/workers spawn "tester-auth" "Read docs/templates/roles/TESTER.md. Your task: Test JWT auth flow when backend-auth and frontend-auth signal ready. Report to squad-lead-auth."
```

**Time:** ~32 seconds + supervisor prompt construction time
**Error risk:** Template paths, worker name references, role descriptions

### Proposed: Supervisor Uses `/teams` Tool

```bash
./tools/teams setup SQUAD_MODEL "Implement user authentication with JWT" --name auth

# Output:
# ✓ Setting up SQUAD_MODEL team 'auth'
# ✓ Spawning auth-squad-lead (Squad Lead)...
# ✓ Spawning auth-backend (Backend Worker)...
# ✓ Spawning auth-frontend (Frontend Worker)...
# ✓ Spawning auth-tester (Tester)...
# ✓ Team 'auth' ready (4 workers)
#
# Workers:
#   ● auth-squad-lead  (docs/templates/roles/SQUAD_LEAD.md)
#   ● auth-backend     (docs/templates/roles/FEATURE_BACKEND.md)
#   ● auth-frontend    (docs/templates/roles/FEATURE_FRONTEND.md)
#   ● auth-tester      (docs/templates/roles/TESTER.md)

# Then supervisor sends specific task breakdowns:
./tools/workers send "auth-squad-lead" "[TASK] Coordinate JWT implementation. Backend handles token creation, frontend handles login UI. Tester validates end-to-end."
```

**Time:** Same ~32 seconds for spawning, but zero prompt construction time for the spawn commands
**Error risk:** Eliminated for template paths and cross-references
