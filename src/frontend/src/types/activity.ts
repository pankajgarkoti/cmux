export type ActivityType =
  | 'tool_call'
  | 'message_sent'
  | 'message_received'
  | 'status_change'
  | 'webhook_received'
  | 'user_message';

export interface Activity {
  id: string;
  timestamp: string;
  type: ActivityType;
  agent_id: string;
  data: Record<string, unknown>;
}

export interface WebSocketEvent {
  event: string;
  data: Record<string, unknown>;
  timestamp: string;
}
