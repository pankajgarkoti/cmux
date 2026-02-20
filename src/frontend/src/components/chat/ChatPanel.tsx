import { useState, useCallback, useRef, useMemo } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { useMessages } from '@/hooks/useMessages';
import { useAgentStore } from '@/stores/agentStore';
import { useViewerStore } from '@/stores/viewerStore';
import { useProjectStore } from '@/stores/projectStore';
import { useAgents } from '@/hooks/useAgents';
import { useProjectAgents } from '@/hooks/useProjects';
import { useChatKeyboard } from '@/hooks/useChatKeyboard';
import { ChatMessages } from './ChatMessages';
import { ChatInput } from './ChatInput';
import { ChatHeader } from './ChatHeader';
import { AgentActivityIndicator } from './AgentActivityIndicator';
import { WorkerConfirmModal } from './WorkerConfirmModal';
import { ArchivedAgentView } from './ArchivedAgentView';
import { MemoryViewer } from '@/components/explorer/MemoryViewer';

export function ChatPanel() {
  const { selectedAgentId, viewingArchivedId } = useAgentStore();
  const { selectedFile } = useViewerStore();
  const { selectedProjectId } = useProjectStore();
  const { data: messagesData } = useMessages();
  const { data: agentsData } = useAgents();
  const { data: projectAgentsData } = useProjectAgents(selectedProjectId);
  const queryClient = useQueryClient();

  // Worker confirmation modal state
  const [showWorkerConfirm, setShowWorkerConfirm] = useState(false);
  const [pendingMessage, setPendingMessage] = useState<string | null>(null);

  // Input ref for keyboard shortcuts
  const inputRef = useRef<HTMLTextAreaElement>(null);

  // Build set of agent IDs for the selected project
  const projectAgentIds = useMemo(() => {
    if (!selectedProjectId || !projectAgentsData?.agents) return null;
    return new Set(projectAgentsData.agents.map(a => a.key));
  }, [selectedProjectId, projectAgentsData]);

  // Filter messages for selected agent: show only user <-> agent conversation
  // Also filter by project when a project is selected
  const allMessages = messagesData?.messages || [];
  const messages = useMemo(() => {
    let filtered = allMessages;

    // Filter by project (if selected)
    if (projectAgentIds) {
      filtered = filtered.filter(
        (m) => projectAgentIds.has(m.from_agent) || projectAgentIds.has(m.to_agent)
      );
    }

    // Filter by specific agent (if selected)
    if (selectedAgentId) {
      if (selectedAgentId === 'supervisor') {
        // Main supervisor: keep user<->supervisor filter (established pattern)
        filtered = filtered.filter(
          (m) =>
            (m.from_agent === selectedAgentId && m.to_agent === 'user') ||
            (m.from_agent === 'user' && m.to_agent === selectedAgentId)
        );
      } else {
        // All other agents: show all messages involving this agent
        filtered = filtered.filter(
          (m) => m.from_agent === selectedAgentId || m.to_agent === selectedAgentId
        );
      }
    }

    return filtered;
  }, [allMessages, selectedAgentId, projectAgentIds]);

  const targetAgent = selectedAgentId || 'supervisor';

  // Check if the selected agent is a worker
  const selectedAgent = agentsData?.agents?.find((a) => a.id === selectedAgentId);
  const isWorker = selectedAgent?.type === 'worker';

  const sendMutation = useMutation({
    mutationFn: (content: string) => api.sendMessageToAgent(targetAgent, content),
  });

  const handleSendDirect = useCallback((message: string) => {
    sendMutation.mutate(message);
    setPendingMessage(null);
  }, [sendMutation]);

  const handleSend = useCallback((message: string) => {
    // If sending to a worker, show confirmation modal
    if (isWorker) {
      setPendingMessage(message);
      setShowWorkerConfirm(true);
    } else {
      handleSendDirect(message);
    }
  }, [isWorker, handleSendDirect]);

  const handleWorkerConfirm = useCallback(() => {
    if (pendingMessage) {
      handleSendDirect(pendingMessage);
    }
    setShowWorkerConfirm(false);
  }, [pendingMessage, handleSendDirect]);

  const handleSuggestionClick = (text: string) => {
    handleSend(text);
  };

  const handleClearChat = useCallback(() => {
    // For now, just invalidate the messages query to refresh
    // In a full implementation, this could call an API to clear messages
    queryClient.invalidateQueries({ queryKey: ['messages'] });
  }, [queryClient]);

  // Keyboard shortcuts
  useChatKeyboard({
    inputRef,
    onSend: () => {
      // The ChatInput component handles its own Enter key,
      // but Cmd+Enter from anywhere should trigger send
      const textarea = inputRef.current;
      if (textarea && textarea.value.trim()) {
        handleSend(textarea.value.trim());
        textarea.value = '';
      }
    },
    enabled: !selectedFile,
  });

  // If a file is selected, show the file viewer instead of chat
  if (selectedFile) {
    return (
      <div className="h-full flex flex-col">
        <MemoryViewer file={selectedFile} />
      </div>
    );
  }

  // If viewing an archived agent, show the archive view
  if (viewingArchivedId) {
    return <ArchivedAgentView archiveId={viewingArchivedId} />;
  }

  return (
    <div className="h-full flex flex-col">
      {/* Enhanced Header */}
      <ChatHeader
        agentId={selectedAgentId}
        agent={selectedAgent}
        isWorker={isWorker}
        onClearChat={handleClearChat}
      />

      {/* Chat Content */}
      <ChatMessages
        messages={messages}
        onSuggestionClick={handleSuggestionClick}
      />

      {/* Activity Indicator - shows when agent is working */}
      <AgentActivityIndicator agentId={targetAgent} />

      {/* Input */}
      <ChatInput
        onSend={handleSend}
        isPending={sendMutation.isPending}
        placeholder={`Message ${targetAgent}...`}
        inputRef={inputRef}
        agents={agentsData?.agents || []}
      />
      {sendMutation.isError && (
        <p className="px-4 pb-2 text-sm text-destructive">
          Failed to send message. Please try again.
        </p>
      )}

      {/* Worker Confirmation Modal */}
      <WorkerConfirmModal
        open={showWorkerConfirm}
        onOpenChange={setShowWorkerConfirm}
        agentName={selectedAgent?.name || targetAgent}
        onConfirm={handleWorkerConfirm}
      />
    </div>
  );
}
