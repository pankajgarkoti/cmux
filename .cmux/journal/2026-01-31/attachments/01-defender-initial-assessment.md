# Auth Plan Defense - Initial Assessment

**From:** worker-auth-defender (DEFENDER & PRAGMATIST)
**To:** worker-auth-critic
**Subject:** Initial Defense of Auth Implementation Plan

---

## Executive Summary

After thorough review of `.cmux/plans/auth-implementation.md`, I find this to be a **well-structured, practical plan** that addresses real security gaps while remaining implementable. Here's my defense of the key design decisions:

---

## Strong Points Worth Defending

### 1. JWT + API Keys Hybrid Approach

This is the **right choice** for CMUX's architecture:

- **JWT for users/frontend**: Stateless validation aligns with FastAPI's async model. No database lookup per request.
- **API Keys for M2M**: Webhooks and Claude Code hooks need long-lived, revocable credentials - JWT would be cumbersome here.
- **Practical separation**: User auth and machine auth have different lifecycles and security requirements.

*Challenge for critics: What alternative hybrid would you propose that's simpler yet equally flexible?*

### 2. Phased Implementation

The 6-phase approach is pragmatic:

- Phase 1-3 together (core + REST + WebSocket) creates a **minimum viable security layer**
- Feature flag for rollout enables **testing without commitment**
- Health daemon integration provides **automatic recovery** if auth breaks the system

*This isn't over-engineering - it's responsible incremental delivery.*

### 3. WebSocket Token Handling

The query parameter approach with server-side refresh notifications is practical:

- Query params work across all WebSocket libraries
- `token_expiring` events prevent abrupt disconnections
- The alternative (first-message auth) adds complexity to every WS handler

### 4. Scope-Based Access Control

The granular scopes (`agents:read`, `agents:write`, `sessions:manage`) provide:

- **Future flexibility** for multi-user scenarios
- **Principle of least privilege** for API consumers
- **Clear authorization boundaries** in code

### 5. Rollback Plan

The feature flag + health daemon combo is CMUX's secret weapon:

- `CMUX_AUTH_ENABLED=false` for instant disable
- Auto-rollback if health checks fail
- Zero-downtime recovery path

---

## Areas I'll Concede Might Need Discussion

1. **Token storage in frontend**: Plan mentions both localStorage concerns and "store in memory" - needs clarity
2. **User storage**: File-based vs database isn't specified
3. **15-minute access token**: Might be aggressive for long sessions
4. **OAuth in Phase 6**: Could be de-prioritized further

---

## My Position

This plan solves the **immediate critical problem** (zero authentication) with a **proven technology stack** (JWT, FastAPI dependencies, Zustand). It's not perfect, but it's implementable and recoverable.

**I'm ready to defend specific technical choices. Critic - bring your challenges.**

---

*Waiting for critique from worker-auth-critic...*
