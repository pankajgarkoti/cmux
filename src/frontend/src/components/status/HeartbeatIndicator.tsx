import { useEffect, useState, useCallback } from 'react';
import { Heart, Clock, Inbox, Users, ListTodo, Monitor, Shield, Bell, GitBranch, Activity } from 'lucide-react';
import { useHeartbeatStore } from '../../stores/heartbeatStore';
import { cn } from '../../lib/utils';
import { API_BASE } from '../../lib/constants';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '../ui/dropdown-menu';
import { Button } from '../ui/button';

const SECTION_ICONS: Record<string, typeof Inbox> = {
  mailbox: Inbox,
  workers: Users,
  backlog: ListTodo,
  supervisors: Monitor,
  watchdog: Shield,
  reminders: Bell,
  git: GitBranch,
  health: Activity,
};

type HeartStatus = 'idle' | 'clear' | 'active' | 'alert';

export function HeartbeatIndicator() {
  const { latest, setLatest } = useHeartbeatStore();
  const [secondsAgo, setSecondsAgo] = useState<number | null>(null);
  const [pulse, setPulse] = useState(false);

  // Fetch initial heartbeat on mount
  useEffect(() => {
    fetch(`${API_BASE}/api/heartbeat`)
      .then((r) => r.json())
      .then((data) => {
        if (data.timestamp) setLatest(data);
      })
      .catch(() => {});
  }, [setLatest]);

  // Pulse animation on new heartbeat data
  useEffect(() => {
    if (!latest) return;
    setPulse(true);
    const timer = setTimeout(() => setPulse(false), 2000);
    return () => clearTimeout(timer);
  }, [latest]);

  // Update "X seconds ago" every second
  useEffect(() => {
    if (!latest) return;
    const update = () => {
      const ago = Math.floor(Date.now() / 1000 - latest.timestamp);
      setSecondsAgo(ago);
    };
    update();
    const interval = setInterval(update, 1000);
    return () => clearInterval(interval);
  }, [latest]);

  const getStatus = useCallback((): HeartStatus => {
    if (!latest) return 'idle';
    if (latest.all_clear) return 'clear';
    const pri = latest.highest_priority?.toLowerCase() || '';
    if (pri.includes('failed') || pri.includes('health') || pri.includes('stuck') || pri.includes('down')) {
      return 'alert';
    }
    return 'active';
  }, [latest]);

  const status = getStatus();

  const heartColor = {
    idle: 'text-muted-foreground',
    clear: 'text-emerald-500 fill-emerald-500',
    active: 'text-red-500 fill-red-500',
    alert: 'text-red-600 fill-red-600',
  }[status];

  const formatAgo = (s: number | null) => {
    if (s === null) return 'No data';
    if (s < 60) return `${s}s ago`;
    if (s < 3600) return `${Math.floor(s / 60)}m ago`;
    return `${Math.floor(s / 3600)}h ago`;
  };

  const sectionEntries = latest
    ? Object.entries(latest.sections).filter(([, v]) => v && v.length > 0)
    : [];

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="h-8 w-8 relative" title="System heartbeat">
          <Heart
            className={cn(
              'h-4 w-4 transition-colors',
              heartColor,
              pulse && status !== 'idle' && 'animate-heartbeat',
            )}
          />
          <span className="sr-only">System heartbeat</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-80">
        <DropdownMenuLabel className="flex items-center justify-between">
          <span className="flex items-center gap-1.5">
            <Heart className={cn('h-3.5 w-3.5', heartColor)} />
            Autonomy Scan
          </span>
          <span className="text-[11px] font-normal text-muted-foreground flex items-center gap-1">
            <Clock className="h-3 w-3" />
            {formatAgo(secondsAgo)}
          </span>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />

        {!latest && (
          <div className="px-3 py-4 text-xs text-muted-foreground text-center">
            Waiting for first heartbeat scan...
          </div>
        )}

        {latest?.all_clear && sectionEntries.length === 0 && (
          <div className="px-3 py-4 flex items-center justify-center gap-2 text-xs text-emerald-600 dark:text-emerald-400">
            <Heart className="h-4 w-4 fill-emerald-500 text-emerald-500" />
            All clear — system healthy
          </div>
        )}

        {sectionEntries.length > 0 && (
          <div className="px-1 py-1 space-y-0.5">
            {sectionEntries.map(([key, value]) => {
              const Icon = SECTION_ICONS[key] || Activity;
              return (
                <div
                  key={key}
                  className="flex items-start gap-2.5 px-2 py-1.5 rounded-md text-xs hover:bg-accent/50"
                >
                  <Icon className="h-3.5 w-3.5 text-muted-foreground flex-shrink-0 mt-0.5" />
                  <div className="flex-1 min-w-0">
                    <span className="font-medium text-foreground capitalize">
                      {key.replace(/_/g, ' ')}
                    </span>
                    <p className="text-muted-foreground mt-0.5 leading-snug">{value}</p>
                  </div>
                </div>
              );
            })}
          </div>
        )}

        {latest?.highest_priority && (
          <>
            <DropdownMenuSeparator />
            <div className="px-3 py-2 text-xs">
              <span className="font-semibold text-orange-600 dark:text-orange-400">Next action: </span>
              <span className="text-muted-foreground">{latest.highest_priority}</span>
            </div>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
