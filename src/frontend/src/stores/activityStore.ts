import { create } from 'zustand';
import type { Activity } from '../types/activity';
import { MAX_ACTIVITIES } from '../lib/constants';

interface ActivityState {
  activities: Activity[];
  addActivity: (activity: Activity) => void;
  addActivities: (activities: Activity[]) => void;
  clearActivities: () => void;
  getActivitiesByAgent: (agentId: string) => Activity[];
}

// Helper to rebuild seenIds from activities array
// This prevents unbounded memory growth
function buildSeenIds(activities: Activity[]): Set<string> {
  return new Set(activities.map((a) => a.id));
}

export const useActivityStore = create<ActivityState>((set, get) => ({
  activities: [],

  addActivity: (activity) =>
    set((state) => {
      // Check against current activities to deduplicate
      const existingIds = buildSeenIds(state.activities);
      if (existingIds.has(activity.id)) {
        return state;
      }
      return {
        activities: [activity, ...state.activities].slice(0, MAX_ACTIVITIES),
      };
    }),

  addActivities: (activities) =>
    set((state) => {
      // Build set from current activities
      const existingIds = buildSeenIds(state.activities);
      const newActivities: Activity[] = [];

      for (const activity of activities) {
        if (!existingIds.has(activity.id)) {
          existingIds.add(activity.id);
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
      };
    }),

  clearActivities: () => set({ activities: [] }),

  getActivitiesByAgent: (agentId) =>
    get().activities.filter((a) => a.agent_id === agentId),
}));
