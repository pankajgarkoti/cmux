import { useEffect, useRef, useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useConnectionStore } from '../stores/connectionStore';
import { useActivityStore } from '../stores/activityStore';
import { useAgentEventStore } from '../stores/agentEventStore';
import { useSessionStore } from '../stores/sessionStore';
import { WS_URL, RECONNECT_DELAY } from '../lib/constants';
import type { Activity } from '../types/activity';
import type { AgentEvent } from '../types/agent_event';

export function useWebSocket() {
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<number>();
  const queryClient = useQueryClient();

  const { setConnected, setReconnecting } = useConnectionStore();
  const { addActivity } = useActivityStore();
  const { addEvent } = useAgentEventStore();
  const { addSession, removeSession, updateSession } = useSessionStore();

  const connect = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;

    setReconnecting(true);
    const ws = new WebSocket(WS_URL);

    ws.onopen = () => {
      setConnected(true);
      setReconnecting(false);
      console.log('WebSocket connected');
    };

    ws.onmessage = (event) => {
      try {
        const data = JSON.parse(event.data);

        // Handle agent events from hooks
        if (data.event === 'agent_event') {
          const agentEvent: AgentEvent = {
            id: data.data.id || crypto.randomUUID(),
            event_type: data.data.event_type,
            session_id: data.data.session_id,
            tool_name: data.data.tool_name,
            tool_input: data.data.tool_input,
            tool_output: data.data.tool_output,
            timestamp: data.data.timestamp || data.timestamp,
          };
          addEvent(agentEvent);
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

        // Add to general activity feed
        addActivity({
          id: crypto.randomUUID(),
          timestamp: data.timestamp || new Date().toISOString(),
          type: mapEventToActivityType(data.event),
          agent_id: data.data?.agent_id || data.data?.session_id || 'system',
          data: data.data,
        });
      } catch (e) {
        console.error('Failed to parse WebSocket message:', e);
      }
    };

    ws.onclose = () => {
      setConnected(false);
      wsRef.current = null;

      // Auto-reconnect
      reconnectTimeoutRef.current = window.setTimeout(() => {
        connect();
      }, RECONNECT_DELAY);
    };

    ws.onerror = (error) => {
      console.error('WebSocket error:', error);
    };

    wsRef.current = ws;
  }, [setConnected, setReconnecting, addActivity, addEvent, queryClient]);

  const disconnect = useCallback(() => {
    if (reconnectTimeoutRef.current) {
      clearTimeout(reconnectTimeoutRef.current);
    }
    wsRef.current?.close();
  }, []);

  useEffect(() => {
    connect();
    return () => disconnect();
  }, [connect, disconnect]);

  return { connect, disconnect };
}

function mapEventToActivityType(event: string): Activity['type'] {
  switch (event) {
    case 'webhook_received':
      return 'webhook_received';
    case 'message_sent':
      return 'message_sent';
    case 'user_message':
      return 'user_message';
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
