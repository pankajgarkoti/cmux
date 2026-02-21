import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { formatTokenCount } from '@/lib/utils';
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { Coins } from 'lucide-react';

// Claude Opus pricing per 1M tokens
const PRICING = {
  input: 15,
  output: 75,
  cache_read: 1.5,
  cache_creation: 18.75,
};

function formatCost(cost: number): string {
  if (cost < 0.01) return '<$0.01';
  return `$${cost.toFixed(2)}`;
}

/**
 * Compact cost statusline for the header.
 * Shows total cost + total tokens, with breakdown on hover.
 */
export function BudgetStatusline() {
  const { data: budgetData } = useQuery({
    queryKey: ['budget'],
    queryFn: () => api.getBudget(),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
  });

  const totals = useMemo(() => {
    if (!budgetData?.agents || budgetData.agents.length === 0) return null;
    return budgetData.agents.reduce(
      (acc, a) => ({
        input: acc.input + a.input_tokens,
        output: acc.output + a.output_tokens,
        cache_read: acc.cache_read + a.cache_read_tokens,
        cache_write: acc.cache_write + a.cache_creation_tokens,
      }),
      { input: 0, output: 0, cache_read: 0, cache_write: 0 }
    );
  }, [budgetData]);

  if (!totals) return null;

  const totalTokens = totals.input + totals.output;
  const totalCost =
    (totals.input / 1_000_000) * PRICING.input +
    (totals.output / 1_000_000) * PRICING.output +
    (totals.cache_read / 1_000_000) * PRICING.cache_read +
    (totals.cache_write / 1_000_000) * PRICING.cache_creation;

  return (
    <Tooltip>
      <TooltipTrigger asChild>
        <div className="flex items-center gap-1.5 text-xs text-muted-foreground font-mono cursor-default">
          <Coins className="h-3 w-3" />
          <span>{formatCost(totalCost)}</span>
          <span className="opacity-50">·</span>
          <span>{formatTokenCount(totalTokens)} tok</span>
        </div>
      </TooltipTrigger>
      <TooltipContent side="bottom" className="text-xs font-mono">
        <div className="space-y-0.5">
          <div className="flex justify-between gap-4">
            <span className="text-muted-foreground">Input</span>
            <span>{formatTokenCount(totals.input)}</span>
          </div>
          <div className="flex justify-between gap-4">
            <span className="text-muted-foreground">Output</span>
            <span>{formatTokenCount(totals.output)}</span>
          </div>
          <div className="flex justify-between gap-4">
            <span className="text-muted-foreground">Cache read</span>
            <span>{formatTokenCount(totals.cache_read)}</span>
          </div>
          <div className="flex justify-between gap-4">
            <span className="text-muted-foreground">Cache write</span>
            <span>{formatTokenCount(totals.cache_write)}</span>
          </div>
        </div>
      </TooltipContent>
    </Tooltip>
  );
}
