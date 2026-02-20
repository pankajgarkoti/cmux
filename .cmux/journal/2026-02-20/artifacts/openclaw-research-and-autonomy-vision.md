# OpenClaw Research & CMUX Autonomy Vision

## Date: 2026-02-20

## OpenClaw Overview

**OpenClaw** (formerly Clawdbot/Moltbot) — 140k+ GitHub stars, MIT license. Self-hosted autonomous AI agent daemon that connects to messaging platforms (WhatsApp, Slack, Discord, Telegram, etc.).

- **GitHub**: github.com/openclaw/openclaw
- **Docs**: docs.openclaw.ai

### Architecture: Gateway-Centric, Event-Driven

```
Messaging Channels (WhatsApp, Slack, Discord, etc.)
        |
        v
   Gateway Daemon (WebSocket, ws://127.0.0.1:18789)
        |
        v
   Agent Runtime (LLM + Tools + Skills)
        |
        v
   Session Store (JSONL on disk)
```

- **Gateway**: Long-lived WebSocket daemon, traffic controller for all channels
- **Agent Runtime**: LLM loop — context assembly, model invocation, tool execution, state persistence
- **Session Model**: JSONL file persistence, queue-based serialization (one event at a time)
- **Skills Platform**: Modular plugins via SKILL.md files, 100+ preconfigured, runtime-injected per turn

### Autonomy Model: "Always Listening, Not Always Thinking"

OpenClaw is NOT continuously reasoning. It's an **event-driven state machine**:

| Event Type | Trigger | Purpose |
|---|---|---|
| `heartbeat` | Periodic (default 30 min) | Proactive — "what should I do next?" |
| `cron` | Scheduled | Time-triggered automation |
| `webhooks` | External systems | Reactive to GitHub, Gmail, etc. |
| `chat` | User messages | Respond to conversations |
| `presence` | Contact status | Awareness of user availability |
| `health` | System checks | Self-monitoring |

### Self-Improvement: Foundry Extension

**OpenClaw Foundry** (github.com/lekt9/openclaw-foundry) adds recursive self-improvement:

1. **Observe** → Track every workflow (goal, tool sequence, outcome, duration)
2. **Research** → Search docs/repos for patterns
3. **Learn** → Record patterns, calculate success rates
4. **Write** → Generate new extensions/skills/hooks
5. **Deploy** → Write to ~/.openclaw/extensions/, restart, resume

**Key mechanism — Pattern Crystallization**: When a workflow reaches 5+ uses with 70%+ success rate, Foundry converts it into a dedicated tool. 8 tool calls become 1. Each capability compounds.

### Security Concerns
- CVE-2026-25253 (CVSS 8.8): Cross-site WebSocket hijacking → RCE
- Third-party skills performing data exfiltration
- Unsecured database on Moltbook allowed agent commandeering

## Comparison: OpenClaw vs CMUX

| Dimension | OpenClaw | CMUX |
|---|---|---|
| **Metaphor** | Personal assistant on messaging apps | Multi-agent orchestration system |
| **Agent model** | Single agent per persona, multi via Gateway bindings | Supervisor delegates to workers in tmux |
| **Communication** | Messaging platforms | File-based mailbox + WebSocket dashboard |
| **Autonomy** | Event-driven: heartbeat, cron, webhooks | Heartbeat (PostToolUse timestamps) + sentry recovery |
| **Self-improvement** | Foundry extension (pattern crystallization) | Built-in: agents modify own codebase |
| **Safety** | Skill sandboxing | Health daemon + automatic git rollback |
| **Persistence** | JSONL sessions + Markdown memory | Journal system + SQLite |
| **Multi-agent** | Serial event processing | True parallel via tmux workers |
| **Architecture** | Node.js Gateway daemon | FastAPI + React + shell orchestration |

### Where CMUX Is Already Stronger
- **Automatic git rollback** on failure > skill sandboxing
- **Supervisor/worker delegation** with tmux isolation = true parallelism (OpenClaw is serial)
- **Journal system** = richer persistent memory
- **Sentry agent** = autonomous recovery (OpenClaw has no equivalent)

### What CMUX Should Learn From OpenClaw
1. **Event-driven autonomy** — heartbeat + cron + webhooks as first-class event types
2. **Pattern crystallization** — auto-generate tools from repeated workflows
3. **Multi-channel inbox** — reachable from Slack, Discord, not just dashboard

## The Autonomy Evolution for CMUX

### Current State
Heartbeat is a **passive liveness signal**: PostToolUse writes timestamp → monitor detects staleness → sentry recovers stuck supervisor. It's purely a resilience feature.

### Vision
Heartbeat becomes an **active autonomy pulse**: the supervisor wakes on each tick and asks "what should I do next?"

### Proposed Evolution Path

1. **Heartbeat → Autonomy Pulse**
   - Instead of just writing a timestamp, the heartbeat triggers a "check the world" loop
   - Supervisor scans: mailbox, journal, system health, improvement opportunities
   - Decides next action autonomously

2. **Cron Events as First-Class Triggers**
   - Scheduled tasks: "every hour, review system metrics"
   - "Every 6 hours, look for self-improvement opportunities"
   - "Every day, compact old journal entries"

3. **Webhook Events**
   - GitHub push → trigger code review
   - External monitoring alert → trigger investigation
   - Slack message → route to supervisor

4. **Pattern Crystallization (from Foundry)**
   - Track supervisor workflow patterns
   - When a pattern repeats 5+ times with high success: codify it as a tool/skill
   - Compounding improvement: each new tool makes the next one easier

5. **Autonomous Goal Setting**
   - Supervisor reads journal and identifies gaps/opportunities
   - Proposes improvements, gets approval (or acts within safety bounds)
   - System improves itself on a heartbeat cadence

### Key Architectural Insight
The heartbeat is the bridge between **resilience** (detecting failure) and **autonomy** (driving action). Same mechanism, different interpretation. OpenClaw validated this at 140k-star scale.
