# CMUX Authentication Implementation Plan (FINAL)

**Created:** 2026-01-31
**Status:** ✅ Approved
**Authors:** worker-auth-critic, worker-auth-advocate
**Debate Rounds:** 3

---

## Executive Summary

A minimal authentication system for CMUX that:

- Keeps unauthorized users out
- Supports a fixed list of users (add more via config file)
- Uses JWT for stateless verification
- Requires ~240 lines of new code

---

## 1. Requirements (Clarified)

| Requirement                     | Implementation               |
| ------------------------------- | ---------------------------- |
| Protect from unauthorized users | JWT-based authentication     |
| Fixed number of users           | YAML config file             |
| Add users as we go              | Edit config, restart server  |
| Simple authorization            | Binary: authenticated or not |

**What we're NOT building:**

- User self-registration
- OAuth/SSO
- Fine-grained permissions (scopes)
- Refresh tokens
- Admin UI for user management

---

## 2. Technical Design

### 2.1 Authentication Flow

```
1. User visits CMUX dashboard
2. Redirected to /login if not authenticated
3. User enters username + password
4. Server validates against .cmux/users.yaml
5. Server returns 7-day JWT
6. Frontend stores token in memory (+ localStorage for persistence)
7. All API calls include Authorization: Bearer <token>
8. WebSocket sends token as first message after connect
```

### 2.2 User Storage

```yaml
# .cmux/users.yaml
users:
  alice:
    password_hash: "$argon2id$v=19$m=65536,t=3,p=4$..."
  bob:
    password_hash: "$argon2id$v=19$m=65536,t=3,p=4$..."
```

**Adding a user:**

```bash
./scripts/add-user.sh
# Prompts for username and password
# Outputs YAML to add to users.yaml
# Restart CMUX to pick up changes
```

### 2.3 Token Structure

```json
{
  "sub": "alice",
  "exp": 1707350400,
  "iat": 1706745600
}
```

No scopes, no roles - just identity. If the token is valid, the user has full access.

### 2.4 Environment Variables

```bash
# Required
CMUX_AUTH_ENABLED=true
CMUX_AUTH_SECRET="<32-byte-random-string>"

# Optional (defaults shown)
CMUX_AUTH_TOKEN_EXPIRY_DAYS=7
CMUX_AUTH_USERS_FILE=".cmux/users.yaml"

# M2M Authentication
CMUX_WEBHOOK_SECRET=""    # Empty = webhooks require no auth
CMUX_HOOK_SECRET=""       # Empty = hooks require no auth

# CORS
CMUX_CORS_ORIGINS="http://localhost:5173,http://localhost:8000,http://127.0.0.1:5173,http://127.0.0.1:8000"
```

---

## 3. Implementation

### 3.1 Backend Files

```
src/server/auth/
├── __init__.py       # Module exports
├── tokens.py         # JWT create/decode
├── users.py          # Load YAML, verify password
├── middleware.py     # FastAPI dependencies
└── routes.py         # /api/auth/login endpoint
```

#### tokens.py (~25 lines)

```python
import jwt
from datetime import datetime, timedelta
from ..config import settings

def create_token(username: str) -> str:
    payload = {
        "sub": username,
        "iat": datetime.utcnow(),
        "exp": datetime.utcnow() + timedelta(days=settings.auth_token_expiry_days),
    }
    return jwt.encode(payload, settings.auth_secret, algorithm="HS256")

def decode_token(token: str) -> dict:
    return jwt.decode(token, settings.auth_secret, algorithms=["HS256"])
```

#### users.py (~40 lines)

```python
import yaml
from pathlib import Path
from passlib.hash import argon2
from ..config import settings

_users_cache: dict | None = None

def load_users() -> dict:
    global _users_cache
    if _users_cache is None:
        path = Path(settings.auth_users_file)
        if path.exists():
            with open(path) as f:
                data = yaml.safe_load(f)
                _users_cache = data.get("users", {})
        else:
            _users_cache = {}
    return _users_cache

def verify_user(username: str, password: str) -> bool:
    users = load_users()
    user = users.get(username)
    if not user:
        # Timing-safe: still run hash comparison
        argon2.verify(password, "$argon2id$v=19$m=65536,t=3,p=4$dummy$dummy")
        return False
    return argon2.verify(password, user["password_hash"])

def get_user(username: str) -> dict | None:
    users = load_users()
    return users.get(username)
```

#### middleware.py (~30 lines)

```python
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from .tokens import decode_token

security = HTTPBearer()

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security)
) -> str:
    """Returns username if token is valid, raises 401 otherwise."""
    try:
        payload = decode_token(credentials.credentials)
        return payload["sub"]
    except Exception:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired token"
        )

async def get_current_user_optional(
    credentials: HTTPAuthorizationCredentials = Depends(HTTPBearer(auto_error=False))
) -> str | None:
    """Returns username or None (for optional auth endpoints)."""
    if not credentials:
        return None
    try:
        payload = decode_token(credentials.credentials)
        return payload["sub"]
    except Exception:
        return None
```

#### routes.py (~35 lines)

```python
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from .tokens import create_token
from .users import verify_user
from ..config import settings

router = APIRouter(prefix="/api/auth", tags=["auth"])

class LoginRequest(BaseModel):
    username: str
    password: str

class LoginResponse(BaseModel):
    token: str
    expires_in_days: int
    username: str

@router.post("/login", response_model=LoginResponse)
async def login(request: LoginRequest):
    if not verify_user(request.username, request.password):
        raise HTTPException(status_code=401, detail="Invalid credentials")

    token = create_token(request.username)
    return LoginResponse(
        token=token,
        expires_in_days=settings.auth_token_expiry_days,
        username=request.username
    )
```

### 3.2 Frontend Files

```
src/frontend/src/auth/
├── authStore.ts      # Token state management
├── fetchWithAuth.ts  # Authenticated fetch wrapper
└── LoginPage.tsx     # Login form
```

#### authStore.ts (~30 lines)

```typescript
import { create } from "zustand";
import { persist } from "zustand/middleware";

interface AuthState {
  token: string | null;
  username: string | null;
  isAuthenticated: boolean;
  login: (username: string, password: string) => Promise<void>;
  logout: () => void;
}

export const useAuthStore = create<AuthState>()(
  persist(
    (set) => ({
      token: null,
      username: null,
      isAuthenticated: false,

      login: async (username: string, password: string) => {
        const res = await fetch("/api/auth/login", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ username, password }),
        });
        if (!res.ok) throw new Error("Invalid credentials");
        const data = await res.json();
        set({
          token: data.token,
          username: data.username,
          isAuthenticated: true,
        });
      },

      logout: () =>
        set({ token: null, username: null, isAuthenticated: false }),
    }),
    { name: "cmux-auth" },
  ),
);
```

#### fetchWithAuth.ts (~20 lines)

```typescript
import { useAuthStore } from "./authStore";

export async function fetchWithAuth(
  url: string,
  options: RequestInit = {},
): Promise<Response> {
  const { token, logout } = useAuthStore.getState();

  if (!token) {
    throw new Error("Not authenticated");
  }

  const headers = new Headers(options.headers);
  headers.set("Authorization", `Bearer ${token}`);

  const response = await fetch(url, { ...options, headers });

  if (response.status === 401) {
    logout();
    throw new Error("Session expired");
  }

  return response;
}
```

#### LoginPage.tsx (~40 lines)

```tsx
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { useAuthStore } from "./authStore";

export function LoginPage() {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const { login } = useAuthStore();
  const navigate = useNavigate();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError("");
    try {
      await login(username, password);
      navigate("/");
    } catch (err) {
      setError("Invalid username or password");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="login-container">
      <h1>CMUX Login</h1>
      <form onSubmit={handleSubmit}>
        <input
          type="text"
          placeholder="Username"
          value={username}
          onChange={(e) => setUsername(e.target.value)}
        />
        <input
          type="password"
          placeholder="Password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
        />
        <button type="submit" disabled={loading}>
          {loading ? "Logging in..." : "Login"}
        </button>
        {error && <p className="error">{error}</p>}
      </form>
    </div>
  );
}
```

### 3.3 Scripts

#### scripts/add-user.sh (~15 lines)

```bash
#!/bin/bash
set -e

read -p "Username: " USERNAME
read -sp "Password: " PASSWORD
echo

HASH=$(python3 -c "from passlib.hash import argon2; print(argon2.hash('$PASSWORD'))")

echo ""
echo "Add this to .cmux/users.yaml under 'users:':"
echo ""
echo "  $USERNAME:"
echo "    password_hash: \"$HASH\""
```

### 3.4 Example Users File

```yaml
# .cmux/users.yaml.example
# Copy to .cmux/users.yaml and add your users
# Generate password hashes with: ./scripts/add-user.sh

users:
  # Example - replace with real users
  admin:
    password_hash: "$argon2id$v=19$m=65536,t=3,p=4$REPLACE_ME"
```

---

## 4. Existing File Changes

### src/server/config.py

```python
# Add to Settings class
auth_enabled: bool = Field(default=False, description="Enable authentication")
auth_secret: str = Field(default="", description="JWT signing secret")
auth_token_expiry_days: int = Field(default=7, description="Token expiry in days")
auth_users_file: str = Field(default=".cmux/users.yaml", description="Path to users file")
webhook_secret: str = Field(default="", description="Webhook authentication secret")
hook_secret: str = Field(default="", description="Claude hook authentication secret")
cors_origins: str = Field(
    default="http://localhost:5173,http://localhost:8000",
    description="Comma-separated CORS origins"
)
```

### src/server/main.py

```python
# Add auth routes
from .auth.routes import router as auth_router
app.include_router(auth_router)

# Update CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins.split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### src/server/routes/\*.py (all route files)

```python
# Add to each endpoint that needs protection
from ..auth.middleware import get_current_user

@router.get("/")
async def list_agents(user: str = Depends(get_current_user)):
    # user is now the authenticated username
    ...
```

### src/frontend/src/hooks/useWebSocket.ts

```typescript
// Add first-message auth
ws.onopen = () => {
  const { token } = useAuthStore.getState();
  if (token) {
    ws.send(JSON.stringify({ type: "auth", token }));
  }
};
```

---

## 5. WebSocket Authentication

### Backend Handler Update

```python
@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()

    # Wait for auth message (timeout: 5 seconds)
    try:
        auth_message = await asyncio.wait_for(
            websocket.receive_json(),
            timeout=5.0
        )
    except asyncio.TimeoutError:
        await websocket.close(code=4001, reason="Auth timeout")
        return

    if auth_message.get("type") != "auth" or not auth_message.get("token"):
        await websocket.close(code=4001, reason="Auth required")
        return

    try:
        payload = decode_token(auth_message["token"])
        username = payload["sub"]
    except Exception:
        await websocket.close(code=4003, reason="Invalid token")
        return

    # Send auth success
    await websocket.send_json({"type": "auth_success", "username": username})

    # Continue with normal WebSocket handling
    await ws_manager.connect(websocket, username)
    try:
        while True:
            data = await websocket.receive_json()
            # Handle messages...
    except WebSocketDisconnect:
        ws_manager.disconnect(username)
```

---

## 6. Webhook/Hook Authentication

### Webhook Secret Validation

```python
# src/server/routes/webhooks.py
from fastapi import Header, HTTPException
import hmac

@router.post("/{source}")
async def receive_webhook(
    source: str,
    x_webhook_secret: str = Header(None)
):
    if settings.webhook_secret:
        if not x_webhook_secret or not hmac.compare_digest(
            x_webhook_secret, settings.webhook_secret
        ):
            raise HTTPException(status_code=401, detail="Invalid webhook secret")
    # Process webhook...
```

### Claude Hook Secret Validation

```python
# src/server/routes/agent_events.py
@router.post("/")
async def receive_event(
    x_hook_secret: str = Header(None)
):
    if settings.hook_secret:
        if not x_hook_secret or not hmac.compare_digest(
            x_hook_secret, settings.hook_secret
        ):
            raise HTTPException(status_code=401, detail="Invalid hook secret")
    # Process event...
```

---

## 7. Rollback Plan

### Feature Flag

```bash
# Disable auth instantly
CMUX_AUTH_ENABLED=false
./src/orchestrator/cmux.sh restart
```

### Emergency Token Revocation

```bash
# Rotate secret - all tokens become invalid
CMUX_AUTH_SECRET="$(python -c 'import secrets; print(secrets.token_urlsafe(32))')"
./src/orchestrator/cmux.sh restart
# All users must re-login
```

### Health Daemon Integration

Auth failures on `/api/webhooks/health` trigger auto-rollback (existing behavior).

---

## 8. Testing

```bash
# Unit tests
uv run pytest tests/test_auth.py -v

# Manual verification
curl http://localhost:8000/api/agents/           # Should 401
TOKEN=$(curl -s -X POST http://localhost:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"test"}' | jq -r .token)
curl -H "Authorization: Bearer $TOKEN" http://localhost:8000/api/agents/  # Should 200

# WebSocket test
wscat -c ws://localhost:8000/api/agents/ws
> {"type":"auth","token":"<TOKEN>"}
< {"type":"auth_success","username":"admin"}
```

---

## 9. Implementation Phases

### Phase 1: Core Auth (2-3 days)

- [ ] Create `src/server/auth/` module (4 files)
- [ ] Add config settings
- [ ] Mount auth routes
- [ ] Add `Depends(get_current_user)` to all protected routes
- [ ] Update WebSocket with first-message auth
- [ ] Create frontend auth components (3 files)
- [ ] Update `useWebSocket.ts`
- [ ] Add login route to App.tsx
- [ ] Create `scripts/add-user.sh`
- [ ] Create `.cmux/users.yaml.example`

### Phase 2: M2M Auth (1 day)

- [ ] Add webhook secret validation
- [ ] Add hook secret validation
- [ ] Document Claude hook configuration
- [ ] Update CORS configuration

---

## 10. File Summary

| File                                     | Lines    | Action |
| ---------------------------------------- | -------- | ------ |
| `src/server/auth/__init__.py`            | 5        | Create |
| `src/server/auth/tokens.py`              | 25       | Create |
| `src/server/auth/users.py`               | 40       | Create |
| `src/server/auth/middleware.py`          | 30       | Create |
| `src/server/auth/routes.py`              | 35       | Create |
| `src/server/config.py`                   | +15      | Modify |
| `src/server/main.py`                     | +10      | Modify |
| `src/server/routes/*.py`                 | +2 each  | Modify |
| `src/frontend/src/auth/authStore.ts`     | 30       | Create |
| `src/frontend/src/auth/fetchWithAuth.ts` | 20       | Create |
| `src/frontend/src/pages/LoginPage.tsx`   | 40       | Create |
| `scripts/add-user.sh`                    | 15       | Create |
| `.cmux/users.yaml.example`               | 10       | Create |
| **Total new code**                       | **~240** |        |

---

## 11. Debate Summary

This plan emerged from 3 rounds of structured debate:

**Round 1:** Critic identified over-engineering in original 937-line plan
**Round 2:** Requirements clarified ("fixed users, add more as we go")
**Round 3:** Converged on minimal auth with YAML user storage

**Key simplifications from original:**

- 15+ scopes → 1 level (authenticated)
- Refresh tokens → 7-day access only
- User database → YAML config file
- API key management → 2 env var secrets
- 6 phases → 2 phases
- ~1000 lines → ~240 lines

**Accepted tradeoffs:**

- 7-day token theft window (acceptable for dev tool)
- No hot-reload for users (restart required)
- localStorage for tokens (XSS risk documented)

---

**Status:** ✅ APPROVED FOR IMPLEMENTATION

_Plan finalized 2026-01-31 after advocate-critic debate._
