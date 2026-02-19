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


def test_store_internal_message(client):
    """Test the internal message endpoint used by router daemon."""
    payload = {
        "from_agent": "worker-test",
        "to_agent": "supervisor",
        "content": "Test internal message",
        "type": "mailbox"
    }
    response = client.post("/api/messages/internal", json=payload)
    assert response.status_code == 200
    assert response.json()["status"] == "stored"
    assert "id" in response.json()


def test_store_internal_message_default_type(client):
    """Test internal message with default mailbox type."""
    payload = {
        "from_agent": "worker-a",
        "to_agent": "worker-b",
        "content": "Agent to agent message"
    }
    response = client.post("/api/messages/internal", json=payload)
    assert response.status_code == 200
    assert response.json()["status"] == "stored"


def test_store_internal_message_with_task_status(client):
    """Test internal message with task_status field."""
    payload = {
        "from_agent": "worker-test",
        "to_agent": "supervisor",
        "content": "Task with status",
        "type": "mailbox",
        "task_status": "submitted"
    }
    response = client.post("/api/messages/internal", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "stored"
    assert "id" in data


def test_get_tasks_empty(client):
    """Test GET /tasks returns empty list when no tasks exist."""
    response = client.get("/api/messages/tasks")
    assert response.status_code == 200
    data = response.json()
    assert "messages" in data
    assert "total" in data


def test_get_tasks_with_status_filter(client):
    """Test GET /tasks with status filter."""
    # Store a message with task_status
    client.post("/api/messages/internal", json={
        "from_agent": "supervisor",
        "to_agent": "worker-a",
        "content": "Do task A",
        "task_status": "submitted"
    })
    client.post("/api/messages/internal", json={
        "from_agent": "supervisor",
        "to_agent": "worker-b",
        "content": "Do task B",
        "task_status": "working"
    })

    # Get all tasks
    response = client.get("/api/messages/tasks")
    assert response.status_code == 200
    assert response.json()["total"] >= 2

    # Filter by submitted
    response = client.get("/api/messages/tasks?status=submitted")
    assert response.status_code == 200
    for msg in response.json()["messages"]:
        assert msg["task_status"] == "submitted"

    # Filter by working
    response = client.get("/api/messages/tasks?status=working")
    assert response.status_code == 200
    for msg in response.json()["messages"]:
        assert msg["task_status"] == "working"


def test_update_message_status(client):
    """Test PATCH /{message_id}/status to update task lifecycle."""
    # Store a message with task_status
    response = client.post("/api/messages/internal", json={
        "from_agent": "supervisor",
        "to_agent": "worker-test",
        "content": "Lifecycle test task",
        "task_status": "submitted"
    })
    msg_id = response.json()["id"]

    # Update status to working
    response = client.patch(f"/api/messages/{msg_id}/status", json={
        "status": "working"
    })
    assert response.status_code == 200
    assert response.json()["task_status"] == "working"

    # Update status to completed
    response = client.patch(f"/api/messages/{msg_id}/status", json={
        "status": "completed"
    })
    assert response.status_code == 200
    assert response.json()["task_status"] == "completed"


def test_update_message_status_not_found(client):
    """Test updating status for non-existent message returns 404."""
    response = client.patch("/api/messages/nonexistent-id/status", json={
        "status": "working"
    })
    assert response.status_code == 404


def test_update_message_status_invalid(client):
    """Test updating with invalid status returns 422."""
    response = client.patch("/api/messages/some-id/status", json={
        "status": "invalid-status"
    })
    assert response.status_code == 422
