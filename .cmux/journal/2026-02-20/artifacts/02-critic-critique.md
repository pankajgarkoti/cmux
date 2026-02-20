# Critique: Meta Tracking Events Proposal

**Author:** critic
**Date:** 2026-02-20
**Reviewing:** `01-defender-proposal.md`

---

## Verdict Summary

| Section | Verdict | Key Issue |
|---------|---------|-----------|
| Event 1: INR 1 Trial Start | **REVISE** | Reverts intentional removal; client-side double-fire risk; attribution gap is a blocker, not a footnote |
| Event 2: INR 199 Purchase Complete | **REVISE** | Razorpay side is fine; Cashfree addition correct but client-side double-fire unaddressed |
| Event 3: 10+ Messages to Saniya | **REVISE** | Race condition analysis is factually wrong; `fb_mobile_purchase` for non-purchase event pollutes Meta purchase optimization |
| Attribution Gap | **REVISE** | Understated — mobile app does NOT call `setUserID()`, making ALL 3 events unattributable today |

---

## BLOCKING ISSUE: Attribution Is Broken (Affects All 3 Events)

Before critiquing individual events, I must flag a **blocking prerequisite** the defender buried as a recommendation.

The defender writes:
> "Verify that the Hero mobile app (React Native) calls `AppEventsLogger.setUserID()` with the same Supabase UUID used in `anon_id`. This is a client-side concern outside heroweb's scope, but critical for attribution."

**I verified. It does NOT.** I searched `hero/lib/meta-analytics.ts` — the file that wraps all Meta SDK calls — for `setUserID` and found zero hits. The `AppEventsLogger` is imported and used for `logEvent`, `logPurchase`, but `setUserID()` is never called anywhere in the mobile app.

**Impact:** Server-side events send `anon_id: <supabase-uuid>`. Client-side events send the device's advertising ID (IDFA/GAID). Meta has **no way to link these two identities**. All 3 proposed server-side events will appear as orphaned events in Meta's system — no ad attribution, no funnel connection to client-side events, no audience building.

**Counter-proposal:** This must be a **prerequisite** in the implementation plan, not a "recommendation." Before any server-side Meta events have value:
1. Add `AppEventsLogger.setUserID(supabaseUserId)` in the hero mobile app at login
2. Verify this ships before or simultaneously with the server-side events
3. Document this dependency explicitly

---

## Event 1: INR 1 Trial Start — REVISE

### The Good
- Correct identification that `trackMetaTrialPaymentSuccess()` exists as dead code in `lib/meta-capi.ts:101`
- Placement after `trackSubscriptionActivated()` in the `SUBSCRIPTION_INITIAL` block is correct
- Cashfree gap correctly identified — the function was never wired to `webhook-processor.ts`
- Fire-and-forget pattern is appropriate

### Issues

#### 1. Reverting an intentional removal without resolving the original concern

The CHANGELOG says this function was removed because of "no ad attribution context server-side." The defender acknowledges this but proposes re-activating it anyway, deferring the real fix to a vague "verify the mobile app calls setUserID()."

As shown above, the mobile app does NOT call `setUserID()`. Re-activating this function today sends events Meta cannot attribute. It's not harmful (fire-and-forget won't break anything), but it's also not useful until the attribution gap is closed.

#### 2. Client-side double-fire risk

The mobile app already fires `logPaymentDone()` (which calls `AppEventsLogger.logPurchase()` → `fb_mobile_purchase`) from:
- `use-payment-onboarding.ts:229` — mandate payment result screen
- `profile.tsx:248` — payment confirmation
- `premium-upgrade-sheet.tsx:156` — premium upgrade payment

For the ₹1 trial mandate authorization, the onboarding flow calls `logPaymentDone({ type: 'subscription_trial', amount: 1 })`. If we also fire `trackMetaTrialPaymentSuccess` server-side, Meta sees **two** `fb_mobile_purchase` events for the same trial start — one from the device, one from the server.

The defender does not address this overlap. Since `fb_content_id` differs (`trial_payment_success` server-side vs whatever the client sends), Meta may count these as separate purchases, inflating purchase counts.

#### 3. Cashfree paymentId fallback chain is fragile

```typescript
paymentId: subscriptionData.authorization_details?.payment_id
  || subscriptionData.payment_id
  || subscriptionId,
```

Using `subscriptionId` as a fallback `paymentId` is misleading. If neither payment ID field exists, the event reports a subscription ID where Meta expects a payment ID. This won't break anything (fire-and-forget), but it corrupts data quality. Better to skip the event entirely if no real payment ID is available.

### Counter-proposal
1. **Gate this behind the attribution fix**: Only re-activate once `setUserID()` ships in the mobile app
2. **Choose one layer**: Either fire server-side OR ensure client-side `logPaymentDone` covers this. Not both. For webhooks, server-side is more reliable (client may navigate away). If server-side, remove or guard the client-side `logPaymentDone` for trials.
3. **Cashfree**: Use `null` or skip the event if no real payment ID exists instead of falling back to subscriptionId

---

## Event 2: INR 199 Purchase Complete — REVISE

### The Good
- Correctly identifies the Razorpay implementation is already done and correct
- The `(activeSub.current_cycle || 0) === 0` guard at `razorpay-webhook-processor.ts:425` is the right condition
- The Cashfree gap is real — `trackMetaFirstSubscriptionPayment` is only wired to Razorpay
- `nextCycle === 1` is correct for Cashfree (I verified `nextCycle` is computed at line 610 and is in scope at line 684)

### Issues

#### 1. Client-side double-fire (same issue as Event 1)

For the ₹199 purchase: if a user completes a one-time ₹199 purchase via Razorpay Checkout (not the cron-driven recurring charge), the client calls `logPaymentDone({ type: 'subscription', amount: 199 })`. The webhook then fires `trackMetaFirstSubscriptionPayment`. Again, two `fb_mobile_purchase` events.

For **cron-initiated recurring charges**, this isn't an issue — there's no client interaction, so only the webhook event fires. But the first ₹199 charge CAN happen via both paths depending on timing.

#### 2. "Already implemented" for Razorpay is not quite right

The existing Razorpay call at line 425-431 fires `trackMetaFirstSubscriptionPayment` only when `current_cycle === 0`. This is correct for the first ₹199 recurring charge. However, the defender doesn't note that this only fires for `SUBSCRIPTION_RECURRING` orders — the cron-initiated path. If the user somehow gets charged ₹199 through a different order type (e.g., a manual charge or a one-time payment that transitions them to paid), this wouldn't fire. This is an edge case but worth documenting.

### Counter-proposal
1. Accept the Cashfree addition as proposed (it's correct)
2. Document the client-side overlap and decide: for first-time purchases with client interaction, should client or server fire? For cron-driven renewals, only server can fire.
3. Consider deduplication: use the same `fb_content_id` and `payment_id` on both client and server so Meta can deduplicate

---

## Event 3: 10+ Messages Sent to Saniya — REVISE

### The Good
- Correct identification that `incrementMessageCount` returns `newCount`
- Correct placement in the chat route, immediately after the increment
- Saniya bot ID is correct (`28aad775-6dc3-4a75-af02-35ffae908473`)
- The "fire once at exactly 10" intent is correct

### Issues

#### 1. CRITICAL: Race condition analysis is factually wrong

The defender claims:
> "Supabase's read-then-update pattern means one will update to 10 and the other to 11 (since `getOrCreateProfile` reads fresh). The `=== 10` check ensures at most one fires."

**This is incorrect.** I read the actual `incrementMessageCount` code at `lib/db/queries/app-user-profiles.ts:182-200`:

```typescript
async incrementMessageCount(userId: string, botId: string): Promise<number> {
  const profile = await this.getOrCreateProfile(userId, botId);  // READ
  const newCount = profile.totalMessages + 1;                     // COMPUTE
  await supabase.update({ total_messages: newCount }).eq('id', profile.id);  // WRITE
  return newCount;
}
```

This is a classic **read-then-write** pattern with NO atomicity. If two requests arrive concurrently:
1. Request A reads `total_messages = 9`
2. Request B reads `total_messages = 9` (before A's write)
3. Request A writes `total_messages = 10`, returns `10` → **fires event**
4. Request B writes `total_messages = 10`, returns `10` → **fires event AGAIN**

Both requests fire the event. And worse: the final stored count is `10` instead of `11` (a **lost update**). The user's message count is permanently off by 1.

The defender's `=== 10` approach does NOT guarantee "at most one fires." It guarantees "fires for every concurrent request that reads 9."

**Is this likely?** A user sending two messages simultaneously is unlikely but not impossible (e.g., rapid tapping on send, network retries, app backgrounding + foregrounding). For a milestone event, "fires exactly once" should be a hard guarantee, not probabilistic.

#### 2. `fb_mobile_purchase` with `_valueToSum: 0` pollutes Meta purchase optimization

All events go through `sendAppEvent()` which hardcodes `_eventName: 'fb_mobile_purchase'`. The message milestone would appear in Meta as a zero-value purchase.

Meta's ad delivery optimization uses `fb_mobile_purchase` events to build lookalike audiences and optimize for purchase conversions. Injecting zero-value "purchases" for non-purchase actions:
- Inflates purchase event counts (Meta reports "X purchases from this campaign")
- Dilutes ROAS metrics (average purchase value drops)
- Confuses Meta's optimization algorithm (it learns that some "purchasers" have $0 value)

The defender should either:
- Modify `sendAppEvent` to accept a custom `_eventName` parameter (e.g., `fb_mobile_content_view` or a truly custom event name)
- Or create a separate `sendCustomAppEvent` function for non-purchase milestones

#### 3. Error return masks failures

`incrementMessageCount` returns `0` on any error (line 198). If the database update fails silently (e.g., connection timeout), the function returns `0`. Since `0 !== 10`, the event won't fire, and the failure is swallowed. If this happens at message 10, the milestone is permanently missed for that user.

The defender's proposal doesn't account for this. The `=== 10` check is brittle against error returns.

#### 4. Hardcoded bot ID should be centralized

```typescript
const SANIYA_BOT_ID = '28aad775-6dc3-4a75-af02-35ffae908473';
```

This UUID is defined inline in the chat route. If Saniya's bot ID changes, or if other companions need milestones, someone must grep for UUIDs. This should be in a central config file (e.g., `lib/ai/prompts/index.ts` already maps bot IDs to prompt functions — a `BOT_IDS` constant there would be natural).

### Counter-proposal

1. **Fix the race condition**: Replace the read-then-write with an atomic SQL increment:
```sql
UPDATE hero_app_user_profiles
SET total_messages = total_messages + 1, updated_at = NOW()
WHERE user_id = $1 AND bot_id = $2
RETURNING total_messages;
```
This is a single atomic operation. PostgreSQL guarantees serialization at the row level for UPDATE. Two concurrent requests will see `10` and `11`, never both `10`. Supabase supports `.rpc()` for custom SQL or you can use a raw query.

2. **Use a non-purchase event name**: Either parameterize `_eventName` in `sendAppEvent` or create a dedicated function. For the message milestone, use `_eventName: 'saniya_10_messages'` as a custom event, not `fb_mobile_purchase`.

3. **Centralize the bot ID**: Add `SANIYA_BOT_ID` to a shared constants file.

4. **Handle the error-returns-0 case**: Either propagate the error (throw instead of returning 0) or use `> 0 && === 10` as a guard.

---

## Additional Concerns Not Addressed

### 1. Both payment events use `fb_mobile_purchase` — is that intentional?

Meta sees both the ₹1 trial and the ₹199 subscription as "purchases." For ad campaign optimization targeting "purchases," Meta will count the ₹1 trial as a full conversion. Typically you'd want Meta to optimize for the ₹199 conversion (actual revenue). Sending ₹1 as a purchase event may cause Meta to optimize for the lower-barrier action.

If the intent is audience building (not conversion optimization), this is fine. But the proposal doesn't state the intent.

### 2. No deduplication strategy between client and server

The mobile app fires `logPaymentDone()` → `AppEventsLogger.logPurchase()` for payments. The server fires `trackMeta*` → Graph API `fb_mobile_purchase`. These are different API paths with different identifiers. Meta has limited ability to deduplicate them, especially without `setUserID()` linking the two identities.

The proposal should specify: for each event, which layer (client or server) is the source of truth, and whether the other should be suppressed.

### 3. Cashfree is still active

I verified Cashfree webhook routes exist and process payments. The defender's Cashfree additions are justified. (This is a positive — just confirming.)

---

## Revised Summary Table

| Event | Verdict | Blocking Issues | Non-blocking Issues |
|-------|---------|-----------------|---------------------|
| INR 1 Trial | REVISE | Attribution gap (no `setUserID`); client-side double-fire | Cashfree paymentId fallback fragile |
| INR 199 Purchase | REVISE | Client-side double-fire for non-cron path | Minor: only covers `SUBSCRIPTION_RECURRING` order type |
| 10+ Saniya Messages | REVISE | Race condition is real (not dismissed); `fb_mobile_purchase` for non-purchase | Error-return masking; hardcoded bot ID |
| Attribution Gap | REVISE | **BLOCKER**: `setUserID()` not called anywhere in hero mobile app | Should be prerequisite, not recommendation |

---

## What I'd Accept

If the defender revises to address:
1. **Attribution as prerequisite**: Explicitly include `setUserID()` in the mobile app as step 0
2. **Client-server dedup strategy**: For each event, declare one source of truth
3. **Atomic increment for message count**: Replace read-then-write with `RETURNING` or RPC
4. **Non-purchase event name for milestone**: Don't use `fb_mobile_purchase` for messaging events

I would accept the revised proposal. The insertion points and overall approach are sound — the issues are in the details, not the architecture.
