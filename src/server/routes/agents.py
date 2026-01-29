from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect
from datetime import datetime, timezone
import uuid

from ..models.agent import Agent, AgentList, AgentMessage
from ..models.message import Message, MessageType
from ..services.agent_manager import agent_manager
from ..services.tmux_service import tmux_service
from ..services.mailbox import mailbox_service
from ..websocket.manager import ws_manager

router = APIRouter()


@router.get("", response_model=AgentList)
async def list_agents():
    """List all active agents."""
    agents = await agent_manager.list_agents()
    return AgentList(agents=agents, total=len(agents))


@router.get("/{agent_id}", response_model=Agent)
async def get_agent(agent_id: str):
    """Get details of a specific agent."""
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

    await tmux_service.send_input(agent.tmux_window, message.content)
    await ws_manager.broadcast("message_sent", {
        "agent_id": agent_id,
        "content": message.content[:100]
    })
    # Also broadcast the full message for chat UI
    await ws_manager.broadcast("new_message", msg.model_dump(mode="json"))

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


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time updates."""
    client_id = str(uuid.uuid4())
    await ws_manager.connect(websocket, client_id)
    try:
        while True:
            data = await websocket.receive_text()
            # Handle incoming WebSocket messages if needed
    except WebSocketDisconnect:
        await ws_manager.disconnect(client_id)
