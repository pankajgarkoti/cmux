import pytest


def test_get_messages(client):
    response = client.get("/api/messages")
    assert response.status_code == 200
    assert "messages" in response.json()
    assert "total" in response.json()


def test_get_messages_with_limit(client):
    response = client.get("/api/messages?limit=10&offset=0")
    assert response.status_code == 200
    assert "messages" in response.json()


def test_send_user_message(client):
    payload = {
        "content": "Test message",
        "from_agent": "supervisor"
    }
    response = client.post("/api/messages/user", json=payload)
    assert response.status_code == 200
    assert response.json()["success"] is True
    assert "message_id" in response.json()
