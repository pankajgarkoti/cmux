import { useState } from 'react';
import { useActivity } from '@/hooks/useActivity';
import { useLayoutStore } from '@/stores/layoutStore';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Button } from '@/components/ui/button';
import { ActivityTimelineItem } from './ActivityTimelineItem';
import { ActivityFilters } from './ActivityFilters';
import { PanelHeader } from '@/components/layout/PanelHeader';
import { Activity as ActivityIcon, PanelRightClose, PanelRightOpen } from 'lucide-react';
import type { ActivityType } from '@/types/activity';

const MAX_DISPLAYED = 50;

export function ActivityTimeline() {
  const { activities } = useActivity();
  const { activityPanelCollapsed, toggleActivityPanel } = useLayoutStore();
  const [filters, setFilters] = useState<ActivityType[]>([]);

  // Filter activities
  const filteredActivities =
    filters.length === 0
      ? activities
      : activities.filter((a) => filters.includes(a.type));

  const displayedActivities = filteredActivities.slice(0, MAX_DISPLAYED);

  // Collapsed state - just show a minimal header with expand button
  if (activityPanelCollapsed) {
    return (
      <div className="h-full flex flex-col items-center py-2">
        <Button
          variant="ghost"
          size="icon"
          className="h-8 w-8"
          onClick={toggleActivityPanel}
          title="Expand activity panel"
        >
          <PanelRightOpen className="h-4 w-4" />
        </Button>
        <div className="flex-1 flex items-center justify-center">
          <span className="text-xs text-muted-foreground writing-mode-vertical transform rotate-180" style={{ writingMode: 'vertical-rl' }}>
            Activity ({displayedActivities.length})
          </span>
        </div>
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col">
      <PanelHeader
        title="Activity"
        subtitle={`${displayedActivities.length} events`}
        actions={
          <div className="flex items-center gap-1">
            <ActivityFilters activeFilters={filters} onFiltersChange={setFilters} />
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6"
              onClick={toggleActivityPanel}
              title="Collapse activity panel"
            >
              <PanelRightClose className="h-3.5 w-3.5" />
            </Button>
          </div>
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
