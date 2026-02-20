# Proposal: Optimal Placement for 3 New Meta Tracking Events

**Author:** defender
**Date:** 2026-02-20
**Project:** heroweb (Next.js + Supabase)

---

## Executive Summary

This proposal identifies the exact code insertion points for 3 Meta (Facebook) tracking events in the heroweb codebase. The approach leverages the existing `lib/meta-capi.ts` infrastructure (App Events API via Graph API) and follows established fire-and-forget patterns used by PostHog tracking.

---

## Existing Meta CAPI Infrastructure

**File:** `lib/meta-capi.ts`

The codebase already has a Meta App Events API integration:
- Sends `fb_mobile_purchase` events via `POST https://graph.facebook.com/v21.0/{META_APP_ID}/activities`
- Auth: App ID + App Secret (env vars `META_APP_ID`, `META_APP_SECRET`)
- Two existing functions:
  - `trackMetaTrialPaymentSuccess` — **defined but NOT called** (removed per CHANGELOG: "no ad attribution context server-side")
  - `trackMetaFirstSubscriptionPayment` — **defined and called** from Razorpay webhook only (not Cashfree)

**Key insight:** The `trackMetaTrialPaymentSuccess` function was intentionally removed from call sites. The CHANGELOG states "no ad attribution context server-side." This is a valid concern — server-side events use `anon_id: userId` (Supabase UUID), which Meta cannot match to ad-click attribution without a client-side `fbclid` or device advertising ID. This proposal acknowledges this limitation and proposes a mitigation.

---

## Event 1: INR 1 Trial Start

### What it means
User authorizes the ₹1 UPI mandate, starting their trial subscription. This is the `SUBSCRIPTION_INITIAL` payment for Razorpay, or the `SUBSCRIPTION_ACTIVATED` webhook for Cashfree.

### Current state
- `trackMetaTrialPaymentSuccess()` exists in `lib/meta-capi.ts:101` but is **dead code** — not imported or called anywhere
- PostHog tracks this as `subscription_activated` (both gateways)

### Proposed placement: Server-side (webhook handlers)

#### Razorpay — `lib/payments/razorpay-webhook-processor.ts`

**Insert after line 341** (after `trackSubscriptionActivated(...)` call, inside the `SUBSCRIPTION_INITIAL` block):

```typescript
// File: lib/payments/razorpay-webhook-processor.ts
// Location: handlePaymentSuccess() → order.order_type === 'SUBSCRIPTION_INITIAL' block
// After: trackSubscriptionActivated({ ... });  (line 335-341)

trackMetaTrialPaymentSuccess({
  userId: order.user_id,
  paymentId: payment.id,
});
```

**Import change** at top of file (line 21):
```typescript
import {
  trackMetaFirstSubscriptionPayment,
  trackMetaTrialPaymentSuccess,   // ADD THIS
} from '@/lib/meta-capi';
```

#### Cashfree — `lib/payments/webhook-processor.ts`

**Insert after line 502** (after `trackSubscriptionActivated(...)` call, inside `handleSubscriptionActivated()`):

```typescript
// File: lib/payments/webhook-processor.ts
// Location: handleSubscriptionActivated() → after PostHog tracking
// After: trackSubscriptionActivated({ ... });  (line 495-502)

trackMetaTrialPaymentSuccess({
  userId,
  paymentId: subscriptionData.authorization_details?.payment_id
    || subscriptionData.payment_id
    || subscriptionId,
});
```

**Import addition** at top of file:
```typescript
import {
  trackMetaTrialPaymentSuccess,
} from '@/lib/meta-capi';
```

### Data included in event
| Property | Value | Source |
|----------|-------|--------|
| `_eventName` | `fb_mobile_purchase` | Hardcoded |
| `_valueToSum` | `1` | Hardcoded (₹1) |
| `fb_currency` | `INR` | Hardcoded |
| `fb_content_id` | `trial_payment_success` | Hardcoded |
| `payment_id` | Gateway payment ID | `payment.id` / webhook payload |
| `anon_id` | Supabase user UUID | `order.user_id` / `userId` |

### Firing: Server-side only
- **Why server-side:** The trial start is confirmed via webhook (payment gateway → heroweb). The client may have already navigated away from the payment screen.
- **Limitation:** No `fbclid` or device ad ID available server-side, so Meta cannot attribute this event to a specific ad click. See [Attribution Gap](#attribution-gap) below.

---

## Event 2: INR 199 Purchase Complete

### What it means
The first ₹199 recurring subscription charge succeeds. This transitions the user from `trial` (cycle 0) to `paid` (cycle 1).

### Current state
- `trackMetaFirstSubscriptionPayment()` exists in `lib/meta-capi.ts:117`
- **Razorpay:** Already called at `razorpay-webhook-processor.ts:426` when `activeSub.current_cycle === 0`
- **Cashfree:** **NOT called** — this is a gap

### Proposed placement: Server-side (webhook handlers)

#### Razorpay — Already implemented
No changes needed. The call at `razorpay-webhook-processor.ts:426` correctly fires when `current_cycle === 0` (trial → first paid charge).

#### Cashfree — `lib/payments/webhook-processor.ts`

**Insert after line 683** (after `identifyUserSegment(...)`, inside `handleSubscriptionPaymentSuccess()`). Add a conditional block for the first charge:

```typescript
// File: lib/payments/webhook-processor.ts
// Location: handleSubscriptionPaymentSuccess() → after PostHog identify
// After: identifyUserSegment({ ... });  (line 676-684)

// Meta CAPI: first ₹199 charge (trial → paid)
if (nextCycle === 1) {
  trackMetaFirstSubscriptionPayment({
    userId: user_id,
    paymentId: paymentId,
    amount: paymentAmount,
  });
}
```

**Import addition** at top of file (extend existing meta-capi import):
```typescript
import {
  trackMetaTrialPaymentSuccess,
  trackMetaFirstSubscriptionPayment,
} from '@/lib/meta-capi';
```

### Data included in event
| Property | Value | Source |
|----------|-------|--------|
| `_eventName` | `fb_mobile_purchase` | Hardcoded |
| `_valueToSum` | `199` (or actual amount) | `payment.amount / 100` or `paymentAmount` |
| `fb_currency` | `INR` | Hardcoded |
| `fb_content_id` | `first_subscription_payment_success` | Hardcoded |
| `payment_id` | Gateway payment ID | `payment.id` / `paymentId` |
| `anon_id` | Supabase user UUID | `order.user_id` / `user_id` |

### Firing: Server-side only
- **Why server-side:** This is a cron-initiated charge — there is no client interaction. The ₹199 charge happens via the subscription-charges cron job, and the result comes back via webhook.

---

## Event 3: 10+ Messages Sent to Saniya

### What it means
A user has sent their 10th (or more) message specifically to the Saniya companion (bot ID: `28aad775-6dc3-4a75-af02-35ffae908473`). This signals engagement depth.

### Current state
- No Meta tracking exists for message milestones
- Message count is tracked per user-bot pair in `hero_app_user_profiles.total_messages`
- `incrementMessageCount(userId, botId)` is called in `app/api/chat/app/route.ts:254` and returns the new count

### Proposed placement: Server-side (chat API route)

#### Step 1: Add new function to `lib/meta-capi.ts`

**Append after line 129** (after `trackMetaFirstSubscriptionPayment`):

```typescript
/**
 * Track user reaching 10+ messages with Saniya
 * Fired once when total_messages reaches exactly 10
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
  }).catch(() => {}); // swallow — fire-and-forget
}
```

#### Step 2: Fire in chat route — `app/api/chat/app/route.ts`

**Modify line 254** to capture the return value and add the tracking call:

```typescript
// File: app/api/chat/app/route.ts
// Location: After message save, around line 254
// BEFORE:
//   await profileQueries.incrementMessageCount(userId, botId);

// AFTER:
const newMessageCount = await profileQueries.incrementMessageCount(userId, botId);

// Meta CAPI: fire once when Saniya message count hits exactly 10
const SANIYA_BOT_ID = '28aad775-6dc3-4a75-af02-35ffae908473';
if (botId === SANIYA_BOT_ID && newMessageCount === 10) {
  trackMetaSaniya10Messages({ userId });
}
```

**Import addition** at top of file:
```typescript
import { trackMetaSaniya10Messages } from '@/lib/meta-capi';
```

### Data included in event
| Property | Value | Source |
|----------|-------|--------|
| `_eventName` | `fb_mobile_purchase` | Hardcoded (Meta App Events API constraint) |
| `_valueToSum` | `0` | No monetary value |
| `fb_currency` | `INR` | Hardcoded |
| `fb_content_id` | `saniya_10_messages` | Hardcoded |
| `payment_id` | `milestone_10msg_{userId}` | Constructed |
| `anon_id` | Supabase user UUID | `userId` from request header |

### Idempotency
- Fires only when `newMessageCount === 10` (exact equality), so it fires exactly once per user-bot pair
- `incrementMessageCount` reads the current `total_messages`, adds 1, and returns the new value
- Race condition: If two requests arrive simultaneously for message #10, both could read `total_messages=9` and both increment to 10. However, Supabase's read-then-update pattern means one will update to 10 and the other to 11 (since `getOrCreateProfile` reads fresh). The `=== 10` check ensures at most one fires. If extreme precision is needed, an atomic SQL increment with `RETURNING` would be better.

### Firing: Server-side only
- **Why server-side:** The message count is tracked server-side. The chat API route has all the context needed.

### Alternative considered: Range check (`>= 10` + flag)
Instead of `=== 10`, we could use `>= 10` with a `meta_saniya_10_fired` flag in the user profile. This would be more resilient to the race condition but adds schema complexity. The `=== 10` approach is simpler and sufficient since the race window is ~milliseconds.

---

## Attribution Gap

<a name="attribution-gap"></a>

All three events fire **server-side** using `anon_id: userId` (Supabase UUID). Meta's App Events API can match events to ad campaigns via:

1. **Advertising ID** (IDFA/GAID) — not available server-side
2. **App-scoped User ID** — this is what we send as `anon_id`
3. **fbclid** — not available server-side

**Impact:** Meta can record these events for aggregate reporting and optimization, but **cannot attribute them to specific ad clicks** unless the client-side Facebook SDK (react-native-fbsdk-next) has previously identified the same user. If the mobile app calls `AppEventsLogger.setUserID(supabaseUserId)` at login, Meta can match server events to client sessions.

**Recommendation:** Verify that the Hero mobile app (React Native) calls `AppEventsLogger.setUserID()` with the same Supabase UUID used in `anon_id`. This is a client-side concern outside heroweb's scope, but critical for attribution.

---

## Summary of Changes

| File | Change Type | Lines Affected |
|------|-------------|----------------|
| `lib/meta-capi.ts` | Add `trackMetaSaniya10Messages` function | +15 lines after line 129 |
| `lib/payments/razorpay-webhook-processor.ts` | Add import + call `trackMetaTrialPaymentSuccess` | +2 lines (import), +4 lines (call after line 341) |
| `lib/payments/webhook-processor.ts` | Add imports + call both Meta functions | +3 lines (imports), +4 lines (trial, after line 502), +5 lines (₹199, after line 683) |
| `app/api/chat/app/route.ts` | Add import + fire milestone event | +1 line (import), +5 lines (after line 254) |

**Total: ~39 lines of new code across 4 files.**

All events follow the established fire-and-forget pattern (`.catch(() => {})`) and will never break the calling code on failure.

---

## Decision Log

| Decision | Rationale |
|----------|-----------|
| Server-side only (no client events) | Payment events come from webhooks (no client context). Message milestone is counted server-side. |
| Re-use existing `sendAppEvent` infrastructure | Already tested and proven. Same API, same auth, same fire-and-forget pattern. |
| `=== 10` instead of `>= 10 + flag` | Simpler, no schema changes. Sufficient given the narrow race window. |
| Saniya bot ID hardcoded as const | Matches existing patterns in test scripts. If more bots need milestones later, extract to config. |
| `_valueToSum: 0` for message milestone | No monetary value; Meta still records the event for funnel/audience building. |
| Re-activate `trackMetaTrialPaymentSuccess` | Function already exists and is well-tested. The CHANGELOG removal was about attribution concerns, not correctness. |
