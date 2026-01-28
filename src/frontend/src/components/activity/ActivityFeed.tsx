import { useActivity } from '@/hooks/useActivity';
import { useAgentStore } from '@/stores/agentStore';
import { ActivityItem } from './ActivityItem';
import { ScrollArea } from '../ui/scroll-area';
import { Badge } from '../ui/badge';

export function ActivityFeed() {
  const { activities, isFiltered } = useActivity();
  const { selectedAgentId, selectAgent } = useAgentStore();

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <div className="p-4 border-b flex items-center justify-between">
        <h2 className="font-semibold text-lg">Activity</h2>
        {isFiltered && selectedAgentId && (
          <Badge
            variant="outline"
            className="cursor-pointer"
            onClick={() => selectAgent(null)}
          >
            Filtering: {selectedAgentId} ✕
          </Badge>
        )}
      </div>

      <ScrollArea className="flex-1">
        <div className="p-4 space-y-3">
          {activities.length === 0 ? (
            <p className="text-center text-muted-foreground py-8">
              No activity yet
            </p>
          ) : (
            activities.map((activity) => (
              <ActivityItem key={activity.id} activity={activity} />
            ))
          )}
        </div>
      </ScrollArea>
    </div>
  );
}
