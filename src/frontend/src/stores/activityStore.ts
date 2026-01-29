import { create } from 'zustand';
import type { Activity } from '../types/activity';
import { MAX_ACTIVITIES } from '../lib/constants';

interface ActivityState {
  activities: Activity[];
  seenIds: Set<string>;
  addActivity: (activity: Activity) => void;
  addActivities: (activities: Activity[]) => void;
  clearActivities: () => void;
  getActivitiesByAgent: (agentId: string) => Activity[];
}

export const useActivityStore = create<ActivityState>((set, get) => ({
  activities: [],
  seenIds: new Set(),

  addActivity: (activity) =>
    set((state) => {
      // Deduplicate by ID
      if (state.seenIds.has(activity.id)) {
        return state;
      }
      const newSeenIds = new Set(state.seenIds);
      newSeenIds.add(activity.id);
      return {
        activities: [activity, ...state.activities].slice(0, MAX_ACTIVITIES),
        seenIds: newSeenIds,
      };
    }),

  addActivities: (activities) =>
    set((state) => {
      const newSeenIds = new Set(state.seenIds);
      const newActivities: Activity[] = [];

      for (const activity of activities) {
        if (!newSeenIds.has(activity.id)) {
          newSeenIds.add(activity.id);
          newActivities.push(activity);
        }
      }

      if (newActivities.length === 0) {
        return state;
      }

      // Sort by timestamp descending and merge
      const merged = [...newActivities, ...state.activities]
        .sort((a, b) => new Date(b.timestamp).getTime() - new Date(a.timestamp).getTime())
        .slice(0, MAX_ACTIVITIES);

      return {
        activities: merged,
        seenIds: newSeenIds,
      };
    }),

  clearActivities: () => set({ activities: [], seenIds: new Set() }),

  getActivitiesByAgent: (agentId) =>
    get().activities.filter((a) => a.agent_id === agentId),
}));
