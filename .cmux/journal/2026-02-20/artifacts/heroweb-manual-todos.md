# Heroweb — Manual To-Do Checklist

> Things requiring **human action** before features work in production.
> Updated by `cmux:sup-heroweb` whenever workers complete tasks with manual steps.

---

## Meta Campaign Events (`feat/meta-campaign-events`, commit `343913c`)

- [ ] **Run SQL migration on Supabase** — Execute `supabase/migrations/20260220000000_atomic_increment_messages.sql` via Supabase dashboard (SQL Editor) or CLI (`supabase db push`). This creates the `increment_message_count()` RPC function needed for atomic message counting. Without this, `incrementMessageCount()` will gracefully return 0 but the 10-message milestone event will never fire.

- [ ] **Verify Meta env vars in Vercel** — Confirm `META_APP_ID` and `META_APP_SECRET` are set in Vercel project environment variables (Production + Preview). These are required by `lib/meta-capi.ts` to send events to Facebook's App Events API. If missing, all Meta CAPI calls will silently fail.

- [ ] **Ship `setUserID()` in Hero mobile app** — Event 1 (trial purchase attribution) is entirely client-side. The React Native app must call Meta's `setUserID(supabase_uid)` after login so server-side events can be attributed to the correct ad campaign user. This is a prerequisite for Meta to match server events to ad clicks. Tracked separately by `cmux:sup-hero`.

---

## Payment System Fixes (unstaged, from Part 3 review)

- [ ] **Run SQL migration for `last_event_at`** — Execute `supabase/migrations/20260214000000_add_token_last_event_at.sql` to add `last_event_at BIGINT DEFAULT 0` column to the tokens table. Required for token lifecycle guards in the webhook processor.

---

*Last updated: 2026-02-20T14:45 IST*
