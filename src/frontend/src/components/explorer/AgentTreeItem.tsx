import { cn } from '@/lib/utils';
import { Bot, Crown } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import type { Agent, AgentStatus } from '@/types/agent';

interface AgentTreeItemProps {
  agent: Agent;
  isSelected: boolean;
  onClick: () => void;
}

const statusColors: Record<AgentStatus, string> = {
  PENDING: 'bg-gray-400',
  IN_PROGRESS: 'bg-blue-500',
  BLOCKED: 'bg-red-500',
  TESTING: 'bg-yellow-500',
  COMPLETE: 'bg-green-500',
  FAILED: 'bg-red-600',
  IDLE: 'bg-gray-300',
};

export function AgentTreeItem({ agent, isSelected, onClick }: AgentTreeItemProps) {
  const isSupervisor = agent.type === 'supervisor';

  return (
    <button
      onClick={onClick}
      className={cn(
        'w-full flex items-center gap-2 px-2 py-1.5 text-sm rounded-md transition-colors text-left',
        'hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
        isSelected && 'bg-sidebar-accent text-sidebar-accent-foreground'
      )}
    >
      {/* Status indicator */}
      <span
        className={cn('w-2 h-2 rounded-full flex-shrink-0', statusColors[agent.status])}
        title={agent.status}
      />

      {/* Icon */}
      {isSupervisor ? (
        <Crown className="h-4 w-4 text-amber-500 flex-shrink-0" />
      ) : (
        <Bot className="h-4 w-4 text-muted-foreground flex-shrink-0" />
      )}

      {/* Name */}
      <span className="truncate flex-1">{agent.name}</span>

      {/* Type badge */}
      <Badge
        variant="outline"
        className={cn(
          'text-[10px] h-4 px-1',
          isSupervisor ? 'border-amber-500/50 text-amber-600' : 'border-muted'
        )}
      >
        {isSupervisor ? 'SUP' : 'WRK'}
      </Badge>
    </button>
  );
}
