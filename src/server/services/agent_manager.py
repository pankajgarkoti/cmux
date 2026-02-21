from typing import List, Optional
from datetime import datetime, timezone

from ..config import settings
from ..models.agent import Agent, AgentType, AgentRole, AgentStatus
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

    def _enrich_from_registry(self, agent: Agent) -> Agent:
        """Populate agent_id, display_name, role, project_id from the registry."""
        meta = agent_registry.get_agent_metadata(agent.id)
        if meta:
            agent.agent_id = meta.get("agent_id")
            agent.display_name = meta.get("display_name", agent.name)
            role_str = meta.get("role", "worker")
            try:
                agent.role = AgentRole(role_str)
            except ValueError:
                agent.role = AgentRole.WORKER
            # Override type from registry — the registry is the source of truth,
            # not the window name pattern in _is_supervisor()
            if agent.role in (AgentRole.SUPERVISOR, AgentRole.PROJECT_SUPERVISOR):
                agent.type = AgentType.SUPERVISOR
            agent.project_id = meta.get("project_id", "cmux")
            agent.permanent = meta.get('permanent', False)
            agent.role_context = meta.get('role_context')
            agent.reset_count = meta.get('reset_count', 0)
            agent.tasks_since_reset = meta.get('tasks_since_reset', 0)
        else:
            agent.display_name = agent.name
        return agent

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
                agent = self._enrich_from_registry(agent)
                agents.append(agent)
                self._agents[agent_id] = agent

        # Clean up stale registry entries
        all_windows = {a.id for a in agents}
        agent_registry.cleanup_stale(all_windows)

        return agents

    async def get_agent(self, identifier: str) -> Optional[Agent]:
        """Get a specific agent by window-based ID or agent_id (ag_xxx).

        Identifiers can be:
        - "ag_xxxxxxxx" — unique agent ID (tried first)
        - "window_name" for main session (e.g., "supervisor", "worker-1")
        - "session:window_name" for other sessions (e.g., "cmux-feature:supervisor-feature")
        """
        # Try agent_id lookup first (ag_xxx format)
        if identifier.startswith("ag_"):
            agent = self._find_by_agent_id(identifier)
            if agent:
                return agent
            # Not in cache — refresh and try again
            await self.list_agents()
            return self._find_by_agent_id(identifier)

        # Fall back to window-based ID lookup
        if identifier not in self._agents:
            await self.list_agents()
        return self._agents.get(identifier)

    def _find_by_agent_id(self, agent_id: str) -> Optional[Agent]:
        """Find a cached agent by its agent_id (ag_xxx)."""
        for agent in self._agents.values():
            if agent.agent_id == agent_id:
                return agent
        return None

    def resolve_to_window_id(self, identifier: str) -> str:
        """Resolve an identifier (ag_xxx or name) to a window-based ID.

        Used internally to bridge agent_id lookups to window-based operations.
        Falls back to the identifier itself if no match found.
        """
        if identifier.startswith("ag_"):
            result = agent_registry.find_by_agent_id(identifier)
            if result:
                return result[0]  # the registry key (window-based ID)
        return identifier

    def parse_agent_id(self, identifier: str) -> tuple[str, str]:
        """Parse an identifier into (session, window) tuple.

        Supports both ag_xxx IDs and window-based IDs.
        """
        # Resolve ag_xxx to window-based ID first
        window_id = self.resolve_to_window_id(identifier)

        if ":" in window_id:
            session, window = window_id.split(":", 1)
            return session, window
        else:
            return settings.main_session, window_id

    async def create_worker(self, name: str, session: Optional[str] = None) -> Agent:
        """Create a new worker agent in a session."""
        session = session or settings.main_session
        await tmux_service.create_window(name, session)

        window_id = f"{session}:{name}" if session != settings.main_session else name

        # Register in persistent registry (generates agent_id)
        entry = agent_registry.register(window_id, {
            "type": "worker",
            "created_at": datetime.now(timezone.utc).isoformat(),
            "session": session,
            "window": name,
            "display_name": name,
            "role": "worker",
        })

        agent = Agent(
            id=window_id,
            agent_id=entry.get("agent_id"),
            name=name,
            display_name=name,
            type=AgentType.WORKER,
            role=AgentRole.WORKER,
            tmux_window=name,
            session=session,
            status=AgentStatus.PENDING,
            project_id=entry.get("project_id", "cmux"),
        )
        self._agents[window_id] = agent

        return agent

    async def remove_agent(self, identifier: str) -> bool:
        """Remove a worker agent.

        Cannot remove supervisors or the main supervisor.
        Accepts both ag_xxx IDs and window-based IDs.
        """
        agent = await self.get_agent(identifier)
        if not agent:
            return False

        # Cannot remove supervisors
        if agent.type == AgentType.SUPERVISOR:
            return False

        session, window = self.parse_agent_id(agent.id)
        success = await tmux_service.kill_window(window, session)
        if success:
            if agent.id in self._agents:
                del self._agents[agent.id]
            # Unregister from persistent registry
            agent_registry.unregister(agent.id)
        return success

    async def send_message_to_agent(self, identifier: str, message: str) -> bool:
        """Send a message to an agent via tmux."""
        session, window = self.parse_agent_id(identifier)
        if not await tmux_service.window_exists(window, session):
            return False
        await tmux_service.send_input(window, message, session)
        return True

    async def interrupt_agent(self, identifier: str) -> bool:
        """Send Ctrl+C to an agent."""
        session, window = self.parse_agent_id(identifier)
        if not await tmux_service.window_exists(window, session):
            return False
        await tmux_service.send_interrupt(window, session)
        return True

    async def get_agent_terminal(self, identifier: str, lines: int = 100) -> Optional[str]:
        """Capture terminal output from an agent."""
        session, window = self.parse_agent_id(identifier)
        if not await tmux_service.window_exists(window, session):
            return None
        return await tmux_service.capture_pane(window, lines, session)


agent_manager = AgentManager()
