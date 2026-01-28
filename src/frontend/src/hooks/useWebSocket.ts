import { useEffect, useRef, useCallback } from 'react';
import { useConnectionStore } from '../stores/connectionStore';
import { useActivityStore } from '../stores/activityStore';
import { WS_URL, RECONNECT_DELAY } from '../lib/constants';
import type { Activity } from '../types/activity';

export function useWebSocket() {
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimeoutRef = useRef<number>();

  const { setConnected, setReconnecting } = useConnectionStore();
  const { addActivity } = useActivityStore();

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
        addActivity({
          id: crypto.randomUUID(),
          timestamp: data.timestamp || new Date().toISOString(),
          type: mapEventToActivityType(data.event),
          agent_id: data.data?.agent_id || 'system',
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
  }, [setConnected, setReconnecting, addActivity]);

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
    default:
      return 'tool_call';
  }
}
