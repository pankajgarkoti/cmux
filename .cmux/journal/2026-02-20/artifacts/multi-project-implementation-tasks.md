# Multi-Project Implementation — Task List

**Date**: 2026-02-20
**Goal**: Transform CMUX from single-project to multi-project command center

---

## Phase 1 — Core Infrastructure

- [ ] **1.1 Agent ID system**
  - Generate `ag_` + 8-char alphanumeric IDs at agent spawn time
  - Update agent registry schema: add `id`, `display_name`, `role`, `project_id` fields
  - Supervisor Prime gets well-known ID `ag_0000prim`
  - API dual-lookup: accept both ID and name, prefer ID
  - `tools/workers` generates ID on spawn, sets `CMUX_AGENT_ID` env var
  - tmux window name = agent ID

- [ ] **1.2 `tools/workers` — add `--dir` and `--project` flags**
  - `--dir <path>` sets worker's working directory (instead of CMUX root)
  - `--project <id>` associates worker with a project in the registry
  - Set env vars: `CMUX_AGENT_ID`, `CMUX_AGENT_ROLE`, `CMUX_PROJECT_ID`
  - Add CMUX tools to PATH so workers in external projects can use journal/mailbox
  - Backward-compatible: existing spawn commands still work

- [ ] **1.3 Fix path dependencies for external projects**
  - `tools/mailbox` `get_attachments_dir()`: use `CMUX_HOME` instead of relative path
  - `tools/journal`: already uses `CMUX_HOME` (done in refactor)
  - Hook scripts: replace `git rev-parse --show-toplevel` with `$CMUX_HOME` where needed
  - Worker context files: use absolute paths from `CMUX_HOME`

- [ ] **1.4 Project registry — `.cmux/projects.json`**
  - Schema: id, name, path, description, git_remote, is_self, active, supervisor_agent_id, hooks_installed
  - CMUX itself is auto-registered as `is_self: true`
  - `tools/projects` CLI: add, remove, list, info, activate, deactivate
  - Auto-detect git remote, language, directory name on `add`

- [ ] **1.5 Project supervisor lifecycle**
  - Spawn project supervisor in target project's directory on `projects activate`
  - Project supervisor reads target project's CLAUDE.md + CMUX's SUPERVISOR_ROLE.md
  - Immortality: health daemon and sentry skip agents with `CMUX_AGENT_ROLE=project-supervisor`
  - Heartbeat/nudge for project supervisors (same as Supervisor Prime)
  - Auto-start on `cmux.sh start` for all registered projects with `active: true`

## Phase 2 — Teams Tool (built on project supervisor model)

- [ ] **2.1 `tools/teams` CLI**
  - `setup <TEMPLATE> "<task>" [--name <prefix>] [--project <id>]`
  - `teardown <prefix>`
  - `status <prefix>`
  - `list`
  - `templates`
  - Support 6 of 7 templates (defer DEBATE_TO_IMPLEMENTATION)

- [ ] **2.2 `.claude/skills/teams/SKILL.md`**
  - Skill wrapper for teams tool
  - Usage examples, command reference

## Phase 3 — API & Backend

- [ ] **3.1 `/api/projects` endpoints**
  - GET /api/projects — list all
  - POST /api/projects — register
  - GET /api/projects/:id — details
  - PATCH /api/projects/:id — update
  - DELETE /api/projects/:id — unregister
  - GET /api/projects/:id/agents — agents for project
  - POST /api/projects/:id/activate — start supervisor
  - POST /api/projects/:id/deactivate — stop supervisor

- [ ] **3.2 Update agent API for IDs**
  - Dual-lookup by ID or name
  - GET /api/agents/by-project/:pid
  - Include project_id in agent responses
  - WebSocket events include agent ID + display name

- [ ] **3.3 Journal tagging by project**
  - Add `CMUX_PROJECT_ID` to journal entries
  - GET /api/journal filter by project
  - Journal search scoped to project

## Phase 4 — UI

- [ ] **4.1 Project-grouped agent tree**
  - Group agents by project in explorer
  - Crown icon for supervisors, distinct from workers
  - Collapsible project sections

- [ ] **4.2 Project sidebar/switcher**
  - Left sidebar or dropdown to scope all panels
  - Status indicators per project
  - Agent count badges

- [ ] **4.3 Per-project chat, activity, journal**
  - Scope chat panel to selected project
  - Activity feed filtered by project
  - Journal view with project filter

- [ ] **4.4 Register project dialog**
  - Path input with auto-detection
  - Options for hook installation and supervisor start

## Phase 5 — Polish

- [ ] **5.1 Cleanup and cross-project coordination**
  - Cleanup on project removal (kill supervisor, clean hooks, archive journals)
  - Cross-project task coordination via Supervisor Prime
  - `tools/agents list` ID→name utility

---

## Implementation Order

Start with Phase 1 items sequentially (1.1 → 1.2 → 1.3 → 1.4 → 1.5).
Phase 2 can start after 1.2 is done.
Phases 3-5 can be parallelized after Phase 1 completes.
