import { useState, useRef, useEffect, type Ref } from 'react';
import { Textarea } from '@/components/ui/textarea';
import { Button } from '@/components/ui/button';
import { Send, Loader2 } from 'lucide-react';
import { cn } from '@/lib/utils';

interface ChatInputProps {
  onSend: (message: string) => void;
  isPending?: boolean;
  placeholder?: string;
  inputRef?: Ref<HTMLTextAreaElement>;
}

export function ChatInput({ onSend, isPending, placeholder, inputRef }: ChatInputProps) {
  const [message, setMessage] = useState('');
  const internalRef = useRef<HTMLTextAreaElement>(null);

  // Use effect to sync internal ref with external ref
  useEffect(() => {
    if (inputRef && typeof inputRef === 'object' && 'current' in inputRef && internalRef.current) {
      (inputRef as React.MutableRefObject<HTMLTextAreaElement | null>).current = internalRef.current;
    }
  }, [inputRef]);

  const textareaRef = internalRef;

  // Auto-resize textarea
  useEffect(() => {
    const textarea = textareaRef.current;
    if (textarea) {
      textarea.style.height = 'auto';
      textarea.style.height = `${Math.min(textarea.scrollHeight, 200)}px`;
    }
  }, [message]);

  const handleSubmit = () => {
    const trimmed = message.trim();
    if (trimmed && !isPending) {
      onSend(trimmed);
      setMessage('');
      // Reset height after sending
      if (textareaRef.current) {
        textareaRef.current.style.height = 'auto';
      }
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      handleSubmit();
    }
  };

  return (
    <div className="p-4 border-t bg-background/50 backdrop-blur-sm">
      <div className="flex gap-2 items-end">
        <Textarea
          ref={textareaRef}
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          onKeyDown={handleKeyDown}
          placeholder={placeholder || 'Type a message... (Enter to send, Shift+Enter for new line)'}
          disabled={isPending}
          className={cn(
            'min-h-[44px] max-h-[200px] resize-none',
            'bg-muted/50 border-muted-foreground/20',
            'focus-visible:ring-1 focus-visible:ring-primary'
          )}
          rows={1}
        />
        <Button
          onClick={handleSubmit}
          disabled={!message.trim() || isPending}
          size="icon"
          className="h-11 w-11 flex-shrink-0"
        >
          {isPending ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Send className="h-4 w-4" />
          )}
        </Button>
      </div>
      <p className="text-[10px] text-muted-foreground mt-1.5 text-center">
        Press Enter to send, Shift+Enter for new line
      </p>
    </div>
  );
}
