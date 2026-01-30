import { useEffect, useState } from 'react';
import { useAgentEventStore } from '@/stores/agentEventStore';
import { cn } from '@/lib/utils';
import { Loader2 } from 'lucide-react';

interface AgentActivityIndicatorProps {
  agentId?: string;
  className?: string;
}

// Map tool names to human-readable descriptions
function getToolDescription(toolName: string): string {
  const toolDescriptions: Record<string, string> = {
    Read: 'Reading files',
    Write: 'Writing files',
    Edit: 'Editing files',
    Bash: 'Running command',
    Glob: 'Searching files',
    Grep: 'Searching code',
    Task: 'Running task',
    WebFetch: 'Fetching web content',
    WebSearch: 'Searching the web',
    AskUserQuestion: 'Waiting for input',
    TodoRead: 'Reading tasks',
    TodoWrite: 'Updating tasks',
  };
  return toolDescriptions[toolName] || `Using ${toolName}`;
}

export function AgentActivityIndicator({
  agentId,
  className,
}: AgentActivityIndicatorProps) {
  const { latestEventBySession, isAgentActive } = useAgentEventStore();
  const [isVisible, setIsVisible] = useState(false);

  // Find active sessions that match the agent
  const activeSessions = Object.entries(latestEventBySession).filter(
    ([sessionId, event]) => {
      // If no agentId specified, show activity for all agents
      if (!agentId) return isAgentActive(sessionId);

      // Check if the session matches the agent (supervisor sessions often contain 'supervisor')
      const matchesAgent =
        sessionId.toLowerCase().includes(agentId.toLowerCase()) ||
        event.agent_id === agentId;
      return matchesAgent && isAgentActive(sessionId);
    }
  );

  const hasActivity = activeSessions.length > 0;
  const latestActiveEvent = hasActivity ? activeSessions[0][1] : null;

  // Animate visibility with a slight delay for smoother UX
  useEffect(() => {
    if (hasActivity) {
      setIsVisible(true);
    } else {
      // Delay hiding to prevent flicker between rapid tool calls
      const timeout = setTimeout(() => setIsVisible(false), 500);
      return () => clearTimeout(timeout);
    }
  }, [hasActivity]);

  if (!isVisible) return null;

  const toolName = latestActiveEvent?.tool_name || 'Working';
  const description = getToolDescription(toolName);

  return (
    <div
      className={cn(
        'flex items-center gap-2 px-4 py-2 text-sm text-muted-foreground',
        'border-t bg-muted/30',
        className
      )}
    >
      <Loader2 className="h-4 w-4 animate-spin text-primary" />
      <span className="font-medium text-foreground/80">{description}</span>
    </div>
  );
}
