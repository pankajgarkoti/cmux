# Critical Analysis: CMUX Heartbeat & Sentry System

**Author**: worker-heartbeat-critique
**Date**: 2026-02-20
**Verdict**: The heartbeat system is architecturally backwards. It measures the wrong signal, delivers nudges through the wrong channel, and fundamentally cannot produce autonomy because it tries to drive an agent externally rather than giving the agent an internal drive.

---

## 1. Full Flow Trace: What Actually Happens When a Nudge Fires

### The Chain of Events

1. **PostToolUse hook** (settings.json): Every time the supervisor uses any tool, `date +%s` is written to `.cmux/.supervisor-heartbeat`. This is async, non-blocking. (~5ms)

2. **Monitor dashboard loop** (monitor.sh:883-1008): Every 5 seconds, `check_supervisor_heartbeat()` reads the file and computes staleness = `now - last_beat`.

3. **Threshold check** (monitor.sh:406): If staleness < 600s (10 minutes), display green dot. Done.

4. **Idle path** (monitor.sh:477-531): If staleness >= 600s AND supervisor is at prompt (`is_supervisor_at_prompt()` checks for `❯` in pane output):
   - Check nudge cooldown (120s between nudges)
   - Run `tools/autonomy-check` to scan mailbox, backlog, workers, health, git
   - Format output as `[HEARTBEAT] Autonomy scan found N item(s): ...`
   - Send via `tmux_send_keys` (literally types characters into the supervisor's Claude Code prompt)
   - Increment nudge counter (max 3)

5. **Supervisor receives text** in its terminal input buffer. Claude reads it, processes it, and responds. The response involves at least one tool call (e.g., Bash to check something), which updates the heartbeat file.

6. **Heartbeat resets**. Monitor sees fresh timestamp. Goes back to green. Nudge counter resets.

7. **Supervisor goes idle again**. No more work to do. Waits at prompt. 10 minutes later, the cycle repeats.

### The Actual Supervisor Response (from Journal Evidence)

The journal shows entries like:
- "Supervisor recovery — sentry briefing received, system verified healthy. Server up, latest commit c622086, one idle worker (worker-shell-fixes). **Resuming normal operations.**"
- "Supervisor online after sentry recovery. System healthy, latest commit c622086, no pending tasks. **Resuming normal operations.**"

The pattern: acknowledge → verify health → announce "resuming normal operations" → do nothing → go idle.

---

## 2. Why the Supervisor Just Responds With Status Instead of Doing Something

### Root Cause 1: The Nudge Is Informational, Not Actionable

The nudge says:
```
[HEARTBEAT] Autonomy scan found 3 item(s):
[BACKLOG] Next item: #4 Agent Teams evaluation
[CLEANUP] Worker 'worker-shell-fixes' idle for 45m
[GIT] Uncommitted tracked changes: 3 files changed
```

This tells the supervisor **what exists**. It does NOT tell the supervisor:
- Whether to act on any of these items
- What the priority is relative to the supervisor's current context
- Whether the user wants these handled autonomously or is actively managing them

The supervisor reads "backlog has items" and reasonably concludes: "the user put those there, they'll tell me when to work on them." It reads "uncommitted changes" and reasonably concludes: "those are runtime state files (.cmux/), not code I should commit."

### Root Cause 2: SUPERVISOR_ROLE.md Doesn't Define Autonomous Behavior

The supervisor role doc (720 lines) is almost entirely about **reactive** workflows:
- "When you receive a message..." → respond
- "When `from:` is dashboard:user" → delegate
- "When a worker reports [DONE]" → review

The heartbeat section says "check for work — mailbox, worker status, journal TODOs — or find proactive work to do." But it doesn't define what "proactive work" means. There are no instructions like:
- "If the backlog has P1-P2 items and you have no active tasks, start working on them"
- "If workers have been idle for 30+ minutes, kill them to free resources"
- "If there are uncommitted code changes, review and commit them"

The supervisor follows its instructions correctly. Its instructions don't include autonomous behavior. So it doesn't behave autonomously.

### Root Cause 3: The Nudge Is Delivered As Conversation, Not As Instruction

The `[HEARTBEAT]` message arrives as text in the supervisor's conversation. Claude treats it as a message to respond to, not a command to execute. This is subtle but critical:

- A **message** says "here's some information" → Claude responds with acknowledgment
- An **instruction** says "do this specific thing now" → Claude executes

The nudge is the former. It would need to be the latter. But even then, you'd be fighting Claude's design — Claude is a responder, not a self-starter.

### Root Cause 4: MEMORY.md Instructions Are Circular

MEMORY.md says:
> "On heartbeat nudge: run tools/autonomy-check to scan all work sources, then act on the highest-priority finding."

But the monitor ALREADY runs autonomy-check and sends the output. So the instruction is telling the supervisor to re-run a scan that was already done and whose results are already in front of it. The supervisor has no additional insight from re-running the same tool.

---

## 3. The Sentry Fires for Idle Supervisors — Is This Appropriate?

### Evidence: 5+ Sentry Recoveries Today

| Time | Staleness | Context |
|------|-----------|---------|
| 04:55 | 361s | After completing 19-commit sprint. No pending work. |
| 05:03 | 362s | Immediately after previous recovery. Still no work. |
| 05:10 | 363s | Same. Third consecutive false alarm. |
| 05:18 | 362s | Same. Fourth. |
| 06:16 | 361s | After multi-project research. No pending work. |

**Every single sentry recovery was a false positive.** The supervisor was alive, at prompt, with no work to do. The sentry killed it, spawned a new one, which read docs, verified health, announced it was resuming, and then... went idle again. Until the next sentry kill.

### The Cost of False Sentries

Each sentry recovery:
1. **Spawns a Claude instance** (~$0.50-2.00 in API costs per sentry session)
2. **Kills the supervisor** (destroys accumulated context)
3. **Spawns a new supervisor** (more API costs for reading docs + journal + initialization)
4. **The new supervisor does the same nothing** the old one was doing

Estimated waste: 5 sentries x ~$3-5 each in LLM costs = **$15-25 burned today on false positives** before the fixes landed.

### Post-Fix Analysis

The hybrid liveness check (commit b06caa7) should prevent most of these. The flow is now:
- 3 nudges exhaust → liveness check → process alive + at prompt → reset
- This creates an infinite nudge loop instead: nudge every ~10+2+2 = 14 minutes forever

But the fundamental question remains: **should the system be nudging an idle supervisor with no work?** No. If autonomy-check returns nothing actionable (empty mailbox, empty backlog, healthy system), the correct behavior is silence. An idle supervisor with no work is not broken — it's working correctly.

---

## 4. Does the Graduated Nudge System Achieve Anything?

### The Nudge Lifecycle

```
0s     : Supervisor finishes task, goes idle
600s   : Nudge #1 → "autonomy scan found N items: ..."
         Supervisor: "Status: healthy, no action needed" → heartbeat resets
1200s  : Nudge #2 → (same scan, same results)
         Supervisor: "Still idle, nothing to do" → heartbeat resets
1800s  : Nudge #3 → (same scan, same results)
         Supervisor: "Confirmed idle" → heartbeat resets
~1920s : Liveness check → alive → reset nudge counter
~2520s : Nudge #1 again → infinite cycle begins
```

### Verdict: The graduated system is pure noise

The graduation implies escalation — nudge is gentle, sentry is severe. But what actually escalates? Nothing. Each nudge sends the same information. The supervisor gives the same response. The "escalation" is just the monitor counting to 3 and then starting over.

**A truly graduated system would escalate the ACTION**:
1. First nudge: "Here's what autonomy-check found" (informational)
2. Second nudge: "You haven't acted on these. Starting the top backlog item for you." (directive)
3. Third nudge: "Forcing proactive maintenance: killing idle workers, committing uncommitted changes" (automatic)

Currently, all three nudges are identical in effect. The counter exists to gate sentry access, not to drive progressive action.

---

## 5. What Would REAL Autonomy Look Like?

### The Fundamental Architectural Problem

CMUX tries to create autonomy by **poking an agent from the outside**. This is like trying to make a sleeping person productive by shouting at them every 10 minutes. The person wakes up, says "I'm fine," and goes back to sleep.

Real autonomy requires an **internal drive** — the agent itself decides to act, not an external monitor.

### Model A: Internal Event Loop (Recommended)

Instead of the monitor nudging the supervisor, the supervisor should have an internal loop:

```
SUPERVISOR LIFECYCLE:
1. Receive task or event → process it → deliver result
2. After task completion:
   a. Run autonomy-check
   b. If actionable items found → pick highest priority → goto 1
   c. If nothing actionable → write "idle" state → sleep
3. On next external event (mailbox, webhook, user message) → goto 1
```

The key insight: **the supervisor decides to check for work after finishing a task**, not because a monitor told it to. The heartbeat file becomes a signal FROM the supervisor ("I'm alive and my last action was at T") not a signal TO the supervisor ("wake up and do something").

### How To Implement This

The supervisor's post-task behavior needs to change. After any `[DONE]` from a worker or task completion:

```bash
# tools/autonomy-loop (new tool, called by supervisor after each task)
findings=$(tools/autonomy-check)
if [ $? -eq 0 ]; then
    echo "$findings"  # Supervisor reads this and acts
else
    echo "IDLE: No actionable work. Waiting for external events."
    # Write idle marker so monitor knows this is intentional
    echo "idle:$(date +%s)" > .cmux/.supervisor-state
fi
```

Then in SUPERVISOR_ROLE.md, add:
```
After completing any task:
1. Run tools/autonomy-check
2. If it returns work items, act on the highest priority one
3. If nothing, state "Idle: awaiting tasks" and wait
4. DO NOT WAIT TO BE NUDGED — check proactively
```

### Model B: Work Queue-Driven (Complementary to A)

The backlog should BE the autonomy driver. Instead of a heartbeat timer, the system should react to **backlog state changes**:

- New item added to backlog → notify supervisor
- Item priority changes → notify supervisor
- Mailbox message arrives → router already handles this

When the backlog is empty AND the mailbox is empty, idling is correct. No nudge needed. The heartbeat becomes purely a health signal, not an autonomy signal.

### Model C: Differentiated Idle States (Complementary to A+B)

The system needs to distinguish:

| State | Signal | Correct Response |
|-------|--------|-----------------|
| **Active** | Heartbeat < 600s | Do nothing |
| **Idle-with-work** | Heartbeat > 600s + autonomy-check finds items | Nudge once, then auto-act |
| **Idle-without-work** | Heartbeat > 600s + autonomy-check empty | Do nothing. This is correct. |
| **Stuck** | Observation mode, pane frozen 20min | Sentry recovery |
| **Dead** | Process not alive | Sentry recovery |

Currently, the system treats "idle-with-work" and "idle-without-work" identically (nudge both). This is why the nudge feels useless — most of the time the supervisor IS idle-without-work, and nudging it achieves nothing.

---

## 6. Is Heartbeat-as-Tool-Use-Timestamp Even the Right Signal?

### What It Measures vs. What Matters

| Heartbeat measures | What actually matters |
|---|---|
| Time since last tool call | Time since last productive outcome |
| Whether agent is using tools | Whether tasks are progressing |
| Binary alive/dead | Spectrum of idle/working/stuck/dead |

### The Problems With Tool-Use Timestamps

1. **Responding to a nudge counts as "alive"**. The supervisor uses a Bash tool to check health → heartbeat resets → monitor is satisfied → but no real work happened.

2. **A supervisor running in circles looks healthy**. If the supervisor is in a loop calling tools but never completing anything, the heartbeat says "perfectly healthy."

3. **A supervisor waiting correctly looks dead**. Between user tasks, the supervisor SHOULD be idle. But the heartbeat treats this as a problem.

### Better Signals

**Outcome-based tracking**: Instead of "last tool use," track:
- Last task completed (from journal entries or `[DONE]` messages)
- Current task assignment (from worker spawns or mailbox messages)
- Queue depth (backlog items + unprocessed mailbox messages)

**State-based tracking**: Write a state file, not a timestamp:
```
# .cmux/.supervisor-state (written by supervisor, read by monitor)
state: idle          # active | idle | working-on:<task-id>
since: 1708425600    # when this state began
reason: no-pending-work
last_task: "Meta events implementation"
last_completed: 1708425300
```

The monitor reads this and acts differently based on state. No nudge needed for intentional idle. Nudge only for "active" state that's been stale too long (actually stuck).

---

## 7. Concrete Recommendations

### Tier 1: Stop the Bleeding (< 1 hour)

1. **Suppress nudges when autonomy-check finds nothing actionable**. If `tools/autonomy-check` exits 1 (no findings), don't send a nudge. The supervisor has no work. Silence is correct.

2. **Remove sentry escalation from the idle path entirely**. The sentry should ONLY fire from the observation mode path (frozen pane) or when the process is dead. An idle-at-prompt supervisor should never trigger a sentry, period. (Partially done in b06caa7 but should be made more explicit.)

### Tier 2: Make Nudges Actionable (2-4 hours)

3. **Restructure the nudge to be a command, not a status report**. Instead of "Autonomy scan found 3 items: ..." send: "WORK AVAILABLE: Start backlog item #4 'Agent Teams evaluation'. Run: tools/backlog next"

4. **Add `idle-without-work` detection to monitor**. If autonomy-check returns empty, write a "supervisor-idle-clean" marker and suppress all nudges. Only resume nudging when autonomy-check finds something new.

5. **Add the post-task autonomy loop to SUPERVISOR_ROLE.md**. After every task completion, the supervisor should run `tools/autonomy-check` on its own, without waiting for a heartbeat nudge. Make this an explicit instruction.

### Tier 3: Architectural Fix (1-2 days)

6. **Replace the heartbeat file with a state file**. Write `state:reason:timestamp` instead of just a timestamp. Let the monitor make intelligent decisions based on the supervisor's declared state.

7. **Make the backlog the autonomy driver**. When a backlog item is added or a mailbox message arrives, the router/monitor should immediately notify the supervisor (not wait for a heartbeat cycle). The heartbeat becomes purely a health check, not an autonomy mechanism.

8. **Kill the graduated nudge system**. Replace with: single nudge with specific work directive → if supervisor doesn't act within N minutes and has work available → auto-claim the backlog item and spawn a worker directly from monitor.sh, bypassing the supervisor entirely.

### Tier 4: True Autonomy (Aspirational)

9. **Internal event loop in the supervisor agent**. Modify the supervisor's Claude Code setup to include a persistent instruction: "After each response, if you have no pending work, run `tools/autonomy-check`. If it finds work, start on it. If not, wait silently." This eliminates the need for external nudging entirely.

10. **Pattern crystallization** (from OpenClaw). Track what the supervisor does with nudge findings. If it always kills idle workers → create a cron job that does this automatically. If it always checks the same 3 things → create a single compound tool. Reduce LLM involvement for routine decisions.

---

## 8. Summary Verdict

**The heartbeat system sounds good in theory because it maps to a real intuition: "poke the system if it's idle." But it fails in practice because:**

1. **It can't distinguish intentional idle from stuck** (partially fixed by observation mode, but the idle path still nudges pointlessly)
2. **The nudges carry information but not instructions** (the supervisor acknowledges, doesn't act)
3. **The supervisor has no autonomous behavior defined** (SUPERVISOR_ROLE.md is entirely reactive)
4. **The delivery mechanism (tmux send-keys) is unreliable and conversational** (not a control plane)
5. **The escalation (nudge → nudge → nudge → liveness check → reset) is circular** (never achieves anything different on iteration)
6. **The signal (tool-use timestamp) conflates activity with productivity** (responding to a nudge resets the timer without producing value)

**The system needs to flip from "monitor drives agent" to "agent drives itself, monitor verifies."** Until then, the heartbeat is an expensive no-op that wastes LLM API calls on supervisors responding "I'm fine, nothing to do" every 10 minutes.
