# Permanent Team Research — Worker Pattern Analysis

## Worker Inventory (26 workers across 2 days)

### By Category
| Category | Count | % | Examples |
|----------|-------|---|---------|
| Frontend/UI | 8 | 31% | mention-fix, tasks-polish, heartbeat-ui, tasks-ui, fix-duplicate-events, fix-thoughts-tab, persist-thoughts |
| Feature Development | 7 | 27% | task-system, autonomy-engine, task-visibility, tasks-api, heartbeat-ui |
| Research/Debate | 4 | 15% | defender-meta, critic-meta, defender, critic |
| Policy/Documentation | 4 | 15% | testing-policy, coordination-rules, sup-monitoring |
| Infrastructure/System | 3 | 12% | mailbox-inline, safe-send, fix-project-workers |
| Testing | 2 | 8% | test-todo-api, test-todo-ui |

### Key Patterns
1. **Frontend workers are the most spawned** — UI bugs, component enhancements, state integration
2. **Feature dev is second** — full-stack features with backend API + frontend + integration
3. **Testing is always post-implementation** — never in the same worker
4. **Debate pairs used for architectural decisions** — 2 workers per analysis
5. **Infrastructure fixes come in batches** — multiple related system fixes at once

### Recurring Task Shapes
- "Fix X in the frontend" → frontend specialist
- "Add endpoint + UI for feature Y" → feature engineer (or split: backend + frontend)
- "Run tests / verify in browser" → tester
- "Fix orchestrator script / tooling bug" → infra engineer
- "Should we do X or Y?" → debate pair (ephemeral, not permanent)

## Proposed Permanent Roles (for debate)

Based on frequency and recurrence:

1. **Frontend Specialist** — UI rendering, component fixes, styling, state management. 31% of all work.
2. **Backend Engineer** — API endpoints, DB schema, service logic. Subset of feature dev.
3. **Tester** — pytest, browser testing via Chrome MCP, verification after changes. Always needed post-impl.
4. **Infra/Tooling Engineer** — Orchestrator scripts, bash tooling, system reliability.

### Open Questions for Debate
- Should feature dev be split into frontend + backend, or one full-stack role?
- How does a permanent worker get "assigned" a task? Mailbox message with task ID?
- What happens when a permanent worker's context gets too long? Reset procedure?
- Should the tester be permanent or ephemeral (only needed after impl)?
- How do permanent workers coexist with ephemeral ones? Priority? Queueing?
- What prevents a permanent worker from becoming stale/confused over many tasks?
