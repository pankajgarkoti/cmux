import fcntl
import json
import os
import string
import random
from pathlib import Path
from typing import Optional, Set, Dict, Any
from datetime import datetime

REGISTRY_FILE = Path(".cmux/agent_registry.json")

# Well-known agent IDs
SUPERVISOR_PRIME_AGENT_ID = "ag_0000prim"


def generate_agent_id(existing_ids: Set[str] = frozenset()) -> str:
    """Generate a unique agent ID: ag_ + 8 random alphanumeric chars.

    Checks against existing_ids to avoid collisions.
    """
    chars = string.ascii_lowercase + string.digits
    for _ in range(100):  # safety limit
        agent_id = "ag_" + "".join(random.choices(chars, k=8))
        if agent_id not in existing_ids:
            return agent_id
    raise RuntimeError("Failed to generate unique agent ID after 100 attempts")


class AgentRegistry:
    """
    Tracks explicitly registered agents vs random tmux windows.
    Uses file locking for concurrent access safety.

    Registry entries are keyed by their window-based ID (name or session:name)
    and contain an `agent_id` field (ag_xxx) for the unique agent identifier.
    """

    def __init__(self):
        self._agents: Dict[str, Dict[str, Any]] = {}
        self._last_mtime: float = 0.0
        self._load()

    def _load(self):
        """Load registry from disk and record file mtime."""
        if REGISTRY_FILE.exists():
            try:
                self._last_mtime = REGISTRY_FILE.stat().st_mtime
                with open(REGISTRY_FILE, 'r') as f:
                    fcntl.flock(f.fileno(), fcntl.LOCK_SH)
                    self._agents = json.load(f)
                    fcntl.flock(f.fileno(), fcntl.LOCK_UN)
            except (json.JSONDecodeError, IOError):
                self._agents = {}

    def _reload_if_changed(self):
        """Reload registry from disk if the file has been modified externally."""
        if REGISTRY_FILE.exists():
            try:
                current_mtime = REGISTRY_FILE.stat().st_mtime
                if current_mtime != self._last_mtime:
                    self._load()
            except OSError:
                pass

    def _save(self):
        """Save registry to disk with exclusive lock."""
        REGISTRY_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(REGISTRY_FILE, 'w') as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_EX)
            json.dump(self._agents, f, indent=2)
            f.flush()
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)
        self._last_mtime = REGISTRY_FILE.stat().st_mtime

    def _get_all_agent_ids(self) -> Set[str]:
        """Get all agent_id values from the registry."""
        return {
            entry.get("agent_id")
            for entry in self._agents.values()
            if entry.get("agent_id")
        }

    def _migrate_entry(self, key: str, entry: Dict[str, Any]) -> Dict[str, Any]:
        """Add missing fields to a legacy registry entry."""
        changed = False

        if "agent_id" not in entry:
            if key == "supervisor":
                entry["agent_id"] = SUPERVISOR_PRIME_AGENT_ID
            else:
                entry["agent_id"] = generate_agent_id(self._get_all_agent_ids())
            changed = True

        if "display_name" not in entry:
            entry["display_name"] = entry.get("window", key)
            changed = True

        if "role" not in entry:
            agent_type = entry.get("type", "worker")
            if agent_type == "supervisor":
                entry["role"] = "supervisor"
            else:
                entry["role"] = "worker"
            changed = True

        if "project_id" not in entry:
            entry["project_id"] = "cmux"
            changed = True

        return entry

    def register(self, key: str, metadata: Optional[Dict[str, Any]] = None):
        """Register an agent when it's created.

        Args:
            key: The window-based identifier (name or session:name).
            metadata: Additional metadata. Can include:
                - agent_id: Pre-assigned agent ID (ag_xxx). Generated if not provided.
                - display_name: Human-readable name. Defaults to key.
                - role: "worker" | "supervisor" | "project-supervisor". Defaults to "worker".
                - project_id: Project this agent belongs to. Defaults to "cmux".
                - type: Legacy type field ("worker" or "supervisor").
                - created_at: ISO timestamp.
                - created_by: Who created this agent.
        """
        metadata = metadata or {}

        # Generate agent_id if not provided
        if "agent_id" not in metadata:
            if key == "supervisor" or metadata.get("type") == "supervisor":
                metadata["agent_id"] = SUPERVISOR_PRIME_AGENT_ID
            else:
                metadata["agent_id"] = generate_agent_id(self._get_all_agent_ids())

        entry = {
            "registered_at": metadata.get("created_at", datetime.now().isoformat()),
            "type": metadata.get("type", "worker"),
            "created_by": metadata.get("created_by", "system"),
            "agent_id": metadata["agent_id"],
            "display_name": metadata.get("display_name", metadata.get("window", key)),
            "role": metadata.get("role", "supervisor" if metadata.get("type") == "supervisor" else "worker"),
            "project_id": metadata.get("project_id", "cmux"),
            **metadata,
        }

        self._agents[key] = entry
        self._save()
        return entry

    def unregister(self, key: str) -> bool:
        """Remove agent from registry. Returns True if agent existed."""
        if key in self._agents:
            del self._agents[key]
            self._save()
            return True
        return False

    def is_registered(self, key: str) -> bool:
        """Check if a window-based key is a registered agent."""
        return key in self._agents

    def get_registered_agents(self) -> Set[str]:
        """Get all registered agent keys (window-based IDs)."""
        return set(self._agents.keys())

    def get_agent_metadata(self, key: str) -> Optional[Dict[str, Any]]:
        """Get metadata for a registered agent by window-based key."""
        self._reload_if_changed()
        entry = self._agents.get(key)
        if entry:
            return self._migrate_entry(key, entry)
        return None

    def find_by_agent_id(self, agent_id: str) -> Optional[tuple[str, Dict[str, Any]]]:
        """Find a registry entry by its agent_id (ag_xxx).

        Returns (key, metadata) tuple or None.
        """
        self._reload_if_changed()
        for key, entry in self._agents.items():
            entry = self._migrate_entry(key, entry)
            if entry.get("agent_id") == agent_id:
                return (key, entry)
        return None

    def find_by_display_name(self, display_name: str) -> Optional[tuple[str, Dict[str, Any]]]:
        """Find a registry entry by display_name.

        Returns (key, metadata) tuple or None.
        """
        self._reload_if_changed()
        for key, entry in self._agents.items():
            entry = self._migrate_entry(key, entry)
            if entry.get("display_name") == display_name:
                return (key, entry)
        return None

    def get_all_entries(self) -> Dict[str, Dict[str, Any]]:
        """Get all registry entries, migrating any legacy entries."""
        migrated = False
        for key in list(self._agents.keys()):
            old = dict(self._agents[key])
            self._agents[key] = self._migrate_entry(key, self._agents[key])
            if self._agents[key] != old:
                migrated = True

        if migrated:
            self._save()

        return dict(self._agents)

    def cleanup_stale(self, existing_windows: Set[str]):
        """Remove registry entries for windows that no longer exist.

        Permanent workers are never cleaned up — they persist across sessions.
        """
        stale = set(self._agents.keys()) - existing_windows
        if stale:
            for key in list(stale):
                if self._agents.get(key, {}).get('permanent', False):
                    stale.discard(key)
                    continue
                del self._agents[key]
            self._save()
        return stale


agent_registry = AgentRegistry()
