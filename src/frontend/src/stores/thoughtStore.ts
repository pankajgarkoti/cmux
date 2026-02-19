import { create } from 'zustand';

export interface Thought {
  id: string;
  agent_name: string;
  thought_type: 'reasoning' | 'tool_result';
  content?: string | null;
  tool_name?: string | null;
  tool_input?: string | null;
  tool_response?: string | null;
  timestamp: string;
}

const MAX_THOUGHTS = 50;

interface ThoughtState {
  thoughts: Thought[];
  addThought: (thought: Thought) => void;
  clear: () => void;
}

export const useThoughtStore = create<ThoughtState>((set) => ({
  thoughts: [],

  addThought: (thought) =>
    set((state) => ({
      thoughts: [...state.thoughts, thought].slice(-MAX_THOUGHTS),
    })),

  clear: () => set({ thoughts: [] }),
}));
