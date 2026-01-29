import { useState, useCallback } from 'react';
import { useMutation } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { useMessages } from '@/hooks/useMessages';
import { useAgentStore } from '@/stores/agentStore';
import { useViewerStore } from '@/stores/viewerStore';
import { useAgents } from '@/hooks/useAgents';
import { ChatMessages } from './ChatMessages';
import { ChatInput } from './ChatInput';
import { WorkerConfirmModal } from './WorkerConfirmModal';
import { MemoryViewer } from '@/components/explorer/MemoryViewer';

export function ChatPanel() {
  const { selectedAgentId } = useAgentStore();
  const { selectedFile, clearSelectedFile } = useViewerStore();
  const { data: messagesData } = useMessages();
  const { data: agentsData } = useAgents();

  // Worker confirmation modal state
  const [showWorkerConfirm, setShowWorkerConfirm] = useState(false);
  const [pendingMessage, setPendingMessage] = useState<string | null>(null);

  // Filter messages for selected agent or show all if none selected
  const allMessages = messagesData?.messages || [];
  const messages = selectedAgentId
    ? allMessages.filter(
        (m) => m.from_agent === selectedAgentId || m.to_agent === selectedAgentId
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

  // If a file is selected, show the file viewer instead of chat
  if (selectedFile) {
    return (
      <div className="h-full flex flex-col">
        <MemoryViewer file={selectedFile} onClose={clearSelectedFile} />
      </div>
    );
  }

  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="px-4 pt-4 pb-2 border-b">
        <h2 className="text-lg font-semibold">Command Center</h2>
        <p className="text-xs text-muted-foreground">
          {selectedAgentId
            ? `Chatting with ${selectedAgentId}${isWorker ? ' (Worker)' : ''}`
            : 'Send tasks to the supervisor agent'}
        </p>
      </div>

      {/* Chat Content */}
      <ChatMessages
        messages={messages}
        onSuggestionClick={handleSuggestionClick}
      />
      <ChatInput
        onSend={handleSend}
        isPending={sendMutation.isPending}
        placeholder={`Message ${targetAgent}...`}
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
