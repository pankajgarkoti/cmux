import { cn } from '@/lib/utils';
import { Bot, Crown, Loader2, ShieldCheck } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { useAgentEventStore } from '@/stores/agentEventStore';
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
  const isSupervisor = agent.type === 'supervisor' || agent.role === 'project-supervisor';
  const isProjectSupervisor = agent.role === 'project-supervisor';

  // Check if this agent is actively working by matching event agent_id
  // (CMUX_AGENT_NAME set by orchestrator) against agent identifiers
  const { latestEventBySession, isAgentActive } = useAgentEventStore();
  const isWorking = Object.entries(latestEventBySession).some(([sessionId, event]) => {
    const eventAgentId = (event.agent_id || '').toLowerCase();
    const matchesAgent =
      eventAgentId === agent.id.toLowerCase() ||
      eventAgentId === agent.name.toLowerCase() ||
      (agent.display_name && eventAgentId === agent.display_name.toLowerCase());
    return matchesAgent && isAgentActive(sessionId);
  });

  // Use display_name if available, fall back to name
  const displayName = agent.display_name || agent.name;

  // Badge label
  const isPermanent = agent.permanent === true;
  const badgeLabel = isSupervisor
    ? (isProjectSupervisor ? 'P-SUP' : 'SUP')
    : isPermanent ? 'PERM' : 'WRK';

  // Tooltip content: technical name + role type
  const tooltipText = isPermanent
    ? `${agent.name} · Permanent Worker`
    : isSupervisor
      ? `${agent.name} · Supervisor`
      : agent.name;

  const button = (
    <button
      onClick={onClick}
      className={cn(
        'w-full flex items-center gap-2 px-2 py-1.5 text-sm rounded-md transition-colors text-left',
        'hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
        isSelected && 'bg-sidebar-accent text-sidebar-accent-foreground'
      )}
    >
      {/* Status indicator with working animation */}
      <span
        className={cn(
          'w-2 h-2 rounded-full flex-shrink-0',
          statusColors[agent.status],
          isWorking && 'animate-pulse ring-2 ring-green-400/50'
        )}
        title={isWorking ? 'Working...' : agent.status}
      />

      {/* Icon */}
      {isSupervisor ? (
        <Crown className={cn(
          'h-4 w-4 flex-shrink-0',
          isProjectSupervisor ? 'text-purple-500' : 'text-amber-500'
        )} />
      ) : isPermanent ? (
        <ShieldCheck className="h-4 w-4 text-teal-500 flex-shrink-0" />
      ) : (
        <Bot className="h-4 w-4 text-muted-foreground flex-shrink-0" />
      )}

      {/* Name */}
      <span className="truncate flex-1">{displayName}</span>

      {/* Working indicator - animated spinner */}
      {isWorking && (
        <span title="Processing...">
          <Loader2 className="h-3.5 w-3.5 animate-spin text-primary flex-shrink-0" />
        </span>
      )}

      {/* Type badge */}
      <Badge
        variant="outline"
        className={cn(
          'text-[10px] h-4 px-1',
          isProjectSupervisor ? 'border-purple-500/50 text-purple-600' :
          isSupervisor ? 'border-amber-500/50 text-amber-600' :
          isPermanent ? 'border-teal-500/50 text-teal-600' : 'border-muted'
        )}
      >
        {badgeLabel}
      </Badge>
    </button>
  );

  // Show display_name differs from agent.name — tooltip reveals technical identity
  if (agent.display_name && agent.display_name !== agent.name) {
    return (
      <Tooltip>
        <TooltipTrigger asChild>
          {button}
        </TooltipTrigger>
        <TooltipContent side="right" className="text-xs">
          {tooltipText}
        </TooltipContent>
      </Tooltip>
    );
  }

  return button;
}
