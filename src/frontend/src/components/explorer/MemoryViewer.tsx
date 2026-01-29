import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Skeleton } from '@/components/ui/skeleton';
import { FileText, X } from 'lucide-react';
import { Button } from '@/components/ui/button';
import type { FileTreeItem } from './FileTree';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

interface MemoryViewerProps {
  file: FileTreeItem | null;
  onClose: () => void;
}

export function MemoryViewer({ file, onClose }: MemoryViewerProps) {
  const { data: content, isLoading } = useQuery({
    queryKey: ['file-content', file?.path],
    queryFn: () => api.getFileContent(file!.path),
    enabled: !!file,
    staleTime: 5000,
  });

  if (!file) {
    return (
      <div className="flex-1 flex items-center justify-center text-muted-foreground text-sm">
        <FileText className="h-8 w-8 mr-2 opacity-30" />
        Select a file to view
      </div>
    );
  }

  const isStatusLog = file.name === 'status.log';
  const isMarkdown = file.name.endsWith('.md');
  const isJournalEntry = file.path.includes('/journal/');

  return (
    <div className="flex-1 flex flex-col border-l overflow-hidden">
      {/* Header */}
      <div className="px-3 py-2 border-b bg-muted/30 flex items-center justify-between flex-shrink-0">
        <div className="flex items-center gap-2 min-w-0">
          <FileText className="h-4 w-4 text-muted-foreground flex-shrink-0" />
          <span className="text-sm font-medium truncate">{file.name}</span>
        </div>
        <Button variant="ghost" size="icon" className="h-6 w-6" onClick={onClose}>
          <X className="h-4 w-4" />
        </Button>
      </div>

      {/* Content */}
      {isStatusLog ? (
        <div className="flex-1 min-h-0 p-3" style={{ position: 'relative' }}>
          <div style={{ position: 'absolute', inset: 0, overflow: 'auto', padding: '0.75rem' }}>
            {isLoading ? (
              <div className="space-y-2">
                <Skeleton className="h-4 w-full" />
                <Skeleton className="h-4 w-3/4" />
                <Skeleton className="h-4 w-1/2" />
              </div>
            ) : (
              <StatusLogViewer content={content || ''} />
            )}
          </div>
        </div>
      ) : (
        <ScrollArea className="flex-1">
          <div className="p-3">
            {isLoading ? (
              <div className="space-y-2">
                <Skeleton className="h-4 w-full" />
                <Skeleton className="h-4 w-3/4" />
                <Skeleton className="h-4 w-1/2" />
              </div>
            ) : isMarkdown || isJournalEntry ? (
              <MarkdownViewer content={content || ''} />
            ) : (
              <pre className="text-xs font-mono whitespace-pre-wrap text-muted-foreground">
                {content || 'Empty file'}
              </pre>
            )}
          </div>
        </ScrollArea>
      )}
    </div>
  );
}

function StatusLogViewer({ content }: { content: string }) {
  if (!content.trim()) {
    return <p className="text-sm text-muted-foreground">No log entries</p>;
  }

  // Render as preformatted text with horizontal scroll
  return (
    <pre className="text-xs font-mono whitespace-pre text-muted-foreground">
      {content}
    </pre>
  );
}

function MarkdownViewer({ content }: { content: string }) {
  return (
    <div className="prose prose-sm dark:prose-invert max-w-none">
      <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
    </div>
  );
}
