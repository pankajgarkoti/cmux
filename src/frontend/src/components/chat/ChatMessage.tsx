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
import { Bot, User, ChevronDown, ChevronUp } from 'lucide-react';
import { formatDistanceToNow, format } from 'date-fns';
import { ToolCallGroup } from './ToolCallGroup';
import { ThoughtGroup } from './ThoughtGroup';
import type { Message } from '@/types/message';
import type { Activity } from '@/types/activity';
import type { Thought } from '@/stores/thoughtStore';

interface ChatMessageProps {
  message: Message;
  toolCalls?: Activity[];
  thoughts?: Thought[];
}

const COLLAPSE_THRESHOLD = 500;
const PREVIEW_LENGTH = 200;

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

export function ChatMessage({ message, toolCalls, thoughts }: ChatMessageProps) {
  const [isExpanded, setIsExpanded] = useState(false);

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
              {message.from_agent === 'supervisor' ? 'SUP' : 'WRK'}
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

        {/* Agent thoughts that led to this response */}
        {!isUser && thoughts && thoughts.length > 0 && (
          <ThoughtGroup thoughts={thoughts} />
        )}

        {/* Tool calls that produced this response */}
        {!isUser && toolCalls && toolCalls.length > 0 && (
          <ToolCallGroup events={toolCalls} />
        )}

        {/* Content */}
        {isUser ? (
          <p className="text-sm whitespace-pre-wrap">{message.content}</p>
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
