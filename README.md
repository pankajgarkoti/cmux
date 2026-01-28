# cmux

This project uses a parallelized development workflow with multiple Claude Code instances.

## Quick Start

```bash
# Run the full development loop (orchestrator + workers)
multiclaude run .

# Auto-create GitHub PR when QA passes
multiclaude run . --auto-pr

# Check status anytime
multiclaude status .

# View logs/mailbox
multiclaude logs .

# Stop the session
multiclaude stop .
```

## Project Structure

```
├── .multiclaude/
│   ├── settings.json        # Claude permissions
│   ├── ALL_MERGED           # Created when features merged
│   ├── qa-report.json       # QA test results
│   ├── QA_COMPLETE          # Created when QA passes
│   ├── QA_NEEDS_FIXES       # Created when QA fails
│   ├── specs/
│   │   ├── PROJECT_SPEC.md  # Master project specification
│   │   ├── STANDARDS.md     # Quality standards for QA
│   │   ├── .features        # Feature list (one per line)
│   │   └── features/        # Per-feature specifications
│   └── worktrees/feature-*/ # Feature worktrees
│       └── .multiclaude/
│           ├── FEATURE_SPEC.md  # Feature specification
│           ├── status.log       # Worker status
│           └── inbox.md         # Commands from orchestrator
├── src/                     # Base implementation
└── CLAUDE.md                # Project instructions
```

## Workflow

1. **Specification**: Edit `.multiclaude/specs/PROJECT_SPEC.md` with your project details
2. **Feature Specs**: Create detailed specs in `.multiclaude/specs/features/`
3. **Run**: Execute `multiclaude run .` to start the full workflow
4. **Monitor**: Watch the orchestrator or use `multiclaude status .`
5. **Complete**: Orchestrator handles merge, QA, and fix cycles automatically

## How It Works

The `multiclaude run` command starts a bash orchestrator that:
1. Launches worker Claude agents in tmux (one per feature)
2. Monitors worker status logs for COMPLETE status
3. When all workers complete, runs merge agent (`claude -p`, auto-exits)
4. After merge, runs QA agent (`claude -p --chrome`, auto-exits)
5. If QA fails, assigns FIX_TASK to workers via their inbox.md
6. Repeats until QA passes, then marks PROJECT_COMPLETE

## MCP Servers

All Claude instances have access to the following MCP servers (configured in `.mcp.json`):

### context7
- **Purpose**: Library documentation and code context lookup
- **Usage**: Fetch docs for React, Express, Prisma, or any npm package
- **Config**: `@upstash/context7-mcp`

### browseruse
- **Purpose**: Web browser automation for research
- **Usage**: Look up API docs, verify package versions, research solutions
- **Config**: `@anthropic/browseruse-mcp` (headless mode enabled)

## Status Codes

| Code | Meaning |
|------|---------|
| PENDING | Not started |
| IN_PROGRESS | Active development |
| BLOCKED | Cannot proceed |
| TESTING | Running tests |
| COMPLETE | Ready for merge |
| FAILED | Needs intervention |
