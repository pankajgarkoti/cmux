import { useEffect, useRef } from 'react';
import { useThoughtStore, type Thought } from '@/stores/thoughtStore';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Brain, Wrench } from 'lucide-react';

function ThoughtItem({ thought }: { thought: Thought }) {
  const time = new Date(thought.timestamp).toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  });

  if (thought.thought_type === 'reasoning') {
    return (
      <div className="flex gap-2 text-xs py-1 px-2 rounded hover:bg-muted/50">
        <Brain className="h-3 w-3 mt-0.5 shrink-0 text-violet-400" />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5 mb-0.5">
            <span className="font-medium text-violet-400">{thought.agent_name}</span>
            <span className="text-muted-foreground">{time}</span>
          </div>
          {thought.content ? (
            <p className="text-muted-foreground truncate">{thought.content}</p>
          ) : thought.tool_name ? (
            <p className="text-muted-foreground truncate">
              → {thought.tool_name}
              {thought.tool_input ? `: ${thought.tool_input}` : ''}
            </p>
          ) : null}
        </div>
      </div>
    );
  }

  // tool_result
  return (
    <div className="flex gap-2 text-xs py-1 px-2 rounded hover:bg-muted/50">
      <Wrench className="h-3 w-3 mt-0.5 shrink-0 text-emerald-400" />
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-1.5 mb-0.5">
          <span className="font-medium text-emerald-400">{thought.agent_name}</span>
          <span className="font-mono text-muted-foreground">{thought.tool_name}</span>
          <span className="text-muted-foreground">{time}</span>
        </div>
        {thought.tool_response && (
          <p className="text-muted-foreground truncate">{thought.tool_response}</p>
        )}
      </div>
    </div>
  );
}

export function ThoughtStream() {
  const thoughts = useThoughtStore((s) => s.thoughts);
  const viewportRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom when new thoughts arrive
  useEffect(() => {
    const el = viewportRef.current;
    if (el) {
      el.scrollTop = el.scrollHeight;
    }
  }, [thoughts.length]);

  if (thoughts.length === 0) {
    return (
      <div className="h-full flex items-center justify-center p-4">
        <div className="text-center">
          <Brain className="h-6 w-6 text-muted-foreground mx-auto mb-2" />
          <p className="text-xs text-muted-foreground">
            Agent thoughts will stream here in real-time.
          </p>
        </div>
      </div>
    );
  }

  return (
    <ScrollArea className="h-full" viewportRef={viewportRef}>
      <div className="py-1">
        {thoughts.map((thought) => (
          <ThoughtItem key={thought.id} thought={thought} />
        ))}
      </div>
    </ScrollArea>
  );
}
