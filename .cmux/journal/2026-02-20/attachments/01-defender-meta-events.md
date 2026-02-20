# Defender Proposal: Meta Campaign Tracking Events

## Executive Summary

This proposal adds 3 new Meta (Facebook) tracking events to the Hero app for campaign optimization. Each event uses the existing `AppEventsLogger` from `react-native-fbsdk-next` (already initialized in `lib/meta-analytics.ts`) and follows the established pattern: a new exported function in `lib/meta-analytics.ts`, a corresponding web stub in `lib/meta-analytics.web.ts`, and callsite(s) in the appropriate flow.

---

## Event 1: INR 1 Trial Start

### Event Definition

```typescript
// lib/meta-analytics.ts — new export
export function logTrialStart(params: {
  subscriptionId: string;
  source: string;
}): void {
  try {
    AppEventsLogger.logEvent("fb_mobile_start_trial", 1, {
      fb_currency: "INR",
      fb_subscription_id: params.subscriptionId,
      fb_content_type: "subscription_trial",
      source: params.source,
    });
    logger.log("[Meta] trial_start:", params);
  } catch (e) {
    logger.warn("[Meta] Error:", e);
  }
}
```

**Event name**: `fb_mobile_start_trial` — This is a [Meta standard event](https://developers.facebook.com/docs/app-events/reference) (`StartTrial`) which enables Meta's ML to optimize ad delivery for trial conversions. Using the standard event name is critical for campaign optimization; a custom name would not trigger Meta's value-based optimization.

**Value**: `1` (INR) — the actual trial charge amount.

### Web Stub

```typescript
// lib/meta-analytics.web.ts — new export
export function logTrialStart(_params: { subscriptionId: string; source: string }): void {}
```

### Exact Placement: `hooks/use-payment-onboarding.ts`, line ~224 (inside `handleAppSelection`, after `result.success && result.verified`)

**Where**: Inside the `if (result.success && result.verified)` block in `handleAppSelection`, after `setTrialActive()` and `setSubscriptionActive()` are called, but before navigation to `/payment/result`.

```typescript
// hooks/use-payment-onboarding.ts — inside handleAppSelection callback, after line 212
// (after addPurchase, before trackPaymentCompleted)

logTrialStart({
  subscriptionId: result.subscriptionId || "",
  source: "onboarding",
});
```

### All 4 Callsites (subscription success paths)

The ₹1 trial subscription flow is triggered from 4 places. All share the same `startSubscriptionFlowS2S()` → `result.success && result.verified` pattern:

| # | File | Function | Source tag | Lines |
|---|------|----------|------------|-------|
| 1 | `hooks/use-payment-onboarding.ts` | `handleAppSelection` | `"onboarding"` | ~182-247 |
| 2 | `components/premium-upgrade-sheet.tsx` | `handleUPIAppSelected` | `"premium_sheet"` | ~132-170 |
| 3 | `app/(tabs)/profile.tsx` | inline handler | `"profile"` | ~222-254 |
| 4 | `app/onboarding-valentine/payment.tsx` | delegates to `usePaymentOnboarding` hook | covered by #1 | — |

**Note**: Valentine payment (#4) uses the shared `usePaymentOnboarding` hook, so it's automatically covered by callsite #1. No separate instrumentation needed.

### Why This Location (Not Earlier/Later)

- **Not at `handleStartTrial`** (button tap): That fires before UPI app selection and payment. The user hasn't started the trial yet — they've only expressed intent. Firing here would inflate trial-start counts with users who never complete payment.
- **Not at `startSubscriptionFlowS2S` call**: The mandate hasn't been authorized yet. The UPI app is just being launched.
- **At `result.success && result.verified`**: This is the earliest point where we have confirmation that the ₹1 was charged and the mandate authorized. The backend has verified the payment. This is the true "trial started" moment.
- **Not at `/payment/result` screen**: That screen's logic is a display layer; subscription benefits are already granted before navigation. Additionally, `payment/result.tsx` has no knowledge of whether this was a new trial vs. a re-subscription.

### Edge Cases

| Edge Case | Handling |
|-----------|----------|
| **Duplicate fires** | Cannot happen: `handleAppSelection` runs once per tap (guarded by `paymentFlowStarted` ref + `isLoading` state). The `result.success && result.verified` branch executes exactly once. |
| **Retry after failure** | If payment fails and user retries, a new `startSubscriptionFlowS2S` call creates a new mandate. Success = new event with new subscriptionId. Correct behavior. |
| **Offline** | `react-native-fbsdk-next` queues events internally via the Facebook SDK. Events are flushed when connectivity returns. No app-level handling needed. |
| **App crash mid-flow** | If crash occurs after `setTrialActive` but before `logTrialStart`, the event is lost. Acceptable: Meta campaigns tolerate minor undercount vs. backend subscription records. |

---

## Event 2: INR 199 Purchase Complete

### Event Definition

```typescript
// lib/meta-analytics.ts — new export
export function logSubscriptionPurchaseComplete(params: {
  subscriptionId: string;
  source: string;
}): void {
  try {
    AppEventsLogger.logPurchase(199, "INR", {
      fb_content_type: "subscription_monthly",
      fb_subscription_id: params.subscriptionId,
      source: params.source,
    });
    logger.log("[Meta] subscription_purchase_complete:", params);
  } catch (e) {
    logger.warn("[Meta] Error:", e);
  }
}
```

**Event name**: Uses `logPurchase()` (Meta standard `Purchase` event) — this is the gold standard for Meta campaign ROAS optimization. The `logPurchase` call automatically sets `fb_mobile_purchase` as the event name, which Meta Ads Manager uses for purchase-based optimization.

**Value**: `199` (INR) — the monthly subscription amount after the trial period.

### Web Stub

```typescript
// lib/meta-analytics.web.ts — new export
export function logSubscriptionPurchaseComplete(_params: { subscriptionId: string; source: string }): void {}
```

### Exact Placement: Backend webhook / cron (NOT client-side)

**Critical insight**: The ₹199 charge happens **server-side after the 30-day trial**. There is no client-side flow for this — Razorpay auto-charges the mandate. The client never sees a "₹199 purchase complete" event in real-time.

**Recommended approach — two options**:

#### Option A: Backend Webhook (Preferred)

The ₹199 charge is triggered by Razorpay's recurring payment system. The backend receives a webhook (`payment.captured` or `subscription.charged`) when the first ₹199 is deducted. The backend should call Meta's Server-Side API (Conversions API) to log this event.

This is **not a client-side change** — it requires backend work. However, it is the correct architecture because:
- The client may not be open when the charge happens
- Server-side events are more reliable for campaign attribution
- Meta's Conversions API supports purchase events with full attribution data

#### Option B: Client-Side Detection (Fallback)

If backend changes are not feasible in the short term, we can detect the transition on the client:

```typescript
// lib/meta-analytics.ts — new export (Option B only)
export function logSubscriptionRenewalDetected(params: {
  subscriptionId: string;
}): void {
  try {
    AppEventsLogger.logPurchase(199, "INR", {
      fb_content_type: "subscription_renewal_detected",
      fb_subscription_id: params.subscriptionId,
    });
    logger.log("[Meta] subscription_renewal_detected:", params);
  } catch (e) {
    logger.warn("[Meta] Error:", e);
  }
}
```

**Placement for Option B**: In the app's session start or subscription status check, when the client detects that `subscription.status` has transitioned from `trial` to `active` (i.e., the trial period ended and the ₹199 charge succeeded). This would require:

1. Storing a flag `hasLoggedFirstRenewal` in Zustand/AsyncStorage
2. On app open, checking if `subscription.isTrialActive === false && subscription.isActive === true && !hasLoggedFirstRenewal`
3. If so, firing `logSubscriptionRenewalDetected` and setting the flag

**Callsite for Option B**: `app/_layout.tsx` (in the root layout's useEffect that runs on app mount), or a new `useSubscriptionRenewalDetection()` hook.

### Why This Architecture

- The existing `logPaymentDone` calls in the codebase fire with `amount: 1` (the trial amount), NOT `amount: 199`. See `use-payment-onboarding.ts:229-233` and `premium-upgrade-sheet.tsx:156-160`.
- The `addPurchase` call records `amount: 199` as the `description: 'VIP Monthly Subscription'` but this is a UI-level record of the subscription plan price, not an actual ₹199 transaction at trial time.
- The actual ₹199 charge is a **recurring mandate debit** that happens 30 days after trial start, handled entirely server-side by Razorpay.

### Edge Cases

| Edge Case | Handling |
|-----------|----------|
| **User cancelled before ₹199** | No webhook fires, no event logged. Correct. |
| **Duplicate webhook** | Backend should deduplicate by `subscription_id + charge_period`. |
| **Option B: app not opened** | Event fires on next app open. Attribution window may have passed (Meta allows 7-day click / 1-day view), so this is lossy. This is why Option A (server-side) is preferred. |
| **Option B: duplicate detection** | `hasLoggedFirstRenewal` flag in persistent storage prevents re-firing. |

---

## Event 3: 10+ Messages Sent to Saniya

### Event Definition

```typescript
// lib/meta-analytics.ts — new export
export function logMilestoneMessagesSent(params: {
  botId: string;
  botName: string;
  messageCount: number;
}): void {
  try {
    AppEventsLogger.logEvent("fb_mobile_achievement_unlocked", {
      fb_description: `sent_${params.messageCount}_messages`,
      bot_id: params.botId,
      bot_name: params.botName,
      message_count: params.messageCount,
    });
    logger.log("[Meta] milestone_messages_sent:", params);
  } catch (e) {
    logger.warn("[Meta] Error:", e);
  }
}
```

**Event name**: `fb_mobile_achievement_unlocked` — Meta standard event (`AchievementUnlocked`). This is semantically correct for a milestone event and enables Meta's engagement-based optimization.

### Web Stub

```typescript
// lib/meta-analytics.web.ts — new export
export function logMilestoneMessagesSent(_params: { botId: string; botName: string; messageCount: number }): void {}
```

### Exact Placement: `hooks/useChat.ts`, inside `sendMessage()`, after `sessionMessageCount` increment

**Key challenge**: The current `sessionMessageCount` ref in `useChat.ts` only tracks messages **within the current session**. It resets to 0 when the user leaves and re-enters the chat. For a "10+ messages ever sent to Saniya" milestone, we need the **total historical count**.

### Implementation Approach

The conversation history is already loaded via `useConversationHistory()` which returns all messages from the backend. We can count user messages from the loaded history.

**Step 1**: Add a `totalUserMessages` computed value in `useChat.ts`:

```typescript
// hooks/useChat.ts — inside useChat(), after messages query

const SANIYA_BOT_ID = "28aad775-6dc3-4a75-af02-35ffae908473";
const MILESTONE_THRESHOLD = 10;

// Track whether milestone has been fired this session to prevent re-fires
const milestoneLogged = useRef(false);
```

**Step 2**: In the `sendMessage()` function, after the optimistic message is added:

```typescript
// hooks/useChat.ts — inside sendMessage(), after line 274 (sessionMessageCount increment)

// Check 10-message milestone for Saniya
if (
  botId === SANIYA_BOT_ID &&
  !milestoneLogged.current
) {
  // Count all user messages in the current cache (history + optimistic)
  const allMessages = queryClient.getQueryData<ChatMessage[]>(
    queryKeys.chatHistory(botId, userId)
  ) ?? [];
  const totalUserMessages = allMessages.filter(m => m.role === "user").length;

  if (totalUserMessages >= MILESTONE_THRESHOLD) {
    milestoneLogged.current = true;
    logMilestoneMessagesSent({
      botId,
      botName,
      messageCount: totalUserMessages,
    });
  }
}
```

**Step 3**: Same check in `sendMediaMessage()` (voice notes and images also count as messages):

```typescript
// hooks/useChat.ts — inside sendMediaMessage(), after line 372 (sessionMessageCount increment)

// Check 10-message milestone for Saniya (media messages count too)
if (
  botId === SANIYA_BOT_ID &&
  !milestoneLogged.current
) {
  const allMessages = queryClient.getQueryData<ChatMessage[]>(
    queryKeys.chatHistory(botId, userId)
  ) ?? [];
  const totalUserMessages = allMessages.filter(m => m.role === "user").length;

  if (totalUserMessages >= MILESTONE_THRESHOLD) {
    milestoneLogged.current = true;
    logMilestoneMessagesSent({
      botId,
      botName,
      messageCount: totalUserMessages,
    });
  }
}
```

### Why This Location

- **After `sessionMessageCount` increment** (line 274/372): The message has been committed to the optimistic cache. We're counting real user messages, not speculative ones.
- **Not in `sendToApi`**: That's the API call layer. The user has already "sent" the message (optimistically added). We want to count intent, not delivery confirmation.
- **Not in a `useEffect` watching `messages.length`**: Effects fire asynchronously and can cause timing issues. Inline in `sendMessage` is synchronous and deterministic.
- **Filtered to Saniya only** (`botId === SANIYA_BOT_ID`): The milestone is specific to Saniya. No performance impact for other bot chats.

### Why Count from Cache (Not a Separate Counter)

- **No new persistent state needed**: The React Query cache already holds the full conversation history loaded from the backend on screen mount.
- **Automatically includes historical messages**: When the user enters the chat, `useConversationHistory` fetches all past messages. Optimistic messages are prepended. So `allMessages.filter(m => m.role === "user").length` gives the true total.
- **`milestoneLogged` ref prevents re-fires within a session**: Once the event fires, it won't fire again until the user leaves the chat and returns. Since the history is re-fetched on mount, if they already had 10+ messages, the milestone would fire on the first new message of the next session — but only once.

### Cross-Session Deduplication

**Problem**: If the user has already sent 15 messages to Saniya and comes back next time, the first message will trigger the milestone again (since `milestoneLogged` resets on component mount).

**Solution**: Add a persistent flag in `AsyncStorage` or the Zustand user store:

```typescript
// In useChat.ts, at the start of the hook:
const [hasLoggedSaniyaMilestone, setHasLoggedSaniyaMilestone] = useState<boolean>(() => {
  // Read from Zustand store on init
  return useUserStore.getState().milestones?.saniya10Messages ?? false;
});

// In the milestone check:
if (
  botId === SANIYA_BOT_ID &&
  !milestoneLogged.current &&
  !hasLoggedSaniyaMilestone  // persistent cross-session guard
) {
  // ...fire event...
  milestoneLogged.current = true;
  setHasLoggedSaniyaMilestone(true);
  useUserStore.getState().setMilestone('saniya10Messages', true);
}
```

This requires adding a `milestones` map to the Zustand user store (`stores/user-store.ts`):

```typescript
// stores/user-store.ts — add to state
milestones: Record<string, boolean>;

// stores/user-store.ts — add action
setMilestone: (key: string, value: boolean) => void;
```

### Edge Cases

| Edge Case | Handling |
|-----------|----------|
| **Duplicate fires (same session)** | `milestoneLogged` ref prevents re-fires within a session. |
| **Duplicate fires (cross-session)** | Zustand `milestones.saniya10Messages` persists across sessions. |
| **Offline messages** | Optimistic messages are in the cache and counted. If the message fails to send, it's removed from cache. But the milestone event is already fired. Acceptable: the user demonstrated engagement intent. |
| **Message failed + retry** | If message #10 fails and is removed, count drops to 9. Next successful send re-triggers the check. The Zustand flag prevents duplicate if already fired. |
| **Bot renamed / ID changed** | Hardcoded `SANIYA_BOT_ID` matches the existing pattern in `use-payment-onboarding.ts:40`. If the bot ID changes, update both constants. |
| **Cache not yet loaded** | `queryClient.getQueryData` returns `undefined` → fallback to `[]` → `totalUserMessages = 0` (from optimistic only). First session with a fresh cache may under-count. This is acceptable as the history loads quickly and subsequent sends will count correctly. |

---

## Summary of Changes

### Files to Modify

| File | Changes |
|------|---------|
| `lib/meta-analytics.ts` | Add `logTrialStart()`, `logSubscriptionPurchaseComplete()` (Option B), `logMilestoneMessagesSent()` |
| `lib/meta-analytics.web.ts` | Add corresponding no-op stubs |
| `hooks/use-payment-onboarding.ts` | Add `logTrialStart()` call in success branch |
| `components/premium-upgrade-sheet.tsx` | Add `logTrialStart()` call in success branch |
| `app/(tabs)/profile.tsx` | Add `logTrialStart()` call in success branch |
| `hooks/useChat.ts` | Add 10-message milestone check in `sendMessage()` and `sendMediaMessage()` |
| `stores/user-store.ts` | Add `milestones` state + `setMilestone` action |

### Import Additions

```typescript
// hooks/use-payment-onboarding.ts (line 13)
import { logOnboardingComplete, logPaymentDone, logTrialStart } from "@/lib/meta-analytics";

// components/premium-upgrade-sheet.tsx (line 11)
import { logPaymentDone, logTrialStart } from '@/lib/meta-analytics';

// app/(tabs)/profile.tsx (line 20)
import { logPaymentDone, logTrialStart } from '@/lib/meta-analytics';

// hooks/useChat.ts (new import)
import { logMilestoneMessagesSent } from "@/lib/meta-analytics";
```

### No Changes Needed

- `app/onboarding-valentine/payment.tsx` — uses the shared `usePaymentOnboarding` hook
- `lib/razorpay.ts` — payment library stays event-agnostic (correct separation of concerns)
- `app/payment/result.tsx` — display layer, not the source of truth for payment status

---

## Open Questions for Critic

1. **Event 2 (₹199)**: Should we proceed with Option A (backend webhook) or Option B (client-side detection)? Option A is architecturally correct but requires backend work. Option B is client-only but lossy.
2. **Event 3 milestone**: Is the `milestones` Zustand map the right persistence approach, or should we use a dedicated `AsyncStorage` key to avoid polluting the user store?
3. **Event 3 threshold**: The task says "10 or more messages." Should we fire on exactly 10 (once-ever), or on every message after 10 (repeated engagement signal)?
4. **Saniya bot ID**: Currently hardcoded in `use-payment-onboarding.ts`. Should we centralize it to a constants file (e.g., `constants/bots.ts`) to avoid duplication?
