from typing import List, Optional
from datetime import datetime, timezone

from ..config import settings
from ..models.agent import Agent, AgentType, AgentStatus
from .tmux_service import tmux_service
from .agent_registry import agent_registry


class AgentManager:
    def __init__(self):
        self._agents: dict[str, Agent] = {}

    def _is_supervisor(self, window: str, session: str) -> bool:
        """Determine if a window is a supervisor based on naming convention."""
        # Main session supervisor is just "supervisor"
        if session == settings.main_session and window == "supervisor":
            return True
        # Spawned session supervisors start with "supervisor-"
        return window.startswith("supervisor-")

    async def list_agents(self, session: Optional[str] = None) -> List[Agent]:
        """List all active agents based on tmux windows.

        Args:
            session: If provided, only list agents from this session.
                     If None, list agents from all cmux sessions.
        """
        agents = []

        # Get list of sessions to query
        if session:
            sessions = [session]
        else:
            sessions = await tmux_service.list_sessions()

        for sess in sessions:
            windows = await tmux_service.list_windows(sess)

            for window in windows:
                # Filter out system windows (like "monitor")
                if window in settings.system_windows:
                    continue

                agent_type = AgentType.SUPERVISOR if self._is_supervisor(window, sess) else AgentType.WORKER
                agent_id = f"{sess}:{window}" if sess != settings.main_session else window

                agent = Agent(
                    id=agent_id,
                    name=window,
                    type=agent_type,
                    tmux_window=window,
                    session=sess,
                    status=AgentStatus.IDLE
                )
                agents.append(agent)
                self._agents[agent_id] = agent

        # Clean up stale registry entries
        all_windows = {a.id for a in agents}
        agent_registry.cleanup_stale(all_windows)

        return agents

    async def get_agent(self, agent_id: str) -> Optional[Agent]:
        """Get a specific agent by ID.

        Agent IDs can be:
        - "window_name" for main session (e.g., "supervisor", "worker-1")
        - "session:window_name" for other sessions (e.g., "cmux-feature:supervisor-feature")
        """
        if agent_id not in self._agents:
            await self.list_agents()
        return self._agents.get(agent_id)

    def parse_agent_id(self, agent_id: str) -> tuple[str, str]:
        """Parse an agent ID into (session, window) tuple."""
        if ":" in agent_id:
            session, window = agent_id.split(":", 1)
            return session, window
        else:
            return settings.main_session, agent_id

    async def create_worker(self, name: str, session: Optional[str] = None) -> Agent:
        """Create a new worker agent in a session."""
        session = session or settings.main_session
        await tmux_service.create_window(name, session)

        agent_id = f"{session}:{name}" if session != settings.main_session else name
        agent = Agent(
            id=agent_id,
            name=name,
            type=AgentType.WORKER,
            tmux_window=name,
            session=session,
            status=AgentStatus.PENDING
        )
        self._agents[agent_id] = agent

        # Register in persistent registry
        agent_registry.register(agent_id, {
            "type": "worker",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "session": session,
            "window": name
        })

        return agent

    async def remove_agent(self, agent_id: str) -> bool:
        """Remove a worker agent.

        Cannot remove supervisors or the main supervisor.
        """
        agent = await self.get_agent(agent_id)
        if not agent:
            return False

        # Cannot remove supervisors
        if agent.type == AgentType.SUPERVISOR:
            return False

        session, window = self.parse_agent_id(agent_id)
        success = await tmux_service.kill_window(window, session)
        if success:
            if agent_id in self._agents:
                del self._agents[agent_id]
            # Unregister from persistent registry
            agent_registry.unregister(agent_id)
        return success

    async def send_message_to_agent(self, agent_id: str, message: str) -> bool:
        """Send a message to an agent via tmux."""
        session, window = self.parse_agent_id(agent_id)
        if not await tmux_service.window_exists(window, session):
            return False
        await tmux_service.send_input(window, message, session)
        return True

    async def interrupt_agent(self, agent_id: str) -> bool:
        """Send Ctrl+C to an agent."""
        session, window = self.parse_agent_id(agent_id)
        if not await tmux_service.window_exists(window, session):
            return False
        await tmux_service.send_interrupt(window, session)
        return True

    async def get_agent_terminal(self, agent_id: str, lines: int = 100) -> Optional[str]:
        """Capture terminal output from an agent."""
        session, window = self.parse_agent_id(agent_id)
        if not await tmux_service.window_exists(window, session):
            return None
        return await tmux_service.capture_pane(window, lines, session)


agent_manager = AgentManager()
