import { useState } from 'react';
import { useActivity } from '@/hooks/useActivity';
import { ScrollArea } from '@/components/ui/scroll-area';
import { ActivityTimelineItem } from './ActivityTimelineItem';
import { ActivityFilters } from './ActivityFilters';
import { PanelHeader } from '@/components/layout/PanelHeader';
import { Activity as ActivityIcon } from 'lucide-react';
import type { ActivityType } from '@/types/activity';

const MAX_DISPLAYED = 50;

export function ActivityTimeline() {
  const { activities } = useActivity();
  const [filters, setFilters] = useState<ActivityType[]>([]);

  // Filter activities
  const filteredActivities =
    filters.length === 0
      ? activities
      : activities.filter((a) => filters.includes(a.type));

  const displayedActivities = filteredActivities.slice(0, MAX_DISPLAYED);

  return (
    <div className="h-full flex flex-col">
      <PanelHeader
        title="Activity"
        subtitle={`${displayedActivities.length} events`}
        actions={
          <ActivityFilters activeFilters={filters} onFiltersChange={setFilters} />
        }
      />

      <ScrollArea className="flex-1">
        <div className="p-3 space-y-2">
          {displayedActivities.length === 0 ? (
            <div className="text-center py-12">
              <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
                <ActivityIcon className="h-6 w-6 text-muted-foreground" />
              </div>
              <p className="text-sm text-muted-foreground">
                {filters.length > 0
                  ? 'No matching activities'
                  : 'No activity yet. Events will appear here as agents work.'}
              </p>
            </div>
          ) : (
            displayedActivities.map((activity, index) => (
              <ActivityTimelineItem
                key={activity.id}
                activity={activity}
                isLast={index === displayedActivities.length - 1}
              />
            ))
          )}
        </div>
      </ScrollArea>
    </div>
  );
}
