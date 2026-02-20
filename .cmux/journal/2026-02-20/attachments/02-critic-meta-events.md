# Critic Critique: Meta Campaign Tracking Events

## Verdict Summary

| Event | Verdict | Key Issue |
|-------|---------|-----------|
| Event 1: INR 1 Trial Start | **ACCEPT** | Solid proposal. Minor placement note. |
| Event 2: INR 199 Purchase | **REVISE** | Option B is fundamentally broken for its stated purpose. Option A only, or defer. |
| Event 3: 10+ Messages to Saniya | **REVISE** | Good core idea, but code duplication + Zustand migration gap + open questions need firm answers. |

---

## Event 1: INR 1 Trial Start — ACCEPT

### The Good

- **Correct Meta standard event**: `fb_mobile_start_trial` (StartTrial) is exactly the right event for Meta's ML-based ad delivery optimization for trial conversions. A custom event name would break Meta's value-based optimization. Well-researched.
- **Correct placement**: After `result.success && result.verified` is the earliest point of confirmed payment. The proposal correctly rejects:
  - `handleStartTrial` (intent, not action)
  - `startSubscriptionFlowS2S` call site (mandate not yet authorized)
  - `/payment/result` screen (display layer, not source of truth)
- **All 4 callsites correctly identified**: The `usePaymentOnboarding` hook covers both standard and valentine onboarding. `premium-upgrade-sheet.tsx` and `profile.tsx` are the remaining subscription entry points. I verified all 3 success branches follow the same `startSubscriptionFlowS2S` → `result.success && result.verified` → grant benefits pattern.
- **Edge case analysis is thorough and correct**: The `paymentFlowStarted` ref prevents concurrent flows. Each `handleAppSelection` invocation creates a new mandate, so retries get new subscriptionIds. The Facebook SDK's internal event queue handles offline correctly.

### Minor Notes

1. **Relationship with existing `logPaymentDone`**: The proposal doesn't explicitly address the interaction between the new `logTrialStart` (fires `StartTrial` event) and the existing `logPaymentDone` (fires `Purchase` event with amount=1). These are **different Meta standard events** and having both is actually correct — Meta recommends tracking both trial starts and purchases separately for different optimization objectives. No issue here, but worth documenting in a comment so future developers don't think it's duplication.

2. **Placement order within the success block**: The proposal says "after `addPurchase`, before `trackPaymentCompleted`." I'd suggest placing it **adjacent to the existing `logPaymentDone` call** instead, to group all Meta event calls together. In `use-payment-onboarding.ts`, that means after line 233 (the `logPaymentDone` call). In `premium-upgrade-sheet.tsx`, after line 160. In `profile.tsx`, after line 252. This is a readability suggestion, not a correctness issue.

3. **Value parameter**: The proposal passes `1` as the value parameter. Confirmed correct — `AppEventsLogger.logEvent(name, valueToSum, params)` where `valueToSum` is the monetary amount. ₹1 is the trial charge.

### Verdict: ACCEPT

No blocking issues. Ship as proposed with the optional placement reordering for readability.

---

## Event 2: INR 199 Purchase Complete — REVISE

### The Good

- **Correctly identifies the core architectural reality**: The ₹199 charge is a server-side Razorpay mandate auto-debit that happens 30 days after trial activation. There is NO client-side event when this charge occurs. This is the most important insight in the proposal.
- **Option A (backend webhook + Conversions API) is the right architecture**: Server-side events are more reliable, don't depend on the app being open, and Meta's Conversions API supports full attribution data.
- **Correctly notes that existing `logPaymentDone` fires with amount=1, NOT 199**: The `addPurchase({amount: 199})` in the success blocks is a UI record of the plan price, not an actual ₹199 transaction.

### Issues

#### 1. Option B is fundamentally broken for its stated purpose — REJECT it entirely

The proposal frames Option B (client-side detection on next app open) as a "fallback" that's merely "lossy." This dramatically understates the problem.

**Meta's attribution window**: Meta allows **7-day click-through** and **1-day view-through** attribution. The ₹199 charge happens **30 days** after the ad click (trial start). By the time the client detects the renewal on next app open (day 30+), the attribution window closed **23 days ago**.

This means:
- Meta **cannot** attribute this purchase event back to any ad campaign
- The event will appear in Meta's event manager as an "unattributed" purchase
- Meta's ML **cannot** use this event for ROAS optimization (the entire stated purpose)
- It provides **zero value** for campaign optimization while adding code complexity

Option B isn't "lossy" — it's **100% useless** for the use case it's meant to serve. It adds dead code, a new Zustand flag, a new hook, and a new app-level check — all for an event that Meta will ignore for campaign purposes.

#### 2. Option A's function signature is wrong

The proposal defines `logSubscriptionPurchaseComplete` using `AppEventsLogger.logPurchase()` — but that's the **client-side** Facebook SDK. Option A explicitly says to use Meta's **Conversions API** (server-side). These are completely different:

- **Client-side**: `AppEventsLogger.logPurchase()` from `react-native-fbsdk-next`
- **Server-side**: HTTPS POST to `https://graph.facebook.com/v18.0/{pixel_id}/events` with server access token

The proposal provides a client-side function signature for a server-side recommendation. The actual implementation would be in the **hero-web backend** (Next.js), not in `lib/meta-analytics.ts`.

#### 3. Missing server-side implementation details

If pursuing Option A, the proposal needs to specify:
- Which webhook event to hook into (the backend already processes `SUBSCRIPTION_PAYMENT_SUCCESS` — see ANALYTICS-SPEC.md section 4)
- Where in the hero-web codebase to add the Conversions API call (alongside existing `posthog-events.ts` tracking in `lib/payments/webhook-processor.ts`)
- The Meta Conversions API payload format (event_name, event_time, user_data with hashed phone, custom_data with value/currency)
- Required secrets: Meta pixel ID, server access token (different from client app ID)

### Counter-Proposal

**If backend work is in scope**: Implement Option A in `hero-web/lib/payments/webhook-processor.ts`, adjacent to the existing `trackSubscriptionRenewed()` PostHog call. Provide the Conversions API implementation details.

**If backend work is NOT in scope**: **Defer this event entirely**. Do not implement Option B. Document the requirement for the backend team with the architectural rationale. A stub function in `lib/meta-analytics.ts` with a `// TODO: Implement via Conversions API on backend` comment is acceptable if you want to define the interface.

### Verdict: REVISE

Option B must be removed from the proposal. Option A is correct but needs actual server-side implementation details (or explicit deferral to backend team).

---

## Event 3: 10+ Messages to Saniya — REVISE

### The Good

- **Correctly identifies the session-scope limitation**: `sessionMessageCount` ref resets on component mount. A historical total requires a different approach.
- **Counting from React Query cache is clever**: `useConversationHistory` fetches all past messages from the backend on screen mount. Counting `m.role === "user"` from the cache gives the true total without new API calls or persistent counters.
- **Dual-layer deduplication**: `milestoneLogged` ref for intra-session + Zustand `milestones` map for cross-session. This is correct.
- **`fb_mobile_achievement_unlocked` (AchievementUnlocked)**: Semantically correct Meta standard event for engagement milestones.
- **Covers both `sendMessage` and `sendMediaMessage`**: Voice notes and images count as messages. Correct.

### Issues

#### 1. Code duplication between `sendMessage` and `sendMediaMessage`

The milestone check is a 12-line block copy-pasted into both functions. This violates DRY and creates a maintenance hazard (e.g., if the threshold changes, both copies must be updated).

**Counter-proposal**: Extract a helper function within `useChat`:

```typescript
// Inside useChat(), after milestoneLogged ref declaration
const checkSaniyaMilestone = useCallback(() => {
  if (botId !== SANIYA_BOT_ID || milestoneLogged.current) return;

  const allMessages = queryClient.getQueryData<ChatMessage[]>(
    queryKeys.chatHistory(botId, userId)
  ) ?? [];
  const totalUserMessages = allMessages.filter(m => m.role === "user").length;

  if (totalUserMessages >= MILESTONE_THRESHOLD) {
    milestoneLogged.current = true;
    // Persist cross-session
    useUserStore.getState().setMilestone('saniya10Messages', true);
    logMilestoneMessagesSent({ botId, botName, messageCount: totalUserMessages });
  }
}, [botId, botName, userId, queryClient]);
```

Then call `checkSaniyaMilestone()` in both `sendMessage` (after line 274) and `sendMediaMessage` (after line 372).

#### 2. Zustand store migration not addressed

The proposal adds `milestones: Record<string, boolean>` to the user store. But the user store uses Zustand's `persist` middleware (it persists to AsyncStorage). Existing users' stores won't have a `milestones` field.

This needs:
- A default value in the store definition: `milestones: {}` (empty object)
- Verification that Zustand's persist middleware handles missing fields gracefully (it does — missing fields get their default values on hydration, but this should be stated explicitly)
- Or, use a version migration if the store has a `version` field

Without this, `useUserStore.getState().milestones?.saniya10Messages` could be `undefined` on first access for existing users. The proposal's code uses optional chaining (`?.`) which handles this, but the store definition should still include the default.

#### 3. Persistent flag initialization in the hook

The proposal suggests:
```typescript
const [hasLoggedSaniyaMilestone, setHasLoggedSaniyaMilestone] = useState<boolean>(() => {
  return useUserStore.getState().milestones?.saniya10Messages ?? false;
});
```

This creates a React state that mirrors Zustand state — unnecessary indirection. Just read from Zustand directly in the check:

```typescript
if (
  botId === SANIYA_BOT_ID &&
  !milestoneLogged.current &&
  !(useUserStore.getState().milestones?.saniya10Messages)
) { ... }
```

No need for the extra `useState`. The ref handles intra-session dedup, Zustand handles cross-session. Reading `getState()` is synchronous and cheap.

#### 4. SANIYA_BOT_ID should be centralized NOW, not left as an open question

The bot ID `28aad775-6dc3-4a75-af02-35ffae908473` already appears in:
- `hooks/use-payment-onboarding.ts:40` (as `SANIYA_BOT_ID`)
- `constants/payment-variations.ts:2` (as `PAYMENT_VARIATION_BOT_IDS.FRIEND`)

Adding a third copy in `hooks/useChat.ts` is not acceptable. Either:
- Import from `constants/payment-variations.ts`: `import { PAYMENT_VARIATION_BOT_IDS } from '@/constants/payment-variations'` and use `PAYMENT_VARIATION_BOT_IDS.FRIEND`
- Or create `constants/bots.ts` with `export const SANIYA_BOT_ID = '28aad775-6dc3-4a75-af02-35ffae908473'` and update all references

I recommend the second approach: `constants/bots.ts`. The payment-variations file is about payment flow variations, not bot identity. A `bots.ts` constants file is semantically cleaner. But either is better than a third hardcoded copy.

#### 5. Cache timing: acknowledged but acceptable

The proposal notes that if history hasn't loaded yet, the count will be low. I agree this is acceptable in practice — history loads in 1-2 seconds, and users don't type 10 messages that fast. The `milestoneLogged` ref resets on next mount, so the check runs again when the user returns to chat (with full history loaded). No fix needed.

### Answers to Open Questions

**Q3: Fire once at 10, or on every message after 10?**

**Fire once at exactly 10 (first time total reaches >= 10).** Meta's campaign optimization works on unique conversion events per user. Firing on every message after 10 would:
- Inflate event counts artificially (one engaged user = dozens of events)
- Confuse Meta's ML about what constitutes a "conversion"
- Make the event useless for CPA (cost-per-acquisition) reporting

The Zustand persistent flag ensures once-ever semantics. This is correct.

**Q4: Centralize SANIYA_BOT_ID?**

Yes. Create `constants/bots.ts`. See issue #4 above.

### Verdict: REVISE

Core approach is sound. Required changes:
1. Extract milestone check helper (don't copy-paste)
2. Address Zustand store migration (default value for `milestones`)
3. Drop the unnecessary `useState` wrapper — read Zustand directly
4. Centralize `SANIYA_BOT_ID` to `constants/bots.ts` (not an open question — do it)
5. Confirm: fire once at 10 (the persistent flag already implements this)

---

## Overall Assessment

The defender's proposal demonstrates strong understanding of the codebase, correct identification of all subscription entry points, and appropriate use of Meta standard events. The main gaps are:

1. **Event 2 needs a firm architectural decision**, not two options where one is broken
2. **Event 3 has unnecessary code duplication** and loose ends around persistence
3. **Bot ID centralization** should be a requirement, not a question

The proposal is well-structured and most of the work is correct. With the revisions above, this will be a clean, maintainable implementation.
