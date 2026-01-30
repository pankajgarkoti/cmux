import { create } from 'zustand';
import type { Agent } from '../types/agent';
import { useViewerStore } from './viewerStore';

interface AgentState {
  agents: Agent[];
  selectedAgentId: string | null;
  setAgents: (agents: Agent[]) => void;
  updateAgent: (id: string, updates: Partial<Agent>) => void;
  selectAgent: (id: string | null) => void;
}

export const useAgentStore = create<AgentState>((set) => ({
  agents: [],
  selectedAgentId: null,

  setAgents: (agents) => set({ agents }),

  updateAgent: (id, updates) =>
    set((state) => ({
      agents: state.agents.map((agent) =>
        agent.id === id ? { ...agent, ...updates } : agent
      ),
    })),

  selectAgent: (id) => {
    // Clear file selection when switching to an agent
    useViewerStore.getState().clearSelectedFile();
    set({ selectedAgentId: id });
  },
}));
