import { useActivityStore } from '../stores/activityStore';
import { useAgentStore } from '../stores/agentStore';
import { useMemo } from 'react';

export function useActivity() {
  const { activities, clearActivities } = useActivityStore();
  const { selectedAgentId } = useAgentStore();

  const filteredActivities = useMemo(() => {
    if (!selectedAgentId) return activities;
    return activities.filter((a) => a.agent_id === selectedAgentId);
  }, [activities, selectedAgentId]);

  return {
    activities: filteredActivities,
    allActivities: activities,
    clearActivities,
    isFiltered: !!selectedAgentId,
  };
}
