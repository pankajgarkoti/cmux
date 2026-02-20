import { useState } from 'react';
import { cn } from '@/lib/utils';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from '@/components/ui/tooltip';
import { MarkdownContent } from './MarkdownContent';
import { MessageActions } from './MessageActions';
import { useAgentStore } from '@/stores/agentStore';
import { Bot, User, ChevronDown, ChevronUp, HeartPulse, ShieldAlert, Radio } from 'lucide-react';
import { formatDistanceToNow, format } from 'date-fns';
import { InterleavedTimeline } from './InterleavedTimeline';
import type { Message } from '@/types/message';
import type { Activity } from '@/types/activity';
import type { Thought } from '@/stores/thoughtStore';

// Fixed-prefix patterns for incoming system messages (heartbeat pings, sentry briefings)
const SYSTEM_CONTENT_PREFIXES = [
  { prefix: 'SENTRY BRIEFING', label: 'Sentry Recovery', icon: 'shield' as const },
  { prefix: 'SYSTEM ALERT', label: 'System Alert', icon: 'shield' as const },
  { prefix: '[HEARTBEAT]', label: 'Heartbeat', icon: 'heartbeat' as const },
  { prefix: '[SYSTEM AUTO-JOURNAL', label: 'Journal Reminder', icon: 'radio' as const },
] as const;

const SYSTEM_AGENTS = new Set(['health', 'monitor', 'system']);

type SystemIcon = 'heartbeat' | 'shield' | 'radio';

export function getSystemNotificationInfo(message: Message): { label: string; icon: SystemIcon; summary: string } | null {
  const content = message.content.trim();

  // Primary: check message.type === 'system' (set by backend when agent prefixes with [SYS])
  if (message.type === 'system') {
    return { label: 'System', icon: 'radio', summary: getFirstSentence(content) };
  }

  // Check from_agent for system sources
  if (SYSTEM_AGENTS.has(message.from_agent)) {
    if (content.includes('rollback') || content.includes('SYSTEM ALERT')) {
      return { label: 'System Alert', icon: 'shield', summary: getFirstSentence(content) };
    }
    return { label: 'System Message', icon: 'radio', summary: getFirstSentence(content) };
  }

  // Fallback: check fixed content prefixes for legacy/incoming system messages
  for (const { prefix, label, icon } of SYSTEM_CONTENT_PREFIXES) {
    if (content.startsWith(prefix)) {
      return { label, icon, summary: getFirstSentence(content) };
    }
  }

  return null;
}

function getFirstSentence(content: string): string {
  // Get the first meaningful sentence, max 120 chars
  const cleaned = content.replace(/^(SENTRY BRIEFING:|SYSTEM ALERT:|---\s*MESSAGE\s*---[\s\S]*?---\s*)/i, '').trim();
  const firstLine = cleaned.split(/[.\n]/)[0]?.trim() || cleaned;
  return firstLine.length > 120 ? firstLine.slice(0, 117) + '...' : firstLine;
}

const SystemIconComponent = ({ icon }: { icon: SystemIcon }) => {
  switch (icon) {
    case 'heartbeat': return <HeartPulse className="h-3 w-3" />;
    case 'shield': return <ShieldAlert className="h-3 w-3" />;
    case 'radio': return <Radio className="h-3 w-3" />;
  }
};

interface ChatMessageProps {
  message: Message;
  toolCalls?: Activity[];
  thoughts?: Thought[];
  collapseCount?: number;
}

const COLLAPSE_THRESHOLD = 500;
const PREVIEW_LENGTH = 200;

// Regex to match @mentions (agent names are alphanumeric with hyphens)
const MENTION_REGEX = /@([\w-]+)/g;

/**
 * Renders text with @mentions highlighted as colored badges.
 */
function renderWithMentions(text: string, className?: string) {
  const parts: (string | JSX.Element)[] = [];
  let lastIndex = 0;

  for (const match of text.matchAll(MENTION_REGEX)) {
    const mentionFull = match[0];
    const mentionName = match[1];
    const matchIndex = match.index!;

    // Add text before this match
    if (matchIndex > lastIndex) {
      parts.push(text.slice(lastIndex, matchIndex));
    }

    // Add highlighted mention
    parts.push(
      <span
        key={`${mentionName}-${matchIndex}`}
        className="inline-flex items-center bg-primary/15 text-primary font-medium rounded px-1 py-0.5 text-[0.9em]"
      >
        {mentionFull}
      </span>
    );

    lastIndex = matchIndex + mentionFull.length;
  }

  // Add remaining text
  if (lastIndex < text.length) {
    parts.push(text.slice(lastIndex));
  }

  // If no mentions found, return plain text
  if (parts.length === 0) {
    return <p className={className}>{text}</p>;
  }

  return <p className={className}>{parts}</p>;
}

// Get preview content, trying to not break markdown
function getPreviewContent(content: string): string {
  // If there's a code block near the start, include it
  const firstCodeBlockMatch = content.match(/```[\s\S]*?```/);
  if (firstCodeBlockMatch && firstCodeBlockMatch.index !== undefined) {
    const codeBlockEnd = firstCodeBlockMatch.index + firstCodeBlockMatch[0].length;
    if (codeBlockEnd <= PREVIEW_LENGTH * 2) {
      // Include the code block in preview
      return content.slice(0, codeBlockEnd);
    }
  }

  // Otherwise, truncate at a reasonable point
  let truncated = content.slice(0, PREVIEW_LENGTH);

  // Try to break at a sentence or paragraph
  const lastNewline = truncated.lastIndexOf('\n\n');
  const lastPeriod = truncated.lastIndexOf('. ');

  if (lastNewline > PREVIEW_LENGTH * 0.5) {
    truncated = truncated.slice(0, lastNewline);
  } else if (lastPeriod > PREVIEW_LENGTH * 0.5) {
    truncated = truncated.slice(0, lastPeriod + 1);
  }

  return truncated;
}

function SystemNotification({ message, info, collapseCount }: { message: Message; info: { label: string; icon: SystemIcon; summary: string }; collapseCount?: number }) {
  const [expanded, setExpanded] = useState(false);
  const messageDate = new Date(message.timestamp);
  const relativeTime = formatDistanceToNow(messageDate, { addSuffix: true });
  const preciseTime = format(messageDate, 'MMM d, yyyy h:mm:ss a');

  return (
    <div className="space-y-1">
      <div className="flex items-center gap-2 py-1 max-w-full">
        <div className="flex-1 h-px bg-border/40" />
        <button
          onClick={() => setExpanded(!expanded)}
          className="flex items-center gap-1.5 text-[11px] text-muted-foreground/70 hover:text-muted-foreground transition-colors px-2 py-0.5 rounded-full hover:bg-muted/50 shrink-0"
        >
          <SystemIconComponent icon={info.icon} />
          <span className="font-medium">{info.label}</span>
          {collapseCount && collapseCount > 1 && (
            <span className="bg-muted-foreground/20 text-muted-foreground px-1.5 py-0 rounded-full text-[10px] font-medium">
              ×{collapseCount}
            </span>
          )}
          {!expanded && (
            <span className="max-w-[200px] truncate opacity-60">
              {info.summary}
            </span>
          )}
          <Tooltip>
            <TooltipTrigger asChild>
              <span className="opacity-50 whitespace-nowrap">{relativeTime}</span>
            </TooltipTrigger>
            <TooltipContent side="top" className="text-xs">
              {preciseTime}
            </TooltipContent>
          </Tooltip>
          {expanded ? (
            <ChevronUp className="h-2.5 w-2.5 opacity-50" />
          ) : (
            <ChevronDown className="h-2.5 w-2.5 opacity-50" />
          )}
        </button>
        <div className="flex-1 h-px bg-border/40" />
      </div>
      {expanded && (
        <div className="mx-8 bg-muted/30 border border-border/50 rounded-lg px-3 py-2 text-xs text-muted-foreground">
          <MarkdownContent content={message.content} className="text-xs [&_p]:mb-1 [&_p]:last:mb-0" />
        </div>
      )}
    </div>
  );
}

export function ChatMessage({ message, toolCalls, thoughts, collapseCount }: ChatMessageProps) {
  const [isExpanded, setIsExpanded] = useState(false);
  const agents = useAgentStore((s) => s.agents);

  // Check if this is a system notification (heartbeat ping, sentry briefing, etc.)
  const systemInfo = getSystemNotificationInfo(message);
  if (systemInfo) {
    return <SystemNotification message={message} info={systemInfo} collapseCount={collapseCount} />;
  }

  const isUser = message.type === 'user' || message.from_agent === 'user';
  const messageDate = new Date(message.timestamp);
  const relativeTime = formatDistanceToNow(messageDate, { addSuffix: true });
  const preciseTime = format(messageDate, 'MMM d, yyyy h:mm:ss a');
  const displayName = isUser ? 'You' : message.from_agent;

  const shouldCollapse =
    message.content.length > COLLAPSE_THRESHOLD && !isUser;
  const isCollapsed = shouldCollapse && !isExpanded;
  const displayContent = isCollapsed
    ? getPreviewContent(message.content)
    : message.content;

  return (
    <div
      className={cn(
        'group flex gap-3 max-w-[85%]',
        isUser ? 'ml-auto flex-row-reverse' : 'mr-auto'
      )}
    >
      {/* Avatar */}
      <Avatar className="h-8 w-8 flex-shrink-0">
        <AvatarFallback
          className={cn(
            'text-xs',
            isUser
              ? 'bg-primary text-primary-foreground'
              : 'bg-secondary text-secondary-foreground'
          )}
        >
          {isUser ? <User className="h-4 w-4" /> : <Bot className="h-4 w-4" />}
        </AvatarFallback>
      </Avatar>

      {/* Message Bubble */}
      <div
        className={cn(
          'rounded-2xl px-4 py-2.5 min-w-0 relative',
          isUser
            ? 'bg-primary text-primary-foreground rounded-tr-sm'
            : 'bg-muted rounded-tl-sm'
        )}
      >
        {/* Header */}
        <div
          className={cn(
            'flex items-center gap-2 mb-1',
            isUser ? 'flex-row-reverse' : ''
          )}
        >
          <span className="text-xs font-medium">{displayName}</span>
          {!isUser && (
            <Badge
              variant="outline"
              className="text-[10px] h-4 px-1 border-current/20"
            >
              {(() => {
                const agentData = agents.find(a => a.name === message.from_agent || a.id === message.from_agent);
                return agentData?.type === 'supervisor' || agentData?.role === 'project-supervisor' ? 'SUP' : 'WRK';
              })()}
            </Badge>
          )}
          <Tooltip>
            <TooltipTrigger asChild>
              <span
                className={cn(
                  'text-[10px] cursor-default',
                  isUser
                    ? 'text-primary-foreground/70'
                    : 'text-muted-foreground'
                )}
              >
                {relativeTime}
              </span>
            </TooltipTrigger>
            <TooltipContent side="top" className="text-xs">
              {preciseTime}
            </TooltipContent>
          </Tooltip>

          {/* Message Actions - appear on hover */}
          <MessageActions
            content={message.content}
            isUser={isUser}
            className={cn(
              'ml-auto',
              isUser ? 'mr-auto ml-0' : ''
            )}
          />
        </div>

        {/* Interleaved thoughts + tool calls timeline */}
        {!isUser && ((thoughts && thoughts.length > 0) || (toolCalls && toolCalls.length > 0)) && (
          <InterleavedTimeline
            thoughts={thoughts || []}
            toolCalls={toolCalls || []}
          />
        )}

        {/* Content */}
        {isUser ? (
          renderWithMentions(message.content, 'text-sm whitespace-pre-wrap')
        ) : (
          <>
            <MarkdownContent
              content={displayContent}
              className={cn(
                'text-sm',
                '[&_p]:mb-1 [&_p]:last:mb-0',
                '[&_pre]:bg-background/20 [&_code]:bg-background/20'
              )}
            />

            {/* Collapse/Expand controls */}
            {shouldCollapse && (
              <div className="mt-2 flex items-center gap-2">
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setIsExpanded(!isExpanded)}
                  className="h-6 px-2 text-xs text-muted-foreground hover:text-foreground"
                >
                  {isCollapsed ? (
                    <>
                      <ChevronDown className="h-3 w-3 mr-1" />
                      Show more ({message.content.length - displayContent.length}{' '}
                      more chars)
                    </>
                  ) : (
                    <>
                      <ChevronUp className="h-3 w-3 mr-1" />
                      Show less
                    </>
                  )}
                </Button>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
