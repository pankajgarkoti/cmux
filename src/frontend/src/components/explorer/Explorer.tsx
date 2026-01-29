import { useState } from 'react';
import { ChevronRight, Bot, FolderOpen, RefreshCw, Inbox, Crown } from 'lucide-react';
import { cn } from '@/lib/utils';
import { ScrollArea } from '@/components/ui/scroll-area';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { Badge } from '@/components/ui/badge';
import {
  Collapsible,
  CollapsibleContent,
  CollapsibleTrigger,
} from '@/components/ui/collapsible';
import { useAgents } from '@/hooks/useAgents';
import { useAgentStore } from '@/stores/agentStore';
import { useFilesystem, buildFileTree } from '@/hooks/useFilesystem';
import { FileTree, type FileTreeItem } from './FileTree';
import { MemoryViewer } from './MemoryViewer';
import type { Agent, AgentStatus } from '@/types/agent';

const statusColors: Record<AgentStatus, string> = {
  PENDING: 'bg-gray-400',
  IN_PROGRESS: 'bg-blue-500',
  BLOCKED: 'bg-red-500',
  TESTING: 'bg-yellow-500',
  COMPLETE: 'bg-green-500',
  FAILED: 'bg-red-600',
  IDLE: 'bg-gray-300',
};

export function Explorer() {
  const [agentsOpen, setAgentsOpen] = useState(true);
  const [mailboxOpen, setMailboxOpen] = useState(true);
  const [memoryOpen, setMemoryOpen] = useState(true);
  const [selectedFile, setSelectedFile] = useState<FileTreeItem | null>(null);

  const { selectedAgentId, selectAgent } = useAgentStore();
  const { data: agentsData, isLoading: agentsLoading, error: agentsError } = useAgents();
  const { data: filesystemData, isLoading: fsLoading, refetch: refetchFs } = useFilesystem();

  const agents = agentsData?.agents || [];
  const sortedAgents = [...agents].sort((a, b) => {
    if (a.type === 'supervisor') return -1;
    if (b.type === 'supervisor') return 1;
    return a.name.localeCompare(b.name);
  });

  // Build file tree and separate mailbox
  const allItems: FileTreeItem[] = filesystemData?.items
    ? buildFileTree(filesystemData.items).map((item) => ({
        name: item.name,
        path: item.path,
        type: item.type,
        children: item.children?.map((child) => ({
          name: child.name,
          path: child.path,
          type: child.type,
          children: child.children?.map((c) => ({
            name: c.name,
            path: c.path,
            type: c.type,
          })),
        })),
      }))
    : [];

  const mailboxItem = allItems.find(item => item.name === 'mailbox');
  const fileTree = allItems.filter(item => item.name !== 'mailbox');

  const handleFileSelect = (item: FileTreeItem) => {
    if (item.type === 'file') {
      setSelectedFile(item);
    }
  };

  return (
    <div className="h-full flex flex-col">
      <ScrollArea className="flex-1">
        <div className="p-2">
          {/* AGENTS Section */}
          <Collapsible open={agentsOpen} onOpenChange={setAgentsOpen}>
            <CollapsibleTrigger asChild>
              <button className="w-full flex items-center gap-1 px-2 py-1.5 text-xs font-semibold uppercase tracking-wider text-sidebar-foreground/70 hover:text-sidebar-foreground">
                <ChevronRight
                  className={cn(
                    'h-3.5 w-3.5 transition-transform',
                    agentsOpen && 'rotate-90'
                  )}
                />
                <Bot className="h-3.5 w-3.5" />
                <span>Agents</span>
                <span className="ml-auto text-[10px] font-normal text-muted-foreground">
                  {agents.length}
                </span>
              </button>
            </CollapsibleTrigger>
            <CollapsibleContent className="mt-1">
              {agentsLoading ? (
                <div className="space-y-2 px-2">
                  <Skeleton className="h-7 w-full" />
                  <Skeleton className="h-7 w-full" />
                </div>
              ) : agentsError ? (
                <p className="px-2 text-xs text-destructive">Failed to load agents</p>
              ) : sortedAgents.length === 0 ? (
                <p className="px-2 text-xs text-muted-foreground">No agents running</p>
              ) : (
                <div className="space-y-0.5">
                  {sortedAgents.map((agent) => (
                    <AgentItem
                      key={agent.id}
                      agent={agent}
                      isSelected={selectedAgentId === agent.id}
                      onClick={() => selectAgent(agent.id)}
                    />
                  ))}
                </div>
              )}
            </CollapsibleContent>
          </Collapsible>

          {/* MAILBOX Section */}
          {mailboxItem && (
            <Collapsible open={mailboxOpen} onOpenChange={setMailboxOpen} className="mt-4">
              <CollapsibleTrigger asChild>
                <button className="w-full flex items-center gap-1 px-2 py-1.5 text-xs font-semibold uppercase tracking-wider text-sidebar-foreground/70 hover:text-sidebar-foreground">
                  <ChevronRight
                    className={cn(
                      'h-3.5 w-3.5 transition-transform',
                      mailboxOpen && 'rotate-90'
                    )}
                  />
                  <Inbox className="h-3.5 w-3.5" />
                  <span>Mailbox</span>
                </button>
              </CollapsibleTrigger>
              <CollapsibleContent className="mt-1">
                <button
                  onClick={() => handleFileSelect(mailboxItem)}
                  className={cn(
                    'w-full flex items-center gap-2 px-3 py-1.5 text-sm rounded-md transition-colors text-left',
                    'hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
                    selectedFile?.path === mailboxItem.path && 'bg-sidebar-accent text-sidebar-accent-foreground'
                  )}
                >
                  <Inbox className="h-4 w-4 text-blue-500 flex-shrink-0" />
                  <span className="truncate">Pending Messages</span>
                </button>
              </CollapsibleContent>
            </Collapsible>
          )}

          {/* MEMORY Section */}
          <Collapsible open={memoryOpen} onOpenChange={setMemoryOpen} className="mt-4">
            <div className="flex items-center">
              <CollapsibleTrigger asChild>
                <button className="flex-1 flex items-center gap-1 px-2 py-1.5 text-xs font-semibold uppercase tracking-wider text-sidebar-foreground/70 hover:text-sidebar-foreground">
                  <ChevronRight
                    className={cn(
                      'h-3.5 w-3.5 transition-transform',
                      memoryOpen && 'rotate-90'
                    )}
                  />
                  <FolderOpen className="h-3.5 w-3.5" />
                  <span>Memory</span>
                </button>
              </CollapsibleTrigger>
              <Button
                variant="ghost"
                size="icon"
                className="h-6 w-6 mr-1"
                onClick={() => refetchFs()}
                title="Refresh"
              >
                <RefreshCw className="h-3 w-3" />
              </Button>
            </div>
            <CollapsibleContent className="mt-1">
              {fsLoading ? (
                <div className="space-y-2 px-2">
                  <Skeleton className="h-5 w-full" />
                  <Skeleton className="h-5 w-3/4" />
                  <Skeleton className="h-5 w-1/2" />
                </div>
              ) : fileTree.length === 0 ? (
                <p className="px-2 text-xs text-muted-foreground">
                  No .cmux directory found
                </p>
              ) : (
                <FileTree
                  items={fileTree}
                  onFileSelect={handleFileSelect}
                  selectedPath={selectedFile?.path}
                />
              )}
            </CollapsibleContent>
          </Collapsible>
        </div>
      </ScrollArea>

      {/* Memory Viewer (when file selected) */}
      {selectedFile && (
        <MemoryViewer file={selectedFile} onClose={() => setSelectedFile(null)} />
      )}
    </div>
  );
}

function AgentItem({
  agent,
  isSelected,
  onClick
}: {
  agent: Agent;
  isSelected: boolean;
  onClick: () => void;
}) {
  const isSupervisor = agent.type === 'supervisor';

  return (
    <button
      onClick={onClick}
      className={cn(
        'w-full flex items-center gap-2 px-3 py-1.5 text-sm rounded-md transition-colors text-left',
        'hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
        isSelected && 'bg-sidebar-accent text-sidebar-accent-foreground'
      )}
    >
      <span
        className={cn('w-2 h-2 rounded-full flex-shrink-0', statusColors[agent.status])}
        title={agent.status}
      />
      {isSupervisor ? (
        <Crown className="h-4 w-4 text-amber-500 flex-shrink-0" />
      ) : (
        <Bot className="h-4 w-4 text-muted-foreground flex-shrink-0" />
      )}
      <span className="truncate flex-1">{agent.name}</span>
      <Badge
        variant="outline"
        className={cn(
          'text-[10px] h-4 px-1',
          isSupervisor ? 'border-amber-500/50 text-amber-600' : 'border-muted'
        )}
      >
        {isSupervisor ? 'SUP' : 'WRK'}
      </Badge>
    </button>
  );
}
