import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { formatTokenCount } from '@/lib/utils';
import { useAgentStore } from '@/stores/agentStore';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Loader2, DollarSign } from 'lucide-react';
import type { BudgetAgentUsage } from '@/lib/api';

// Claude Opus pricing per 1M tokens
const PRICING = {
  input: 15,
  output: 75,
  cache_read: 1.5,
  cache_creation: 18.75,
};

function calcCost(agent: BudgetAgentUsage): number {
  return (
    (agent.input_tokens / 1_000_000) * PRICING.input +
    (agent.output_tokens / 1_000_000) * PRICING.output +
    (agent.cache_read_tokens / 1_000_000) * PRICING.cache_read +
    (agent.cache_creation_tokens / 1_000_000) * PRICING.cache_creation
  );
}

function formatCost(cost: number): string {
  if (cost < 0.01) return '<$0.01';
  if (cost < 1) return `$${cost.toFixed(2)}`;
  return `$${cost.toFixed(2)}`;
}

export function BudgetPanel() {
  const agents = useAgentStore((s) => s.agents);

  const { data: budgetData, isLoading } = useQuery({
    queryKey: ['budget'],
    queryFn: () => api.getBudget(),
    staleTime: 30_000,
    refetchOnWindowFocus: false,
  });

  // Map agent_id to display name
  const nameMap = useMemo(() => {
    const map = new Map<string, string>();
    for (const a of agents) {
      map.set(a.id, a.display_name || a.name);
      map.set(a.name, a.display_name || a.name);
    }
    return map;
  }, [agents]);

  // Enrich and sort by cost descending
  const rows = useMemo(() => {
    if (!budgetData?.agents) return [];
    return budgetData.agents
      .map((a) => ({
        ...a,
        displayName: nameMap.get(a.agent_id) || a.agent_id,
        cost: calcCost(a),
      }))
      .sort((a, b) => b.cost - a.cost);
  }, [budgetData, nameMap]);

  // Totals
  const totals = useMemo(() => {
    if (rows.length === 0) return null;
    return rows.reduce(
      (acc, r) => ({
        input_tokens: acc.input_tokens + r.input_tokens,
        output_tokens: acc.output_tokens + r.output_tokens,
        cache_read_tokens: acc.cache_read_tokens + r.cache_read_tokens,
        cache_creation_tokens: acc.cache_creation_tokens + r.cache_creation_tokens,
        cost: acc.cost + r.cost,
      }),
      { input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, cache_creation_tokens: 0, cost: 0 }
    );
  }, [rows]);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (rows.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-center">
        <div className="w-12 h-12 rounded-full bg-muted flex items-center justify-center mb-3">
          <DollarSign className="h-6 w-6 text-muted-foreground" />
        </div>
        <p className="text-sm text-muted-foreground">
          No token usage data yet.
        </p>
        <p className="text-xs text-muted-foreground/60 mt-1">
          Usage appears as agents work.
        </p>
      </div>
    );
  }

  return (
    <ScrollArea className="h-full">
      <div className="p-3 pt-0">
        {/* Total cost summary */}
        {totals && (
          <div className="flex items-center justify-between px-2 py-2 mb-2 rounded-md bg-muted/50">
            <span className="text-xs font-medium text-muted-foreground">Total</span>
            <span className="text-sm font-semibold">{formatCost(totals.cost)}</span>
          </div>
        )}

        {/* Table */}
        <table className="w-full text-[11px]">
          <thead>
            <tr className="text-muted-foreground border-b border-border/50">
              <th className="text-left font-medium py-1.5 pr-2">Agent</th>
              <th className="text-right font-medium py-1.5 px-1">In</th>
              <th className="text-right font-medium py-1.5 px-1">Out</th>
              <th className="text-right font-medium py-1.5 px-1">Cache R</th>
              <th className="text-right font-medium py-1.5 px-1">Cache W</th>
              <th className="text-right font-medium py-1.5 pl-1">Cost</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.agent_id} className="border-b border-border/30 hover:bg-muted/30">
                <td className="py-1.5 pr-2 truncate max-w-[120px]" title={row.agent_id}>
                  {row.displayName}
                </td>
                <td className="text-right py-1.5 px-1 text-muted-foreground tabular-nums">
                  {formatTokenCount(row.input_tokens)}
                </td>
                <td className="text-right py-1.5 px-1 text-muted-foreground tabular-nums">
                  {formatTokenCount(row.output_tokens)}
                </td>
                <td className="text-right py-1.5 px-1 text-muted-foreground tabular-nums">
                  {formatTokenCount(row.cache_read_tokens)}
                </td>
                <td className="text-right py-1.5 px-1 text-muted-foreground tabular-nums">
                  {formatTokenCount(row.cache_creation_tokens)}
                </td>
                <td className="text-right py-1.5 pl-1 font-medium tabular-nums">
                  {formatCost(row.cost)}
                </td>
              </tr>
            ))}
          </tbody>
          {totals && (
            <tfoot>
              <tr className="border-t border-border font-medium">
                <td className="py-1.5 pr-2">Total</td>
                <td className="text-right py-1.5 px-1 tabular-nums">
                  {formatTokenCount(totals.input_tokens)}
                </td>
                <td className="text-right py-1.5 px-1 tabular-nums">
                  {formatTokenCount(totals.output_tokens)}
                </td>
                <td className="text-right py-1.5 px-1 tabular-nums">
                  {formatTokenCount(totals.cache_read_tokens)}
                </td>
                <td className="text-right py-1.5 px-1 tabular-nums">
                  {formatTokenCount(totals.cache_creation_tokens)}
                </td>
                <td className="text-right py-1.5 pl-1 tabular-nums">
                  {formatCost(totals.cost)}
                </td>
              </tr>
            </tfoot>
          )}
        </table>
      </div>
    </ScrollArea>
  );
}
