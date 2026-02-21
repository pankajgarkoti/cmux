"""Tests for Telegram integration routes.

These test the API endpoints, not the actual Telegram Bot API calls.
The bot is not configured in tests (no TELEGRAM_BOT_TOKEN), so send
operations return success=False gracefully.
"""


def test_telegram_status_unconfigured(client):
    """Test status endpoint when bot is not configured."""
    response = client.get("/api/telegram/status")
    assert response.status_code == 200
    data = response.json()
    assert "configured" in data
    assert "running" in data
    # In tests, TELEGRAM_BOT_TOKEN is not set
    assert data["configured"] is False
    assert data["running"] is False


def test_telegram_send_unconfigured(client):
    """Test send endpoint returns error when bot is not configured."""
    response = client.post("/api/telegram/send", json={
        "text": "Hello from test",
    })
    assert response.status_code == 200
    data = response.json()
    assert data["success"] is False
    assert "not configured" in data["error"]


def test_telegram_webhook_no_message(client):
    """Test webhook endpoint handles empty updates."""
    response = client.post("/api/telegram/webhook", json={
        "update_id": 12345,
    })
    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_telegram_webhook_with_message(client):
    """Test webhook endpoint processes message updates."""
    response = client.post("/api/telegram/webhook", json={
        "update_id": 12346,
        "message": {
            "message_id": 1,
            "chat": {"id": 999},
            "text": "Hello CMUX",
            "date": 1700000000,
        },
    })
    assert response.status_code == 200
    assert response.json()["ok"] is True


def test_telegram_reload(client):
    """Test reload endpoint returns status fields."""
    response = client.post("/api/telegram/reload")
    assert response.status_code == 200
    data = response.json()
    assert "configured" in data
    assert "running" in data
    assert "chat_id" in data
