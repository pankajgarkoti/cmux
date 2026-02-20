import { useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { api } from '../lib/api';
import { useThoughtStore } from '../stores/thoughtStore';
import type { Thought } from '../stores/thoughtStore';

/**
 * Hook to load historical thoughts on app start
 * and populate the thought store so they persist across page refreshes.
 */
export function useThoughts() {
  const { addThoughts } = useThoughtStore();

  const { data, isLoading, error } = useQuery({
    queryKey: ['thoughts'],
    queryFn: () => api.getThoughts(200),
    staleTime: 60000,
    refetchInterval: 60000,
  });

  // Populate thought store with historical thoughts on load
  useEffect(() => {
    if (data?.thoughts && data.thoughts.length > 0) {
      const thoughts: Thought[] = data.thoughts.map((t) => ({
        id: t.id,
        agent_name: t.agent_name,
        thought_type: t.thought_type as Thought['thought_type'],
        content: t.content,
        tool_name: t.tool_name,
        tool_input: t.tool_input,
        tool_response: t.tool_response,
        timestamp: t.timestamp,
      }));
      addThoughts(thoughts);
    }
  }, [data, addThoughts]);

  return { thoughts: data?.thoughts || [], isLoading, error };
}
