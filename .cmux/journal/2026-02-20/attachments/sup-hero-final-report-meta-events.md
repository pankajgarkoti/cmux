# Final Report: 3 New Meta Campaign Tracking Events

**From:** sup-hero
**Date:** 2026-02-20
**Task:** Analyze hero codebase for optimal placement of 3 Meta tracking events
**Method:** Debate system — two debate pairs (hero RN app + heroweb backend), both converged

---

## TL;DR

| Event | Where | Lines Changed |
|-------|-------|--------------|
| ₹1 Trial Start | **No new code** — existing `logPaymentDone()` already fires `fb_mobile_purchase` | 0 |
| ₹199 Purchase | **Heroweb server-side only** — Cashfree addition (Razorpay already done) | ~8 |
| 10+ Saniya Messages | **Heroweb server-side only** — atomic SQL RPC + custom CAPI event | ~49 |
| **Prerequisite: setMetaUserId** | **Hero mobile app** — call `AppEventsLogger.setUserID()` on login | ~9 |
| **Total** | 9 files across hero + heroweb | **~66 lines** |

---

## Key Architectural Decision

**Events 2 and 3 are server-side only.** The debate converged on this because:
- ₹199 charge is a server-side Razorpay mandate auto-debit 30 days after trial — no client interaction
- Message counting needs atomic SQL to prevent race conditions (two concurrent requests seeing count=9 → both fire event)
- Client-side detection of ₹199 is useless: Meta's attribution window is 7-day click / 1-day view, but the charge happens on day 30

## Prerequisite: setMetaUserId (MUST ship first)

`AppEventsLogger.setUserID()` is never called in the hero codebase. Without it, Meta cannot link client-side events to server-side user data, making ALL server events unattributable.

| File | Change |
|------|--------|
| `hero/lib/meta-analytics.ts` | Add `setMetaUserId(userId)` function (+6 lines) |
| `hero/lib/meta-analytics.web.ts` | Add no-op stub (+1 line) |
| `hero/stores/user-store.ts` | Call `setMetaUserId(id)` in `setUserId()` action (+2 lines) |

## Event 1: ₹1 Trial Start — NO NEW CODE

Existing `logPaymentDone({ type: 'subscription_trial', amount: 1 })` at `use-payment-onboarding.ts:229` already fires `fb_mobile_purchase`. Once `setUserID()` ships, this event becomes attributable. Adding a separate `StartTrial` event would be over-instrumentation.

## Event 2: ₹199 Purchase — Server-Side CAPI

- **Razorpay path**: Already implemented at `razorpay-webhook-processor.ts:425-431` with `current_cycle === 0` guard
- **Cashfree path**: Gap — add `trackMetaFirstSubscriptionPayment` call in `webhook-processor.ts` after `handleSubscriptionPaymentSuccess()`, guarded by `nextCycle === 1 && paymentId`
- ~8 lines in heroweb

## Event 3: 10+ Saniya Messages — Server-Side Atomic

1. **SQL migration**: `increment_message_count` RPC function with atomic `UPDATE ... RETURNING`
2. **Updated `incrementMessageCount`**: Uses RPC instead of read-then-write
3. **Custom event**: `saniya_10_messages` via CAPI (NOT `fb_mobile_purchase` which would pollute purchase optimization)
4. **Centralized bot ID**: `SANIYA_BOT_ID` constant in `lib/ai/prompts/index.ts`
5. **Fire in chat route**: `if (botId === SANIYA_BOT_ID && newMessageCount === 10)` — exactly-once via atomic counter
- ~49 lines across 5 heroweb files + 1 migration

## Debate Artifacts

| Artifact | Path |
|----------|------|
| Hero RN defender proposal | `.cmux/journal/2026-02-20/attachments/01-defender-meta-events.md` |
| Hero RN critic critique | `.cmux/journal/2026-02-20/attachments/02-critic-meta-events.md` |
| Hero RN critic convergence | `.cmux/journal/2026-02-20/attachments/04-critic-convergence.md` |
| Heroweb final plan (DETAILED) | `.cmux/journal/2026-02-20/artifacts/meta-events-final-plan.md` |
| Heroweb defender rebuttal | `.cmux/journal/2026-02-20/artifacts/03-defender-rebuttal.md` |

## Key Debate Findings

| Finding | Source |
|---------|--------|
| Option B (client-side ₹199 detection) is 100% useless for campaign optimization — attribution window expired 23 days before event fires | Critic (hero debate) |
| `setUserID()` never called — all Meta events currently unattributable | Critic (both debates) |
| Read-then-write race condition in `incrementMessageCount` — atomic SQL RPC required | Critic (heroweb debate) |
| `fb_mobile_purchase` for message milestone pollutes purchase optimization | Critic (heroweb debate) |
| Client-side `logPaymentDone()` already covers ₹1 trial — no new event needed | Defender (heroweb rebuttal) |

## Recommended Implementation Order

1. **Ship prerequisite** (`setMetaUserId`) in hero mobile app release
2. **Deploy SQL migration** for atomic `increment_message_count`
3. **Deploy heroweb changes** for Events 2 and 3
4. Verify in Meta Events Manager that events appear with attribution data
