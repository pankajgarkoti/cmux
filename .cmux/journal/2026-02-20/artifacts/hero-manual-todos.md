# Hero App — Manual To-Do Checklist

Items requiring **human action** (app submissions, device testing, SDK config, etc).
Updated by `sup-hero` as tasks complete.

---

## Meta Campaign Events (feat/meta-campaign-events)

- [ ] **Push & merge `feat/meta-campaign-events` branch** — commit `30b077d` adds `setMetaUserId()` (Step 0 prerequisite). Must be merged to `main` and included in the next release build before server-side campaign events (Events 2 & 3) can attribute conversions to users.
- [ ] **Include in next App Store / Play Store release** — the `setMetaUserId` call only takes effect once the updated binary is live on user devices. Coordinate with release schedule.
- [ ] **Verify Meta Events Manager receives `setUserID` calls** — after release, confirm in [Meta Events Manager](https://business.facebook.com/events_manager) that `user_id` parameter appears on client-side events (session_start, payment events, etc). This validates Advanced Matching is working.
- [ ] **Coordinate with heroweb team on Events 2 & 3 go-live** — server-side Conversions API events (subscription charge, renewal) depend on the client shipping Step 0 first. Signal heroweb team once the release containing `setMetaUserId` is live so they can enable their server-side event firing.

---

*Last updated: 2026-02-20T14:45+05:30 by sup-hero*
