import { cn } from '@/lib/utils';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { MarkdownContent } from './MarkdownContent';
import { Bot, User } from 'lucide-react';
import { formatDistanceToNow } from 'date-fns';
import type { Message } from '@/types/message';

interface ChatMessageProps {
  message: Message;
}

export function ChatMessage({ message }: ChatMessageProps) {
  const isUser = message.type === 'user' || message.from_agent === 'user';
  const time = formatDistanceToNow(new Date(message.timestamp), { addSuffix: true });
  const displayName = isUser ? 'You' : message.from_agent;

  return (
    <div
      className={cn(
        'flex gap-3 max-w-[85%]',
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
          'rounded-2xl px-4 py-2.5 min-w-0',
          isUser
            ? 'bg-primary text-primary-foreground rounded-tr-sm'
            : 'bg-muted rounded-tl-sm'
        )}
      >
        {/* Header */}
        <div className={cn(
          'flex items-center gap-2 mb-1',
          isUser ? 'flex-row-reverse' : ''
        )}>
          <span className="text-xs font-medium">{displayName}</span>
          {!isUser && (
            <Badge
              variant="outline"
              className="text-[10px] h-4 px-1 border-current/20"
            >
              {message.from_agent === 'supervisor' ? 'SUP' : 'WRK'}
            </Badge>
          )}
          <span className={cn(
            'text-[10px]',
            isUser ? 'text-primary-foreground/70' : 'text-muted-foreground'
          )}>
            {time}
          </span>
        </div>

        {/* Content */}
        {isUser ? (
          <p className="text-sm whitespace-pre-wrap">{message.content}</p>
        ) : (
          <MarkdownContent
            content={message.content}
            className={cn(
              'text-sm',
              '[&_p]:mb-1 [&_p]:last:mb-0',
              '[&_pre]:bg-background/20 [&_code]:bg-background/20'
            )}
          />
        )}
      </div>
    </div>
  );
}
