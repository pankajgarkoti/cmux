import { useState, useMemo, useEffect } from 'react';
import { ChevronRight, Bot, FolderOpen, RefreshCw, Inbox, Crown, Layers, Trash2, Pause, Play, Plus, MoreHorizontal, AlertCircle, Users, Archive, Mail, MessageSquare, ArrowRight } from 'lucide-react';
import { useMutation, useQueryClient, useQuery } from '@tanstack/react-query';
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
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  DropdownMenuSeparator,
} from '@/components/ui/dropdown-menu';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Textarea } from '@/components/ui/textarea';
import { useAgents } from '@/hooks/useAgents';
import { useAgentStore } from '@/stores/agentStore';
import { useViewerStore } from '@/stores/viewerStore';
import { useFilesystem, buildFileTree } from '@/hooks/useFilesystem';
import { FileTree, type FileTreeItem } from './FileTree';
import { api } from '@/lib/api';
import type { Agent, AgentStatus } from '@/types/agent';
import type { SessionStatus } from '@/types/session';
import type { Message } from '@/types/message';

interface SessionGroup {
  session: string;
  isMain: boolean;
  agents: Agent[];
  status?: SessionStatus;
}

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
  const [archivedOpen, setArchivedOpen] = useState(false);
  const [mailboxOpen, setMailboxOpen] = useState(true);
  const [memoryOpen, setMemoryOpen] = useState(true);
  const [createSessionOpen, setCreateSessionOpen] = useState(false);
  const [newSessionName, setNewSessionName] = useState('');
  const [newSessionTask, setNewSessionTask] = useState('');

  const { selectedAgentId, selectAgent, archivedAgents, setArchivedAgents, viewingArchivedId, viewArchive } = useAgentStore();
  const { selectedFile, setSelectedFile } = useViewerStore();
  const { data: agentsData, isLoading: agentsLoading, error: agentsError } = useAgents();
  const { data: filesystemData, isLoading: fsLoading, refetch: refetchFs } = useFilesystem();
  const queryClient = useQueryClient();

  // Fetch archived agents
  const { data: archivedData } = useQuery({
    queryKey: ['archivedAgents'],
    queryFn: () => api.getArchivedAgents(),
  });

  // Sync archived agents to store
  useEffect(() => {
    if (archivedData) {
      setArchivedAgents(archivedData);
    }
  }, [archivedData, setArchivedAgents]);

  const createSessionMutation = useMutation({
    mutationFn: (data: { name: string; task_description: string }) => api.createSession(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['agents'] });
      queryClient.invalidateQueries({ queryKey: ['sessions'] });
      setCreateSessionOpen(false);
      setNewSessionName('');
      setNewSessionTask('');
    },
  });

  const agents = agentsData?.agents || [];

  // Group agents by session
  const sessionGroups = useMemo((): SessionGroup[] => {
    const groups = new Map<string, Agent[]>();

    for (const agent of agents) {
      const session = agent.session || 'cmux';
      if (!groups.has(session)) {
        groups.set(session, []);
      }
      groups.get(session)!.push(agent);
    }

    // Sort agents within each group (supervisors first, then by name)
    for (const [, groupAgents] of groups) {
      groupAgents.sort((a, b) => {
        if (a.type === 'supervisor' && b.type !== 'supervisor') return -1;
        if (b.type === 'supervisor' && a.type !== 'supervisor') return 1;
        return a.name.localeCompare(b.name);
      });
    }

    // Convert to array, with main session first
    const result: SessionGroup[] = [];
    const mainSession = groups.get('cmux');
    if (mainSession) {
      result.push({ session: 'cmux', isMain: true, agents: mainSession });
      groups.delete('cmux');
    }

    // Add other sessions sorted by name
    const otherSessions = Array.from(groups.entries())
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([session, groupAgents]) => ({
        session,
        isMain: false,
        agents: groupAgents,
      }));

    return [...result, ...otherSessions];
  }, [agents]);

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
          <Dialog open={createSessionOpen} onOpenChange={setCreateSessionOpen}>
            <Collapsible open={agentsOpen} onOpenChange={setAgentsOpen}>
              <div className="flex items-center">
                <CollapsibleTrigger asChild>
                  <button className="flex-1 flex items-center gap-1 px-2 py-1.5 text-xs font-semibold uppercase tracking-wider text-sidebar-foreground/70 hover:text-sidebar-foreground">
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
                <Button
                  variant="ghost"
                  size="icon"
                  className="h-6 w-6 mr-1"
                  onClick={() => setCreateSessionOpen(true)}
                  title="Create new session"
                >
                  <Plus className="h-3 w-3" />
                </Button>
              </div>
            <CollapsibleContent className="mt-1">
              {/* All Agents - returns to overview showing all messages */}
              <button
                onClick={() => selectAgent(null)}
                className={cn(
                  'w-full flex items-center gap-2 px-3 py-1.5 text-sm rounded-md transition-colors text-left mb-2',
                  'hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
                  selectedAgentId === null && 'bg-sidebar-accent text-sidebar-accent-foreground'
                )}
              >
                <Users className="h-4 w-4 text-blue-500 flex-shrink-0" />
                <span className="truncate flex-1">All Agents</span>
                <Badge
                  variant="outline"
                  className={cn(
                    'text-[10px] h-4 px-1',
                    selectedAgentId === null ? 'border-blue-500/50 text-blue-600' : 'border-muted'
                  )}
                >
                  ALL
                </Badge>
              </button>

              {agentsLoading ? (
                <div className="space-y-2 px-2">
                  <Skeleton className="h-7 w-full" />
                  <Skeleton className="h-7 w-full" />
                </div>
              ) : agentsError ? (
                <p className="px-2 text-xs text-destructive">Failed to load agents</p>
              ) : sessionGroups.length === 0 ? (
                <p className="px-2 text-xs text-muted-foreground">No agents running</p>
              ) : (
                <div className="space-y-2">
                  {sessionGroups.map((group) => (
                    <SessionAgentGroup
                      key={group.session}
                      group={group}
                      selectedAgentId={selectedAgentId}
                      onSelectAgent={selectAgent}
                    />
                  ))}
                </div>
              )}
            </CollapsibleContent>
            </Collapsible>

            {/* Create Session Dialog */}
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Create New Session</DialogTitle>
                <DialogDescription>
                  Create a new orchestration session with its own supervisor agent.
                </DialogDescription>
              </DialogHeader>
              <div className="space-y-4 py-4">
                <div className="space-y-2">
                  <label className="text-sm font-medium">Session Name</label>
                  <Input
                    placeholder="feature-auth"
                    value={newSessionName}
                    onChange={(e) => setNewSessionName(e.target.value)}
                  />
                  <p className="text-xs text-muted-foreground">
                    Will be prefixed with "cmux-"
                  </p>
                </div>
                <div className="space-y-2">
                  <label className="text-sm font-medium">Task Description</label>
                  <Textarea
                    placeholder="Implement user authentication with JWT..."
                    value={newSessionTask}
                    onChange={(e) => setNewSessionTask(e.target.value)}
                    rows={3}
                  />
                </div>
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setCreateSessionOpen(false)}>
                  Cancel
                </Button>
                <Button
                  onClick={() => createSessionMutation.mutate({
                    name: newSessionName,
                    task_description: newSessionTask,
                  })}
                  disabled={createSessionMutation.isPending || !newSessionName || !newSessionTask}
                >
                  {createSessionMutation.isPending ? 'Creating...' : 'Create Session'}
                </Button>
              </DialogFooter>
              {createSessionMutation.isError && (
                <p className="text-sm text-red-500 mt-2">
                  {createSessionMutation.error?.message || 'Failed to create session'}
                </p>
              )}
            </DialogContent>
          </Dialog>

          {/* ARCHIVED WORKERS Section */}
          {archivedAgents.length > 0 && (
            <Collapsible open={archivedOpen} onOpenChange={setArchivedOpen} className="mt-4">
              <CollapsibleTrigger asChild>
                <button className="w-full flex items-center gap-1 px-2 py-1.5 text-xs font-semibold uppercase tracking-wider text-sidebar-foreground/70 hover:text-sidebar-foreground">
                  <ChevronRight
                    className={cn(
                      'h-3.5 w-3.5 transition-transform',
                      archivedOpen && 'rotate-90'
                    )}
                  />
                  <Archive className="h-3.5 w-3.5" />
                  <span>Archived</span>
                  <span className="ml-auto text-[10px] font-normal text-muted-foreground">
                    {archivedAgents.length}
                  </span>
                </button>
              </CollapsibleTrigger>
              <CollapsibleContent className="mt-1 space-y-0.5">
                {archivedAgents.map((archived) => (
                  <button
                    key={archived.id}
                    onClick={() => viewArchive(archived.id)}
                    className={cn(
                      'w-full flex items-center gap-2 px-3 py-1.5 text-sm rounded-md transition-colors text-left',
                      'hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
                      viewingArchivedId === archived.id && 'bg-sidebar-accent text-sidebar-accent-foreground'
                    )}
                  >
                    <Archive className="h-4 w-4 text-gray-400 flex-shrink-0" />
                    <span className="truncate flex-1">{archived.agent_name}</span>
                    <Badge
                      variant="outline"
                      className="text-[10px] h-4 px-1 border-gray-400/50 text-gray-500"
                    >
                      ARC
                    </Badge>
                  </button>
                ))}
              </CollapsibleContent>
            </Collapsible>
          )}

          {/* MAILBOX Section - Agent Communication */}
          <MailboxSection
            mailboxOpen={mailboxOpen}
            setMailboxOpen={setMailboxOpen}
            mailboxItem={mailboxItem}
            selectedFile={selectedFile}
            handleFileSelect={handleFileSelect}
          />

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
    </div>
  );
}

function SessionAgentGroup({
  group,
  selectedAgentId,
  onSelectAgent,
}: {
  group: SessionGroup;
  selectedAgentId: string | null;
  onSelectAgent: (id: string) => void;
}) {
  const [isOpen, setIsOpen] = useState(true);
  const [confirmTerminate, setConfirmTerminate] = useState(false);
  const queryClient = useQueryClient();

  const terminateMutation = useMutation({
    mutationFn: () => api.terminateSession(group.session),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['agents'] });
      queryClient.invalidateQueries({ queryKey: ['sessions'] });
      setConfirmTerminate(false);
    },
  });

  const pauseMutation = useMutation({
    mutationFn: () => api.pauseSession(group.session),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['sessions'] }),
  });

  const resumeMutation = useMutation({
    mutationFn: () => api.resumeSession(group.session),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['sessions'] }),
  });

  const isPaused = group.status === 'PAUSED';
  const isLoading = terminateMutation.isPending || pauseMutation.isPending || resumeMutation.isPending;

  // For main session, show agents directly without grouping header
  if (group.isMain) {
    return (
      <div className="space-y-0.5">
        <div className="flex items-center gap-1 px-2 py-1 text-xs text-muted-foreground">
          <Crown className="h-3 w-3 text-amber-500" />
          <span>Main Session</span>
        </div>
        {group.agents.map((agent) => (
          <AgentItem
            key={agent.id}
            agent={agent}
            isSelected={selectedAgentId === agent.id}
            onClick={() => onSelectAgent(agent.id)}
          />
        ))}
      </div>
    );
  }

  // For spawned sessions, show collapsible group with actions
  return (
    <Dialog open={confirmTerminate} onOpenChange={setConfirmTerminate}>
      <Collapsible open={isOpen} onOpenChange={setIsOpen}>
        <div className="flex items-center group">
          <CollapsibleTrigger asChild>
            <button className="flex-1 flex items-center gap-1 px-2 py-1 text-xs text-muted-foreground hover:text-foreground">
              <ChevronRight
                className={cn(
                  'h-3 w-3 transition-transform',
                  isOpen && 'rotate-90'
                )}
              />
              <Layers className="h-3 w-3" />
              <span className="truncate">{group.session.replace('cmux-', '')}</span>
              {isPaused && (
                <Badge variant="outline" className="text-[9px] h-3.5 px-1 ml-1 border-yellow-500/50 text-yellow-600">
                  PAUSED
                </Badge>
              )}
              <span className="ml-auto text-[10px]">{group.agents.length}</span>
            </button>
          </CollapsibleTrigger>

          {/* Session actions dropdown */}
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                className="h-5 w-5 opacity-0 group-hover:opacity-100 transition-opacity"
                disabled={isLoading}
              >
                <MoreHorizontal className="h-3 w-3" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-40">
              {isPaused ? (
                <DropdownMenuItem
                  onClick={() => resumeMutation.mutate()}
                  disabled={resumeMutation.isPending}
                >
                  <Play className="h-3.5 w-3.5 mr-2 text-green-500" />
                  Resume
                </DropdownMenuItem>
              ) : (
                <DropdownMenuItem
                  onClick={() => pauseMutation.mutate()}
                  disabled={pauseMutation.isPending}
                >
                  <Pause className="h-3.5 w-3.5 mr-2 text-yellow-500" />
                  Pause
                </DropdownMenuItem>
              )}
              <DropdownMenuSeparator />
              <DropdownMenuItem
                onClick={() => setConfirmTerminate(true)}
                className="text-red-600 focus:text-red-600"
              >
                <Trash2 className="h-3.5 w-3.5 mr-2" />
                Terminate
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>

        <CollapsibleContent className="ml-2 space-y-0.5">
          {group.agents.map((agent) => (
            <AgentItem
              key={agent.id}
              agent={agent}
              isSelected={selectedAgentId === agent.id}
              onClick={() => onSelectAgent(agent.id)}
            />
          ))}
        </CollapsibleContent>
      </Collapsible>

      {/* Terminate confirmation dialog */}
      <DialogContent>
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <AlertCircle className="h-5 w-5 text-red-500" />
            Terminate Session
          </DialogTitle>
          <DialogDescription>
            Are you sure you want to terminate <strong>{group.session}</strong>?
            This will gracefully stop all {group.agents.length} agent(s) in this session.
          </DialogDescription>
        </DialogHeader>
        <DialogFooter>
          <Button variant="outline" onClick={() => setConfirmTerminate(false)}>
            Cancel
          </Button>
          <Button
            variant="destructive"
            onClick={() => terminateMutation.mutate()}
            disabled={terminateMutation.isPending}
          >
            {terminateMutation.isPending ? 'Terminating...' : 'Terminate'}
          </Button>
        </DialogFooter>
        {terminateMutation.isError && (
          <p className="text-sm text-red-500 mt-2">
            {terminateMutation.error?.message || 'Failed to terminate session'}
          </p>
        )}
      </DialogContent>
    </Dialog>
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

function MailboxSection({
  mailboxOpen,
  setMailboxOpen,
  mailboxItem,
  selectedFile,
  handleFileSelect,
}: {
  mailboxOpen: boolean;
  setMailboxOpen: (open: boolean) => void;
  mailboxItem: FileTreeItem | undefined;
  selectedFile: FileTreeItem | null;
  handleFileSelect: (item: FileTreeItem) => void;
}) {
  const { data: messagesData, isLoading } = useQuery({
    queryKey: ['mailboxMessages'],
    queryFn: () => api.getMailboxMessages(10),
    refetchInterval: 5000, // Refresh every 5 seconds
  });

  const recentMessages = messagesData?.messages || [];
  const messageCount = recentMessages.length;

  // Extract subject from content (before "(see:" if present)
  const parseSubject = (content: string) => {
    const seeIdx = content.indexOf(' (see:');
    if (seeIdx > 0) return content.substring(0, seeIdx);
    return content;
  };

  return (
    <Collapsible open={mailboxOpen} onOpenChange={setMailboxOpen} className="mt-4">
      <CollapsibleTrigger asChild>
        <button className="w-full flex items-center gap-1 px-2 py-1.5 text-xs font-semibold uppercase tracking-wider text-sidebar-foreground/70 hover:text-sidebar-foreground">
          <ChevronRight
            className={cn(
              'h-3.5 w-3.5 transition-transform',
              mailboxOpen && 'rotate-90'
            )}
          />
          <Mail className="h-3.5 w-3.5" />
          <span className="flex-1 text-left">Mailbox</span>
          {messageCount > 0 && (
            <Badge
              variant="secondary"
              className="h-5 px-1.5 text-xs bg-blue-500/20 text-blue-400 animate-pulse"
            >
              {messageCount}
            </Badge>
          )}
        </button>
      </CollapsibleTrigger>
      <CollapsibleContent className="mt-1 space-y-0.5">
        {/* View raw mailbox file */}
        {mailboxItem && (
          <button
            onClick={() => handleFileSelect(mailboxItem)}
            className={cn(
              'w-full flex items-center gap-2 px-3 py-1.5 text-sm rounded-md transition-colors text-left',
              'hover:bg-sidebar-accent hover:text-sidebar-accent-foreground',
              selectedFile?.path === mailboxItem.path && 'bg-sidebar-accent text-sidebar-accent-foreground'
            )}
          >
            <Inbox className="h-4 w-4 text-blue-500 flex-shrink-0" />
            <span className="truncate">View Raw Mailbox</span>
          </button>
        )}

        {/* Recent messages */}
        {isLoading ? (
          <div className="px-3 py-2">
            <Skeleton className="h-4 w-full" />
          </div>
        ) : recentMessages.length > 0 ? (
          <div className="space-y-0.5 pt-1">
            {recentMessages.slice(0, 5).map((msg: Message) => (
              <div
                key={msg.id}
                className="w-full flex items-start gap-2 px-3 py-1.5 text-xs rounded-md hover:bg-sidebar-accent/50"
              >
                <MessageSquare className="h-3.5 w-3.5 text-blue-400 flex-shrink-0 mt-0.5" />
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-1 text-muted-foreground">
                    <span className="font-medium text-foreground/80">{msg.from_agent}</span>
                    <ArrowRight className="h-2.5 w-2.5" />
                    <span className="font-medium text-foreground/80">{msg.to_agent}</span>
                  </div>
                  <p className="truncate text-muted-foreground mt-0.5">
                    {parseSubject(msg.content)}
                  </p>
                </div>
              </div>
            ))}
          </div>
        ) : (
          <p className="px-3 py-2 text-xs text-muted-foreground">
            No recent agent messages
          </p>
        )}
      </CollapsibleContent>
    </Collapsible>
  );
}
