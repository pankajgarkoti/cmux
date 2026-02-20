import { formatDistanceToNow, format } from 'date-fns';
import { useConnectionStore } from '@/stores/connectionStore';
import { useAgentEventStore } from '@/stores/agentEventStore';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import {
  Wifi,
  WifiOff,
  MoreVertical,
  Trash2,
  StopCircle,
  RefreshCw,
  MessagesSquare,
  MessageSquare,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { useAgentStore } from '@/stores/agentStore';
import { useMessages } from '@/hooks/useMessages';
import type { Agent } from '@/types/agent';

interface ChatHeaderProps {
  agentId?: string | null;
  agent?: Agent | null;
  isWorker?: boolean;
  onClearChat?: () => void;
  showAllMessages?: boolean;
  onToggleFilter?: () => void;
}

// Map agent status to display style
function getStatusDisplay(status: string | undefined, isActive: boolean) {
  if (isActive) {
    return {
      label: 'WORKING',
      className: 'bg-yellow-500/20 text-yellow-600 border-yellow-500/30',
    };
  }

  switch (status) {
    case 'IDLE':
      return {
        label: 'IDLE',
        className: 'bg-green-500/20 text-green-600 border-green-500/30',
      };
    case 'IN_PROGRESS':
      return {
        label: 'WORKING',
        className: 'bg-yellow-500/20 text-yellow-600 border-yellow-500/30',
      };
    case 'PENDING':
      return {
        label: 'PENDING',
        className: 'bg-blue-500/20 text-blue-600 border-blue-500/30',
      };
    case 'BLOCKED':
      return {
        label: 'BLOCKED',
        className: 'bg-orange-500/20 text-orange-600 border-orange-500/30',
      };
    case 'FAILED':
      return {
        label: 'FAILED',
        className: 'bg-red-500/20 text-red-600 border-red-500/30',
      };
    case 'COMPLETE':
      return {
        label: 'COMPLETE',
        className: 'bg-green-500/20 text-green-600 border-green-500/30',
      };
    default:
      return {
        label: status || 'UNKNOWN',
        className: 'bg-muted text-muted-foreground',
      };
  }
}

export function ChatHeader({
  agentId,
  agent,
  isWorker,
  onClearChat,
  showAllMessages,
  onToggleFilter,
}: ChatHeaderProps) {
  const { isConnected, isReconnecting } = useConnectionStore();
  const { getActiveSessions, latestEventBySession } = useAgentEventStore();
  const agents = useAgentStore((state) => state.agents);
  const { total: totalMessagesCount } = useMessages();

  const isCommandCenter = !agentId;

  // Check if the current agent is active
  const activeSessions = getActiveSessions();
  const isAgentActive = agentId
    ? activeSessions.some(
        (sessionId) =>
          sessionId.toLowerCase().includes(agentId.toLowerCase()) ||
          latestEventBySession[sessionId]?.agent_id === agentId
      )
    : activeSessions.length > 0;

  const statusDisplay = getStatusDisplay(agent?.status, isAgentActive);

  // Get last activity time
  const lastActivity = agent?.last_activity;
  const lastActivityDate = lastActivity ? new Date(lastActivity) : null;
  const relativeActivity = lastActivityDate
    ? formatDistanceToNow(lastActivityDate, { addSuffix: true })
    : null;
  const preciseActivity = lastActivityDate
    ? format(lastActivityDate, 'MMM d, yyyy h:mm:ss a')
    : null;

  // Command Center stats
  const activeAgentCount = agents.filter(
    (a) => a.status === 'IN_PROGRESS' || a.status === 'IDLE'
  ).length;
  const workerCount = agents.filter((a) => a.type === 'worker').length;
  const totalMessages = totalMessagesCount;

  const displayName = agentId || 'supervisor';
  const title = agentId ? displayName : 'Command Center';
  const subtitle = agentId
    ? `${isWorker ? 'Worker' : 'Supervisor'} agent`
    : 'Multi-agent orchestration dashboard';

  return (
    <div className="px-4 pt-4 pb-2 border-b flex items-center justify-between gap-4">
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <h2 className="text-lg font-semibold truncate">{title}</h2>
          {isCommandCenter ? (
            <>
              <Badge
                variant="outline"
                className="text-[10px] h-5 px-1.5 bg-green-500/20 text-green-600 border-green-500/30"
              >
                {activeAgentCount} active
              </Badge>
              <Badge
                variant="outline"
                className="text-[10px] h-5 px-1.5 bg-blue-500/20 text-blue-600 border-blue-500/30"
              >
                {workerCount} workers
              </Badge>
              <Badge
                variant="outline"
                className="text-[10px] h-5 px-1.5 bg-purple-500/20 text-purple-600 border-purple-500/30"
              >
                {totalMessages} msgs
              </Badge>
            </>
          ) : (
            <Badge
              variant="outline"
              className={cn('text-[10px] h-5 px-1.5', statusDisplay.className)}
            >
              {statusDisplay.label}
            </Badge>
          )}
        </div>
        <div className="flex items-center gap-2 text-xs text-muted-foreground">
          <span>{subtitle}</span>
          {lastActivityDate && (
            <>
              <span className="text-muted-foreground/50">|</span>
              <Tooltip>
                <TooltipTrigger asChild>
                  <span className="cursor-default">
                    Active {relativeActivity}
                  </span>
                </TooltipTrigger>
                <TooltipContent side="bottom" className="text-xs">
                  {preciseActivity}
                </TooltipContent>
              </Tooltip>
            </>
          )}
        </div>
      </div>

      {/* Right side - connection status and actions */}
      <div className="flex items-center gap-2">
        {/* Message filter toggle - only show when viewing a specific agent */}
        {agentId && onToggleFilter && (
          <Tooltip>
            <TooltipTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                className={cn(
                  'h-8 w-8',
                  showAllMessages && 'bg-accent'
                )}
                onClick={onToggleFilter}
              >
                {showAllMessages ? (
                  <MessagesSquare className="h-4 w-4" />
                ) : (
                  <MessageSquare className="h-4 w-4" />
                )}
              </Button>
            </TooltipTrigger>
            <TooltipContent side="bottom" className="text-xs">
              {showAllMessages ? 'Showing all messages' : 'Showing user messages only'}
            </TooltipContent>
          </Tooltip>
        )}

        {/* Connection indicator */}
        <Tooltip>
          <TooltipTrigger asChild>
            <div
              className={cn(
                'flex items-center gap-1.5 px-2 py-1 rounded-md text-xs',
                isConnected
                  ? 'bg-green-500/10 text-green-600'
                  : isReconnecting
                    ? 'bg-yellow-500/10 text-yellow-600'
                    : 'bg-red-500/10 text-red-600'
              )}
            >
              {isConnected ? (
                <Wifi className="h-3 w-3" />
              ) : isReconnecting ? (
                <RefreshCw className="h-3 w-3 animate-spin" />
              ) : (
                <WifiOff className="h-3 w-3" />
              )}
              <span className="hidden sm:inline">
                {isConnected
                  ? 'Connected'
                  : isReconnecting
                    ? 'Reconnecting'
                    : 'Disconnected'}
              </span>
            </div>
          </TooltipTrigger>
          <TooltipContent side="bottom" className="text-xs">
            WebSocket {isConnected ? 'connected' : 'disconnected'}
          </TooltipContent>
        </Tooltip>

        {/* Actions menu */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button variant="ghost" size="icon" className="h-8 w-8">
              <MoreVertical className="h-4 w-4" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            {onClearChat && (
              <DropdownMenuItem onClick={onClearChat}>
                <Trash2 className="h-4 w-4 mr-2" />
                Clear chat
              </DropdownMenuItem>
            )}
            <DropdownMenuItem
              disabled
              className="text-muted-foreground"
            >
              <StopCircle className="h-4 w-4 mr-2" />
              Interrupt agent
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
    </div>
  );
}
