import type { AgentListResponse, Agent } from '../types/agent';
import type { MessageListResponse } from '../types/message';
import { API_BASE } from './constants';

export const api = {
  async getAgents(): Promise<AgentListResponse> {
    const res = await fetch(`${API_BASE}/api/agents`);
    if (!res.ok) throw new Error('Failed to fetch agents');
    return res.json();
  },

  async getAgent(id: string): Promise<Agent> {
    const res = await fetch(`${API_BASE}/api/agents/${id}`);
    if (!res.ok) throw new Error('Failed to fetch agent');
    return res.json();
  },

  async sendMessageToAgent(agentId: string, content: string): Promise<void> {
    const res = await fetch(`${API_BASE}/api/agents/${agentId}/message`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content }),
    });
    if (!res.ok) throw new Error('Failed to send message');
  },

  async interruptAgent(agentId: string): Promise<void> {
    const res = await fetch(`${API_BASE}/api/agents/${agentId}/interrupt`, {
      method: 'POST',
    });
    if (!res.ok) throw new Error('Failed to interrupt agent');
  },

  async compactAgent(agentId: string): Promise<void> {
    const res = await fetch(`${API_BASE}/api/agents/${agentId}/compact`, {
      method: 'POST',
    });
    if (!res.ok) throw new Error('Failed to compact agent');
  },

  async getMessages(limit = 50, offset = 0): Promise<MessageListResponse> {
    const res = await fetch(
      `${API_BASE}/api/messages?limit=${limit}&offset=${offset}`
    );
    if (!res.ok) throw new Error('Failed to fetch messages');
    return res.json();
  },
};
