import { useState, useCallback, useRef } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { useMessages } from '@/hooks/useMessages';
import { useAgentStore } from '@/stores/agentStore';
import { useViewerStore } from '@/stores/viewerStore';
import { useAgents } from '@/hooks/useAgents';
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
  const { data: messagesData } = useMessages();
  const { data: agentsData } = useAgents();
  const queryClient = useQueryClient();

  // Worker confirmation modal state
  const [showWorkerConfirm, setShowWorkerConfirm] = useState(false);
  const [pendingMessage, setPendingMessage] = useState<string | null>(null);

  // Input ref for keyboard shortcuts
  const inputRef = useRef<HTMLTextAreaElement>(null);

  // Filter messages for selected agent: show only user <-> agent conversation
  const allMessages = messagesData?.messages || [];
  const messages = selectedAgentId
    ? allMessages.filter(
        (m) =>
          (m.from_agent === selectedAgentId && m.to_agent === 'user') ||
          (m.from_agent === 'user' && m.to_agent === selectedAgentId)
      )
    : allMessages;

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
