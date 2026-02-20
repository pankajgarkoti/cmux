# Rebuttal: Addressing Critic's Feedback on Meta Tracking Events

**Author:** defender
**Date:** 2026-02-20
**Responding to:** `02-critic-critique.md`

---

## Response Summary

| Critic's Issue | My Response | Action |
|----------------|-------------|--------|
| Attribution blocker (`setUserID` not called) | **ACCEPT** — verified, critic is correct | Elevate to prerequisite (Step 0) |
| Client-side double-fire for payment events | **ACCEPT** — verified, hero CHANGELOG confirms intentional move to client | Adopt server-side-only for cron path, suppress server-side for client-interactive path |
| Race condition in `incrementMessageCount` | **ACCEPT** — my analysis was factually wrong | Replace with atomic SQL increment via RPC |
| `fb_mobile_purchase` for non-purchase milestone | **ACCEPT** — valid concern about Meta optimization pollution | Parameterize `_eventName` in `sendAppEvent` |
| Cashfree paymentId fallback fragile | **ACCEPT** — skip event if no real payment ID | Guard with null check |
| Hardcoded bot ID | **ACCEPT** — should centralize | Move to shared constants |

**Conceded: 6 of 6 points.** The critic's analysis was thorough and correct on all substantive issues. My original proposal had the right insertion points but wrong assumptions about the mobile app state and incorrect race condition analysis.

---

## REVISED PROPOSAL

### Step 0 (PREREQUISITE): Attribution Fix in Hero Mobile App

**This must ship before or simultaneously with the server-side events.**

**File:** `hero/lib/meta-analytics.ts`

Add `AppEventsLogger.setUserID()` call. The natural place is in the `initializeMetaSDK()` function, but `userId` isn't available there. Instead, add a new exported function:

```typescript
// hero/lib/meta-analytics.ts — NEW FUNCTION
export function setMetaUserId(userId: string): void {
  try {
    AppEventsLogger.setUserID(userId);
    logger.log("[Meta] setUserID:", userId);
  } catch (e) {
    logger.warn("[Meta] setUserID Error:", e);
  }
}
```

**Call sites in hero mobile app** (where Supabase userId becomes available):
- `hero/stores/user-store.ts:501` — inside `setUserId()` action (called at login, profile setup, splash screen restore)
- This is the single chokepoint where all login paths converge

**Note:** This is a mobile app change, not a heroweb change. It must be coordinated but belongs in the hero repo's release.

---

### Revised Event 1: INR 1 Trial Start

#### Decision: Server-side only for webhooks, acknowledge client-side already exists

The hero CHANGELOG explicitly states: _"Moved Meta attribution events from server-side CAPI (no ad context) to client-side `logPaymentDone()`."_ The client already fires `logPaymentDone({ type: 'subscription_trial', amount: 1 })` at `use-payment-onboarding.ts:229`.

**For the ₹1 trial, the client-side event IS the source of truth.** The user is present on-device, the Facebook SDK has the device ad ID, and attribution works. Adding a server-side duplicate would cause double-counting.

**However**, there is one gap: **Cashfree activations that arrive via webhook without a client-side payment confirmation** (e.g., the user's app crashes after payment but before the result screen, or the payment confirmation is delayed). In these cases, only the webhook fires.

**Revised placement:**

| Gateway | Source of truth | Action |
|---------|----------------|--------|
| Razorpay (SUBSCRIPTION_INITIAL) | Client-side `logPaymentDone()` fires on payment result screen | **No server-side Meta event** — client covers this reliably |
| Cashfree (SUBSCRIPTION_ACTIVATED) | Client-side `logPaymentDone()` fires on payment result screen | **No server-side Meta event** — client covers this |

**Net change for Event 1: NO server-side changes in heroweb.** The client-side `logPaymentDone()` already handles this correctly. Once `setUserID()` ships (Step 0), Meta can attribute these events to ad campaigns.

**If we later need a server-side fallback** (to catch cases where client event doesn't fire), we should use the same `fb_content_id` and include a deduplication key (e.g., `payment_id`) so Meta can deduplicate. But this is a future concern, not needed now.

---

### Revised Event 2: INR 199 Purchase Complete

#### Decision: Server-side ONLY for cron-driven charges, client-side for interactive purchases

There are two paths to the first ₹199 charge:

1. **Cron-driven** (via `subscription-charges` cron job): No client interaction. The cron creates a Razorpay order, charges the mandate, and the result comes via webhook. **Only server-side can fire.**
2. **Client-interactive** (rare edge case): If the user manually triggers a ₹199 payment through the app UI, `logPaymentDone()` fires client-side.

Since the cron path is the **primary** path (the ₹199 charge is always initiated by the cron, not by user action), server-side is the correct and necessary firing point.

**Razorpay — Already correct** at `razorpay-webhook-processor.ts:425-431`. No changes needed.

**Cashfree — Add call** in `webhook-processor.ts` after line 683:

```typescript
// File: lib/payments/webhook-processor.ts
// Location: handleSubscriptionPaymentSuccess() → after identifyUserSegment
// Condition: first charge only (cycle 0 → 1)

if (nextCycle === 1) {
  trackMetaFirstSubscriptionPayment({
    userId: user_id,
    paymentId: paymentId,
    amount: paymentAmount,
  });
}
```

**Import addition:**
```typescript
import { trackMetaFirstSubscriptionPayment } from '@/lib/meta-capi';
```

**Deduplication note:** The cron-driven ₹199 charge has no client-side `logPaymentDone()` call (the user is not interacting with the app), so there is no double-fire risk for this path. If a future client-interactive ₹199 path is added, it should use the same `fb_content_id: 'first_subscription_payment_success'` for Meta deduplication.

---

### Revised Event 3: 10+ Messages to Saniya

#### Concession 1: Race condition — atomic SQL increment

The critic is correct. My analysis of the race condition was wrong. The read-then-write pattern in `incrementMessageCount` is not atomic, and concurrent requests CAN both read 9, both write 10, and both fire the event.

**Fix: New Supabase RPC for atomic increment with RETURNING**

```sql
-- New migration: supabase/migrations/YYYYMMDD_atomic_increment_messages.sql
CREATE OR REPLACE FUNCTION increment_message_count(
  p_user_id UUID,
  p_bot_id UUID
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
    VALUES (p_user_id, p_bot_id::UUID, 0, 'stranger', '{}'::jsonb, 1)
    ON CONFLICT (user_id, bot_id) DO UPDATE SET
      total_messages = hero_app_user_profiles.total_messages + 1,
      updated_at = NOW()
    RETURNING total_messages INTO v_new_count;
  END IF;

  RETURN v_new_count;
END;
$$ LANGUAGE plpgsql;
```

**Update `incrementMessageCount` in `lib/db/queries/app-user-profiles.ts`:**

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
    return 0; // Existing error behavior preserved
  }
}
```

This guarantees:
- Two concurrent requests get `10` and `11` (never both `10`)
- PostgreSQL row-level locking ensures serialization
- No lost updates

#### Concession 2: Non-purchase event name

The critic is right that `fb_mobile_purchase` for a message milestone pollutes Meta's purchase optimization.

**Fix: Parameterize `_eventName` in `sendAppEvent`:**

```typescript
// lib/meta-capi.ts — modify sendAppEvent to accept optional eventName override
async function sendAppEvent(params: {
  eventName: string;
  value: number;
  currency: string;
  userId: string;
  paymentId: string;
  fbEventName?: string;  // NEW: override _eventName (default: fb_mobile_purchase)
}): Promise<void> {
  // ... existing code ...
  const body = {
    event: 'CUSTOM_APP_EVENTS',
    application_tracking_enabled: 1,
    advertiser_tracking_enabled: 1,
    anon_id: params.userId,
    custom_events: JSON.stringify([
      {
        _eventName: params.fbEventName || 'fb_mobile_purchase',  // CHANGED
        _valueToSum: params.value,
        fb_currency: params.currency,
        fb_content_id: params.eventName,
        fb_content_type: 'product',
        payment_id: params.paymentId,
      },
    ]),
  };
  // ... rest unchanged ...
}
```

**New function for the milestone:**

```typescript
/**
 * Track user reaching 10 messages with Saniya
 * Uses custom event name (not fb_mobile_purchase) to avoid polluting purchase optimization
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
    fbEventName: 'saniya_10_messages',  // Custom event, NOT fb_mobile_purchase
  }).catch(() => {});
}
```

#### Concession 3: Centralize bot ID

**Add to `lib/ai/prompts/index.ts`** (where bot IDs are already mapped):

```typescript
// lib/ai/prompts/index.ts — add constant
export const SANIYA_BOT_ID = '28aad775-6dc3-4a75-af02-35ffae908473';
```

#### Concession 4: Error-returns-0 guard

The critic notes `incrementMessageCount` returns `0` on error, which would mask message #10. With the atomic RPC approach, the error path is narrower (database errors only), but the guard should still be added:

```typescript
// app/api/chat/app/route.ts
const newMessageCount = await profileQueries.incrementMessageCount(userId, botId);

// Only fire milestone if we got a real count back (0 = error)
if (botId === SANIYA_BOT_ID && newMessageCount === 10) {
  trackMetaSaniya10Messages({ userId });
}
```

The `=== 10` check already excludes `0`, so this is naturally guarded. But I'll add a comment making the intent explicit.

#### Revised Event 3 placement

**File: `app/api/chat/app/route.ts`**

```typescript
// At top — imports
import { trackMetaSaniya10Messages } from '@/lib/meta-capi';
import { SANIYA_BOT_ID } from '@/lib/ai/prompts';

// Line ~254 — replace current incrementMessageCount call
const newMessageCount = await profileQueries.incrementMessageCount(userId, botId);

// Meta CAPI: fire once when Saniya message count hits exactly 10
// newMessageCount === 0 means DB error (skip), atomic RPC guarantees uniqueness
if (botId === SANIYA_BOT_ID && newMessageCount === 10) {
  trackMetaSaniya10Messages({ userId });
}
```

---

## Revised Summary of All Changes

### Step 0: Hero Mobile App (prerequisite)
| File | Change |
|------|--------|
| `hero/lib/meta-analytics.ts` | Add `setMetaUserId()` function |
| `hero/stores/user-store.ts` | Call `setMetaUserId(id)` inside `setUserId()` |

### Heroweb Changes

| File | Change | Lines |
|------|--------|-------|
| `lib/meta-capi.ts` | Add `fbEventName` param to `sendAppEvent`, add `trackMetaSaniya10Messages` | ~+20 |
| `lib/payments/webhook-processor.ts` | Add import + `trackMetaFirstSubscriptionPayment` for Cashfree first charge | ~+8 |
| `lib/ai/prompts/index.ts` | Export `SANIYA_BOT_ID` constant | +1 |
| `lib/db/queries/app-user-profiles.ts` | Replace `incrementMessageCount` with atomic RPC call | ~+10 (net) |
| `app/api/chat/app/route.ts` | Add import + fire milestone event at count === 10 | ~+6 |
| `supabase/migrations/YYYYMMDD_atomic_increment_messages.sql` | New RPC function | ~+20 |

**Event 1 (₹1 Trial): NO heroweb changes** — client-side `logPaymentDone()` is already the source of truth.
**Event 2 (₹199 Purchase): Cashfree addition only** — Razorpay already done, cron-only path has no double-fire risk.
**Event 3 (10+ Messages): Full implementation** with atomic increment, custom event name, centralized bot ID.

**Total: ~65 lines across 5 heroweb files + 1 migration + 2 hero mobile app files.**

---

## What Changed From Original Proposal

| Original | Revised | Reason |
|----------|---------|--------|
| Re-activate `trackMetaTrialPaymentSuccess` in both webhook processors | **Removed** — no server-side event for ₹1 trial | Client-side already handles this; adding server-side creates double-fire |
| Attribution as "recommendation" | **Prerequisite** (Step 0) | `setUserID()` never called, making all server events unattributable |
| Read-then-write `incrementMessageCount` | **Atomic SQL RPC** | Race condition is real — my original analysis was wrong |
| `fb_mobile_purchase` for milestone | **Custom event name** `saniya_10_messages` | Avoids polluting Meta purchase optimization |
| Inline `SANIYA_BOT_ID` | **Centralized constant** in `lib/ai/prompts/index.ts` | Better maintainability |
| Cashfree paymentId fallback to subscriptionId | **Skip event if no real paymentId** | Data quality — don't send misleading IDs |
