import { Activity } from 'lucide-react';

export function Header() {
  return (
    <header className="h-14 border-b flex items-center justify-between px-6">
      <div className="flex items-center gap-2">
        <Activity className="h-6 w-6 text-primary" />
        <h1 className="text-xl font-semibold">CMUX Dashboard</h1>
      </div>
      <div className="flex items-center gap-4">
        <span className="text-sm text-muted-foreground">
          Claude Multi-Agent Orchestrator
        </span>
      </div>
    </header>
  );
}
