import { useEffect, useRef, useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useConnectionStore } from '../stores/connectionStore';
import { useActivityStore } from '../stores/activityStore';
import { useAgentEventStore } from '../stores/agentEventStore';
import { useSessionStore } from '../stores/sessionStore';
import { useAgentStore } from '../stores/agentStore';
import { useThoughtStore } from '../stores/thoughtStore';
import { WS_URL, RECONNECT_DELAY_BASE, RECONNECT_DELAY_MAX } from '../lib/constants';
import type { Activity } from '../types/activity';
import type { AgentEvent } from '../types/agent_event';

export function useWebSocket() {
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<number>();
  const reconnectAttemptRef = useRef<number>(0);
  const queryClient = useQueryClient();

  const { setConnected, setReconnecting } = useConnectionStore();
  const { addActivity } = useActivityStore();
  const { addEvent } = useAgentEventStore();
  const { addSession, removeSession, updateSession } = useSessionStore();
  const { addArchivedAgent, viewArchive, selectedAgentId } = useAgentStore();
  const { addThought } = useThoughtStore();

  // Calculate delay with exponential backoff
  const getReconnectDelay = useCallback(() => {
    const delay = Math.min(
      RECONNECT_DELAY_BASE * Math.pow(2, reconnectAttemptRef.current),
      RECONNECT_DELAY_MAX
    );
    return delay;
  }, []);

  // Send pong response to server ping
  const sendPong = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ event: 'pong' }));
    }
  }, []);

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    setReconnecting(true);
    const ws = new WebSocket(WS_URL);

    ws.onopen = () => {
      setConnected(true);
      setReconnecting(false);
      // Reset backoff counter on successful connection
      reconnectAttemptRef.current = 0;
      console.log('WebSocket connected');
    };

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);

        // Handle ping from server - respond with pong
        if (data.event === 'ping') {
          sendPong();
          return; // Don't process ping as activity
        }

        // Handle agent events from hooks
        if (data.event === 'agent_event') {
          const agentEvent: AgentEvent = {
            id: data.data.id || crypto.randomUUID(),
            event_type: data.data.event_type,
            session_id: data.data.session_id,
            agent_id: data.data.agent_id,
            tool_name: data.data.tool_name,
            tool_input: data.data.tool_input,
            tool_output: data.data.tool_output,
            timestamp: data.data.timestamp || data.timestamp,
          };
          addEvent(agentEvent);
        }

        // Handle agent thought stream
        if (data.event === 'agent_thought') {
          addThought({
            id: crypto.randomUUID(),
            agent_name: data.data.agent_name,
            thought_type: data.data.thought_type,
            content: data.data.content,
            tool_name: data.data.tool_name,
            tool_input: data.data.tool_input,
            tool_response: data.data.tool_response,
            timestamp: data.data.timestamp || data.timestamp,
          });
        }

        // Handle new messages for chat UI
        if (data.event === 'new_message' || data.event === 'user_message') {
          queryClient.invalidateQueries({ queryKey: ['messages'] });
        }

        // Handle session events
        if (data.event === 'session_created') {
          addSession(data.data.session);
          queryClient.invalidateQueries({ queryKey: ['sessions'] });
        }

        if (data.event === 'session_terminated') {
          removeSession(data.data.session_id);
          queryClient.invalidateQueries({ queryKey: ['sessions'] });
        }

        if (data.event === 'session_status_changed') {
          updateSession(data.data.session_id, { status: data.data.status });
          queryClient.invalidateQueries({ queryKey: ['sessions'] });
        }

        // Handle agent archived event
        if (data.event === 'agent_archived') {
          const archived = {
            id: data.data.archive_id,
            agent_id: data.data.agent_id,
            agent_name: data.data.agent_name,
            agent_type: data.data.agent_type,
            archived_at: data.data.archived_at,
          };
          addArchivedAgent(archived);

          // If the archived agent was currently selected, switch to archived view
          if (selectedAgentId === data.data.agent_id) {
            viewArchive(data.data.archive_id);
          }

          // Refresh agents list since one was archived (and will be killed)
          queryClient.invalidateQueries({ queryKey: ['agents'] });
        }

        // Add to general activity feed
        addActivity({
          id: crypto.randomUUID(),
          timestamp: data.timestamp || new Date().toISOString(),
          type: mapEventToActivityType(data.event, data.data as Record<string, unknown>),
          agent_id: data.data?.agent_id || data.data?.session_id || data.data?.from_agent || 'system',
          data: data.data,
        });
      } catch (e) {
        console.error('Failed to parse WebSocket message:', e);
      }
    };

    ws.onclose = () => {
      setConnected(false);
      wsRef.current = null;

      // Increment reconnect attempt counter for exponential backoff
      reconnectAttemptRef.current += 1;
      const delay = getReconnectDelay();

      console.log(`WebSocket closed, reconnecting in ${delay}ms (attempt ${reconnectAttemptRef.current})`);

      // Auto-reconnect with exponential backoff
      reconnectTimeoutRef.current = window.setTimeout(() => {
        connect();
      }, delay);
    };

    ws.onerror = (error) => {
      console.error('WebSocket error:', error);
    };

    wsRef.current = ws;
  }, [setConnected, setReconnecting, addActivity, addEvent, addThought, queryClient, getReconnectDelay, sendPong, addSession, removeSession, updateSession, addArchivedAgent, viewArchive, selectedAgentId]);

  const disconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
    }
    // Reset backoff counter when explicitly disconnecting
    reconnectAttemptRef.current = 0;
    wsRef.current?.close();
  }, []);

  useEffect(() => {
    connect();
    return () => disconnect();
  }, [connect, disconnect]);

  return { connect, disconnect };
}

function mapEventToActivityType(event: string, data?: Record<string, unknown>): Activity['type'] {
  switch (event) {
    case 'webhook_received':
      return 'webhook_received';
    case 'message_sent':
      return 'message_sent';
    case 'user_message':
      return 'user_message';
    case 'new_message':
      // Check if it's a mailbox message (agent-to-agent)
      if (data?.type === 'mailbox') {
        return 'mailbox_message';
      }
      return 'message_received';
    case 'status_change':
      return 'status_change';
    case 'agent_event':
      return 'tool_call';
    case 'session_created':
    case 'session_terminated':
    case 'session_status_changed':
      return 'status_change';
    default:
      return 'tool_call';
  }
}
