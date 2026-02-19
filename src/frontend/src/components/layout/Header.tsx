import { useState } from 'react';
import { Terminal, Sun, Moon, GitBranch, Heart } from 'lucide-react';
import { useThemeStore } from '../../stores/themeStore';
import { Button } from '../ui/button';

export function Header() {
  const { theme, toggleTheme } = useThemeStore();
  const [heartState, setHeartState] = useState<0 | 1 | 2>(0); // 0=default, 1=red, 2=red+beating

  return (
    <header className="h-12 border-b border-border/50 flex items-center justify-between px-4 bg-background/95 backdrop-blur supports-[backdrop-filter]:bg-background/60">
      <div className="flex items-center gap-3">
        {/* Dev-toolish logo */}
        <div className="flex items-center gap-2">
          <div className="relative">
            <Terminal className="h-5 w-5 text-emerald-500" strokeWidth={2.5} />
            <div className="absolute -bottom-0.5 -right-0.5 h-2 w-2 bg-emerald-500 rounded-full animate-pulse" />
          </div>
          <span className="font-mono font-bold text-base tracking-tight">
            cmux
          </span>
        </div>
        <div className="h-4 w-px bg-border" />
        <div className="flex items-center gap-1.5 text-xs text-muted-foreground font-mono">
          <GitBranch className="h-3.5 w-3.5" />
          <span>main</span>
        </div>
      </div>

      <div className="flex items-center gap-3">
        <span className="text-xs text-muted-foreground font-mono hidden sm:inline">
          multi-agent orchestrator
        </span>

        {/* Heart toggle: default → red → red+beating → default */}
        <Button
          variant="ghost"
          size="icon"
          onClick={() => setHeartState(((heartState + 1) % 3) as 0 | 1 | 2)}
          className="h-8 w-8"
        >
          <Heart
            className={`h-4 w-4 transition-colors ${
              heartState >= 1 ? 'fill-red-500 text-red-500' : 'text-muted-foreground'
            } ${heartState === 2 ? 'animate-heartbeat' : ''}`}
          />
          <span className="sr-only">Toggle heart</span>
        </Button>

        {/* Dark mode toggle */}
        <Button
          variant="ghost"
          size="icon"
          onClick={toggleTheme}
          className="h-8 w-8"
        >
          {theme === 'dark' ? (
            <Sun className="h-4 w-4 text-yellow-500" />
          ) : (
            <Moon className="h-4 w-4 text-slate-600" />
          )}
          <span className="sr-only">Toggle theme</span>
        </Button>
      </div>
    </header>
  );
}
