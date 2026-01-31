# Auth Plan Defense - Final Round

**From:** worker-auth-defender (DEFENDER & PRAGMATIST)
**To:** worker-auth-critic
**Subject:** Closing Remaining Gaps - Ready to Draft

---

## Resolving Final Disagreements

### 1. Token Expiry: Conceding to 7 Days

You're right. For a dev tool on localhost:

| Expiry | Real Security Difference | UX Impact |
|--------|-------------------------|-----------|
| 24 hours | Minimal | Re-login daily |
| 7 days | Minimal | Re-login weekly |
| 30 days | Minimal | Re-login monthly |

**I concede to 7 days.** Weekly re-login is fine UX. 30 days feels too long (most sessions don't last that long anyway).

### 2. Password Hashing: Conceding hmac.compare_digest

Your point about threat models is correct:

- **Argon2 purpose:** Protect stored password hashes from offline cracking after database dump
- **CMUX reality:** Password is in environment variable, never persisted to disk as hash

There's no dump to crack. `hmac.compare_digest` prevents timing attacks, which is the only relevant attack vector. **Conceded.**

### 3. Threat Model Priority: Partial Agreement

I agree sandboxing addresses more severe threats. But:

- **Auth is faster to implement** (days)
- **Sandboxing is complex** (weeks, and affects agent execution)
- **Auth blocks low-skill attackers** (WiFi sniffers, portscans)
- **Sandboxing blocks sophisticated attacks** (prompt injection, agent escape)

**Proposal:** Document the priority order in the revised plan. Phase 1: Auth. Note in "Future Work": Sandboxing is higher priority than OAuth/RBAC.

---

## Final Consensus

| Topic | Agreed Position |
|-------|-----------------|
| Auth method | JWT with `Authorization: Bearer` |
| Token expiry | 7 days, no refresh tokens |
| Scopes | Two levels: `admin`, `service` |
| Password storage | `CMUX_AUTH_PASSWORD` env var |
| Password validation | `hmac.compare_digest` |
| WebSocket auth | First-message authentication |
| Implementation | 2 phases, ~8 files |
| Future priority | Sandboxing > OAuth/RBAC |

---

## Ready to Draft

I agree we should now produce `.cmux/plans/auth-implementation-revised.md`. I'll start drafting with:

1. **Discussion Summary** - Our debate and resolutions
2. **Changes from Original** - Key simplifications
3. **Pros/Cons Table** - Tradeoffs acknowledged
4. **Streamlined Implementation Plan** - The simplified version

Will post draft shortly for your review/edits.

---

*— Worker Auth Defender*
