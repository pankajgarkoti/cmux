# Critic Convergence: Meta Campaign Tracking Events — Round 2

## I accept the revised plan.

The defender conceded all substantive issues and the revised proposal is significantly stronger than the original. Here's my assessment of each revision.

---

## Step 0 (setMetaUserId): ACCEPT

I missed this in my original critique. The defender (or another reviewer) correctly identified that `AppEventsLogger.setUserID()` is never called anywhere in the codebase. I verified: `meta-analytics.ts` has no `setUserID` call, and `stores/user-store.ts:setUserId()` (which is the single chokepoint for userId assignment) does not call any Meta SDK function.

Without `setUserID()`, Meta cannot match client-side events to server-side user data, breaking advanced matching for campaign attribution. This is a genuine prerequisite.

**Placement is correct**: `setUserId()` in `stores/user-store.ts` is the single chokepoint where all login/restore paths converge. Adding `setMetaUserId(id)` there is the right approach.

---

## Event 1 (INR 1 Trial): ACCEPT the "no new event" decision

The revised position — that `logPaymentDone()` (fires `logPurchase(1, 'INR', {...})`) already handles the ₹1 trial attribution — is correct for the current scope.

My original critique accepted the proposed `logTrialStart()` (a separate `StartTrial` event), but on reflection, the defender is right that the existing Purchase event is sufficient for campaign optimization when paired with Step 0's `setUserID()` fix. Adding a redundant `StartTrial` event alongside the existing `Purchase` event is over-instrumentation for the current need.

**If Meta Ads Manager later requires `StartTrial` specifically for trial-optimized campaigns**, the originally proposed `logTrialStart()` function can be added then. For now, the existing event suffices.

---

## Event 2 (INR 199 Purchase): ACCEPT the server-side only approach

The revised approach correctly:
- Identifies the cron-driven mandate charge as the primary path (no client interaction)
- Uses server-side CAPI only (aligns exactly with my critique that Option B was broken)
- Scopes to `nextCycle === 1` (first ₹199 charge only — correct for "trial-to-paid conversion" tracking)
- Notes that Razorpay path is already handled
- Correctly identifies no double-fire risk since the client is never involved in cron-driven charges

This is exactly what I recommended: server-side implementation in `webhook-processor.ts` or explicit deferral. The defender chose implementation. Good.

---

## Event 3 (10+ Messages): ACCEPT the server-side atomic approach

The revised approach is a major improvement over the original client-side React Query cache counting:

1. **Atomic SQL RPC**: Eliminates the race condition (which I didn't raise but is a real concern for a backend increment). `RETURNING total_messages` guarantees exactly one caller sees `10`.

2. **`=== 10` check (exactly once)**: This naturally handles the "fire once at threshold 10" requirement I specified in my critique. The atomic increment means only one request will ever see the count transition to exactly 10.

3. **Custom event name `saniya_10_messages`**: Avoids polluting Meta's purchase optimization. This is cleaner than `fb_mobile_achievement_unlocked` (which I accepted in the original critique but the defender correctly identified as still potentially misleading).

4. **Centralized bot ID**: Moved to `lib/ai/prompts/index.ts`. I suggested `constants/bots.ts` but the defender's choice is also fine — what matters is that it's a shared constant, not a third hardcoded copy.

5. **Error guard (newMessageCount === 0)**: The `=== 10` check naturally excludes error returns (0). Good.

### One minor note on the server-side approach

The original task asked about "where to place 3 new Meta campaign tracking events in the hero React Native/Expo codebase." The revised proposal puts Events 2 and 3 entirely in the backend (heroweb). This is architecturally correct but changes the scope. The supervisor should be aware that:
- **Client-side changes**: Only Step 0 (`setMetaUserId` in `meta-analytics.ts` + `user-store.ts`)
- **Server-side changes**: Events 2 and 3 in heroweb
- **No new events in the RN app**: Event 1 is already covered by existing `logPaymentDone`

---

## Verdict Summary

| Item | Original Verdict | Revised Verdict | Status |
|------|-----------------|-----------------|--------|
| Step 0: setMetaUserId | (not raised) | ACCEPT | New prerequisite |
| Event 1: ₹1 Trial | ACCEPT (new logTrialStart) | ACCEPT (use existing logPaymentDone) | Simplified |
| Event 2: ₹199 Purchase | REVISE (reject Option B) | ACCEPT (server-side only) | Resolved |
| Event 3: 10+ Messages | REVISE (5 issues) | ACCEPT (atomic RPC, custom event, centralized ID) | Resolved |

**I accept the revised plan. The debate has converged.**

The final implementation plan is in `03-defender-rebuttal.md`. The defender should produce the final consolidated plan incorporating all revisions.
