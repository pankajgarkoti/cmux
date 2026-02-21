# Hero App — Comprehensive Codebase Research Report

**Researcher**: hero-research
**Date**: 2026-02-21
**Project Path**: `/Users/pankajgarkoti/Desktop/code/zonko/hero`
**Companion Backend**: `/Users/pankajgarkoti/Desktop/code/zonko/heroweb`

---

## 1. Product Overview

**Hero** is a personalized shareable creatives app targeting Tier 2/3 India. Package: `com.zonkoai.hero`. Two core modes:

- **Daily Mode (Templates)**: Browse free templates, ₹99/month subscription to download/share
- **Magic Mode (AI)**: Hyper-personalized AI images where the user is the "hero" — 1 coin each, powered by Google Gemini

**Key Metrics**:
- Version: 0.0.8b (versionCode 9)
- Launch: Jan 2025
- Revenue: ₹1 trial → ₹199/month auto-debit (hidden from user), coin packs (₹99/₹199/₹499)
- Content: Hindi + English, UI in English only
- 8 supported languages for content: EN, HI, BN, MR, TA, TE, GU, KN

---

## 2. Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| Framework | React Native + Expo | RN 0.81.5, Expo 54.0.30 |
| Language | TypeScript | 5.9.2 |
| Routing | Expo Router (file-based) | 6.0.21 |
| State (client) | Zustand | 5.0.9 |
| State (server) | React Query (@tanstack) | 5.90.16 |
| Database | Supabase (PostgreSQL) | 2.89.0 |
| Auth | Phone OTP via Twilio Verify | - |
| Payments | Razorpay (S2S UPI Intent for subscriptions, Standard Checkout for coins) | 2.3.1 |
| AI | Google Gemini (@google/genai) | 1.34.0 |
| Video | FFmpeg Kit | 6.1.2 |
| Audio | react-native-nitro-sound | 0.2.10 |
| Push | Expo Notifications + Firebase | - |
| Analytics | PostHog + Facebook SDK | 4.17.2 |
| Platform | Android-first (min SDK 24, target SDK 35) | - |
| Architecture | New Architecture enabled, React Compiler experiment | - |

---

## 3. Project Structure

```
hero/
├── app/                    # 32 route files across 8 route groups
│   ├── _layout.tsx         # Root: AuthNavigator, DeeplinkHandler, ScreenTracker, push
│   ├── index.tsx           # Entry: hydration wait → splash or chat redirect
│   ├── splash.tsx          # Animated carousel, navigation decision tree
│   ├── (tabs)/             # Main app: home (templates feed), gallery, profile
│   ├── onboarding/         # 5-screen standard flow: language → profile → phone → religion → payment
│   ├── onboarding-valentine/ # 3-screen valentine flow: profile → phone → payment
│   ├── chat/               # [botId].tsx dynamic chat screen
│   ├── generate/           # AI generation: loading → result, valentine-partner → valentine-result, editor
│   ├── payment/            # result.tsx — payment callback verification
│   ├── stylish-ai.tsx      # AI category picker hub
│   ├── refer.tsx           # Referral program with leaderboard
│   ├── love.tsx            # Valentine hub with template gallery
│   ├── companions.tsx      # AI companion bot list
│   └── faq.tsx             # Help/FAQ page
│
├── stores/                 # 5 Zustand stores
│   ├── user-store.ts       # 49KB — profile, subscription, onboarding, analytics, deeplinks
│   ├── chat-store.ts       # Conversation IDs (persisted), inputs/errors (transient)
│   ├── payment-store.ts    # Order + subscription state, loading, errors
│   ├── upload-store.ts     # Transient upload progress per message
│   └── audioPlaybackStore.ts # Singleton audio playback state
│
├── hooks/                  # 21 hooks
│   ├── useChat.ts          # 557 lines — central chat logic, drip-feed, queuing, streaming
│   ├── useMediaUpload.ts   # Exponential backoff retry (3 attempts)
│   ├── useVoiceRecorder.ts # Recording with waveform, auto-stop at 30s
│   ├── use-payment-onboarding.ts # Full subscription flow (UPI selection → Razorpay → verify)
│   ├── use-phone-verification.ts # Auto-proceed on 10 digits, user switching
│   ├── use-profile-setup.ts # Photo + name + Supabase sync
│   ├── use-premium-gate.ts # Subscription check + upgrade sheet
│   ├── use-magic-images.ts # React Query wrappers for AI gallery
│   └── queries/            # React Query hooks: useChat, useContent
│
├── lib/                    # 34 service modules
│   ├── chat-api.ts         # 19KB — bots API, chat streaming, media upload
│   ├── razorpay.ts         # S2S UPI mandates + Standard Checkout
│   ├── coins-api.ts        # Fire-and-forget coin ledger
│   ├── posthog-analytics.ts # 43KB — 100+ event tracking functions
│   ├── meta-analytics.ts   # Facebook pixel / CAPI integration
│   ├── gemini.ts           # Gemini AI image generation
│   ├── supabase.ts         # Client initialization
│   ├── api-config.ts       # Backend URL resolver (production + local dev probe)
│   ├── notifications.ts    # Push notification registration
│   ├── audio-cache.ts      # LRU audio file cache
│   └── ...                 # deeplink-parser, otp-service, version-check, etc.
│
├── components/             # 63 TSX components
│   ├── chat/               # 11 files: ChatInput, ChatHeader, MessageBubble, AudioMessage, etc.
│   ├── ui/                 # 10 primitives: button, card, input, modal, shimmer, otp-input
│   ├── templates/          # 7 files: TemplateCard, StatusCard, CategoryPills, BotGrid
│   ├── common/             # 5 files: Header, ActionBar, EmptyState, LoadingOverlay
│   ├── navbar/             # 3 files: FloatingNavbar, NavItemButton
│   ├── payment-onboarding/ # 3 variations: GodPayment, FriendPayment, StatusMakerPayment
│   ├── valentine/          # 9 seasonal components: FloatingHearts, ValentineHomeScreen
│   └── (root)              # 15 modals/sheets: coin-topup, premium-upgrade, force-update, etc.
│
├── constants/              # 16 config files
│   ├── theme.ts            # Design system: saffron #F26B1D + gold #F5A623
│   ├── payments.ts         # COIN_PACKS, SUBSCRIPTION_AMOUNT (₹199)
│   ├── translations.ts     # 99KB — multilingual strings (8 languages)
│   ├── valentine-*.ts      # Seasonal theme + categories (active Jan 20 - Feb 15)
│   └── ...                 # languages, faqs, indian-cities, api, posthog, supabase
│
├── types/                  # 3 type files: audio.ts, chat.ts, react-native-razorpay.d.ts
├── utils/                  # 7 utils: logger, upi-apps, audio/*, location-service
├── modules/                # Native: text-renderer (Kotlin, Android-only)
├── plugins/                # 4 Expo plugins: SecureScreen, FfmpegMin, FacebookDeferredLinks, FacebookMarketing
├── scripts/                # build.js (EAS build + DB version update), generate-valentine-assets
├── data/                   # Template datasets: CSV, enriched, republic, onboarding
├── backend/                # Lean Vercel serverless layer (see section 6)
├── docs/                   # PRD, payment docs, analytics guides, feature specs
└── specs/                  # Feature specifications with implementation plans + progress tracking
```

---

## 4. Architecture & Data Flow

### Communication Architecture

```
Hero Mobile App (React Native)
  │
  │  HTTP + Headers (X-App-Client: hero-mobile-1.0, X-User-Id: <uuid>)
  │
  ▼
Heroweb API (Next.js 16, Vercel)  ← hero.zonko.ai
  │
  ├── Supabase (PostgreSQL + Storage) — shared between hero & heroweb
  ├── Google Gemini 2.5 Flash — AI chat responses
  ├── ElevenLabs — TTS audio responses
  ├── Razorpay — S2S UPI mandates + Standard Checkout
  └── Expo Push API — push notifications
```

### State Management Pattern

- **Client state** (profile, subscription, onboarding) → Zustand stores with AsyncStorage persistence
- **Server state** (bots, conversations, templates) → React Query with configurable stale/cache times
- **Transient state** (uploads, audio playback, UI loading) → Zustand stores without persistence
- **Partialize strategy**: Large data (base64 images, magic images) excluded from persistence to prevent AsyncStorage overflow

### Key Data Flows

**Chat Message**:
1. App sends `POST /api/chat/app` → Heroweb validates headers → builds Gemini prompt with persona + user context → streams response
2. If audio input: generates TTS via ElevenLabs
3. Optimistic UI updates + drip-feed (timed multi-bubble reveals)
4. Every ~10 messages: memory extraction updates user profile

**Subscription (S2S UPI Intent)**:
1. App calls `create-upi-mandate` → backend creates Razorpay customer + recurring order
2. Returns `intent_url` → app opens UPI app via `Linking.openURL()`
3. App polls `check-mandate-status` (AppState-aware, 90s timeout)
4. On authorization: stores `token_id`, activates subscription, grants 30 days + 15 coins
5. Daily cron charges expiring subscriptions using stored tokens

**AI Generation**:
1. User selects category on stylish-ai.tsx → deducts 1 coin
2. Loading screen with rotating tips (30s countdown)
3. Calls Gemini API with category-specific prompts
4. Result screen: 1-4 generated images with download/share/regenerate

---

## 5. Route Structure (32 files, 8 groups)

### Route Groups

| Group | Screens | Purpose |
|-------|---------|---------|
| `(tabs)` | index, gallery, profile | Main app — hidden tab bar, header-based nav |
| `/onboarding` | language, index, phone, religion, payment | 5-step standard onboarding |
| `/onboarding-valentine` | index, phone, payment | 3-step valentine onboarding |
| `/chat` | [botId] | Dynamic AI companion chat |
| `/generate` | index, result, valentine-partner, valentine-result, editor | AI generation pipeline |
| `/payment` | result | Payment callback verification |
| (standalone) | splash, stylish-ai, refer, love, companions, faq | Standalone screens |

### Navigation Decision Tree (splash.tsx)

```
Profile incomplete? → onboarding (regular or valentine theme)
Phone not verified? → phone verification
Pending deeplink? → navigate to chat/tab/home
Payment pending? → payment screen
Default → /(tabs)
```

### Deep Link Format

```
hero://                          → Home tab
hero://tab/1                     → Templates tab
hero://tab/2                     → AI/Magic tab
hero://chat/<botId>              → Bot chat screen
hero://chat/<botId>?botName=X    → Bot chat with name hint
hero://payment/result?order_id=X → Payment callback
```

4 independent deep link entry points: Facebook deferred, cold start URL, runtime deep link, notification tap.

---

## 6. Backend Architecture

### Heroweb (Primary Backend) — `/Users/pankajgarkoti/Desktop/code/zonko/heroweb`

Next.js 16 app deployed on Vercel. This is the main API backend.

**API Endpoints**:
- `GET /api/bots/public` — live bot listing
- `POST /api/chat/app` — send chat message (streaming)
- `POST /api/chat/app/upload` — media upload (audio/image/video)
- `GET /api/chat/app/bot/[botId]/history` — conversation history
- `POST /api/payments/razorpay/create-order` — coin purchase order
- `POST /api/payments/razorpay/verify` — payment signature verification
- `POST /api/payments/razorpay/create-upi-mandate` — S2S subscription
- `POST /api/payments/razorpay/check-mandate-status` — poll mandate status
- `POST /api/webhooks/razorpay` — HMAC-SHA256 validated webhook
- `POST /api/admin/notifications/send` — push notification dispatch
- `GET /api/cron/morning-notifications` — daily 4:00 AM IST push
- `GET /api/cron/subscription-charges` — daily recurring charge processing

**Database Tables** (Supabase, `hero_app_` / `hero_admin_` prefixed):
- `hero_admin_bots` — bot definitions with system prompts
- `hero_app_conversations` / `hero_app_messages` — chat data
- `hero_app_media_messages` — media attachments
- `hero_app_user_profiles` — user data
- `hero_app_payment_subscriptions` — subscription lifecycle (CREATED → ACTIVE → CANCELLED → EXPIRED)
- `hero_app_payment_orders` — payment orders
- `hero_app_payment_transactions` — immutable payment ledger
- `hero_app_coin_ledger` — internal credits
- `hero_app_payment_customer_tokens` — Razorpay customer + UPI mandate tokens
- `hero_app_payment_webhook_events` — webhook audit log
- `hero_app_audio_tts_*` — TTS tracking and deduplication

### Hero Backend (Lightweight) — `hero/backend/`

Lean Vercel serverless layer for payment integration and Meta analytics.

- `GET /api/health` — health check
- `POST /api/create-checkout` — DodoPayments checkout session (4 tiers)
- `POST /api/dodo/webhook` — payment webhook → Meta CAPI forwarding

**Note**: This appears to be a secondary/legacy backend. The primary payment flow uses Razorpay via heroweb. DodoPayments integration in `hero/backend/` may be an alternative or experimental payment provider.

---

## 7. Payment System

### Revenue Model

| Revenue Stream | Price | Mechanism |
|---------------|-------|-----------|
| Trial | ₹1 (refunded in 6 hrs) | UPI mandate creation |
| Subscription | ₹199/month | Auto-debit via stored UPI token (hidden from user) |
| Coin Packs | ₹99 (8), ₹199 (20), ₹499 (55) | Razorpay Standard Checkout |

### Coin Economy

| Source | Amount | Trigger |
|--------|--------|---------|
| Free signup | 3 coins | Account creation |
| Trial/subscription start | 15 coins | Payment activation |
| Daily login (subscribers) | 3 coins | Daily claim |
| Referral | 10 coins | Successful referral |
| Coin purchase | 8/20/55 | In-app purchase |
| AI generation | -1 coin | Per image generation |

### Payment Providers

1. **Razorpay** (primary): S2S UPI Intent for subscriptions, Standard Checkout for coins
2. **Cashfree** (configured but appears legacy): SDK v2.2.5, sandbox mode
3. **DodoPayments** (in `hero/backend/`): 4-tier checkout, test mode

---

## 8. AI & Content System

### AI Integration

- **Google Gemini** (`@google/genai` 1.34.0) — image generation from user photo + category prompts
- **Gemini 2.5 Flash** (via heroweb) — AI chat responses with persona-specific system prompts
- **ElevenLabs** — TTS audio responses in chat
- Generation cost: ~₹14/image (server-side)
- User cost: 1 coin per generation
- Output: 1080 x 1350px (4:5 ratio), no watermark

### Content Categories (10 MVP)

Good Morning, Good Night, Spiritual (with deity sub-options for Hindu users), Motivation, Success/Money, Family, Festival (dynamic based on calendar), Boss Life, Love (including Heartbreak), Birthday

### Religion-Based Content Filtering

Critical rule: Muslim users see ONLY Muslim content. Other religions see their content + generic. Hindu users get deity picker (Hanuman, Shiva, Krishna, Ganesh, Lakshmi, Durga).

### Seasonal Features

- **Valentine** (Jan 20 - Feb 15): Separate onboarding flow, pink theme, couple photo generation (boyfriend/girlfriend), valentine template gallery
- **Festivals**: Dynamic based on calendar (Makar Sankranti, Republic Day, etc.)

---

## 9. Analytics & Tracking

### PostHog (100+ events)

Comprehensive funnel tracking across: app lifecycle, onboarding (7+ step events), home/templates, AI generation, gallery, chat, payments, referral, premium gating, app review. Event file: `lib/posthog-analytics.ts` (43KB).

### Meta/Facebook

- SDK initialization on cold start
- `CompletedRegistration` on onboarding complete
- `Purchase` on subscription auth
- `fb_mobile_initiated_checkout` on coin pack selection
- Server-side CAPI via `hero/backend/lib/meta-capi.ts` for webhook-driven tracking

### Key Funnels

- Onboarding: start → photo → phone → payment → complete
- Payment: viewed → CTA clicked → UPI app opened → mandate authorized → subscription active
- AI Generation: category selected → generation started → completed → downloaded/shared

---

## 10. Native Modules & Plugins

### Custom Native Module
- `modules/text-renderer/` — Kotlin Android module for native text rendering on images

### Expo Plugins
- `withSecureScreen` — FLAG_SECURE on content screens (screenshot prevention)
- `withFfmpegMin` — FFmpeg kit with minimal configuration
- `withFacebookDeferredLinks` — Facebook deferred deep link support with install referrer decryption
- `withFacebookMarketing` — Facebook marketing SDK integration

---

## 11. Feature Specifications (Active/Recent)

Located in `docs/` and `specs/`:

| Feature | Status | Key Files |
|---------|--------|-----------|
| App Media Messages | In progress | `docs/hero-app/specs/app-media-messages/` |
| Cashfree Revamp | In progress | `docs/hero-app/specs/cashfree-revamp/` |
| Chat Refactoring | Completed | `docs/hero-app/specs/chat-refactoring/` |
| Profile Support Bot | In progress | `docs/hero-app/specs/profile-support-bot/` |
| Payments System | In progress | `docs/hero-app/specs/payments-system/` |
| Admin Dashboard | In progress | `docs/hero-backend/specs/admin-dashboard/` |
| Audio TTS Response | Completed | `docs/hero-backend/specs/audio-tts-response/` |
| Razorpay S2S | Documented | `docs/razorpay-s2s-implementation.md` |
| Urgent Cashfree Fix | Documented | `docs/URGENT-CASHFREE-FIX.md` |

---

## 12. Security Measures

- **FLAG_SECURE**: Screenshot/recording prevention on content screens (via `withSecureScreen` plugin)
- **Screen recording detection**: Black overlay + toast when detected
- **HMAC-SHA256**: Razorpay webhook signature validation
- **Header-based auth**: `X-App-Client` allowlist + `X-User-Id` for API requests
- **JWT + bcrypt**: Admin dashboard authentication
- **Supabase RLS**: Row-level security on all database tables
- **No client-side API keys**: Payment processing is server-side only

---

## 13. Build & Deployment

### Mobile App
```bash
npx expo run:android              # Local build + install
eas build --profile preview       # Preview APK
eas build --profile production    # Production AAB
npm run build:android             # Build + auto-update version in Supabase
```

### Backend (Heroweb)
- Deployed on Vercel (Next.js 16)
- Cron jobs via `vercel.json`: morning notifications + subscription charges at 22:30 UTC (4:00 AM IST)

### Testing
```bash
adb shell pm clear com.zonkoai.hero    # Reset app state
adb shell am start -a android.intent.action.VIEW -d "hero://chat/<botId>"  # Test deep links
adb logcat -d | grep "ReactNativeJS"   # View logs
adb reverse tcp:3000 tcp:3000          # Connect to local backend
```

---

## 14. Key Technical Patterns & Gotchas

1. **Store Persistence Strategy**: Only persist essential data; exclude base64 images, magic images, and transient UI state to prevent AsyncStorage overflow
2. **Fire-and-Forget**: Analytics, coin ledger, Supabase sync — non-blocking to preserve app flow
3. **Optimistic UI**: Chat messages appear instantly with background sync
4. **Drip-Feed**: Multi-bubble bot responses revealed with timed delays for natural UX
5. **AppState-Aware Polling**: Payment mandate polling checks immediately when user returns from UPI app instead of waiting for next interval
6. **Audio Singleton**: Only one audio message plays at a time across the entire app
7. **LRU Cache**: Audio files cached with configurable size, automatic cleanup
8. **Exponential Backoff**: Media uploads retry 3 times (1s, 2s, 4s) with transient/permanent error classification
9. **React Native Layout**: Never use `height: '100%'` when parent has no fixed height (Android/iOS inconsistency)
10. **Expo Router Types**: Route types auto-generated at `.expo/types/router.d.ts` — never use `as any` casts

---

## 15. Known Bot IDs

| Bot | ID | Usage |
|-----|----|-------|
| Saniya (default/support) | `125a1dd0-3446-4e93-9218-05fc94daaac7` | Default chat + support bot |
| Friend | `28aad775-6dc3-4a75-af02-35ffae908473` | Payment variation flow |
| God | `81184f2f-6b0b-4cbd-92e4-2e9464793611` | Payment variation flow |
| Valentine | `b44a7954-...-valentine` | Valentine onboarding theme trigger |

---

## 16. Summary for Squad Members

### For hero-backend worker:
- Primary backend is **heroweb** (Next.js 16, Vercel) — NOT the `hero/backend/` directory
- Payment system uses Razorpay S2S UPI Intent for subscriptions, Standard Checkout for coins
- All API requests include `X-App-Client` and `X-User-Id` headers
- Database is Supabase PostgreSQL with `hero_app_` / `hero_admin_` table prefixes
- 12 migration files in `heroweb/supabase/migrations/`

### For hero-frontend worker:
- Expo Router 6.0.21 with file-based routing, 32 route files
- 5 Zustand stores (user-store is 49KB — the god store)
- 21 hooks, 34 service modules, 63 components
- Theme: saffron #F26B1D + gold #F5A623, Poppins font
- Valentine seasonal features active Jan 20 - Feb 15
- Always use typed routes (never `as any`), check `.expo/types/router.d.ts`

### For hero-tester worker:
- Android package: `com.zonkoai.hero`
- Min SDK 24, Target SDK 35
- Deep link scheme: `hero://`
- Clear app data before testing onboarding: `adb shell pm clear com.zonkoai.hero`
- 4 deep link entry points to test (Facebook deferred, cold start, runtime, notification tap)
- Payment flow requires UPI app on device/emulator
- Chrome MCP for browser testing, `adb logcat` for native logs
