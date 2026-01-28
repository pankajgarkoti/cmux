import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from '../lib/api';

export function useMessages(limit = 50, offset = 0) {
  return useQuery({
    queryKey: ['messages', limit, offset],
    queryFn: () => api.getMessages(limit, offset),
  });
}

export function useSendMessage() {
  const queryClient = useQueryClient();

  return useMutation({
    mutationFn: ({ agentId, content }: { agentId: string; content: string }) =>
      api.sendMessageToAgent(agentId, content),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['messages'] });
    },
  });
}
