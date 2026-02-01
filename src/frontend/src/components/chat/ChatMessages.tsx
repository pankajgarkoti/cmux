import { useRef, useEffect, useState, useCallback, useMemo } from 'react';
import { ScrollArea } from '@/components/ui/scroll-area';
import { ChatMessage } from './ChatMessage';
import { MessageSquare, ArrowDown } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import type { Message } from '@/types/message';

interface ChatMessagesProps {
  messages: Message[];
  onSuggestionClick?: (text: string) => void;
}

const suggestions = [
  'Check the mailbox for pending tasks',
  'Create a worker to review code',
  'What can you help me with?',
];

const SCROLL_THRESHOLD = 100; // pixels from bottom to consider "near bottom"

export function ChatMessages({ messages, onSuggestionClick }: ChatMessagesProps) {
  const bottomRef = useRef<HTMLDivElement>(null);
  const viewportRef = useRef<HTMLDivElement>(null);
  const [isNearBottom, setIsNearBottom] = useState(true);
  const [unreadCount, setUnreadCount] = useState(0);
  const prevMessageCountRef = useRef(messages.length);

  // Memoize sorted messages to prevent re-sorting on every render
  const sortedMessages = useMemo(
    () =>
      [...messages].sort(
        (a, b) => new Date(a.timestamp).getTime() - new Date(b.timestamp).getTime()
      ),
    [messages]
  );

  // Track scroll position to determine if user is near bottom
  const handleScroll = useCallback(() => {
    const viewport = viewportRef.current;
    if (!viewport) return;

    const { scrollTop, scrollHeight, clientHeight } = viewport;
    const distanceFromBottom = scrollHeight - scrollTop - clientHeight;
    const nearBottom = distanceFromBottom < SCROLL_THRESHOLD;

    setIsNearBottom(nearBottom);
    // Clear unread count when user scrolls to bottom
    if (nearBottom) {
      setUnreadCount(0);
    }
  }, []);

  // Scroll to bottom function
  const scrollToBottom = useCallback((smooth = true) => {
    bottomRef.current?.scrollIntoView({
      behavior: smooth ? 'smooth' : 'instant',
    });
    setUnreadCount(0);
  }, []);

  // Track new messages - never auto-scroll, just update unread count
  useEffect(() => {
    const newMessageCount = messages.length;
    const newMessages = newMessageCount - prevMessageCountRef.current;

    if (newMessages > 0 && !isNearBottom) {
      // User is reading history, increment unread count
      setUnreadCount((prev) => prev + newMessages);
    }

    prevMessageCountRef.current = newMessageCount;
  }, [messages.length, isNearBottom]);

  // Scroll to bottom on agent switch (messages array reference changes)
  const messagesRef = useRef(messages);
  useEffect(() => {
    // Check if this is a different agent's messages (array reference changed completely)
    const isAgentSwitch =
      messages !== messagesRef.current &&
      messages.length > 0 &&
      (messagesRef.current.length === 0 ||
        messages[0]?.id !== messagesRef.current[0]?.id);

    if (isAgentSwitch) {
      // Reset unread count and scroll to bottom for new agent
      setUnreadCount(0);
      prevMessageCountRef.current = messages.length;
      requestAnimationFrame(() => {
        scrollToBottom(false);
      });
    }

    messagesRef.current = messages;
  }, [messages, scrollToBottom]);

  if (messages.length === 0) {
    return (
      <div className="flex-1 flex items-center justify-center p-8">
        <div className="text-center max-w-md">
          <div className="w-16 h-16 rounded-full bg-muted flex items-center justify-center mx-auto mb-4">
            <MessageSquare className="h-8 w-8 text-muted-foreground" />
          </div>
          <h3 className="text-lg font-medium mb-2">Ready to work</h3>
          <p className="text-sm text-muted-foreground mb-6">
            Send a task to the supervisor agent. It will delegate work to specialized workers
            and coordinate the results.
          </p>
          {onSuggestionClick && (
            <div className="flex flex-wrap justify-center gap-2">
              {suggestions.map((suggestion) => (
                <button
                  key={suggestion}
                  onClick={() => onSuggestionClick(suggestion)}
                  className="px-3 py-1.5 text-sm bg-muted hover:bg-muted/80 rounded-full transition-colors"
                >
                  {suggestion}
                </button>
              ))}
            </div>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col relative overflow-hidden">
      <ScrollArea
        className="flex-1"
        viewportRef={viewportRef}
        onScroll={handleScroll}
      >
        <div className="p-4 space-y-4">
          {sortedMessages.map((message) => (
            <ChatMessage key={message.id} message={message} />
          ))}
          <div ref={bottomRef} />
        </div>
      </ScrollArea>

      {/* Scroll to bottom indicator with unread count - absolutely positioned outside ScrollArea */}
      {unreadCount > 0 && !isNearBottom && (
        <div className="absolute bottom-4 right-4 z-10">
          <Button
            variant="secondary"
            size="icon"
            onClick={() => scrollToBottom(true)}
            className="relative h-10 w-10 rounded-full shadow-lg animate-in fade-in slide-in-from-bottom-2 duration-200"
          >
            <ArrowDown className="h-5 w-5" />
            <Badge
              variant="destructive"
              className="absolute -top-2 -right-2 h-5 min-w-5 px-1.5 flex items-center justify-center"
            >
              {unreadCount > 99 ? '99+' : unreadCount}
            </Badge>
          </Button>
        </div>
      )}
    </div>
  );
}
