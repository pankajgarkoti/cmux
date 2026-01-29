import { useQuery } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Skeleton } from '@/components/ui/skeleton';
import { X, BookOpen, FileCode, File } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { useViewerStore, type ViewerFile } from '@/stores/viewerStore';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';

interface MemoryViewerProps {
  file: ViewerFile;
}

export function MemoryViewer({ file }: MemoryViewerProps) {
  const { clearSelectedFile } = useViewerStore();

  const { data: content, isLoading } = useQuery({
    queryKey: ['file-content', file.path],
    queryFn: () => api.getFileContent(file.path),
    enabled: !!file,
    staleTime: 5000,
  });

  const isStatusLog = file.name === 'status.log';
  const isMarkdown = file.name.endsWith('.md');
  const isJournalEntry = file.path.includes('/journal/');
  const isJson = file.name.endsWith('.json');

  const getFileIcon = () => {
    if (isMarkdown || isJournalEntry) return <BookOpen className="h-4 w-4" />;
    if (isJson || isStatusLog) return <FileCode className="h-4 w-4" />;
    return <File className="h-4 w-4" />;
  };

  const getFileType = () => {
    if (isJournalEntry) return 'Journal Entry';
    if (isMarkdown) return 'Markdown';
    if (isJson) return 'JSON';
    if (isStatusLog) return 'Log';
    return 'File';
  };

  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="px-4 py-3 border-b flex items-center justify-between bg-muted/30">
        <div className="flex items-center gap-3 min-w-0">
          <div className="flex items-center justify-center h-8 w-8 rounded-md bg-primary/10 text-primary">
            {getFileIcon()}
          </div>
          <div className="min-w-0">
            <h2 className="text-sm font-semibold truncate">{file.name}</h2>
            <p className="text-xs text-muted-foreground">{getFileType()}</p>
          </div>
        </div>
        <Button variant="ghost" size="icon" className="h-8 w-8 flex-shrink-0" onClick={clearSelectedFile}>
          <X className="h-4 w-4" />
          <span className="sr-only">Close</span>
        </Button>
      </div>

      {/* Content */}
      <ScrollArea className="flex-1">
        <div className="p-6">
          {isLoading ? (
            <div className="space-y-3">
              <Skeleton className="h-6 w-3/4" />
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-2/3" />
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-1/2" />
            </div>
          ) : isMarkdown || isJournalEntry ? (
            <MarkdownViewer content={content || ''} />
          ) : isStatusLog ? (
            <StatusLogViewer content={content || ''} />
          ) : isJson ? (
            <JsonViewer content={content || ''} />
          ) : (
            <pre className="text-sm font-mono whitespace-pre-wrap text-muted-foreground">
              {content || 'Empty file'}
            </pre>
          )}
        </div>
      </ScrollArea>
    </div>
  );
}

function MarkdownViewer({ content }: { content: string }) {
  return (
    <article className="prose prose-sm dark:prose-invert max-w-none prose-headings:font-semibold prose-h1:text-2xl prose-h2:text-xl prose-h3:text-lg prose-p:text-muted-foreground prose-li:text-muted-foreground prose-code:bg-muted prose-code:px-1 prose-code:py-0.5 prose-code:rounded prose-pre:bg-muted prose-pre:border">
      <ReactMarkdown remarkPlugins={[remarkGfm]}>{content}</ReactMarkdown>
    </article>
  );
}

function StatusLogViewer({ content }: { content: string }) {
  if (!content.trim()) {
    return <p className="text-sm text-muted-foreground">No log entries</p>;
  }

  return (
    <pre className="text-xs font-mono whitespace-pre overflow-x-auto text-muted-foreground bg-muted/50 p-4 rounded-lg border">
      {content}
    </pre>
  );
}

function JsonViewer({ content }: { content: string }) {
  let formatted = content;
  try {
    formatted = JSON.stringify(JSON.parse(content), null, 2);
  } catch {
    // Keep original if not valid JSON
  }

  return (
    <pre className="text-xs font-mono whitespace-pre overflow-x-auto text-muted-foreground bg-muted/50 p-4 rounded-lg border">
      {formatted}
    </pre>
  );
}
