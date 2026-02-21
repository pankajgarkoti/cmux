def test_get_budget_summary_empty(client):
    """Test budget summary returns empty list when no usage data exists."""
    response = client.get("/api/budget")
    assert response.status_code == 200
    data = response.json()
    assert "agents" in data
    assert isinstance(data["agents"], list)


def test_get_budget_summary_with_usage(client):
    """Test budget summary aggregates usage from Stop events."""
    # Post two Stop events with usage for the same agent
    client.post("/api/agent-events", json={
        "event_type": "Stop",
        "session_id": "sess-budget-1",
        "agent_id": "worker-budget-a",
        "usage": {
            "input_tokens": 1000,
            "output_tokens": 200,
            "cache_read_input_tokens": 50,
            "cache_creation_input_tokens": 100,
        },
    })
    client.post("/api/agent-events", json={
        "event_type": "Stop",
        "session_id": "sess-budget-1",
        "agent_id": "worker-budget-a",
        "usage": {
            "input_tokens": 500,
            "output_tokens": 150,
            "cache_read_input_tokens": 25,
            "cache_creation_input_tokens": 0,
        },
    })

    response = client.get("/api/budget")
    assert response.status_code == 200
    data = response.json()
    # Find our agent in the results
    agent_data = [a for a in data["agents"] if a["agent_id"] == "worker-budget-a"]
    assert len(agent_data) >= 1
    agent = agent_data[0]
    assert agent["input_tokens"] >= 1500
    assert agent["output_tokens"] >= 350
    assert agent["cache_read_tokens"] >= 75
    assert agent["cache_creation_tokens"] >= 100
    assert agent["event_count"] >= 2


def test_get_agent_budget_detail(client):
    """Test single agent budget returns totals and recent events."""
    # Post an event with usage
    client.post("/api/agent-events", json={
        "event_type": "Stop",
        "session_id": "sess-budget-2",
        "agent_id": "worker-budget-b",
        "usage": {
            "input_tokens": 800,
            "output_tokens": 300,
            "cache_read_input_tokens": 40,
            "cache_creation_input_tokens": 60,
        },
    })

    response = client.get("/api/budget/worker-budget-b")
    assert response.status_code == 200
    data = response.json()
    assert "totals" in data
    assert "recent_events" in data
    assert data["totals"]["agent_id"] == "worker-budget-b"
    assert data["totals"]["input_tokens"] >= 800
    assert data["totals"]["output_tokens"] >= 300
    assert len(data["recent_events"]) >= 1
    # Verify events include usage
    for evt in data["recent_events"]:
        assert evt["usage"] is not None


def test_get_agent_budget_no_data(client):
    """Test single agent budget returns zeros when no usage data exists."""
    response = client.get("/api/budget/nonexistent-agent")
    assert response.status_code == 200
    data = response.json()
    assert data["totals"]["input_tokens"] == 0
    assert data["totals"]["output_tokens"] == 0
    assert data["totals"]["event_count"] == 0
    assert data["recent_events"] == []


def test_event_without_usage_not_counted(client):
    """Test that events without usage field don't appear in budget."""
    # Post a PostToolUse event without usage
    client.post("/api/agent-events", json={
        "event_type": "PostToolUse",
        "session_id": "sess-budget-3",
        "agent_id": "worker-budget-c",
        "tool_name": "Bash",
    })

    response = client.get("/api/budget/worker-budget-c")
    assert response.status_code == 200
    data = response.json()
    assert data["totals"]["event_count"] == 0
    assert data["recent_events"] == []
