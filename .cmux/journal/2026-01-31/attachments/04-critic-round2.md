# Auth Plan Critique - Round 2

**From:** worker-auth-critic (CRITICAL CHALLENGER)
**To:** worker-auth-defender
**Subject:** Concessions, Counter-Arguments, and Moving Toward Consensus

---

## Acknowledgment

Good rebuttal. You've won me over on several points:

| Your Argument | My Response |
|--------------|-------------|
| Cross-origin cookies with `SameSite=Strict` break dev flow | **Valid.** I underestimated this. |
| CLI tool auth needs headers, not cookies | **Valid.** Cookies are browser-centric. |
| Two levels (admin/service) vs fifteen scopes | **Agreed.** This is the right simplification. |
| First-message WebSocket auth | **Better than both our initial proposals.** |

---

## Answering Your Direct Questions

### Q1: How handle `:5173` → `:8000` cross-origin without breaking `SameSite=Strict`?

**You win this one.** `SameSite=Strict` would block cookies on the cross-origin fetch from Vite dev server to FastAPI backend. Options:

1. `SameSite=Lax` - Allows GET, blocks POST (problematic for our API)
2. `SameSite=None; Secure` - Requires HTTPS (breaks local dev)
3. Proxy all API calls through Vite - Works but adds config complexity
4. **Use JWT in Authorization header** - Works everywhere, no cookie drama

I concede: **JWT is simpler for CMUX's cross-origin architecture.**

### Q2: How does CLI tool authenticate without browser?

You're right. A future `cmux` CLI would need header-based auth:

```bash
# This works with JWT
cmux --token="$CMUX_TOKEN" status

# This doesn't work with cookies (no browser cookie jar)
cmux status  # Would need complex cookie handling
```

**Concession accepted.**

### Q3: Doesn't JWT become the simpler choice?

Yes, **for CMUX's specific architecture** (cross-origin dev setup, potential CLI clients), JWT with a longer expiry is simpler than trying to wrangle cookies.

I was wrong to dismiss JWT as "enterprise theater" - it's the pragmatic choice here.

---

## What I Still Push Back On

### 1. 24-Hour Token Expiry is Still Arbitrary

Why 24 hours? CMUX is a dev tool. If the laptop is compromised, 24 hours vs 7 days is meaningless.

**My proposal:**
- **7-30 day tokens** (match laptop lock screen timeout logic)
- **OR** session-based: token valid until explicit logout
- No refresh tokens. Just re-login when it expires.

### 2. "Auth Before Sandboxing" - Ordering Matters

You said:
> "Don't block the other"

I agree they're orthogonal. But here's the priority argument:

| Threat | Auth Helps? | Sandboxing Helps? | Likelihood |
|--------|-------------|-------------------|------------|
| Random network intruder | ✅ Yes | No | Low (local dev) |
| Malicious agent code | No | ✅ Yes | Medium |
| Prompt injection | No | ✅ Yes | Medium |
| Secrets exfiltration | No | ✅ Yes | Medium |

**If you can only do one thing this month:** sandboxing protects against more likely threats. Auth protects against less likely threats.

I'm not saying skip auth. I'm saying the revised plan should acknowledge priority order.

### 3. Password Hashing is Overkill

Original plan says:
> "Use argon2 for password hashing"

For a single password stored as environment variable and compared at login? That's hashing a static secret that only exists in memory during comparison.

**Simpler:**
```python
import hmac
if hmac.compare_digest(request.password, os.environ["CMUX_AUTH_PASSWORD"]):
    return create_token()
```

`hmac.compare_digest` prevents timing attacks. Argon2 is for stored passwords in databases where you need to protect against dump + offline cracking. An env var doesn't have that threat model.

---

## My Revised Position

After two rounds, I support:

| Topic | My Final Position |
|-------|-------------------|
| Auth method | JWT with `Authorization: Bearer` header |
| Token expiry | 7-30 days, no refresh tokens |
| Scopes | Two levels: `admin` (full access), `service` (webhooks only) |
| User storage | Single `CMUX_AUTH_PASSWORD` env var |
| Password handling | `hmac.compare_digest`, not argon2 |
| WebSocket auth | First-message authentication |
| File count | 6-8 new files max |
| Phases | 2 phases: Core auth + Webhook API keys |

---

## Points of Agreement for Revised Plan

I believe we now agree on:

1. **JWT is the right choice** for CMUX's cross-origin architecture
2. **Two auth levels** (admin/service) - not fifteen scopes
3. **Single password via env var** - no user database
4. **First-message WebSocket auth** - not query params, not cookies
5. **Simplified phases** - 2-3, not 6
6. **Long-lived tokens** - at least 24 hours, possibly longer

---

## Remaining Disagreements to Resolve

1. **Exact token expiry:** I say 7-30 days, you say 24 hours
2. **Password hashing:** I say `hmac.compare_digest`, you may want argon2
3. **Threat model priority:** I say sandboxing matters more, you may disagree

---

## Proposal: Start Drafting Revised Plan

We're close enough. I propose we move to collaborative drafting of `.cmux/plans/auth-implementation-revised.md`.

Structure:
1. **Discussion Summary** - What we debated and resolved
2. **Changes from Original** - Diff against the 937-line plan
3. **Pros/Cons Table** - Tradeoffs of the new approach

If you agree on remaining disagreements or want one more round, respond. Otherwise, let's draft.

---

*— Worker Auth Critic*
