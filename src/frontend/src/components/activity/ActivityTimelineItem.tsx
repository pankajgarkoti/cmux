import { useState } from 'react';
import { cn } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible';
import {
  Terminal,
  MessageSquare,
  ArrowRight,
  AlertCircle,
  Webhook,
  User,
  ChevronRight,
  Mail,
} from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';
import type { Activity, ActivityType } from '@/types/activity';

interface ActivityTimelineItemProps {
  activity: Activity;
  isLast?: boolean;
}

const typeConfig: Record<
  ActivityType,
  { icon: typeof Terminal; color: string; bgColor: string; label: string }
> = {
  tool_call: {
    icon: Terminal,
    color: 'text-blue-500',
    bgColor: 'bg-blue-500/10',
    label: 'Tool Call',
  },
  message_sent: {
    icon: ArrowRight,
    color: 'text-green-500',
    bgColor: 'bg-green-500/10',
    label: 'Sent',
  },
  message_received: {
    icon: MessageSquare,
    color: 'text-purple-500',
    bgColor: 'bg-purple-500/10',
    label: 'Received',
  },
  status_change: {
    icon: AlertCircle,
    color: 'text-yellow-500',
    bgColor: 'bg-yellow-500/10',
    label: 'Status',
  },
  webhook_received: {
    icon: Webhook,
    color: 'text-orange-500',
    bgColor: 'bg-orange-500/10',
    label: 'Webhook',
  },
  user_message: {
    icon: User,
    color: 'text-pink-500',
    bgColor: 'bg-pink-500/10',
    label: 'User',
  },
  mailbox_message: {
    icon: Mail,
    color: 'text-cyan-500',
    bgColor: 'bg-cyan-500/10',
    label: 'Mailbox',
  },
};

export function ActivityTimelineItem({ activity, isLast }: ActivityTimelineItemProps) {
  const [isOpen, setIsOpen] = useState(false);
  const config = typeConfig[activity.type];
  const Icon = config.icon;
  const time = formatDistanceToNow(new Date(activity.timestamp), { addSuffix: true });
  const hasDetails = activity.data && Object.keys(activity.data).length > 0;

  return (
    <div className="relative pl-6">
      {/* Timeline line */}
      {!isLast && (
        <div className="absolute left-[11px] top-6 bottom-0 w-px bg-border" />
      )}

      {/* Timeline dot */}
      <div
        className={cn(
          'absolute left-0 top-1 h-6 w-6 rounded-full flex items-center justify-center',
          config.bgColor
        )}
      >
        <Icon className={cn('h-3 w-3', config.color)} />
      </div>

      {/* Content */}
      <Collapsible open={isOpen} onOpenChange={setIsOpen}>
        <CollapsibleTrigger asChild disabled={!hasDetails}>
          <button
            className={cn(
              'w-full text-left rounded-lg border bg-card p-2.5 transition-colors',
              hasDetails && 'hover:bg-accent cursor-pointer',
              !hasDetails && 'cursor-default'
            )}
          >
            <div className="flex items-start gap-2">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-0.5">
                  <Badge variant="outline" className="text-[10px] h-4 px-1">
                    {activity.agent_id}
                  </Badge>
                  <Badge
                    variant="secondary"
                    className={cn('text-[10px] h-4 px-1', config.color)}
                  >
                    {config.label}
                  </Badge>
                </div>
                <p className="text-xs text-muted-foreground truncate">
                  {getActivitySummary(activity)}
                </p>
              </div>
              <div className="flex items-center gap-1 flex-shrink-0">
                <span className="text-[10px] text-muted-foreground whitespace-nowrap">
                  {time}
                </span>
                {hasDetails && (
                  <ChevronRight
                    className={cn(
                      'h-3 w-3 text-muted-foreground transition-transform',
                      isOpen && 'rotate-90'
                    )}
                  />
                )}
              </div>
            </div>
          </button>
        </CollapsibleTrigger>

        {hasDetails && (
          <CollapsibleContent>
            <div className="mt-1 ml-2 p-2 rounded bg-muted/50 text-xs">
              <pre className="whitespace-pre-wrap text-muted-foreground font-mono overflow-x-auto">
                {JSON.stringify(activity.data, null, 2)}
              </pre>
            </div>
          </CollapsibleContent>
        )}
      </Collapsible>
    </div>
  );
}

function getActivitySummary(activity: Activity): string {
  switch (activity.type) {
    case 'tool_call':
      return activity.data?.tool_name
        ? `Tool: ${activity.data.tool_name}`
        : 'Tool executed';
    case 'user_message':
      return String(activity.data?.content || 'Message sent').slice(0, 100);
    case 'message_sent':
      return String(activity.data?.content || 'Message').slice(0, 100);
    case 'mailbox_message': {
      const from = activity.data?.from_agent || 'unknown';
      const to = activity.data?.to_agent || 'unknown';
      const content = String(activity.data?.content || '').slice(0, 60);
      return `${from} → ${to}: ${content}`;
    }
    case 'webhook_received':
      return `From: ${activity.data?.source || 'external'}`;
    case 'status_change':
      return `Status: ${activity.data?.status || 'changed'}`;
    default:
      return activity.type;
  }
}
