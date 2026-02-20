import { useState } from 'react';
import { useTasks } from '@/hooks/useTasks';
import { useAgentStore } from '@/stores/agentStore';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Badge } from '@/components/ui/badge';
import { Collapsible, CollapsibleTrigger, CollapsibleContent } from '@/components/ui/collapsible';
import { ChevronRight, ListTodo, ExternalLink } from 'lucide-react';
import { cn } from '@/lib/utils';
import type { Task } from '@/types/task';

const STATUS_STYLES: Record<string, string> = {
  pending: 'bg-muted text-muted-foreground',
  assigned: 'bg-yellow-500/15 text-yellow-600 border-yellow-500/30',
  'in-progress': 'bg-blue-500/15 text-blue-600 border-blue-500/30',
  done: 'bg-green-500/15 text-green-600 border-green-500/30',
  blocked: 'bg-red-500/15 text-red-600 border-red-500/30',
};

function StatusBadge({ status }: { status: string }) {
  return (
    <Badge variant="outline" className={cn('text-[10px] px-1.5 py-0 h-4 font-medium', STATUS_STYLES[status])}>
      {status}
    </Badge>
  );
}

function TaskNode({ task, depth = 0 }: { task: Task; depth?: number }) {
  const [open, setOpen] = useState(true);
  const hasChildren = task.children && task.children.length > 0;

  return (
    <div>
      <Collapsible open={open} onOpenChange={setOpen}>
        <div
          className="flex items-start gap-1.5 py-1 px-2 rounded hover:bg-muted/50 group"
          style={{ paddingLeft: `${depth * 16 + 8}px` }}
        >
          {hasChildren ? (
            <CollapsibleTrigger asChild>
              <button className="mt-0.5 p-0 h-4 w-4 shrink-0 text-muted-foreground hover:text-foreground">
                <ChevronRight className={cn('h-3 w-3 transition-transform', open && 'rotate-90')} />
              </button>
            </CollapsibleTrigger>
          ) : (
            <span className="w-4 shrink-0" />
          )}

          <div className="flex-1 min-w-0 space-y-0.5">
            <div className="flex items-center gap-1.5">
              <StatusBadge status={task.status} />
              <span className="text-xs font-medium truncate">{task.title}</span>
            </div>

            <div className="flex items-center gap-2 flex-wrap">
              {task.assigned_to && (
                <span className="text-[10px] text-muted-foreground">
                  @{task.assigned_to}
                </span>
              )}
              {task.project && depth === 0 && (
                <span className="text-[10px] text-muted-foreground/70">
                  [{task.project}]
                </span>
              )}
              {task.resources.length > 0 && task.resources.map((url, i) => (
                <a
                  key={i}
                  href={url}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-[10px] text-blue-500 hover:underline inline-flex items-center gap-0.5"
                >
                  <ExternalLink className="h-2.5 w-2.5" />
                  link
                </a>
              ))}
            </div>
          </div>
        </div>

        {hasChildren && (
          <CollapsibleContent>
            {task.children!.map((child) => (
              <TaskNode key={child.id} task={child} depth={depth + 1} />
            ))}
          </CollapsibleContent>
        )}
      </Collapsible>
    </div>
  );
}

export function TasksPanel() {
  const { selectedAgentId, agents } = useAgentStore();

  // Determine project filter from selected agent
  const selectedAgent = selectedAgentId ? agents.find((a) => a.id === selectedAgentId) : null;
  const projectFilter = selectedAgent?.project_id || undefined;

  const { data, isLoading, error } = useTasks(projectFilter);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-8">
        <span className="text-xs text-muted-foreground">Loading tasks...</span>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center justify-center py-8">
        <span className="text-xs text-muted-foreground">No tasks yet</span>
      </div>
    );
  }

  const tasks = data?.tasks || [];

  if (tasks.length === 0) {
    return (
      <div className="text-center py-12">
        <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
          <ListTodo className="h-6 w-6 text-muted-foreground" />
        </div>
        <p className="text-sm text-muted-foreground">
          {projectFilter ? 'No tasks for this project' : 'No tasks yet. Tasks will appear as agents create them.'}
        </p>
      </div>
    );
  }

  return (
    <ScrollArea className="flex-1 h-full">
      <div className="p-2 space-y-0.5">
        {tasks.map((task) => (
          <TaskNode key={task.id} task={task} />
        ))}
      </div>
      <div className="px-3 pb-2">
        <span className="text-[10px] text-muted-foreground">
          {data?.total || 0} task{(data?.total || 0) !== 1 ? 's' : ''}
          {projectFilter ? ` in ${projectFilter}` : ''}
        </span>
      </div>
    </ScrollArea>
  );
}
