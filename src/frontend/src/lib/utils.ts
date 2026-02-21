import { type ClassValue, clsx } from 'clsx';
import { twMerge } from 'tailwind-merge';
import type { Agent } from '@/types/agent';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** Unified agent badge label used across sidebar, chat messages, and @mention dropdown */
export function getAgentBadgeLabel(agent: Pick<Agent, 'type' | 'role' | 'permanent'>): 'SUP' | 'P-SUP' | 'PERM' | 'WRK' {
  const isSupervisor = agent.type === 'supervisor' || agent.role === 'project-supervisor';
  const isProjectSupervisor = agent.role === 'project-supervisor';
  if (isSupervisor) return isProjectSupervisor ? 'P-SUP' : 'SUP';
  if (agent.permanent) return 'PERM';
  return 'WRK';
}

/** Badge color classes keyed by label */
export function getAgentBadgeColor(label: 'SUP' | 'P-SUP' | 'PERM' | 'WRK'): string {
  switch (label) {
    case 'P-SUP': return 'border-purple-500/50 text-purple-600';
    case 'SUP': return 'border-amber-500/50 text-amber-600';
    case 'PERM': return 'border-teal-500/50 text-teal-600';
    case 'WRK': return 'border-muted';
  }
}

/** Format a token count as compact string: 842, 12.4k, 1.2M */
export function formatTokenCount(n: number): string {
  if (n < 1000) return String(n);
  if (n < 1_000_000) return (n / 1000).toFixed(1).replace(/\.0$/, '') + 'k';
  return (n / 1_000_000).toFixed(1).replace(/\.0$/, '') + 'M';
}

/** Message prefix → badge config. Returns null if no known prefix found. */
const MESSAGE_PREFIXES = [
  { tag: '[TASK]', label: 'TASK', className: 'bg-indigo-500/15 text-indigo-600 border-indigo-500/30' },
  { tag: '[UPDATE]', label: 'UPDATE', className: 'bg-sky-500/15 text-sky-600 border-sky-500/30' },
  { tag: '[DONE]', label: 'DONE', className: 'bg-green-500/15 text-green-600 border-green-500/30' },
  { tag: '[STATUS]', label: 'STATUS', className: 'bg-gray-500/15 text-gray-500 border-gray-500/30' },
  { tag: '[BLOCKED]', label: 'BLOCKED', className: 'bg-red-500/15 text-red-600 border-red-500/30' },
  { tag: '[QUESTION]', label: 'QUESTION', className: 'bg-amber-500/15 text-amber-600 border-amber-500/30' },
  { tag: '[PRIORITY]', label: 'PRIORITY', className: 'bg-orange-500/15 text-orange-600 border-orange-500/30' },
  { tag: '[COMPLETE]', label: 'COMPLETE', className: 'bg-green-500/15 text-green-600 border-green-500/30' },
  { tag: '[REVIEW-REQUEST]', label: 'REVIEW', className: 'bg-purple-500/15 text-purple-600 border-purple-500/30' },
  { tag: '[TASK-CANCEL]', label: 'CANCELLED', className: 'bg-red-500/15 text-red-600 border-red-500/30' },
] as const;

export function parseMessagePrefix(content: string): { label: string; className: string; rest: string } | null {
  const trimmed = content.trimStart();
  for (const { tag, label, className } of MESSAGE_PREFIXES) {
    if (trimmed.startsWith(tag)) {
      return { label, className, rest: trimmed.slice(tag.length).trimStart() };
    }
  }
  return null;
}
