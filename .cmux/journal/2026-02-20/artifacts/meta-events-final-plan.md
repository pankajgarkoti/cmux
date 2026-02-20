# Final Plan: 3 New Meta Tracking Events for Heroweb

**Status:** CONVERGED (critic accepts revised proposal)
**Date:** 2026-02-20
**Authors:** defender (proposal), critic (review)
**Debate rounds:** 2 (proposal → critique → rebuttal → convergence)

---

## Executive Summary

Place 3 Meta tracking events in the heroweb codebase. After debate, the plan is:
- **Event 1 (₹1 Trial):** No heroweb changes — client-side `logPaymentDone()` already handles this
- **Event 2 (₹199 Purchase):** Server-side only, add Cashfree support (Razorpay already done)
- **Event 3 (10+ Saniya Messages):** Server-side in chat route, with atomic SQL increment and custom event name

**Prerequisite:** Ship `AppEventsLogger.setUserID()` in the hero mobile app to enable ad attribution.

---

## Step 0: PREREQUISITE — Attribution Fix (Hero Mobile App)

**Must ship before or simultaneously with heroweb changes.**

### Why
Server-side Meta events use `anon_id: <supabase-uuid>`. Client-side events use the device advertising ID. Without `setUserID()`, Meta cannot link these two identities, making server-side events unattributable to ad campaigns.

### Changes

**File: `hero/lib/meta-analytics.ts`** — Add new function:
```typescript
export function setMetaUserId(userId: string): void {
  try {
    AppEventsLogger.setUserID(userId);
  } catch (e) {
    // Swallow — non-critical
  }
}
```

**File: `hero/stores/user-store.ts`** — Call in `setUserId()` action:
```typescript
import { setMetaUserId } from '@/lib/meta-analytics';

// Inside setUserId() action (the chokepoint where all login paths converge)
setMetaUserId(id);
```

**File: `hero/lib/meta-analytics.web.ts`** — Add no-op stub:
```typescript
export function setMetaUserId(_userId: string): void {}
```

---

## Event 1: INR 1 Trial Start — NO HEROWEB CHANGES

### Decision
The client-side `logPaymentDone({ type: 'subscription_trial', amount: 1 })` at `hero/hooks/use-payment-onboarding.ts:229` is already the source of truth. The hero CHANGELOG confirms the intentional move from server-side to client-side for trial events.

Adding a server-side duplicate would cause double-counting. Once Step 0 ships, client-side events will be attributable.

### What already exists
| Gateway | Client-side event | Server-side event |
|---------|------------------|-------------------|
| Razorpay | `logPaymentDone()` → `fb_mobile_purchase` | None (intentionally removed) |
| Cashfree | `logPaymentDone()` → `fb_mobile_purchase` | None |

---

## Event 2: INR 199 Purchase Complete — CASHFREE ADDITION ONLY

### Decision
- **Razorpay:** Already implemented at `razorpay-webhook-processor.ts:425-431` with correct `current_cycle === 0` guard. No changes needed.
- **Cashfree:** Gap identified — add `trackMetaFirstSubscriptionPayment` call.

The ₹199 charge is cron-driven (no client interaction), so only server-side can fire. No double-fire risk.

### Changes

**File: `lib/payments/webhook-processor.ts`** — Add import:
```typescript
import { trackMetaFirstSubscriptionPayment } from '@/lib/meta-capi';
```

**Insert after line 684** (after `identifyUserSegment(...)` in `handleSubscriptionPaymentSuccess()`):
```typescript
// Meta CAPI: first ₹199 charge (trial → paid, cycle 0 → 1)
if (nextCycle === 1 && paymentId) {
  trackMetaFirstSubscriptionPayment({
    userId: user_id,
    paymentId: paymentId,
    amount: paymentAmount,
  });
}
```

**Guard:** `paymentId` must be truthy — skip event if no real payment ID available (don't fall back to subscriptionId).

---

## Event 3: 10+ Messages Sent to Saniya — FULL IMPLEMENTATION

### Overview
Fire a custom Meta event when a user sends their 10th message to Saniya. Uses atomic SQL increment to guarantee exactly-once firing.

### Change 1: Atomic SQL increment

**New migration: `supabase/migrations/YYYYMMDD_atomic_increment_messages.sql`**
```sql
CREATE OR REPLACE FUNCTION increment_message_count(
  p_user_id TEXT,
  p_bot_id TEXT
) RETURNS INTEGER AS $$
DECLARE
  v_new_count INTEGER;
BEGIN
  UPDATE hero_app_user_profiles
  SET total_messages = total_messages + 1,
      updated_at = NOW()
  WHERE user_id = p_user_id AND bot_id = p_bot_id
  RETURNING total_messages INTO v_new_count;

  -- If no row found, create profile first then increment
  IF v_new_count IS NULL THEN
    INSERT INTO hero_app_user_profiles (user_id, bot_id, conversation_count, relationship_stage, user_profile, total_messages)
    VALUES (p_user_id, p_bot_id, 0, 'stranger', '{}'::jsonb, 1)
    ON CONFLICT (user_id, bot_id) DO UPDATE SET
      total_messages = hero_app_user_profiles.total_messages + 1,
      updated_at = NOW()
    RETURNING total_messages INTO v_new_count;
  END IF;

  RETURN v_new_count;
END;
$$ LANGUAGE plpgsql;
```

**Note:** Parameter types should match actual column types. Verify `user_id` and `bot_id` column types in the `hero_app_user_profiles` table before deploying. The defender's original proposal used UUID; this plan uses TEXT as a conservative default based on the application code patterns. Adjust as needed.

### Change 2: Update `incrementMessageCount` to use RPC

**File: `lib/db/queries/app-user-profiles.ts`** — Replace `incrementMessageCount`:
```typescript
async incrementMessageCount(userId: string, botId: string): Promise<number> {
  try {
    const { data, error } = await (this.supabase as any)
      .rpc('increment_message_count', {
        p_user_id: userId,
        p_bot_id: botId,
      });

    if (error) {
      throw new Error(`Failed to increment message count: ${error.message}`);
    }

    return data as number;
  } catch (error) {
    logger.error('db.user-profiles', 'incrementMessageCount failed', error);
    return 0;
  }
}
```

### Change 3: Parameterize `_eventName` in `sendAppEvent`

**File: `lib/meta-capi.ts`** — Add `fbEventName` parameter:
```typescript
async function sendAppEvent(params: {
  eventName: string;
  value: number;
  currency: string;
  userId: string;
  paymentId: string;
  fbEventName?: string;  // Override _eventName (default: fb_mobile_purchase)
}): Promise<void> {
  // ... existing setup code ...
  const body = {
    event: 'CUSTOM_APP_EVENTS',
    application_tracking_enabled: 1,
    advertiser_tracking_enabled: 1,
    anon_id: params.userId,
    custom_events: JSON.stringify([
      {
        _eventName: params.fbEventName || 'fb_mobile_purchase',
        _valueToSum: params.value,
        fb_currency: params.currency,
        fb_content_id: params.eventName,
        fb_content_type: 'product',
        payment_id: params.paymentId,
      },
    ]),
  };
  // ... existing fetch code ...
}
```

### Change 4: Add `trackMetaSaniya10Messages` function

**File: `lib/meta-capi.ts`** — Append after `trackMetaFirstSubscriptionPayment`:
```typescript
/**
 * Track user reaching 10 messages with Saniya.
 * Uses custom event name (NOT fb_mobile_purchase) to avoid polluting purchase optimization.
 */
export function trackMetaSaniya10Messages(params: {
  userId: string;
}): void {
  sendAppEvent({
    eventName: 'saniya_10_messages',
    value: 0,
    currency: 'INR',
    userId: params.userId,
    paymentId: `milestone_10msg_${params.userId}`,
    fbEventName: 'saniya_10_messages',
  }).catch(() => {});
}
```

### Change 5: Centralize bot ID

**File: `lib/ai/prompts/index.ts`** — Add constant:
```typescript
export const SANIYA_BOT_ID = '28aad775-6dc3-4a75-af02-35ffae908473';
```

### Change 6: Fire event in chat route

**File: `app/api/chat/app/route.ts`** — Imports:
```typescript
import { trackMetaSaniya10Messages } from '@/lib/meta-capi';
import { SANIYA_BOT_ID } from '@/lib/ai/prompts';
```

**Replace line 254** (`await profileQueries.incrementMessageCount(userId, botId);`):
```typescript
const newMessageCount = await profileQueries.incrementMessageCount(userId, botId);

// Meta CAPI: fire once when Saniya message count hits exactly 10
// newMessageCount === 0 means DB error → skip. Atomic RPC guarantees uniqueness.
if (botId === SANIYA_BOT_ID && newMessageCount === 10) {
  trackMetaSaniya10Messages({ userId });
}
```

---

## Complete File Change Summary

### Hero Mobile App (prerequisite, separate release)
| File | Change | Lines |
|------|--------|-------|
| `hero/lib/meta-analytics.ts` | Add `setMetaUserId()` | +6 |
| `hero/lib/meta-analytics.web.ts` | Add no-op stub | +1 |
| `hero/stores/user-store.ts` | Call `setMetaUserId(id)` in `setUserId()` | +2 |

### Heroweb (main changes)
| File | Change | Lines |
|------|--------|-------|
| `supabase/migrations/YYYYMMDD_atomic_increment_messages.sql` | New RPC function | +20 |
| `lib/meta-capi.ts` | Add `fbEventName` param + `trackMetaSaniya10Messages` | +20 |
| `lib/payments/webhook-processor.ts` | Add import + Meta tracking for Cashfree first charge | +8 |
| `lib/ai/prompts/index.ts` | Export `SANIYA_BOT_ID` | +1 |
| `lib/db/queries/app-user-profiles.ts` | Replace `incrementMessageCount` with atomic RPC | +10 (net) |
| `app/api/chat/app/route.ts` | Add imports + fire milestone event | +7 |

**Total: ~66 heroweb lines + ~9 hero mobile app lines = ~75 lines across 9 files.**

---

## Key Design Decisions

| Decision | Rationale | Debated? |
|----------|-----------|----------|
| No server-side event for ₹1 trial | Client already fires `logPaymentDone()`. Adding server creates double-count. | Yes — critic flagged, defender conceded |
| `setUserID()` as prerequisite | Without it, all server events are unattributable. Mobile app never called it. | Yes — critic found the gap, defender elevated to prerequisite |
| Atomic SQL for message count | Read-then-write pattern has race condition. Two concurrent requests can both fire. | Yes — critic proved defender's original analysis wrong |
| Custom `_eventName` for milestone | `fb_mobile_purchase` with value=0 pollutes Meta purchase optimization. | Yes — critic flagged, defender conceded |
| Centralized `SANIYA_BOT_ID` | Hardcoded UUID in chat route is a maintenance risk. | Yes — critic flagged |
| `paymentId` guard for Cashfree | Falling back to subscriptionId corrupts data quality. Skip event instead. | Yes — critic flagged |
| Column types as TEXT in SQL | Conservative default based on application code patterns. Verify before deploy. | Critic's observation — check actual column types |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `setUserID()` not shipped with mobile release | Medium | All events unattributable | Make it a release blocker |
| SQL function type mismatch | Low | RPC call fails silently | Verify column types before writing migration |
| Message milestone fires for non-Saniya bots | None | N/A | `botId === SANIYA_BOT_ID` guard |
| Meta rate limiting on App Events API | Very low | Events dropped | Fire-and-forget already handles this |
| `incrementMessageCount` returns 0 on error at exactly message 10 | Very low | Milestone missed for one user | Acceptable — same behavior as before, plus atomic RPC reduces error surface |
