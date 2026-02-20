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
  display_name?: string;
  role?: string;
  project_id?: string;
}

export interface AgentListResponse {
  agents: Agent[];
  total: number;
}

export interface ArchivedAgentSummary {
  id: string;
  agent_id: string;
  agent_name: string;
  agent_type: AgentType;
  archived_at: string;
}

export interface ArchivedAgent extends ArchivedAgentSummary {
  terminal_output: string | null;
}
