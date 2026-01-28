from typing import List, Optional

from ..models.agent import Agent, AgentType, AgentStatus
from .tmux_service import tmux_service


class AgentManager:
    def __init__(self):
        self._agents: dict[str, Agent] = {}

    async def list_agents(self) -> List[Agent]:
        """List all active agents based on tmux windows."""
        windows = await tmux_service.list_windows()
        agents = []

        for window in windows:
            agent_type = AgentType.SUPERVISOR if window == "supervisor" else AgentType.WORKER
            agent = Agent(
                id=window,
                name=window,
                type=agent_type,
                tmux_window=window,
                status=AgentStatus.IDLE
            )
            agents.append(agent)
            self._agents[window] = agent

        return agents

    async def get_agent(self, agent_id: str) -> Optional[Agent]:
        """Get a specific agent by ID."""
        if agent_id not in self._agents:
            await self.list_agents()
        return self._agents.get(agent_id)

    async def create_worker(self, name: str) -> Agent:
        """Create a new worker agent."""
        await tmux_service.create_window(name)
        agent = Agent(
            id=name,
            name=name,
            type=AgentType.WORKER,
            tmux_window=name,
            status=AgentStatus.PENDING
        )
        self._agents[name] = agent
        return agent

    async def remove_agent(self, agent_id: str) -> bool:
        """Remove a worker agent."""
        if agent_id == "supervisor":
            return False  # Cannot remove supervisor

        success = await tmux_service.kill_window(agent_id)
        if success and agent_id in self._agents:
            del self._agents[agent_id]
        return success


agent_manager = AgentManager()
