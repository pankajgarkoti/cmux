# CMUX Authentication Implementation Plan

**Created:** 2026-01-31
**Status:** Draft
**Author:** Claude Code Analysis

---

## Executive Summary

CMUX currently has **zero authentication** - all 34 API endpoints and WebSocket connections are completely open to any network access. This plan outlines a comprehensive authentication system using **JWT (JSON Web Tokens)** with support for future OAuth integration.

---

## Table of Contents

1. [Current State Analysis](#1-current-state-analysis)
2. [Authentication Method Recommendation](#2-authentication-method-recommendation)
3. [Endpoint Protection Strategy](#3-endpoint-protection-strategy)
4. [WebSocket Authentication](#4-websocket-authentication)
5. [Frontend Authentication Flow](#5-frontend-authentication-flow)
6. [Implementation Phases](#6-implementation-phases)
7. [Security Considerations](#7-security-considerations)
8. [Configuration & Environment](#8-configuration--environment)
9. [Testing Strategy](#9-testing-strategy)
10. [Rollback Plan](#10-rollback-plan)

---

## 1. Current State Analysis

### 1.1 Attack Surface

| Vulnerability                        | Risk Level  | Impact                       |
| ------------------------------------ | ----------- | ---------------------------- |
| Zero authentication on all endpoints | 🔴 Critical | Full system control          |
| WebSocket without auth               | 🔴 Critical | Real-time data hijacking     |
| Agent event forgery                  | 🔴 Critical | Fake tool execution events   |
| File system exposure                 | 🟠 High     | Read all `.cmux` files       |
| Session manipulation                 | 🟠 High     | Pause/terminate any session  |
| Journal access                       | 🟠 High     | Read all decision logs       |
| Message forgery                      | 🟠 High     | Inject messages as any agent |
| Webhook injection                    | 🟡 Medium   | Trigger arbitrary webhooks   |
| CORS allows all origins              | 🟡 Medium   | Cross-site requests          |

### 1.2 Current Architecture

**Backend:**

- FastAPI app in `src/server/main.py`
- 7 route modules under `src/server/routes/`
- CORS middleware allows `["*"]` origins
- Pydantic Settings for configuration

**Frontend:**

- React + TypeScript + Vite
- Plain `fetch()` API calls in `src/frontend/src/lib/api.ts`
- Zustand stores for state management
- WebSocket with auto-reconnect in `useWebSocket.ts`

### 1.3 Endpoints Inventory

| Route Group          | Endpoints            | Current Auth |
| -------------------- | -------------------- | ------------ |
| `/api/agents/`       | 10 (incl. WebSocket) | None         |
| `/api/sessions/`     | 9                    | None         |
| `/api/messages/`     | 2                    | None         |
| `/api/journal/`      | 6                    | None         |
| `/api/filesystem/`   | 2                    | None         |
| `/api/agent-events/` | 3                    | None         |
| `/api/webhooks/`     | 2                    | None         |
| **Total**            | **34**               | **None**     |

---

## 2. Authentication Method Recommendation

### 2.1 Options Evaluated

| Method        | Pros                                    | Cons                                       | Fit for CMUX         |
| ------------- | --------------------------------------- | ------------------------------------------ | -------------------- |
| **JWT**       | Stateless, scalable, WebSocket-friendly | Token revocation complexity                | ✅ Recommended       |
| Session-based | Simple, easy revocation                 | Requires session store, stateful           | ❌ Less suitable     |
| OAuth 2.0     | Standard, third-party auth              | Complex setup, overkill for single-user    | 🟡 Future addition   |
| API Keys      | Simple for M2M                          | Not suitable for frontend, no user context | 🟡 For webhooks only |

### 2.2 Recommended Approach: JWT + API Keys Hybrid

**Primary:** JWT tokens for user/frontend authentication

- Short-lived access tokens (15 minutes)
- Long-lived refresh tokens (7 days)
- Stateless validation

**Secondary:** API keys for machine-to-machine

- Webhook signature validation
- Claude Code hook authentication
- External service integration

**Future:** OAuth 2.0 provider support

- GitHub OAuth for team access
- Pluggable provider architecture

### 2.3 Token Structure

```json
{
  "sub": "user_id",
  "exp": 1706745600,
  "iat": 1706744700,
  "type": "access",
  "scope": ["agents:read", "agents:write", "sessions:manage"],
  "session_id": "cmux-main"
}
```

---

## 3. Endpoint Protection Strategy

### 3.1 Protection Levels

| Level         | Description            | Endpoints                                          |
| ------------- | ---------------------- | -------------------------------------------------- |
| **Public**    | No auth required       | `/api/webhooks/health`                             |
| **API Key**   | Machine authentication | `/api/webhooks/{source}`, `/api/agent-events` POST |
| **User Auth** | JWT required           | All other endpoints                                |
| **Admin**     | Special permissions    | Session termination, system config                 |

### 3.2 Route-by-Route Protection

#### Agents (`/api/agents/`)

```python
GET  /                    → User Auth (agents:read)
GET  /{agent_id}          → User Auth (agents:read)
POST /{agent_id}/message  → User Auth (agents:write)
POST /{agent_id}/interrupt → User Auth (agents:write)
POST /{agent_id}/compact  → User Auth (agents:write)
GET  /{agent_id}/terminal → User Auth (agents:read)
POST /{agent_id}/archive  → User Auth (agents:write)
GET  /archived            → User Auth (agents:read)
GET  /archived/{id}       → User Auth (agents:read)
WS   /ws                  → User Auth (query token)
```

#### Sessions (`/api/sessions/`)

```python
GET  /                    → User Auth (sessions:read)
POST /                    → User Auth (sessions:create)
GET  /{session_id}        → User Auth (sessions:read)
DELETE /{session_id}      → Admin Auth (sessions:delete)
POST /{session_id}/pause  → User Auth (sessions:manage)
POST /{session_id}/resume → User Auth (sessions:manage)
POST /{session_id}/clear  → User Auth (sessions:manage)
POST /{session_id}/message → User Auth (sessions:write)
GET  /{session_id}/agents → User Auth (sessions:read)
```

#### Messages (`/api/messages/`)

```python
GET  /                    → User Auth (messages:read)
POST /user                → Internal Only (agents only)
```

#### Journal (`/api/journal/`)

```python
GET  /                    → User Auth (journal:read)
POST /entry               → User Auth (journal:write)
GET  /dates               → User Auth (journal:read)
GET  /search              → User Auth (journal:read)
POST /artifact            → User Auth (journal:write)
GET  /artifact/{filename} → User Auth (journal:read)
```

#### Filesystem (`/api/filesystem/`)

```python
GET  /                    → User Auth (filesystem:read)
GET  /content             → User Auth (filesystem:read)
```

#### Agent Events (`/api/agent-events/`)

```python
POST /                    → API Key (hook authentication)
GET  /                    → User Auth (events:read)
GET  /sessions            → User Auth (events:read)
```

#### Webhooks (`/api/webhooks/`)

```python
GET  /health              → Public
POST /{source}            → API Key (per-source)
```

### 3.3 FastAPI Dependency Implementation

```python
# src/server/auth/dependencies.py

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials

security = HTTPBearer()

async def verify_token(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> TokenPayload:
    """Verify JWT and return payload."""
    token = credentials.credentials
    try:
        payload = decode_jwt(token)
        return TokenPayload(**payload)
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token"
        )

async def require_scope(required: str):
    """Factory for scope-checking dependency."""
    async def checker(token: TokenPayload = Depends(verify_token)):
        if required not in token.scope:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"Scope '{required}' required"
            )
        return token
    return checker

# Usage in routes:
@router.get("/")
async def list_agents(
    user: TokenPayload = Depends(require_scope("agents:read"))
):
    ...
```

---

## 4. WebSocket Authentication

### 4.1 Challenge

WebSocket connections cannot use HTTP headers after the initial handshake. Options:

1. **Query parameter token** - Pass JWT in URL (`?token=xxx`)
2. **First message authentication** - Send token as first message
3. **Cookie-based** - Use HTTP-only cookies

### 4.2 Recommended: Query Parameter + Validation

```python
# src/server/routes/agents.py

@router.websocket("/ws")
async def websocket_endpoint(
    websocket: WebSocket,
    token: str = Query(None)
):
    # Validate token before accepting connection
    if not token:
        await websocket.close(code=4001, reason="Token required")
        return

    try:
        payload = decode_jwt(token)
        user_id = payload["sub"]
    except JWTError:
        await websocket.close(code=4003, reason="Invalid token")
        return

    # Accept connection with authenticated user
    await ws_manager.connect(websocket, user_id)
    try:
        while True:
            data = await websocket.receive_json()
            # Handle authenticated messages
    except WebSocketDisconnect:
        ws_manager.disconnect(user_id)
```

### 4.3 Frontend WebSocket Auth

```typescript
// src/frontend/src/hooks/useWebSocket.ts

import { useAuthStore } from "../auth/authStore";

export function useWebSocket() {
  const { accessToken } = useAuthStore();

  const connect = useCallback(() => {
    if (!accessToken) return;

    const url = `${WS_URL}?token=${encodeURIComponent(accessToken)}`;
    const ws = new WebSocket(url);
    // ... rest of connection logic
  }, [accessToken]);

  // Reconnect when token changes
  useEffect(() => {
    if (accessToken) {
      connect();
    }
  }, [accessToken, connect]);
}
```

### 4.4 Token Refresh During WebSocket

WebSocket connections may outlive access tokens. Strategy:

1. Server tracks token expiry per connection
2. Server sends `token_expiring` event 1 minute before expiry
3. Client refreshes token and sends `token_refresh` message
4. Server updates connection's token

```typescript
// Client-side handling
ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  if (data.type === "token_expiring") {
    const newToken = await refreshToken();
    ws.send(JSON.stringify({ type: "token_refresh", token: newToken }));
  }
};
```

---

## 5. Frontend Authentication Flow

### 5.1 New Auth Store

```typescript
// src/frontend/src/auth/authStore.ts

import { create } from "zustand";
import { persist } from "zustand/middleware";

interface AuthState {
  user: User | null;
  accessToken: string | null;
  refreshToken: string | null;
  isAuthenticated: boolean;
  isLoading: boolean;

  login: (username: string, password: string) => Promise<void>;
  logout: () => void;
  refresh: () => Promise<void>;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set, get) => ({
      user: null,
      accessToken: null,
      refreshToken: null,
      isAuthenticated: false,
      isLoading: false,

      login: async (username, password) => {
        set({ isLoading: true });
        try {
          const res = await fetch(`${API_BASE}/api/auth/login`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ username, password }),
          });
          if (!res.ok) throw new Error("Login failed");
          const data = await res.json();
          set({
            user: data.user,
            accessToken: data.access_token,
            refreshToken: data.refresh_token,
            isAuthenticated: true,
          });
        } finally {
          set({ isLoading: false });
        }
      },

      logout: () => {
        set({
          user: null,
          accessToken: null,
          refreshToken: null,
          isAuthenticated: false,
        });
      },

      refresh: async () => {
        const { refreshToken } = get();
        if (!refreshToken) {
          get().logout();
          return;
        }
        const res = await fetch(`${API_BASE}/api/auth/refresh`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ refresh_token: refreshToken }),
        });
        if (!res.ok) {
          get().logout();
          return;
        }
        const data = await res.json();
        set({ accessToken: data.access_token });
      },
    }),
    { name: "cmux-auth" },
  ),
);
```

### 5.2 Authenticated Fetch Wrapper

```typescript
// src/frontend/src/auth/fetchWithAuth.ts

import { useAuthStore } from "./authStore";

export async function fetchWithAuth(
  url: string,
  options: RequestInit = {},
): Promise<Response> {
  const { accessToken, refresh, logout } = useAuthStore.getState();

  if (!accessToken) {
    throw new Error("Not authenticated");
  }

  const headers = new Headers(options.headers);
  headers.set("Authorization", `Bearer ${accessToken}`);

  let res = await fetch(url, { ...options, headers });

  // Handle token expiry
  if (res.status === 401) {
    await refresh();
    const newToken = useAuthStore.getState().accessToken;
    if (!newToken) {
      logout();
      throw new Error("Session expired");
    }
    headers.set("Authorization", `Bearer ${newToken}`);
    res = await fetch(url, { ...options, headers });
  }

  return res;
}
```

### 5.3 Update API Client

```typescript
// src/frontend/src/lib/api.ts

import { fetchWithAuth } from "../auth/fetchWithAuth";

export const api = {
  // Replace all fetch() calls with fetchWithAuth()
  async listAgents(): Promise<Agent[]> {
    const res = await fetchWithAuth(`${API_BASE}/api/agents/`);
    if (!res.ok) throw new Error("Failed to fetch agents");
    return res.json();
  },
  // ... update all other methods
};
```

### 5.4 Protected Route Component

```typescript
// src/frontend/src/auth/ProtectedRoute.tsx

import { Navigate } from 'react-router-dom';
import { useAuthStore } from './authStore';

export function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { isAuthenticated, isLoading } = useAuthStore();

  if (isLoading) {
    return <div>Loading...</div>;
  }

  if (!isAuthenticated) {
    return <Navigate to="/login" replace />;
  }

  return <>{children}</>;
}
```

### 5.5 Login Page

```typescript
// src/frontend/src/pages/Login.tsx

export function LoginPage() {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const { login, isLoading } = useAuthStore();
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    try {
      await login(username, password);
      navigate('/');
    } catch (err) {
      setError('Invalid credentials');
    }
  };

  return (
    <form onSubmit={handleSubmit}>
      <input value={username} onChange={e => setUsername(e.target.value)} />
      <input type="password" value={password} onChange={e => setPassword(e.target.value)} />
      <button type="submit" disabled={isLoading}>Login</button>
      {error && <p>{error}</p>}
    </form>
  );
}
```

---

## 6. Implementation Phases

### Phase 1: Core Auth Infrastructure (Foundation)

**Backend:**

- [ ] Create `src/server/auth/` module
- [ ] Implement JWT utilities (`tokens.py`)
- [ ] Add auth configuration to `config.py`
- [ ] Create user model and storage
- [ ] Implement `/api/auth/login` endpoint
- [ ] Implement `/api/auth/refresh` endpoint
- [ ] Create `verify_token` dependency

**Frontend:**

- [ ] Create `src/frontend/src/auth/` directory
- [ ] Implement `authStore.ts`
- [ ] Create `fetchWithAuth.ts` wrapper
- [ ] Add login page component

**Files to Create:**

```
src/server/auth/
├── __init__.py
├── config.py         # Auth settings (secret key, token expiry)
├── tokens.py         # JWT encode/decode
├── models.py         # User, TokenPayload models
├── dependencies.py   # FastAPI Depends functions
├── users.py          # User storage/validation
└── routes.py         # /api/auth/* endpoints

src/frontend/src/auth/
├── authStore.ts
├── fetchWithAuth.ts
├── ProtectedRoute.tsx
├── useAuth.ts
└── types.ts
```

### Phase 2: Protect REST Endpoints

**Backend:**

- [ ] Add auth dependencies to `/api/agents/`
- [ ] Add auth dependencies to `/api/sessions/`
- [ ] Add auth dependencies to `/api/messages/`
- [ ] Add auth dependencies to `/api/journal/`
- [ ] Add auth dependencies to `/api/filesystem/`
- [ ] Add auth dependencies to `/api/agent-events/` GET
- [ ] Update CORS to restrict origins

**Frontend:**

- [ ] Update `lib/api.ts` to use `fetchWithAuth`
- [ ] Add `ProtectedRoute` wrapper to App.tsx
- [ ] Handle 401 responses globally
- [ ] Add logout on auth failure

### Phase 3: WebSocket Authentication

**Backend:**

- [ ] Add token query parameter to WebSocket endpoint
- [ ] Validate token before accepting connection
- [ ] Track user ID per connection
- [ ] Implement token refresh during connection

**Frontend:**

- [ ] Update `useWebSocket.ts` to include token
- [ ] Handle `token_expiring` events
- [ ] Reconnect on token refresh

### Phase 4: API Key Authentication

**Backend:**

- [ ] Create API key model and storage
- [ ] Implement API key generation endpoint
- [ ] Add API key validation for webhooks
- [ ] Add API key validation for agent events

**Files:**

```
src/server/auth/
├── api_keys.py       # API key generation/validation
└── webhook_auth.py   # Webhook signature verification
```

### Phase 5: Enhanced Security

- [ ] Add rate limiting
- [ ] Implement audit logging
- [ ] Add password hashing (argon2)
- [ ] Session management (optional)
- [ ] Role-based access control (RBAC)
- [ ] CORS origin whitelist

### Phase 6: OAuth Integration (Future)

- [ ] OAuth provider abstraction
- [ ] GitHub OAuth implementation
- [ ] Google OAuth implementation
- [ ] SSO support

---

## 7. Security Considerations

### 7.1 Token Security

| Concern             | Mitigation                        |
| ------------------- | --------------------------------- |
| Token theft         | Short expiry (15 min), HTTPS only |
| Refresh token theft | HTTP-only cookie option, rotation |
| XSS attacks         | Store in memory, not localStorage |
| CSRF attacks        | SameSite cookies, CSRF tokens     |

### 7.2 Password Security

- Use **argon2** for password hashing (not bcrypt)
- Minimum password requirements: 12 chars, mixed case, numbers
- Account lockout after 5 failed attempts
- Rate limit login attempts

### 7.3 API Key Security

- Generate 256-bit random keys
- Hash keys in storage (only show once at creation)
- Scope keys to specific actions
- Automatic expiry option

### 7.4 CORS Configuration

```python
# Replace current permissive CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:5173",  # Dev frontend
        "http://localhost:8000",  # Production
        # Add production domains
    ],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)
```

### 7.5 WebSocket Security

- Validate token before accepting connection
- Close connection on token expiry
- Rate limit messages per connection
- Validate message schema

---

## 8. Configuration & Environment

### 8.1 New Environment Variables

```bash
# Authentication
CMUX_AUTH_SECRET_KEY="your-256-bit-secret-key"
CMUX_AUTH_ALGORITHM="HS256"
CMUX_AUTH_ACCESS_TOKEN_EXPIRE_MINUTES=15
CMUX_AUTH_REFRESH_TOKEN_EXPIRE_DAYS=7

# Initial Admin User
CMUX_ADMIN_USERNAME="admin"
CMUX_ADMIN_PASSWORD="secure-password-here"

# API Keys
CMUX_WEBHOOK_API_KEY="webhook-secret-key"
CMUX_AGENT_HOOK_API_KEY="agent-hook-key"

# CORS
CMUX_CORS_ORIGINS="http://localhost:5173,http://localhost:8000"
```

### 8.2 Config Model Update

```python
# src/server/config.py additions

class AuthSettings(BaseSettings):
    secret_key: str = Field(..., description="JWT signing key")
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 15
    refresh_token_expire_days: int = 7

    model_config = SettingsConfigDict(
        env_prefix="CMUX_AUTH_",
        env_file=".env",
    )

class Settings(BaseSettings):
    # ... existing fields ...
    auth: AuthSettings = Field(default_factory=AuthSettings)
    cors_origins: list[str] = ["http://localhost:5173"]
```

### 8.3 Secret Key Generation

```bash
# Generate secure secret key
python -c "import secrets; print(secrets.token_urlsafe(32))"
```

---

## 9. Testing Strategy

### 9.1 Unit Tests

```python
# tests/test_auth.py

class TestJWTTokens:
    def test_create_access_token(self):
        token = create_access_token({"sub": "user1"})
        payload = decode_jwt(token)
        assert payload["sub"] == "user1"

    def test_expired_token_rejected(self):
        token = create_access_token({"sub": "user1"}, expires_delta=timedelta(seconds=-1))
        with pytest.raises(JWTError):
            decode_jwt(token)

class TestAuthDependencies:
    async def test_missing_token_returns_401(self):
        async with AsyncClient() as client:
            res = await client.get("/api/agents/")
            assert res.status_code == 401

    async def test_valid_token_succeeds(self):
        token = create_access_token({"sub": "user1", "scope": ["agents:read"]})
        async with AsyncClient() as client:
            res = await client.get(
                "/api/agents/",
                headers={"Authorization": f"Bearer {token}"}
            )
            assert res.status_code == 200
```

### 9.2 Integration Tests

```python
# tests/test_auth_flow.py

class TestLoginFlow:
    async def test_login_returns_tokens(self):
        res = await client.post("/api/auth/login", json={
            "username": "admin",
            "password": "test-password"
        })
        assert res.status_code == 200
        data = res.json()
        assert "access_token" in data
        assert "refresh_token" in data

    async def test_refresh_token_works(self):
        # Login first
        login_res = await client.post("/api/auth/login", json={...})
        refresh_token = login_res.json()["refresh_token"]

        # Refresh
        res = await client.post("/api/auth/refresh", json={
            "refresh_token": refresh_token
        })
        assert res.status_code == 200
        assert "access_token" in res.json()
```

### 9.3 WebSocket Auth Tests

```python
# tests/test_websocket_auth.py

class TestWebSocketAuth:
    async def test_connection_without_token_rejected(self):
        async with websockets.connect("ws://localhost:8000/api/agents/ws") as ws:
            # Should be closed with 4001
            pass  # Connection should fail

    async def test_connection_with_valid_token(self):
        token = create_access_token({"sub": "user1"})
        async with websockets.connect(
            f"ws://localhost:8000/api/agents/ws?token={token}"
        ) as ws:
            # Should succeed
            await ws.send(json.dumps({"type": "ping"}))
            response = await ws.recv()
            assert json.loads(response)["type"] == "pong"
```

---

## 10. Rollback Plan

### 10.1 Feature Flags

Implement auth behind feature flag for gradual rollout:

```python
# src/server/config.py
class Settings:
    auth_enabled: bool = False  # Start disabled

# src/server/auth/dependencies.py
async def verify_token_optional(...):
    if not settings.auth_enabled:
        return None  # Skip auth when disabled
    return await verify_token(...)
```

### 10.2 Rollback Procedure

1. **Immediate:** Set `CMUX_AUTH_ENABLED=false` and restart
2. **If frontend broken:** Revert frontend to pre-auth commit
3. **If backend broken:** Health daemon auto-rollback triggers
4. **Manual rollback:**
   ```bash
   git stash
   git checkout <last-known-good-commit>
   ./src/orchestrator/cmux.sh stop
   ./src/orchestrator/cmux.sh start
   ```

### 10.3 Compatibility

During transition, support both authenticated and unauthenticated access:

```python
async def verify_token_or_legacy(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security_optional)
):
    if settings.auth_enabled and credentials:
        return await verify_token(credentials)
    elif settings.auth_enabled:
        raise HTTPException(401, "Token required")
    return None  # Legacy mode
```

---

## Appendix A: File Changes Summary

| File                                       | Action | Description                    |
| ------------------------------------------ | ------ | ------------------------------ |
| `src/server/auth/__init__.py`              | Create | Auth module exports            |
| `src/server/auth/config.py`                | Create | Auth settings                  |
| `src/server/auth/tokens.py`                | Create | JWT utilities                  |
| `src/server/auth/models.py`                | Create | User, Token models             |
| `src/server/auth/dependencies.py`          | Create | FastAPI Depends                |
| `src/server/auth/users.py`                 | Create | User storage                   |
| `src/server/auth/routes.py`                | Create | Auth endpoints                 |
| `src/server/config.py`                     | Modify | Add auth settings              |
| `src/server/main.py`                       | Modify | Mount auth routes, update CORS |
| `src/server/routes/agents.py`              | Modify | Add auth dependencies          |
| `src/server/routes/sessions.py`            | Modify | Add auth dependencies          |
| `src/server/routes/messages.py`            | Modify | Add auth dependencies          |
| `src/server/routes/journal.py`             | Modify | Add auth dependencies          |
| `src/server/routes/filesystem.py`          | Modify | Add auth dependencies          |
| `src/server/routes/agent_events.py`        | Modify | Add auth dependencies          |
| `src/frontend/src/auth/authStore.ts`       | Create | Auth state management          |
| `src/frontend/src/auth/fetchWithAuth.ts`   | Create | Auth fetch wrapper             |
| `src/frontend/src/auth/ProtectedRoute.tsx` | Create | Route guard                    |
| `src/frontend/src/lib/api.ts`              | Modify | Use authenticated fetch        |
| `src/frontend/src/hooks/useWebSocket.ts`   | Modify | Add token to WS URL            |
| `src/frontend/src/pages/Login.tsx`         | Create | Login page                     |
| `src/frontend/src/App.tsx`                 | Modify | Add routes, protection         |

---

## Appendix B: Dependencies to Add

### Backend (pyproject.toml)

```toml
dependencies = [
    # ... existing
    "python-jose[cryptography]>=3.3.0",  # JWT
    "passlib[argon2]>=1.7.4",            # Password hashing
]
```

### Frontend (package.json)

```json
{
  "dependencies": {
    // No new dependencies needed - uses native fetch
  }
}
```

---

## Appendix C: Estimated Effort

| Phase                        | Scope                               | Complexity |
| ---------------------------- | ----------------------------------- | ---------- |
| Phase 1: Core Infrastructure | Backend auth module, frontend store | Medium     |
| Phase 2: REST Protection     | Update 34 endpoints                 | Low-Medium |
| Phase 3: WebSocket Auth      | Connection validation               | Medium     |
| Phase 4: API Keys            | Webhook/hook auth                   | Low        |
| Phase 5: Enhanced Security   | Rate limiting, audit                | Medium     |
| Phase 6: OAuth               | Future work                         | High       |

**Recommended approach:** Implement phases 1-3 together, then phase 4, then phase 5 as needed.

---

_This plan is a living document. Update as implementation progresses._
