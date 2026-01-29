export type AgentStatus =
  | 'PENDING'
  | 'IN_PROGRESS'
  | 'BLOCKED'
  | 'TESTING'
  | 'COMPLETE'
  | 'FAILED'
  | 'IDLE';

export type AgentType = 'supervisor' | 'worker';

export interface Agent {
  id: string;
  name: string;
  type: AgentType;
  status: AgentStatus;
  tmux_window: string;
  session: string;
  created_at: string;
  last_activity: string | null;
  current_task: string | null;
}

export interface AgentListResponse {
  agents: Agent[];
  total: number;
}
