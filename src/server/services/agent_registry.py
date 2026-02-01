import fcntl
import json
from pathlib import Path
from typing import Optional, Set, Dict, Any
from datetime import datetime

REGISTRY_FILE = Path(".cmux/agent_registry.json")


class AgentRegistry:
    """
    Tracks explicitly registered agents vs random tmux windows.
    Uses file locking for concurrent access safety.
    """

    def __init__(self):
        self._agents: Dict[str, Dict[str, Any]] = {}
        self._load()

    def _load(self):
        """Load registry from disk."""
        if REGISTRY_FILE.exists():
            try:
                with open(REGISTRY_FILE, 'r') as f:
                    fcntl.flock(f.fileno(), fcntl.LOCK_SH)
                    self._agents = json.load(f)
                    fcntl.flock(f.fileno(), fcntl.LOCK_UN)
            except (json.JSONDecodeError, IOError):
                self._agents = {}

    def _save(self):
        """Save registry to disk with exclusive lock."""
        REGISTRY_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(REGISTRY_FILE, 'w') as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            json.dump(self._agents, f, indent=2)
            f.flush()
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)

    def register(self, agent_id: str, metadata: Optional[Dict[str, Any]] = None):
        """Register an agent when it's created."""
        metadata = metadata or {}
        self._agents[agent_id] = {
            "registered_at": metadata.get("created_at", datetime.now().isoformat()),
            "type": metadata.get("type", "worker"),
            "created_by": metadata.get("created_by", "system"),
            **metadata
        }
        self._save()

    def unregister(self, agent_id: str) -> bool:
        """Remove agent from registry. Returns True if agent existed."""
        if agent_id in self._agents:
            del self._agents[agent_id]
            self._save()
            return True
        return False

    def is_registered(self, agent_id: str) -> bool:
        """Check if a window is a registered agent."""
        return agent_id in self._agents

    def get_registered_agents(self) -> Set[str]:
        """Get all registered agent IDs."""
        return set(self._agents.keys())

    def get_agent_metadata(self, agent_id: str) -> Optional[Dict[str, Any]]:
        """Get metadata for a registered agent."""
        return self._agents.get(agent_id)

    def cleanup_stale(self, existing_windows: Set[str]):
        """Remove registry entries for windows that no longer exist."""
        stale = set(self._agents.keys()) - existing_windows
        if stale:
            for agent_id in stale:
                del self._agents[agent_id]
            self._save()
        return stale


agent_registry = AgentRegistry()
