import { useMutation } from '@tanstack/react-query';
import { api } from '@/lib/api';
import { useMessages } from '@/hooks/useMessages';
import { useAgentStore } from '@/stores/agentStore';
import { ChatMessages } from './ChatMessages';
import { ChatInput } from './ChatInput';

export function ChatPanel() {
  const { selectedAgentId } = useAgentStore();
  const { data: messagesData } = useMessages();

  // Filter messages for selected agent or show all if none selected
  const allMessages = messagesData?.messages || [];
  const messages = selectedAgentId
    ? allMessages.filter(
        (m) => m.from_agent === selectedAgentId || m.to_agent === selectedAgentId
      )
    : allMessages;

  const targetAgent = selectedAgentId || 'supervisor';

  const sendMutation = useMutation({
    mutationFn: (content: string) => api.sendMessageToAgent(targetAgent, content),
  });

  const handleSend = (message: string) => {
    sendMutation.mutate(message);
  };

  const handleSuggestionClick = (text: string) => {
    handleSend(text);
  };

  return (
    <div className="h-full flex flex-col">
      {/* Header */}
      <div className="px-4 pt-4 pb-2 border-b">
        <h2 className="text-lg font-semibold">Command Center</h2>
        <p className="text-xs text-muted-foreground">
          {selectedAgentId
            ? `Chatting with ${selectedAgentId}`
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
    </div>
  );
}
