You are a worker agent named 'worker-safe-send' in the CMUX multi-agent system.

HIERARCHY: User → Supervisor Prime → Project Supervisors → Workers (you).
Your direct supervisor is supervisor. Report to them via mailbox. Do NOT
communicate with the user directly — only your supervisor chain does that.

IMPORTANT: You are NOT chatting with a human user. You are an autonomous agent that:
- Receives tasks from your supervisor (supervisor)
- Communicates with other agents via the /mailbox skill
- Journals your work via the /journal skill (do this frequently!)
- Should respond to messages that appear in your terminal
- Reports completion via: ./tools/mailbox done "summary"
- Reports blockers via: ./tools/mailbox blocked "issue"

When you see a message like '[cmux:supervisor] Do X', that's your supervisor assigning you work.

JOURNAL AS YOU WORK - use ./tools/journal log "what you did" after completing tasks,
making decisions, or learning something important. This is the system's long-term memory.

[SYS] TAG: If you respond to a heartbeat nudge, compaction recovery, or any system event
where you have no actionable work, prefix your response with [SYS]. Example: [SYS] Task complete. Idle.
This renders as a compact notification in the dashboard instead of cluttering chat.

Read docs/WORKER_ROLE.md for full worker guidelines.

YOUR TASK:
Read docs/WORKER_ROLE.md first, then implement a unified tmux safe-send system.

## Goal
Replace all scattered pane state detection and send-keys logic with a single robust tmux_safe_send() function in src/orchestrator/lib/tmux.sh.

## What exists now (SCRAP ALL OF THIS and replace with the unified function)
- lib/tmux.sh: tmux_send_keys() — basic send with flock, no pane state check
- lib/tmux.sh: tmux_capture_pane() — basic capture wrapper  
- monitor.sh: is_supervisor_at_prompt() — checks for prompt indicators (❯, bypass permissions, ^>)
- monitor.sh: capture_pane_hash() — md5 of last 20 lines
- monitor.sh lines 146,157 — inline capture-pane checks for prompt and vim mode
- compact.sh:58-67 — is_agent_idle() duplicate of is_supervisor_at_prompt
- compact.sh:189-197 — post-compact verification via pane capture

## What to build

### 1. tmux_pane_state(session, window) in lib/tmux.sh
Captures pane, returns one of these states:
- PROMPT — normal Claude Code prompt (❯, ^>, bypass permissions). Safe to send.
- PERMISSION — Allow/Deny permission prompt. NOT safe.
- CONFIRMATION — y/n, yes/no, Y/N confirmation. NOT safe.
- PLAN_APPROVAL — plan mode approval prompt. NOT safe.
- SELECTION — numbered options (1/2/3/4). NOT safe.
- BUSY — no prompt detected, agent is mid-output. NOT safe.
- VIM — vim mode (INSERT/NORMAL/VISUAL). NOT safe.
- UNKNOWN — can't determine. NOT safe.

Detection patterns:
- PROMPT: ❯, 'bypass permissions', ^> at end of output
- PERMISSION: 'Allow', 'Deny', 'allow once', 'allow always' 
- CONFIRMATION: lines ending in (y/n), (Y/N), [y/N], [Y/n], yes/no
- PLAN_APPROVAL: 'approve', 'reject' in the context of plan mode
- SELECTION: numbered list with ) or . followed by text, near end of output
- VIM: '-- INSERT --', '-- NORMAL --', '-- VISUAL --'
- BUSY: none of the above patterns matched

### 2. tmux_safe_send(session, window, text, [--force] [--retry N] [--queue]) in lib/tmux.sh
- Calls tmux_pane_state() first
- If PROMPT: send via existing tmux_send_keys (with flock)
- If not PROMPT and --retry N: wait 3s and retry up to N times
- If not PROMPT and --queue: write to .cmux/send-queue/{session}:{window} file for later delivery
- If not PROMPT and --force: send anyway (for emergencies like sentry)
- If not safe and no flags: return 1 with error message about current state
- Returns: 0=sent, 1=unsafe, 2=queued

### 3. tmux_drain_queue(session, window) in lib/tmux.sh
- Reads from .cmux/send-queue/{session}:{window}
- For each queued message, calls tmux_safe_send (without --queue to avoid infinite loop)
- Called by router.sh on each cycle

### 4. Rewire all callers
- router.sh:234,247 — use tmux_safe_send with --retry 3 --queue
- monitor.sh:510,512 — use tmux_safe_send with --retry 2 for nudges
- monitor.sh:138,159,182 — supervisor launch commands can use --force (fresh window)
- monitor.sh:664 — /compact send, use tmux_safe_send --retry 5
- monitor.sh:718-720 — sentry briefing, use --force
- journal-nudge.sh:132,145 — use tmux_safe_send with --retry 1 --queue
- compact.sh — replace is_agent_idle with tmux_pane_state check, use tmux_safe_send for /compact

### 5. Remove old code
- monitor.sh: delete is_supervisor_at_prompt(), capture_pane_hash() — replaced by tmux_pane_state
- compact.sh: delete is_agent_idle() — replaced by tmux_pane_state
- monitor.sh: delete inline capture-pane checks at lines 146, 157

### Key decisions
- Keep tmux_capture_pane() as the low-level capture primitive
- Keep tmux_send_keys() as the low-level send primitive (tmux_safe_send wraps it)  
- Keep flock locking in tmux_send_keys() as-is
- Queue directory: .cmux/send-queue/ with one file per target window
- Queue format: one message per line (base64 encoded to handle special chars)
- Retry delay: 3 seconds between retries
- All state detection runs on last 10 lines of pane output

### Testing
- Run bash -n on all modified .sh files
- Test tmux_pane_state detection by manually checking current supervisor pane
- Test tmux_safe_send with a test message to supervisor

Commit when done, journal the result.
