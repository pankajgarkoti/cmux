from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect, Body
from datetime import datetime, timezone
from typing import List
import asyncio
import json
import logging
import re
import uuid

from ..models.agent import Agent, AgentList, AgentMessage
from ..models.message import Message, MessageType
from ..services.agent_manager import agent_manager
from ..services.tmux_service import tmux_service
from ..services.mailbox import mailbox_service
from ..services.agent_registry import agent_registry
from ..services.conversation_store import (
    conversation_store,
    ArchivedAgent,
    ArchivedAgentSummary,
)
from ..websocket.manager import ws_manager

logger = logging.getLogger(__name__)

# Regex to extract @mentions from message content
MENTION_PATTERN = re.compile(r"@([\w-]+)")

# Timeout for WebSocket receive operations (seconds)
WS_RECEIVE_TIMEOUT = 60

router = APIRouter()


@router.get("", response_model=AgentList)
async def list_agents():
    """List all active agents."""
    agents = await agent_manager.list_agents()
    return AgentList(agents=agents, total=len(agents))


# IMPORTANT: /archived routes must come BEFORE /{agent_id} to avoid
# FastAPI matching "archived" as an agent_id
@router.get("/archived", response_model=List[ArchivedAgentSummary])
async def list_archived_agents():
    """List all archived agents."""
    return conversation_store.get_archived_agents()


@router.get("/archived/{archive_id}", response_model=ArchivedAgent)
async def get_archived_agent(archive_id: str):
    """Get a specific archived agent with terminal output."""
    archive = conversation_store.get_archive(archive_id)
    if not archive:
        raise HTTPException(status_code=404, detail="Archive not found")
    return archive


@router.get("/by-project/{project_id}")
async def list_agents_by_project(project_id: str):
    """List agents belonging to a specific project.

    Filters the agent registry by project_id and returns matching agents.
    """
    all_entries = agent_registry.get_all_entries()
    agents = []
    for key, entry in all_entries.items():
        if entry.get("project_id") == project_id:
            agents.append({"key": key, **entry})
    return {"project_id": project_id, "agents": agents, "total": len(agents)}


@router.get("/{agent_id}", response_model=Agent)
async def get_agent(agent_id: str):
    """Get details of a specific agent.

    Accepts both agent IDs (ag_xxxxxxxx) and window-based names.
    Agent ID lookup is tried first, then falls back to name.
    """
    agent = await agent_manager.get_agent(agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")
    return agent


@router.post("/{agent_id}/message")
async def send_message_to_agent(agent_id: str, message: AgentMessage):
    """Send a message to a specific agent."""
    agent = await agent_manager.get_agent(agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")

    # Store the user message for chat history
    msg = Message(
        id=str(uuid.uuid4()),
        timestamp=datetime.now(timezone.utc),
        from_agent="user",
        to_agent=agent_id,
        type=MessageType.USER,
        content=message.content
    )
    mailbox_service.store_message(msg)

    # Prefix with [user] so the message starts with an alphabetic character.
    # This prevents tmux send-keys content (e.g. markdown like "- [ ] task")
    # from being interpreted as Claude Code autocomplete suggestions.
    prefixed_content = f"[user] {message.content}"
    await tmux_service.send_input(agent.tmux_window, prefixed_content)
    await ws_manager.broadcast("message_sent", {
        "agent_id": agent_id,
        "content": message.content[:100]
    })
    # Also broadcast the full message for chat UI
    await ws_manager.broadcast("new_message", msg.model_dump(mode="json"))

    # Silently route @mentions to mentioned agents (only in Command Center)
    if agent_id == "supervisor":
        mentioned_names = MENTION_PATTERN.findall(message.content)
        for name in set(mentioned_names):
            if name == agent_id:
                continue
            mentioned_agent = await agent_manager.get_agent(name)
            if mentioned_agent:
                mention_content = f"[cmux:user] @you: {message.content}"
                await tmux_service.send_input(
                    mentioned_agent.tmux_window, mention_content,
                    session=mentioned_agent.session,
                )
                logger.info(f"@mention routed message to {name}")

    return {"success": True, "agent_id": agent_id, "message_id": msg.id}


@router.post("/{agent_id}/interrupt")
async def interrupt_agent(agent_id: str):
    """Send interrupt signal (Ctrl+C) to an agent."""
    agent = await agent_manager.get_agent(agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")

    await tmux_service.send_interrupt(agent.tmux_window)
    return {"success": True, "agent_id": agent_id}


@router.post("/{agent_id}/compact")
async def compact_agent(agent_id: str):
    """Issue /compact command to an agent."""
    agent = await agent_manager.get_agent(agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")

    await tmux_service.send_input(agent.tmux_window, "/compact")
    return {"success": True, "agent_id": agent_id}


@router.get("/{agent_id}/terminal")
async def get_agent_terminal(agent_id: str, lines: int = 50):
    """Get recent terminal output from agent's tmux pane."""
    agent = await agent_manager.get_agent(agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")

    output = await tmux_service.capture_pane(agent.tmux_window, lines)
    return {"agent_id": agent_id, "output": output, "lines": lines}


@router.get("/{agent_id}/history")
async def get_agent_history(agent_id: str, limit: int = 50):
    """Get conversation history for an agent from the conversation store.

    Returns the last N messages involving this agent (both sent and received).
    Useful for agents recovering context after compaction.
    """
    messages = conversation_store.get_messages(limit=limit, agent_id=agent_id)
    return {
        "agent_id": agent_id,
        "messages": [msg.model_dump(mode="json") for msg in messages],
        "count": len(messages),
    }


@router.post("/{agent_id}/archive")
async def archive_agent(agent_id: str, lines: int = 2000):
    """Archive an agent's conversation and terminal output before killing.

    Captures terminal scrollback and stores it along with agent metadata
    in the archive database. Should be called before killing a worker.
    """
    agent = await agent_manager.get_agent(agent_id)
    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")

    # Capture terminal output before archiving
    terminal_output = await tmux_service.capture_pane(agent.tmux_window, lines)

    # Archive the agent
    archive_id = conversation_store.archive_agent(
        agent_id=agent_id,
        agent_name=agent.name,
        agent_type=agent.type,
        terminal_output=terminal_output,
    )

    # Broadcast archive event for frontend to update
    await ws_manager.broadcast("agent_archived", {
        "archive_id": archive_id,
        "agent_id": agent_id,
        "agent_name": agent.name,
        "agent_type": agent.type,
        "archived_at": datetime.now(timezone.utc).isoformat(),
    })

    return {
        "success": True,
        "archive_id": archive_id,
        "agent_id": agent_id,
        "agent_name": agent.name,
    }


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates."""
    client_id = str(uuid.uuid4())
    await ws_manager.connect(websocket, client_id)
    try:
        while True:
            try:
                # Use timeout to prevent indefinitely blocking connections
                data = await asyncio.wait_for(
                    websocket.receive_text(),
                    timeout=WS_RECEIVE_TIMEOUT
                )
                # Handle pong responses from clients
                if data:
                    try:
                        msg = json.loads(data)
                        if msg.get("event") == "pong":
                            logger.debug(f"Received pong from {client_id}")
                    except (json.JSONDecodeError, TypeError):
                        # Not JSON or not a pong, ignore
                        pass
            except asyncio.TimeoutError:
                # Timeout is expected - just continue the loop
                # The ping mechanism will detect dead connections
                continue
    except WebSocketDisconnect:
        logger.debug(f"WebSocket disconnect for {client_id}")
        await ws_manager.disconnect(client_id)
    except Exception as e:
        logger.warning(f"WebSocket error for {client_id}: {e}")
        await ws_manager.disconnect(client_id)


@router.post("/register")
async def register_agent(
    agent_id: str = Body(...),
    agent_type: str = Body("worker"),
    created_by: str = Body("system"),
    display_name: str = Body(None),
    role: str = Body(None),
    project_id: str = Body("cmux"),
    unique_id: str = Body(None),
):
    """Internal endpoint for registering agents from shell scripts.

    Args:
        agent_id: Window-based identifier (name or session:name).
        agent_type: Legacy type field ("worker" or "supervisor").
        created_by: Who created this agent.
        display_name: Human-readable name (defaults to agent_id).
        role: Agent role ("worker", "supervisor", "project-supervisor").
        project_id: Project this agent belongs to.
        unique_id: Pre-assigned agent ID (ag_xxx). Generated if not provided.
    """
    metadata = {
        "type": agent_type,
        "created_at": datetime.now(timezone.utc).isoformat(),
        "created_by": created_by,
        "project_id": project_id,
    }
    if display_name:
        metadata["display_name"] = display_name
    if role:
        metadata["role"] = role
    if unique_id:
        metadata["agent_id"] = unique_id

    entry = agent_registry.register(agent_id, metadata)
    return {"registered": agent_id, "agent_id": entry.get("agent_id")}


@router.delete("/register/{agent_id:path}")
async def unregister_agent(agent_id: str):
    """Internal endpoint for unregistering agents."""
    agent_registry.unregister(agent_id)
    return {"unregistered": agent_id}
