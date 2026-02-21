import { useEffect, useState } from 'react';
import { Activity, AlertTriangle, CheckCircle2, Clock } from 'lucide-react';
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

export function HeartbeatIndicator() {
  const { latest, setLatest } = useHeartbeatStore();
  const [secondsAgo, setSecondsAgo] = useState<number | null>(null);

  // Fetch initial heartbeat on mount
  useEffect(() => {
    fetch(`${API_BASE}/api/heartbeat`)
      .then((r) => r.json())
      .then((data) => {
        if (data.timestamp) setLatest(data);
      })
      .catch(() => {});
  }, [setLatest]);

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

  // Determine status color
  const getStatusColor = () => {
    if (!latest) return 'bg-muted-foreground/50';
    if (latest.all_clear) return 'bg-emerald-500';
    if (
      latest.highest_priority?.toLowerCase().includes('failed') ||
      latest.highest_priority?.toLowerCase().includes('health') ||
      latest.highest_priority?.toLowerCase().includes('stuck') ||
      latest.highest_priority?.toLowerCase().includes('down')
    )
      return 'bg-red-500';
    return 'bg-yellow-500';
  };

  const getStatusIcon = () => {
    if (!latest) return <Activity className="h-3.5 w-3.5 text-muted-foreground" />;
    if (latest.all_clear) return <CheckCircle2 className="h-3.5 w-3.5 text-emerald-500" />;
    if (
      latest.highest_priority?.toLowerCase().includes('failed') ||
      latest.highest_priority?.toLowerCase().includes('health')
    )
      return <AlertTriangle className="h-3.5 w-3.5 text-red-500" />;
    return <Activity className="h-3.5 w-3.5 text-yellow-500" />;
  };

  const formatAgo = (s: number | null) => {
    if (s === null) return 'never';
    if (s < 60) return `${s}s ago`;
    if (s < 3600) return `${Math.floor(s / 60)}m ago`;
    return `${Math.floor(s / 3600)}h ago`;
  };

  const sectionEntries = latest ? Object.entries(latest.sections).filter(([k]) => k !== 'highest_priority') : [];

  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button variant="ghost" size="icon" className="h-8 w-8 relative" title="System heartbeat">
          {getStatusIcon()}
          <div
            className={cn(
              'absolute top-1 right-1 h-2 w-2 rounded-full',
              getStatusColor(),
              latest && 'animate-pulse'
            )}
          />
          <span className="sr-only">System heartbeat</span>
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-72">
        <DropdownMenuLabel className="flex items-center justify-between">
          <span>Autonomy Scan</span>
          <span className="text-xs font-normal text-muted-foreground flex items-center gap-1">
            <Clock className="h-3 w-3" />
            {formatAgo(secondsAgo)}
          </span>
        </DropdownMenuLabel>
        <DropdownMenuSeparator />

        {!latest && (
          <div className="px-2 py-3 text-xs text-muted-foreground text-center">
            No heartbeat data yet
          </div>
        )}

        {latest?.all_clear && sectionEntries.length === 0 && (
          <div className="px-2 py-3 flex items-center gap-2 text-xs text-emerald-600 dark:text-emerald-400">
            <CheckCircle2 className="h-4 w-4" />
            All clear — no pending work
          </div>
        )}

        {sectionEntries.length > 0 && (
          <div className="px-2 py-1.5 space-y-1.5">
            {sectionEntries.map(([key, value]) => (
              <div key={key} className="text-xs">
                <span className="font-medium text-foreground capitalize">
                  {key.replace(/_/g, ' ')}:
                </span>{' '}
                <span className="text-muted-foreground">{value}</span>
              </div>
            ))}
          </div>
        )}

        {latest?.highest_priority && (
          <>
            <DropdownMenuSeparator />
            <div className="px-2 py-1.5 text-xs">
              <span className="font-medium text-orange-600 dark:text-orange-400">Priority: </span>
              <span className="text-muted-foreground">{latest.highest_priority}</span>
            </div>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
