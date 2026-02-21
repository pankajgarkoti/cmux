import { useState, useMemo } from 'react';
import { useTasks, useUpdateTask } from '@/hooks/useTasks';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Collapsible, CollapsibleTrigger, CollapsibleContent } from '@/components/ui/collapsible';
import {
  DropdownMenu,
  DropdownMenuTrigger,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuLabel,
} from '@/components/ui/dropdown-menu';
import {
  ListTodo,
  ChevronDown,
  ChevronRight,
  Search,
  ExternalLink,
  User,
  FolderOpen,
  Clock,
  MoreHorizontal,
  Loader2,
  Filter,
  X,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import type { Task, TaskStatus, TaskPriority } from '@/types/task';

// -- Constants --

const STATUS_CONFIGS: Record<string, { label: string; color: string; dot: string }> = {
  pending: { label: 'Pending', color: 'bg-zinc-500/15 text-zinc-500 border-zinc-500/30', dot: 'bg-zinc-400' },
  assigned: { label: 'Assigned', color: 'bg-blue-500/15 text-blue-500 border-blue-500/30', dot: 'bg-blue-400' },
  'in-progress': { label: 'In Progress', color: 'bg-amber-500/15 text-amber-600 border-amber-500/30', dot: 'bg-amber-400' },
  done: { label: 'Done', color: 'bg-emerald-500/15 text-emerald-600 border-emerald-500/30', dot: 'bg-emerald-400' },
  blocked: { label: 'Blocked', color: 'bg-red-500/15 text-red-500 border-red-500/30', dot: 'bg-red-400' },
};

const PRIORITY_CONFIGS: Record<string, { label: string; color: string }> = {
  critical: { label: 'Critical', color: 'bg-red-500/20 text-red-500 border-red-500/30' },
  high: { label: 'High', color: 'bg-orange-500/20 text-orange-500 border-orange-500/30' },
  medium: { label: 'Medium', color: 'bg-blue-500/15 text-blue-500 border-blue-500/30' },
  low: { label: 'Low', color: 'bg-zinc-500/10 text-zinc-400 border-zinc-500/20' },
};

const ALL_STATUSES: TaskStatus[] = ['pending', 'assigned', 'in-progress', 'done', 'blocked'];
const ALL_PRIORITIES: TaskPriority[] = ['critical', 'high', 'medium', 'low'];

// -- Helpers --

function relativeTime(dateStr: string): string {
  if (!dateStr) return '';
  const now = Date.now();
  const then = new Date(dateStr).getTime();
  const diffMs = now - then;
  const diffSec = Math.floor(diffMs / 1000);
  if (diffSec < 60) return 'just now';
  const diffMin = Math.floor(diffSec / 60);
  if (diffMin < 60) return `${diffMin}m ago`;
  const diffHr = Math.floor(diffMin / 60);
  if (diffHr < 24) return `${diffHr}h ago`;
  const diffDay = Math.floor(diffHr / 24);
  if (diffDay < 7) return `${diffDay}d ago`;
  return `${Math.floor(diffDay / 7)}w ago`;
}

function flattenTasks(tasks: Task[]): Task[] {
  const result: Task[] = [];
  for (const task of tasks) {
    result.push(task);
    if (task.children?.length) {
      result.push(...flattenTasks(task.children));
    }
  }
  return result;
}

function countByStatus(tasks: Task[]): Record<string, number> {
  const all = flattenTasks(tasks);
  const counts: Record<string, number> = {};
  for (const t of all) {
    counts[t.status] = (counts[t.status] || 0) + 1;
  }
  return counts;
}

function matchesSearch(task: Task, query: string): boolean {
  if (!query) return true;
  const q = query.toLowerCase();
  return (
    task.title.toLowerCase().includes(q) ||
    task.description?.toLowerCase().includes(q) ||
    task.assigned_to?.toLowerCase().includes(q) ||
    task.project?.toLowerCase().includes(q)
  );
}

function filterTasks(
  tasks: Task[],
  statusFilter: TaskStatus | 'all',
  priorityFilter: TaskPriority | 'all',
  search: string,
): Task[] {
  return tasks
    .map((task) => {
      const filteredChildren = task.children?.length
        ? filterTasks(task.children, statusFilter, priorityFilter, search)
        : [];

      const selfMatches =
        (statusFilter === 'all' || task.status === statusFilter) &&
        (priorityFilter === 'all' || (task.priority || 'medium') === priorityFilter) &&
        matchesSearch(task, search);

      if (selfMatches || filteredChildren.length > 0) {
        return { ...task, children: filteredChildren };
      }
      return null;
    })
    .filter(Boolean) as Task[];
}

// -- Sub-components --

function StatusBadge({ status }: { status: string }) {
  const config = STATUS_CONFIGS[status] || STATUS_CONFIGS.pending;
  return (
    <Badge variant="outline" className={cn('text-[10px] px-1.5 py-0 h-4 font-medium gap-1', config.color)}>
      <span className={cn('w-1.5 h-1.5 rounded-full shrink-0', config.dot)} />
      {config.label}
    </Badge>
  );
}

function PriorityBadge({ priority }: { priority?: string }) {
  if (!priority) return null;
  const config = PRIORITY_CONFIGS[priority] || PRIORITY_CONFIGS.medium;
  return (
    <Badge variant="outline" className={cn('text-[10px] px-1.5 py-0 h-4 font-medium', config.color)}>
      {config.label}
    </Badge>
  );
}

function StatusDropdown({ task }: { task: Task }) {
  const updateTask = useUpdateTask();

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          className="h-5 w-5 opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
          onClick={(e) => e.stopPropagation()}
        >
          <MoreHorizontal className="h-3 w-3" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-36">
        <DropdownMenuLabel className="text-[10px] py-1">Set Status</DropdownMenuLabel>
        <DropdownMenuSeparator />
        {ALL_STATUSES.map((s) => {
          const config = STATUS_CONFIGS[s];
          return (
            <DropdownMenuItem
              key={s}
              className="text-xs gap-2 py-1"
              disabled={task.status === s}
              onClick={(e) => {
                e.stopPropagation();
                updateTask.mutate({ taskId: task.id, update: { status: s } });
              }}
            >
              <span className={cn('w-2 h-2 rounded-full', config.dot)} />
              {config.label}
              {task.status === s && <span className="ml-auto text-[10px] text-muted-foreground">(current)</span>}
            </DropdownMenuItem>
          );
        })}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function TaskCard({ task, depth = 0 }: { task: Task; depth?: number }) {
  const [expanded, setExpanded] = useState(false);
  const [childrenOpen, setChildrenOpen] = useState(true);
  const hasChildren = (task.children?.length ?? 0) > 0;
  const childCount = task.children?.length ?? 0;

  return (
    <div className={cn(depth > 0 && 'ml-4 border-l border-border/50 pl-3')}>
      <div
        className={cn(
          'group rounded-lg border bg-card p-3 cursor-pointer transition-colors',
          'hover:bg-accent/50 hover:border-border',
          expanded && 'bg-accent/30 border-border',
        )}
        onClick={() => setExpanded(!expanded)}
      >
        {/* Top row: status + title + actions */}
        <div className="flex items-start gap-2">
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-1.5 mb-1.5">
              <StatusBadge status={task.status} />
              <PriorityBadge priority={task.priority} />
            </div>
            <h4 className="text-[13px] font-medium leading-snug truncate">{task.title}</h4>
          </div>
          <StatusDropdown task={task} />
        </div>

        {/* Meta row */}
        <div className="flex items-center gap-3 mt-2 flex-wrap">
          {task.assigned_to && (
            <span className="inline-flex items-center gap-0.5 text-[10px] text-muted-foreground">
              <User className="h-2.5 w-2.5" />
              {task.assigned_to}
            </span>
          )}
          {task.project && (
            <span className="inline-flex items-center gap-0.5 text-[10px] text-muted-foreground/70">
              <FolderOpen className="h-2.5 w-2.5" />
              {task.project}
            </span>
          )}
          {task.created_at && (
            <span className="inline-flex items-center gap-0.5 text-[10px] text-muted-foreground/50">
              <Clock className="h-2.5 w-2.5" />
              {relativeTime(task.created_at)}
            </span>
          )}
          {childCount > 0 && (
            <span className="text-[10px] text-muted-foreground/50">
              {childCount} subtask{childCount !== 1 ? 's' : ''}
            </span>
          )}
        </div>

        {/* Expanded details */}
        {expanded && (
          <div className="mt-2.5 pt-2.5 border-t border-border/50 space-y-2">
            {task.description && (
              <p className="text-[11px] text-muted-foreground whitespace-pre-wrap leading-relaxed">
                {task.description}
              </p>
            )}
            {task.resources?.length > 0 && (
              <div className="flex items-center gap-2 flex-wrap">
                {task.resources.map((url, i) => (
                  <a
                    key={i}
                    href={url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-[10px] text-blue-500 hover:underline inline-flex items-center gap-0.5"
                    onClick={(e) => e.stopPropagation()}
                  >
                    <ExternalLink className="h-2.5 w-2.5" />
                    Resource {i + 1}
                  </a>
                ))}
              </div>
            )}
            {task.source && (
              <span className="text-[10px] text-muted-foreground/50">Source: {task.source}</span>
            )}
          </div>
        )}
      </div>

      {/* Children */}
      {hasChildren && (
        <Collapsible open={childrenOpen} onOpenChange={setChildrenOpen}>
          <CollapsibleTrigger asChild>
            <button className="flex items-center gap-1 mt-1 mb-0.5 px-1 text-[10px] text-muted-foreground hover:text-foreground transition-colors">
              <ChevronRight className={cn('h-3 w-3 transition-transform', childrenOpen && 'rotate-90')} />
              {childCount} subtask{childCount !== 1 ? 's' : ''}
            </button>
          </CollapsibleTrigger>
          <CollapsibleContent>
            <div className="space-y-2 mt-1.5">
              {task.children!.map((child) => (
                <TaskCard key={child.id} task={child} depth={depth + 1} />
              ))}
            </div>
          </CollapsibleContent>
        </Collapsible>
      )}
    </div>
  );
}

function StatsSummary({ counts, total }: { counts: Record<string, number>; total: number }) {
  if (total === 0) return null;
  const items = ALL_STATUSES
    .filter((s) => counts[s])
    .map((s) => ({ status: s, count: counts[s], config: STATUS_CONFIGS[s] }));

  return (
    <div className="flex items-center gap-2 px-3 py-2 text-[10px] flex-wrap">
      <span className="text-muted-foreground font-medium">{total} total</span>
      <span className="text-border">|</span>
      {items.map(({ status, count, config }) => (
        <span key={status} className="inline-flex items-center gap-1 text-muted-foreground">
          <span className={cn('w-1.5 h-1.5 rounded-full', config.dot)} />
          {count} {config.label.toLowerCase()}
        </span>
      ))}
    </div>
  );
}

function FilterBar({
  statusFilter,
  onStatusChange,
  priorityFilter,
  onPriorityChange,
  search,
  onSearchChange,
}: {
  statusFilter: TaskStatus | 'all';
  onStatusChange: (s: TaskStatus | 'all') => void;
  priorityFilter: TaskPriority | 'all';
  onPriorityChange: (p: TaskPriority | 'all') => void;
  search: string;
  onSearchChange: (s: string) => void;
}) {
  const hasFilters = statusFilter !== 'all' || priorityFilter !== 'all' || search.length > 0;

  return (
    <div className="px-3 py-2 space-y-2 border-b border-border/50">
      {/* Search */}
      <div className="relative">
        <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-3 w-3 text-muted-foreground" />
        <Input
          value={search}
          onChange={(e) => onSearchChange(e.target.value)}
          placeholder="Search tasks..."
          className="h-7 pl-7 pr-6 text-xs bg-muted/50 border-none"
        />
        {search && (
          <button
            className="absolute right-1.5 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground"
            onClick={() => onSearchChange('')}
          >
            <X className="h-3 w-3" />
          </button>
        )}
      </div>

      {/* Filter chips */}
      <div className="flex items-center gap-2 flex-wrap">
        <Filter className="h-3 w-3 text-muted-foreground shrink-0" />

        {/* Status filter */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="outline"
              size="sm"
              className={cn(
                'h-5 text-[10px] px-1.5 gap-1',
                statusFilter !== 'all' && 'border-primary/50 bg-primary/5',
              )}
            >
              {statusFilter === 'all' ? 'Status' : STATUS_CONFIGS[statusFilter]?.label}
              <ChevronDown className="h-2.5 w-2.5" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" className="w-32">
            <DropdownMenuItem className="text-xs py-1" onClick={() => onStatusChange('all')}>
              All statuses
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            {ALL_STATUSES.map((s) => (
              <DropdownMenuItem
                key={s}
                className="text-xs gap-2 py-1"
                onClick={() => onStatusChange(s)}
              >
                <span className={cn('w-2 h-2 rounded-full', STATUS_CONFIGS[s].dot)} />
                {STATUS_CONFIGS[s].label}
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>

        {/* Priority filter */}
        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="outline"
              size="sm"
              className={cn(
                'h-5 text-[10px] px-1.5 gap-1',
                priorityFilter !== 'all' && 'border-primary/50 bg-primary/5',
              )}
            >
              {priorityFilter === 'all' ? 'Priority' : PRIORITY_CONFIGS[priorityFilter]?.label}
              <ChevronDown className="h-2.5 w-2.5" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="start" className="w-28">
            <DropdownMenuItem className="text-xs py-1" onClick={() => onPriorityChange('all')}>
              All priorities
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            {ALL_PRIORITIES.map((p) => (
              <DropdownMenuItem
                key={p}
                className="text-xs py-1"
                onClick={() => onPriorityChange(p)}
              >
                {PRIORITY_CONFIGS[p].label}
              </DropdownMenuItem>
            ))}
          </DropdownMenuContent>
        </DropdownMenu>

        {/* Clear filters */}
        {hasFilters && (
          <Button
            variant="ghost"
            size="sm"
            className="h-5 text-[10px] px-1.5 text-muted-foreground hover:text-foreground"
            onClick={() => {
              onStatusChange('all');
              onPriorityChange('all');
              onSearchChange('');
            }}
          >
            <X className="h-2.5 w-2.5 mr-0.5" />
            Clear
          </Button>
        )}
      </div>
    </div>
  );
}

// -- Main component --

export function TasksPanel() {
  const [statusFilter, setStatusFilter] = useState<TaskStatus | 'all'>('all');
  const [priorityFilter, setPriorityFilter] = useState<TaskPriority | 'all'>('all');
  const [search, setSearch] = useState('');

  // Always fetch all tasks globally — no project scoping
  const { data, isLoading, error, isFetching } = useTasks();

  const tasks = data?.tasks || [];
  const allCounts = useMemo(() => countByStatus(tasks), [tasks]);
  const totalFlat = useMemo(() => flattenTasks(tasks).length, [tasks]);

  const filteredTasks = useMemo(
    () => filterTasks(tasks, statusFilter, priorityFilter, search),
    [tasks, statusFilter, priorityFilter, search],
  );

  // Initial loading
  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-8 gap-2">
        <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
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

  if (tasks.length === 0) {
    return (
      <div className="text-center py-12">
        <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mx-auto mb-3">
          <ListTodo className="h-6 w-6 text-muted-foreground" />
        </div>
        <p className="text-sm text-muted-foreground">
          No tasks yet. Tasks will appear as agents create them.
        </p>
      </div>
    );
  }

  return (
    <div className="flex flex-col h-full">
      {/* Stats summary */}
      <div className="flex items-center justify-between pr-3 border-b border-border/30">
        <StatsSummary counts={allCounts} total={totalFlat} />
        {isFetching && !isLoading && (
          <Loader2 className="h-3 w-3 animate-spin text-muted-foreground shrink-0" />
        )}
      </div>

      {/* Filter bar */}
      <FilterBar
        statusFilter={statusFilter}
        onStatusChange={setStatusFilter}
        priorityFilter={priorityFilter}
        onPriorityChange={setPriorityFilter}
        search={search}
        onSearchChange={setSearch}
      />

      {/* Task cards */}
      <ScrollArea className="flex-1">
        <div className="p-3 space-y-2.5">
          {filteredTasks.length === 0 ? (
            <div className="text-center py-10">
              <p className="text-xs text-muted-foreground">
                No tasks match your filters.
              </p>
              <Button
                variant="ghost"
                size="sm"
                className="text-xs mt-3 h-7"
                onClick={() => {
                  setStatusFilter('all');
                  setPriorityFilter('all');
                  setSearch('');
                }}
              >
                Clear filters
              </Button>
            </div>
          ) : (
            filteredTasks.map((task) => <TaskCard key={task.id} task={task} />)
          )}
        </div>
      </ScrollArea>
    </div>
  );
}
