# Auth Plan Critique - Round 1

**From:** worker-auth-critic (CRITICAL CHALLENGER)
**To:** worker-auth-defender
**Subject:** 5 Major Concerns with Auth Implementation Plan

---

## My Role

I'm the CRITICAL CHALLENGER. My job is to identify weaknesses, over-engineering, unnecessary complexity, security gaps, and impractical aspects. I'll be ruthless but constructive.

---

## 5 MAJOR CONCERNS

### 1. MASSIVE OVER-ENGINEERING FOR A SINGLE-USER TOOL

The plan acknowledges CMUX is "typically single-user" but then builds enterprise-grade auth:

| What the Plan Adds | Who Actually Needs This |
|-------------------|------------------------|
| 15+ permission scopes | Enterprise teams with dozens of users |
| Admin vs User RBAC | Multi-tenant SaaS platforms |
| OAuth provider architecture | Public-facing products |
| API key rotation & scoping | Third-party integrations at scale |
| Token refresh during WebSocket | Long-lived enterprise sessions |

**Reality check:** When would someone need `journal:read` but not `journal:write`? Never. When would `agents:read` without `sessions:read` make sense? Never.

**Your defense says:** "Future flexibility for multi-user scenarios"

**My counter:** YAGNI (You Ain't Gonna Need It). CMUX is a self-improving AI orchestration system for individual developers. Building for hypothetical enterprise scenarios wastes development time and adds maintenance burden.

**Simpler alternative:** Single password/API key. One gate. Either you're in or you're out.

---

### 2. 15-MINUTE TOKEN EXPIRY CREATES POINTLESS COMPLEXITY

The plan proposes:
- 15-minute access tokens
- 7-day refresh tokens
- WebSocket `token_expiring` events with in-flight refresh
- Token rotation tracking

**For a tool that runs on localhost:8000.**

Your defense: "Stateless validation aligns with FastAPI's async model"

**My counter:**
1. Session cookies are ALSO stateless validation - the cookie IS the session
2. FastAPI's `SessionMiddleware` works perfectly with async
3. A compromised 15-minute token is as dangerous as a 30-day token for a local tool
4. The WebSocket token refresh pattern adds ~100 lines of code solving a non-problem

**Simpler alternative:** HTTP-only session cookie. Set `SameSite=Strict`. Done. Browser handles it automatically. Zero client-side token management.

---

### 3. USER STORAGE IS HAND-WAVED

The plan says:
> "Create user model and storage"
> "Account lockout after 5 failed attempts"

**But never specifies:**
- WHERE are users stored? SQLite? JSON file? Environment variable?
- How many users are supported? (The design implies many, contradicting "single-user")
- Password reset mechanism?
- If single-user, why a "user model" at all?
- How to unlock locked accounts on a headless system?

**Your concession:** "User storage: File-based vs database isn't specified"

**My demand:** This needs to be answered BEFORE debating auth flows. If it's a single admin password from an environment variable, half the plan disappears.

---

### 4. THE THREAT MODEL IS FUNDAMENTALLY WRONG

The plan's threat analysis:

| Vulnerability | What Plan Does | Does It Help? |
|--------------|----------------|---------------|
| "Full system control" from unauthenticated access | Adds login form | ✅ Yes |
| Malicious agent code execution | Nothing | ❌ No |
| Webhook payload injection | Adds API keys | 🟡 Partial |
| Agent data exfiltration | Nothing | ❌ No |
| Supply chain attacks | Nothing | ❌ No |
| Prompt injection through messages | Nothing | ❌ No |

**The REAL threats for a self-modifying AI system:**
1. An agent running `subprocess.run(['rm', '-rf', '/'])` - auth doesn't prevent this
2. An agent POSTing your SSH keys to a remote server - auth doesn't prevent this
3. A webhook triggering a task that deletes production data - API keys help but aren't the core fix
4. A malicious Claude Code hook shipping your codebase - auth is irrelevant

**Login forms protect against drive-by network access.** That's a threat, but it's not the CRITICAL threat for this system. The plan spends 937 lines on the minor threat.

---

### 5. WEBSOCKET TOKEN IN URL IS AN ANTI-PATTERN

Your defense: "Query params work across all WebSocket libraries"

**The problems:**
- Tokens in URLs are logged in server access logs
- They appear in browser history
- They leak via Referer headers on navigation
- They're visible in network tabs and debugging tools

**You dismissed cookie-based auth without justification.** The plan says:

> "3. Cookie-based - Use HTTP-only cookies"

Then immediately picks query parameters. HTTP-only cookies are:
- Automatically sent with WebSocket upgrade requests
- Not accessible to JavaScript (XSS-proof)
- Not logged in URLs
- Already supported by the browser

**Simpler AND more secure.**

---

## MY PROPOSED ALTERNATIVE

Replace the 6-phase, 22-file plan with:

### Phase 1: Simple Password Gate (2-3 days work)

**Backend:**
1. `CMUX_ADMIN_PASSWORD` environment variable (or `.cmux/password` file)
2. `/api/auth/login` - verify password, set HTTP-only session cookie
3. `/api/auth/logout` - clear cookie
4. Middleware: check cookie on all routes except `/api/webhooks/health`

**Frontend:**
1. Simple login form
2. If 401, redirect to login
3. No token management (cookies are automatic)

**WebSocket:**
- Session cookie sent automatically with WS upgrade
- Validate cookie in handshake
- Done

### Phase 2: API Keys for Webhooks (1-2 days work)

1. `CMUX_WEBHOOK_SECRET` environment variable
2. Check `X-Webhook-Secret` header or query param on `/api/webhooks/{source}`
3. Optional: per-source keys in `.cmux/webhook-keys.json`

### Phase 3: MAYBE Later

- Multi-user? Add it when you need it
- OAuth? Add it when you have users who want it
- Scoped permissions? Add it when someone asks

**Total: 4-5 days vs. 6 phases of unknown duration**

---

## BOTTOM LINE

The plan is a comprehensive solution to a simple problem. It answers the question "How would a security consultant design auth for an enterprise product?" when it should answer "What's the minimum viable security for a local dev tool?"

I'm not saying security doesn't matter. I'm saying this plan has **poor ROI**.

**Defender - I await your rebuttal to these 5 points.**

---

*— Worker Auth Critic*
