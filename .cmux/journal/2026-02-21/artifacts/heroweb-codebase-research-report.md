# Heroweb Codebase Research Report

**Date**: 2026-02-21
**Author**: heroweb-research (CMUX worker agent)
**Project**: `/Users/pankajgarkoti/Desktop/code/zonko/heroweb`
**Actual path note**: The project is at `zonko/heroweb`, not `zonko/hero-web`.

---

## Executive Summary

Heroweb is a **Next.js 16 backend API + admin dashboard** for the **Hero** mobile app (React Native / Expo at `../hero`). It powers AI-driven chat with persona bots (Gemini 2.5 Flash), media messaging, text-to-speech (ElevenLabs), subscription payments (Razorpay S2S UPI + Standard Checkout), coin economy, push notifications (Expo), and a web admin dashboard. Deployed on Vercel. Database is Supabase (PostgreSQL + Storage).

The codebase is **production-grade and well-documented** with a comprehensive README, 23 database migrations, extensive type definitions, and structured error handling throughout.

---

## 1. Architecture Overview

```
Hero Mobile App (React Native / Expo)
       │
       │  HTTP + Headers (X-App-Client, X-User-Id)
       ▼
Heroweb API (Next.js 16 App Router)
  /api/*  ── 38 route handlers
       │
   ┌───┼──────────┬──────────────┐
   ▼   ▼          ▼              ▼
Supabase    Gemini 2.5     ElevenLabs    Razorpay
(DB +       Flash          (TTS)         (Payments)
Storage)    (AI Chat)
```

### Tech Stack

| Layer | Technology |
|-------|-----------|
| Framework | Next.js 16 (App Router, React 19) |
| Language | TypeScript 5 (strict mode) |
| Database | Supabase PostgreSQL + Storage |
| AI | Google Gemini 2.5 Flash |
| TTS | ElevenLabs v3 (eleven_v3 model, mp3_22050_64) |
| Payments | Razorpay (S2S UPI mandates + Standard Checkout) + Cashfree (legacy) |
| Styling | Tailwind CSS 4 + styled-jsx |
| Validation | Zod |
| Auth | JWT + bcrypt (admin), header-based (mobile) |
| Analytics | PostHog, Meta CAPI, Raindrop AI |
| Push | Expo Push API (zero-dependency client) |
| Deployment | Vercel (with cron jobs) |

---

## 2. Project Structure

```
heroweb/
├── app/
│   ├── api/                  # 38 API route handlers
│   │   ├── admin/            # Bot CRUD, auth, avatar, notifications
│   │   ├── bots/public/      # Public bot listing (mobile)
│   │   ├── chat/             # Admin streaming chat
│   │   ├── chat/app/         # Mobile chat, upload, history, intro
│   │   ├── coins/spend/      # Coin deduction
│   │   ├── cron/             # Scheduled jobs (3 crons)
│   │   ├── payments/         # Orders, subscriptions, transactions, Razorpay
│   │   └── webhooks/         # Razorpay + Cashfree webhooks
│   ├── admin/                # Admin dashboard (6 pages)
│   ├── account-deletion/     # Legal/static pages
│   ├── pricing/
│   ├── privacy-policy/
│   ├── refunds/
│   ├── terms/
│   └── contact/
├── lib/
│   ├── ai/                   # 10+ files: Gemini, TTS, security, memory, streaming
│   ├── auth/                 # 4 files: session, middleware, user-session, app-client
│   ├── db/queries/           # 6+ files: conversations, bots, profiles, notifications
│   ├── notifications/        # Push notification dispatcher + Expo client
│   ├── payments/             # 20+ files: complete payment processing stack
│   ├── supabase/             # Client config + generated types
│   ├── logger.ts             # Structured logging (JSON prod, readable dev)
│   ├── rate-limit.ts         # LRU-based rate limiting (4 tiers)
│   ├── posthog.ts            # Event tracking
│   ├── raindrop.ts           # AI observability
│   └── meta-capi.ts          # Meta App Events API
├── types/                    # 6 files: API, bot, chat, payments, webhooks
├── supabase/migrations/      # 23 SQL migration files
├── components/               # Toast.tsx (shared)
├── specs/                    # Feature specifications
├── docs/                     # Events, PostHog funnels, unit economics
├── middleware.ts             # Edge middleware (admin route protection)
├── vercel.json               # Cron schedules
└── scripts/                  # Utility scripts
```

---

## 3. API Routes (38 Total)

### 3.1 Authentication

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/admin/auth/login` | POST | Rate-limited (5/min) | Admin login (email+password → JWT cookie) |
| `/api/admin/auth/logout` | POST | Session | Destroy admin session |

### 3.2 Admin - Bot Management

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/admin/bots` | GET | None | List bots (filter by status, include counts) |
| `/api/admin/bots` | POST | None | Create bot (name, system_prompt required) |
| `/api/admin/bots/[id]` | GET | None | Fetch single bot |
| `/api/admin/bots/[id]` | PUT | None | Update bot fields |
| `/api/admin/bots/[id]` | DELETE | None | Soft-delete bot |
| `/api/admin/bots/upload-avatar` | POST | None | Upload avatar (5MB, JPEG/PNG/WebP/GIF) |

### 3.3 Admin - Notifications

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/admin/notifications/send` | POST | Session + STRICT rate limit | Push to all/subscribed/specific users |
| `/api/admin/notifications/stats` | GET | Session + API rate limit | Token count stats |

### 3.4 Public Bots (Mobile)

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/bots/public` | GET | X-App-Client | List live bots (safe fields only, no system_prompt) |

### 3.5 Chat - Admin Dashboard

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/chat` | POST | Session (withAuth) | SSE streaming chat for bot testing |
| `/api/conversation/[id]/history` | GET | Session | Conversation history for admin |

### 3.6 Chat - Mobile App

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/chat/app` | POST | X-App-Client + X-User-Id | Non-streaming JSON chat (60s timeout) |
| `/api/chat/app/intro` | POST | X-App-Client + X-User-Id | Generate first welcome message |
| `/api/chat/app/bot/[botId]/history` | GET | X-App-Client + X-User-Id | Conversation history with media |
| `/api/chat/app/upload` | POST | X-App-Client + X-User-Id | Media upload (audio 10MB, image 10MB, video 25MB) |
| `/api/chat/app/conversation/[id]/history` | GET | X-App-Client + X-User-Id | Specific conversation history |

### 3.7 Payments - Razorpay

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/payments/razorpay/create-order` | POST | authenticateUser | Create order for coin purchase |
| `/api/payments/razorpay/verify` | POST | authenticateUser | Verify payment signature |
| `/api/payments/razorpay/create-subscription` | POST | authenticateUser | Create recurring subscription |
| `/api/payments/razorpay/create-upi-mandate` | POST | authenticateUser | S2S UPI Intent for mandate auth |
| `/api/payments/razorpay/check-mandate-status` | POST | authenticateUser | Poll mandate authorization |

### 3.8 Payments - Orders & Subscriptions

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/payments/orders` | POST | authenticateUser | Create order (plan-based or amount-based) |
| `/api/payments/orders/me` | GET | authenticateUser | User's order history |
| `/api/payments/orders/[id]` | GET | authenticateUser | Single order details |
| `/api/payments/orders/register` | POST | authenticateUser | Register app-created order |
| `/api/payments/orders/update-status` | POST | authenticateUser | Update order after payment |
| `/api/payments/subscriptions` | POST | authenticateUser | Create subscription |
| `/api/payments/subscriptions/me` | GET | authenticateUser | Active subscription + access info |
| `/api/payments/subscriptions/register` | POST | authenticateUser | Register app-created subscription |
| `/api/payments/subscriptions/[id]/cancel` | POST | authenticateUser | Cancel (preserves access_until) |

### 3.9 Payments - Transactions & Coins

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/payments/transactions/me` | GET | authenticateUser | Transaction history with filters |
| `/api/payments/coins/ledger` | GET/POST | Session/authenticateUser | Coin ledger, balance check, admin-adjust, spend |
| `/api/coins/spend` | POST | authenticateUser | Record coin deduction |

### 3.10 Webhooks

| Endpoint | Method | Auth | Purpose |
|----------|--------|------|---------|
| `/api/webhooks/razorpay` | POST | HMAC SHA256 signature | Razorpay payment events |
| `/api/webhooks/cashfree` | POST | Webhook signature + timestamp | Cashfree payment events |

### 3.11 Cron Jobs (Vercel Scheduled)

| Endpoint | Schedule | Purpose |
|----------|----------|---------|
| `/api/cron/proactive-outreach` | Hourly | Send companion messages based on user activity tier |
| `/api/cron/morning-notifications` | 23:30 UTC | Morning push (skeleton, not yet implemented) |
| `/api/cron/subscription-charges` | 23:00 UTC | S2S recurring charges for expiring subscriptions |
| `/api/cron/subscription-charges/charge` | (Worker, called by dispatcher) | Individual subscription charge with retry |

---

## 4. Database Schema

### 4.1 Tables (23 migrations, 20+ tables)

**Admin Domain:**
- `hero_admin_bots` - Bot definitions with system prompts, avatar, status (draft/live), metadata, version
- `hero_admin_conversations` / `hero_admin_messages` - Admin dashboard chat history
- `hero_admin_sessions` - JWT session tracking

**App Chat Domain:**
- `hero_app_conversations` - User-to-bot conversations
- `hero_app_messages` - Messages with `content` + optional `media_id` + optional `tts_content`
- `hero_app_media_uploads` - Media metadata (soft-delete via `deleted_at`)
- `hero_app_message_reactions` - Emoji reactions (1:1 per message)
- `hero_app_user_profiles` - User data with `conversation_count`, `total_messages`, `user_segment`
- `hero_app_proactive_outreach_log` - Bot-initiated conversation tracking

**Payment Domain:**
- `hero_app_payment_plans` - Plan catalog (code, name, price, interval)
- `hero_app_payment_plan_gateways` - Gateway-specific plan mappings
- `hero_app_payment_subscriptions` - Subscriptions with `current_cycle` and `access_until`
- `hero_app_payment_orders` - Charges with idempotency keys
- `hero_app_payment_transactions` - Immutable payment ledger
- `hero_app_payment_customer_tokens` - Razorpay S2S mandate tokens
- `hero_app_coin_ledger` - Coin balance tracking
- `hero_app_payment_webhook_events` - Webhook audit log

**TTS Domain:**
- `tts_dedup_cache` - SHA-256 hash → audio URL caching
- `tts_quota_daily` - Atomic daily character counter
- `tts_quota_monthly` - Monthly cost accumulator (NUMERIC precision)
- `tts_usage_log` - Detailed audit trail

**Config:**
- `hero_app_version_config` - Singleton version gating table

### 4.2 Key RPC Functions

| Function | Purpose |
|----------|---------|
| `process_payment_webhook()` | Create order + transaction atomically |
| `activate_subscription()` | Transition to ACTIVE with access_until |
| `process_subscription_payment()` | Create recurring order + transaction |
| `sync_subscription_from_webhook()` | Upsert subscription from webhook data |
| `find_user_for_subscription()` | Resolve user by sub ID or phone |
| `compute_user_segment()` | Calculate free/trial/paid across all subs |
| `sync_hero_profile_subscription()` | TRIGGER: sync hero_profiles on sub change |
| `increment_daily_quota()` | Atomic TTS quota check + increment |
| `increment_monthly_cost()` | Atomic monthly cost tracking |
| `increment_message_count()` | Atomic message counter for user/bot |
| `check_subscription_expiry()` | Expire subscriptions + update profiles |

### 4.3 User Segmentation Model

| Segment | Criteria |
|---------|----------|
| `free` | No active subscription or access expired |
| `trial` | ACTIVE + cycle=0 + access_until > NOW() (mandate auth'd, no charge yet) |
| `paid` | ACTIVE + cycle >= 1 (at least one recurring charge) |

Derived via `compute_user_segment()` trigger — single source of truth. No downgrade when worse subscription inserted.

---

## 5. Key Library Modules

### 5.1 AI System (`lib/ai/`)

- **gemini.ts** - Singleton Gemini client with in-memory cache (500 entries, 30min TTL), multimodal support, streaming, error categorization
- **audio-tts-service.ts** - ElevenLabs TTS with atomic quota management, dedup cache (SHA-256), graceful degradation, 800-char truncation
- **security.ts** - Prompt injection detection (regex patterns for jailbreaks, extraction, template injection), HTML stripping, zero-width char removal
- **memory-extraction.ts** - Fire-and-forget user profile learning from conversations (demographics, interests, emotional patterns, relationships)
- **conversation.ts** - In-memory conversation manager with read/write locks, eviction at 100 conversations
- **context-manager.ts** - Token budget management with smart truncation (importance scoring)
- **streaming.ts** - SSE infrastructure with keep-alive pings, error recovery
- **transliterate.ts** - Hinglish → Devanagari + ElevenLabs audio emotion tags
- **message-utils.ts** - Bubble splitting (`---BUBBLE---`), reaction extraction (`---REACT:emoji---`), voice intent detection (`---VOICE---`)
- **prompt-cache.ts** - Generic LRU cache with TTL and version-based invalidation

### 5.2 Auth System (`lib/auth/`)

- **session.ts** - Admin JWT (HS256, 24h, httpOnly cookie)
- **middleware.ts** - `withAuth()` decorator for admin routes
- **user-session.ts** - `authenticateUser()` — multi-method: Bearer token → cookie → app headers
- **app-client.ts** - `X-App-Client` validation (allowlist: `hero-mobile-1.0`), UUID extraction from `X-User-Id`

### 5.3 Payment System (`lib/payments/`, 20+ files)

- **razorpay-client.ts** - SDK wrapper (orders, subscriptions, S2S UPI: customer → recurring order → authorization payment → subsequent payment)
- **order-service.ts** - Order lifecycle with idempotency keys
- **subscription-service.ts** - Subscription lifecycle (cancellation preserves access_until)
- **coin-ledger-service.ts** - Coin balance tracking
- **razorpay-webhook-processor.ts** - Payment event dispatch
- **webhook-validator.ts** - HMAC SHA256 signature verification
- **invoice-generator.ts** - PDF invoice generation
- **types.ts** - Comprehensive enums + interfaces for all payment entities

### 5.4 Rate Limiting (`lib/rate-limit.ts`)

| Tier | Limit | Use Case |
|------|-------|----------|
| AUTH | 5/min | Login brute-force protection |
| CHAT | 20/min | AI chat (expensive) |
| API | 100/min | General API |
| STRICT | 10/min | Sensitive operations |

LRU cache (500 entries), identifier from email → x-forwarded-for → x-real-ip → "unknown".

### 5.5 Analytics

- **PostHog** - Subscription lifecycle events, payment tracking
- **Meta CAPI** - Payment milestone events (trial, first charge, 10 messages)
- **Raindrop AI** - AI interaction tracing with PII redaction

---

## 6. Admin Dashboard (Frontend)

### 6.1 Pages

| Route | Purpose |
|-------|---------|
| `/admin` | Redirects to /admin/bots |
| `/admin/login` | Email/password auth |
| `/admin/bots` | Bot list with search, grid layout, loading skeletons |
| `/admin/bots/new` | Create bot form |
| `/admin/bots/[id]` | Bot detail with tabs (Scenes, LLM Config, Prompts, Monetization) |
| `/admin/bots/[id]/edit` | Edit bot form (name, prompt, avatar, status) |
| `/admin/bots/[id]/test` | Interactive chat testing (iPhone preview frame, SSE streaming) |
| `/admin/notifications` | Dashboard (stats, quick guide) |
| `/admin/notifications/send` | Send form with preview, confirmation modal, targeting |

### 6.2 UI Components

Custom component library in `/admin/components/ui/`:
- **Button** - 6 variants (primary, secondary, outline, ghost, danger, success), 4 sizes, loading state
- **Card** - Container with hover effects, header/content/footer sub-components
- **Badge** - 10 variants, 2 sizes
- **Tabs** - Underline indicator, icon + label
- **LoadingIndicator** - Three animated dots
- **StatusToggle** - Draft/Live with green ping animation
- **PromptEditor** - Auto-resizing textarea with word/char count

### 6.3 Design Patterns

- **Server/Client split**: Server components fetch data, pass to client components for interaction
- **Dark theme**: CSS variables throughout
- **Responsive**: Mobile-first with tablet (768px) and desktop breakpoints
- **Chat streaming**: SSE with AbortController cancellation
- **Persistence**: localStorage for chat history, API for conversations

---

## 7. Key Architectural Patterns

### Error Handling
1. **Custom error classes** per domain (GeminiError, PaymentError, GatewayError, etc.)
2. **Fire-and-forget** for non-critical ops (memory extraction, analytics, TTS tracking)
3. **Graceful degradation** — returns null/false on failure, never breaks the request
4. **Structured logging** — JSON in prod, human-readable in dev, with service context

### Concurrency & Safety
1. **Conversation locks** — read/write with 30s timeout, auto-cleanup
2. **Idempotency keys** — deterministic keys for payment orders
3. **Atomic RPC** — quota checking via Supabase RPC (race-free)
4. **Webhook event ordering** — `last_event_at` prevents out-of-order state overwrites

### Performance
1. **Prompt caching** — Gemini responses cached 30min (500 entries)
2. **TTS dedup cache** — Audio responses reused by content SHA-256 hash
3. **Batch operations** — Media lookups + signed URL generation in single queries
4. **Lazy initialization** — Supabase clients created on first access (avoids build-time errors)

### Security
1. **Prompt injection detection** — Regex patterns for jailbreaks, extraction, template injection
2. **HMAC SHA256** — Payment webhook signature verification
3. **Input sanitization** — Zero-width chars, HTML tags, control chars removed
4. **Rate limiting** — Per-user/IP, configurable by endpoint type
5. **Magic number detection** — File type validation beyond MIME headers

---

## 8. Payment Flow Details

### Subscription via S2S UPI Intent (Primary)

```
1. App calls POST /api/payments/razorpay/create-upi-mandate
2. Backend: get/create Razorpay customer → create recurring order → create authorization payment
3. Returns intent_url → app opens UPI app via Linking.openURL()
4. User authorizes mandate (enters PIN in UPI app)
5. App polls POST /api/payments/razorpay/check-mandate-status every 3s
6. On authorized: webhook stores token_id, activates subscription, grants 30-day access
7. Daily cron charges expiring subscriptions using stored customer_id + token_id
```

### Coin Purchase via Standard Checkout

```
1. App calls POST /api/payments/razorpay/create-order
2. App opens RazorpayCheckout.open() with order details
3. User completes payment in Razorpay modal
4. App calls POST /api/payments/razorpay/verify with signature
5. Backend verifies HMAC, credits coins to ledger
```

### Subscription Lifecycle

```
CREATED → ACTIVE (mandate authorized, cycle=0, trial)
                → cycle incremented on each charge
                → CANCELLED (user cancels, keeps access_until)
                → EXPIRED (access_until passed, no valid token)
```

---

## 9. Proactive Outreach System

The `/api/cron/proactive-outreach` cron runs hourly and:

1. **Quiet hours**: Never sends 11 PM - 7 AM IST
2. **User classification**:
   - Active: last chat <=24h → max 1/day, only if 4-6h since last chat
   - Cooling: 24-72h since last chat → max 1/day
   - Lapsing: >72h since last chat → 1 notification, then 48h cooldown
3. **Generates persona-aware message** via Gemini with user context
4. **Saves to conversation** (appears when user opens chat)
5. **Sends push notification**
6. **Logs to `proactive_outreach_log`** and tracks via PostHog/Raindrop

---

## 10. Dependencies & External Services

| Service | Purpose | Config |
|---------|---------|--------|
| Supabase | DB + Storage + Auth (phone OTP) | NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY |
| Google Gemini | AI chat responses | GEMINI_API_KEY |
| ElevenLabs | TTS audio generation | ELEVENLABS_API_KEY, ELEVENLABS_VOICE_ID |
| Razorpay | Payments (primary) | RAZORPAY_KEY_ID, RAZORPAY_KEY_SECRET, RAZORPAY_WEBHOOK_SECRET |
| Cashfree | Payments (legacy) | Cashfree keys |
| Expo Push | Push notifications | No API key needed (server-to-server) |
| PostHog | Analytics | POSTHOG_API_KEY |
| Raindrop AI | AI observability | Raindrop API key |
| Meta CAPI | App events | FB App ID + App Secret |
| Vercel | Hosting + Cron | CRON_SECRET |

---

## 11. Notable Technical Decisions

1. **No auth.users dependency** — All user IDs are `hero_profiles` UUIDs, not Supabase Auth UUIDs. Webhooks resolve users by subscription ID or phone.

2. **Dual chat endpoints** — Admin uses SSE streaming + session auth; mobile uses JSON response + header auth. Different needs, different implementations.

3. **Fan-out cron pattern** — Subscription charges dispatcher finds eligible subs, then fans out to `/charge` worker endpoint (300s timeout each) in batches of 10 with 2s delays.

4. **Message bubbling** — AI responses use `---BUBBLE---` delimiters for multi-bubble rendering in the app, stripped before context storage.

5. **Transliteration pipeline** — Hinglish text → Devanagari + ElevenLabs audio emotion tags for natural-sounding Hindi TTS.

6. **Multi-gateway support** — Payment system abstracts across Cashfree, Razorpay, Stripe, Manual via enum + gateway-specific adapters. Razorpay is primary for S2S UPI.

7. **Grace period with auto-recovery** — Expired subscriptions can reactivate if a valid token still exists (trial: 30d, recurring: 7d).

---

## 12. Areas for Team Awareness

### For Backend Workers
- **Port 8000 is CMUX-reserved.** Use port 3000 for Next.js dev server.
- Auth is three-layered: admin (JWT session), mobile (X-App-Client + X-User-Id), payments (authenticateUser multi-method).
- Payment webhook handlers always return 200 to prevent retries — errors are logged internally.
- The `hero_app_user_profiles` table is the central user record; many services write to it.

### For Frontend Workers
- Admin dashboard uses styled-jsx + Tailwind CSS 4. Custom component library in `/admin/components/ui/`.
- Chat testing uses SSE streaming with `[DONE]` marker.
- Bot management is the most complete feature; notifications are simpler.
- Dark theme with CSS variables throughout.

### For Testers
- Browser testing required for admin dashboard changes.
- Payment flows need both S2S UPI mandate and Standard Checkout paths tested.
- Proactive outreach has time-of-day and frequency constraints to verify.
- Rate limiting varies by endpoint (5/min for auth, 100/min for general API).

---

*End of research report.*
