# Hooks Analysis: New Possibilities for CMUX
*Generated: 2026-02-20*

## What We're Currently Using

| Hook | What it does |
|------|-------------|
| PostToolUse | Audit logging (.cmux/audit.log), supervisor heartbeat |
| PreCompact | Pre-compaction state capture (structured JSON artifacts) |
| Stop | Agent event notification to CMUX server |

## What We Didn't Know About

### 1. SessionStart with `compact` matcher — GAME CHANGER

When a session resumes AFTER compaction, the `SessionStart` hook fires with matcher `"compact"`. The hook's stdout is **injected directly into Claude's context**.

**This means**: Instead of telling a compacted agent "go read your recovery file", we can **automatically inject the recovery context**. The agent doesn't need to do anything — it just wakes up with its state restored.

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "compact",
        "hooks": [{
          "type": "command",
          "command": ".claude/hooks/inject-recovery-context.sh"
        }]
      }
    ]
  }
}
```

The script reads the latest compaction artifact and prints it to stdout. Claude gets it as context automatically.

### 2. transcript_path — Full Conversation Access

Every hook receives `transcript_path` — the path to the full conversation JSONL file. This means ANY hook can read the agent's entire conversation history, not just terminal output.

**This means**: The pre-compact hook can capture the REAL conversation (not just a pane capture), and the recovery hook can restore it. We can extract exactly what the agent was working on, what decisions it made, what files it touched.

### 3. Stop Hook — Quality Gate Before Stopping

Stop hooks can PREVENT Claude from stopping by returning `exit 2` or `{"decision": "block", "reason": "..."}`. The reason is fed back to Claude and it continues working.

**This means**: We can enforce that workers:
- Journal their work before stopping
- Commit their changes before stopping
- Run tests before stopping
- Report their status via mailbox before stopping

```json
{
  "hooks": {
    "Stop": [{
      "hooks": [{
        "type": "prompt",
        "prompt": "Check if this agent completed its work properly. Context: $ARGUMENTS. Verify: 1) Did the agent commit changes? 2) Did it journal? 3) Did it report via mailbox? If not, respond with {\"ok\": false, \"reason\": \"You must commit, journal, and report before stopping.\"}",
        "timeout": 30
      }]
    }]
  }
}
```

### 4. TaskCompleted Hook — Enforce Completion Criteria

When any agent marks a task as completed, this hook fires. Exit 2 blocks completion with feedback.

**This means**: We can enforce that tasks aren't "done" until tests pass:

```bash
#!/bin/bash
if ! npm test 2>&1; then
  echo "Tests failing. Fix before marking complete." >&2
  exit 2
fi
```

### 5. PreToolUse with updatedInput — Modify Commands Before Execution

PreToolUse can return `updatedInput` to CHANGE tool parameters before they execute.

**This means**: We can:
- Auto-add safety flags to dangerous commands
- Redirect file writes to safe locations
- Inject `--dry-run` for destructive operations during review
- Rewrite git push to git push --dry-run unless explicitly approved

### 6. PermissionRequest — Smart Permission System

Instead of `--dangerously-skip-permissions`, we can build a nuanced permission system. The hook can auto-approve safe operations and block/escalate dangerous ones.

**This means**: Replace blanket skip-permissions with:
- Auto-approve: Read, Glob, Grep, safe Bash commands
- Ask user: Write to protected files, git push, rm commands
- Block: Modifications to orchestrator scripts, .claude/ directory

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedPermissions": [
        {"type": "toolAlwaysAllow", "tool": "Read"}
      ]
    }
  }
}
```

### 7. UserPromptSubmit — Enrich Prompts With Context

Fires when a user submits a prompt, BEFORE Claude processes it. Stdout is added as context.

**This means**: When a user sends a message via the dashboard:
- Auto-inject relevant journal entries
- Add recent agent activity context
- Include system health status
- Provide relevant file contents based on what the user is asking about

### 8. SubagentStart — Inject Context Into Subagents

When a subagent (Task tool) is spawned, we can inject additional context.

**This means**: Every subagent automatically gets:
- Project conventions from CLAUDE.md
- Recent journal entries
- Current system state
- Agent-specific instructions

### 9. Notification[permission_prompt] — Dashboard Approval Queue

When Claude needs permission, the Notification hook fires with type `permission_prompt`.

**This means**: We can route permission requests to the CMUX dashboard and build the approval queue UI we planned in Tier 3. The hook sends the permission request to the API, the frontend shows approve/reject buttons, and a separate mechanism sends the response back.

### 10. Prompt-Based Hooks — LLM Evaluation

Hooks can use `type: "prompt"` to have a FAST Claude model evaluate conditions.

**This means**: Instead of writing complex bash scripts to check conditions, we can use natural language:
- "Did the agent complete all requested tasks?"
- "Is this bash command safe to run in production?"
- "Does this code change look like it could break the system?"

### 11. Agent-Based Hooks — Multi-Turn Verification

Hooks can use `type: "agent"` to spawn a subagent with Read/Grep/Glob access.

**This means**: Before allowing a task to complete, spawn a verifier agent that:
- Reads the modified files
- Runs grep for common issues
- Checks that tests exist for new code
- Verifies the changes match the task description

### 12. PostToolUseFailure — React to Failures

Fires when a tool call fails. Can inject `additionalContext` to help Claude recover.

**This means**: When a test fails, we can automatically:
- Read the test output
- Look up similar failures in the journal
- Provide hints about common fixes
- Log the failure pattern for future reference

### 13. CLAUDE_ENV_FILE — Persistent Environment Variables

SessionStart hooks can write to `$CLAUDE_ENV_FILE` to set environment variables for all subsequent Bash calls.

**This means**: On session start, we can set:
- `CMUX_PROJECT_ROOT` dynamically
- `CMUX_AGENT_ROLE` based on the window name
- Test database URLs
- Feature flags for the current session

### 14. `once` Field — One-Shot Hooks

Hooks with `"once": true` run only once per session then are removed.

**This means**: We can have a setup hook that runs once on session start to configure the environment, then gets out of the way.

### 15. async Hooks — Non-Blocking Background Tasks

Command hooks with `"async": true` run in the background. Results delivered on next turn.

**This means**: After every file write, we can:
- Run tests in the background
- Trigger a build
- Update the dashboard
- All without blocking the agent's work

---

## Updated Implementation Plan

### Immediate (use what we learned NOW)

| # | Hook-Based Improvement | Replaces | Impact |
|---|----------------------|----------|--------|
| 1 | **SessionStart[compact] recovery injection** | Post-compact tmux message | Automatic context recovery — agents wake up with full state |
| 2 | **Stop hook quality gate** | Manual worker discipline | Workers CANNOT stop without committing + journaling + reporting |
| 3 | **transcript_path in PreCompact** | Pane capture for state | Full conversation captured, not just visible terminal |
| 4 | **Notification → approval queue** | Nothing (didn't exist) | Dashboard-based permission approvals |

### Short Term (this week)

| # | Hook-Based Improvement | Impact |
|---|----------------------|--------|
| 5 | **Smart PermissionRequest handler** | Replace --dangerously-skip-permissions with nuanced auto-approve/block |
| 6 | **TaskCompleted test enforcement** | Tasks can't be marked done until tests pass |
| 7 | **UserPromptSubmit context enrichment** | Dashboard messages auto-enriched with journal + agent context |
| 8 | **PostToolUseFailure recovery hints** | Automatic failure analysis and hints |
| 9 | **async PostToolUse test runner** | Background tests after every file change |

### Medium Term (next sprint)

| # | Hook-Based Improvement | Impact |
|---|----------------------|--------|
| 10 | **Agent-based Stop verification** | Subagent verifies code quality before agent stops |
| 11 | **SubagentStart context injection** | Every subagent gets project context automatically |
| 12 | **PreToolUse command sanitization** | Rewrite dangerous commands, add safety flags |
| 13 | **Prompt-based security evaluation** | LLM evaluates if bash commands are safe |

### Architecture Shift: Replace --dangerously-skip-permissions

The PermissionRequest hook enables a FUNDAMENTAL change: instead of running all agents with `--dangerously-skip-permissions` (no safety), we can run them in default permission mode with a smart hook that:

1. Auto-approves: Read, Glob, Grep, Write (to non-protected files), safe Bash
2. Escalates to supervisor: git push, file deletion, modifications to .claude/ or src/orchestrator/
3. Blocks outright: rm -rf, force pushes, modifications to health.sh from workers

This gives us **granular permission control per agent role** instead of all-or-nothing.
