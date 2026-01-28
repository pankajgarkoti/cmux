import { create } from 'zustand';
import type { Activity } from '../types/activity';
import { MAX_ACTIVITIES } from '../lib/constants';

interface ActivityState {
  activities: Activity[];
  addActivity: (activity: Activity) => void;
  clearActivities: () => void;
  getActivitiesByAgent: (agentId: string) => Activity[];
}

export const useActivityStore = create<ActivityState>((set, get) => ({
  activities: [],

  addActivity: (activity) =>
    set((state) => ({
      activities: [activity, ...state.activities].slice(0, MAX_ACTIVITIES),
    })),

  clearActivities: () => set({ activities: [] }),

  getActivitiesByAgent: (agentId) =>
    get().activities.filter((a) => a.agent_id === agentId),
}));
