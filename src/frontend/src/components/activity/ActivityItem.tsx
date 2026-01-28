import { cn } from '@/lib/utils';
import { Card } from '../ui/card';
import { Badge } from '../ui/badge';
import type { Activity } from '@/types/activity';

interface ActivityItemProps {
  activity: Activity;
}

const typeIcons: Record<Activity['type'], string> = {
  tool_call: '🔧',
  message_sent: '📤',
  message_received: '📥',
  status_change: '🔄',
  webhook_received: '🌐',
  user_message: '👤',
};

const typeColors: Record<Activity['type'], string> = {
  tool_call: 'border-l-blue-500',
  message_sent: 'border-l-green-500',
  message_received: 'border-l-purple-500',
  status_change: 'border-l-yellow-500',
  webhook_received: 'border-l-orange-500',
  user_message: 'border-l-pink-500',
};

export function ActivityItem({ activity }: ActivityItemProps) {
  const time = new Date(activity.timestamp).toLocaleTimeString();

  return (
    <Card
      className={cn(
        'p-3 border-l-4',
        typeColors[activity.type]
      )}
    >
      <div className="flex items-center justify-between mb-2">
        <div className="flex items-center gap-2">
          <span>{typeIcons[activity.type]}</span>
          <Badge variant="outline">{activity.agent_id}</Badge>
        </div>
        <span className="text-xs text-muted-foreground">{time}</span>
      </div>

      <div className="text-sm">
        {renderActivityContent(activity)}
      </div>
    </Card>
  );
}

function renderActivityContent(activity: Activity): React.ReactNode {
  switch (activity.type) {
    case 'tool_call':
      return (
        <pre className="bg-muted p-2 rounded text-xs overflow-x-auto">
          {JSON.stringify(activity.data, null, 2)}
        </pre>
      );

    case 'user_message':
      return (
        <p className="whitespace-pre-wrap">{activity.data.content as string}</p>
      );

    case 'webhook_received':
      return (
        <p>
          Webhook from <strong>{activity.data.source as string}</strong>
        </p>
      );

    case 'status_change':
      return (
        <p>
          Status changed to <Badge>{activity.data.status as string}</Badge>
        </p>
      );

    default:
      return <p>{JSON.stringify(activity.data)}</p>;
  }
}
