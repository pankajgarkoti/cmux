import { create } from 'zustand';
import type { AgentEvent } from '../types/agent_event';

const MAX_EVENTS_PER_SESSION = 100;

interface AgentEventState {
  // Events indexed by session_id
  eventsBySession: Record<string, AgentEvent[]>;

  // Add a new event
  addEvent: (event: AgentEvent) => void;

  // Get events for a session
  getEventsForSession: (sessionId: string) => AgentEvent[];

  // Clear events for a session
  clearSession: (sessionId: string) => void;

  // Clear all events
  clearAll: () => void;
}

export const useAgentEventStore = create<AgentEventState>((set, get) => ({
  eventsBySession: {},

  addEvent: (event) =>
    set((state) => {
      const sessionId = event.session_id;
      const existing = state.eventsBySession[sessionId] || [];

      // Add new event and limit size
      const updated = [event, ...existing].slice(0, MAX_EVENTS_PER_SESSION);

      return {
        eventsBySession: {
          ...state.eventsBySession,
          [sessionId]: updated,
        },
      };
    }),

  getEventsForSession: (sessionId) => {
    return get().eventsBySession[sessionId] || [];
  },

  clearSession: (sessionId) =>
    set((state) => {
      const { [sessionId]: _, ...rest } = state.eventsBySession;
      return { eventsBySession: rest };
    }),

  clearAll: () => set({ eventsBySession: {} }),
}));
