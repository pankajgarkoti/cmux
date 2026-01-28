import { useMutation } from '@tanstack/react-query';
import { useAgentStore } from '@/stores/agentStore';
import { api } from '@/lib/api';
import { Card, CardContent, CardHeader, CardTitle } from '../ui/card';
import { Badge } from '../ui/badge';
import { Button } from '../ui/button';
import { Separator } from '../ui/separator';
import type { AgentStatus } from '@/types/agent';

const statusLabels: Record<AgentStatus, { label: string; color: string }> = {
  IDLE: { label: 'Idle', color: 'bg-gray-500' },
  PENDING: { label: 'Pending', color: 'bg-yellow-500' },
  IN_PROGRESS: { label: 'In Progress', color: 'bg-blue-500' },
  BLOCKED: { label: 'Blocked', color: 'bg-red-500' },
  TESTING: { label: 'Testing', color: 'bg-purple-500' },
  COMPLETE: { label: 'Complete', color: 'bg-green-500' },
  FAILED: { label: 'Failed', color: 'bg-red-700' },
};

export function AgentDetail() {
  const { agents, selectedAgentId } = useAgentStore();
  const agent = agents.find((a) => a.id === selectedAgentId);

  const interruptMutation = useMutation({
    mutationFn: () => api.interruptAgent(selectedAgentId!),
  });

  const compactMutation = useMutation({
    mutationFn: () => api.compactAgent(selectedAgentId!),
  });

  if (!agent) {
    return (
      <div className="h-full flex items-center justify-center text-muted-foreground">
        Select an agent to view details
      </div>
    );
  }

  const statusInfo = statusLabels[agent.status];

  return (
    <div className="h-full p-4 space-y-4">
      <Card>
        <CardHeader>
          <CardTitle className="flex items-center justify-between">
            <span>{agent.name}</span>
            <Badge variant={agent.type === 'supervisor' ? 'default' : 'secondary'}>
              {agent.type}
            </Badge>
          </CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="flex items-center gap-2">
            <div className={`w-3 h-3 rounded-full ${statusInfo.color}`} />
            <span className="font-medium">{statusInfo.label}</span>
          </div>

          {agent.current_task && (
            <>
              <Separator />
              <div>
                <p className="text-sm text-muted-foreground">Current Task</p>
                <p className="mt-1">{agent.current_task}</p>
              </div>
            </>
          )}

          <Separator />

          <div className="grid grid-cols-2 gap-2">
            <div>
              <p className="text-sm text-muted-foreground">Window</p>
              <p className="font-mono text-sm">{agent.tmux_window}</p>
            </div>
            <div>
              <p className="text-sm text-muted-foreground">Created</p>
              <p className="text-sm">
                {new Date(agent.created_at).toLocaleDateString()}
              </p>
            </div>
          </div>

          <Separator />

          <div className="flex gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => interruptMutation.mutate()}
              disabled={interruptMutation.isPending}
            >
              Interrupt
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => compactMutation.mutate()}
              disabled={compactMutation.isPending}
            >
              Compact
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
