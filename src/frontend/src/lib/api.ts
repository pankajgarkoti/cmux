import type { AgentListResponse, Agent, ArchivedAgentSummary, ArchivedAgent } from '../types/agent';
import type { MessageListResponse } from '../types/message';
import type { AgentEventsResponse } from '../types/agent_event';
import type { JournalDayResponse, JournalDatesResponse, JournalSearchResponse } from '../types/journal';
import type { FilesystemResponse } from '../types/filesystem';
import type { SessionListResponse, Session, SessionCreateRequest } from '../types/session';
import type { ProjectList, Project, ProjectCreate, ProjectAgentsResponse } from '../types/project';
import type { TaskListResponse, TaskTreeResponse, TaskStatsResponse, Task } from '../types/task';
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

  async getAgentTerminal(agentId: string, lines = 50): Promise<{ agent_id: string; output: string; lines: number }> {
    const res = await fetch(`${API_BASE}/api/agents/${agentId}/terminal?lines=${lines}`);
    if (!res.ok) throw new Error('Failed to get terminal output');
    return res.json();
  },

  async getMessages(limit = 50, offset = 0, agentId?: string): Promise<MessageListResponse> {
    const params = new URLSearchParams({
      limit: String(limit),
      offset: String(offset),
    });
    if (agentId) params.set('agent_id', agentId);
    const res = await fetch(`${API_BASE}/api/messages?${params}`);
    if (!res.ok) throw new Error('Failed to fetch messages');
    return res.json();
  },

  async getMailboxMessages(limit = 10): Promise<MessageListResponse> {
    // Fetch recent messages and filter for mailbox type
    const res = await fetch(
      `${API_BASE}/api/messages?limit=${limit}&offset=0`
    );
    if (!res.ok) throw new Error('Failed to fetch mailbox messages');
    const data: MessageListResponse = await res.json();
    // Filter to only mailbox messages
    const mailboxMessages = data.messages.filter(m => m.type === 'mailbox');
    return { messages: mailboxMessages, total: mailboxMessages.length, has_more: false };
  },

  async getAgentEvents(sessionId?: string, limit = 50): Promise<AgentEventsResponse> {
    const params = new URLSearchParams();
    if (sessionId) params.set('session_id', sessionId);
    params.set('limit', String(limit));
    const res = await fetch(`${API_BASE}/api/agent-events?${params}`);
    if (!res.ok) throw new Error('Failed to fetch agent events');
    return res.json();
  },

  async getEventsByMessage(messageId: string): Promise<AgentEventsResponse> {
    const res = await fetch(`${API_BASE}/api/agent-events/by-message/${encodeURIComponent(messageId)}`);
    if (!res.ok) throw new Error('Failed to fetch events for message');
    return res.json();
  },

  async getEventsByMessages(messageIds: string[]): Promise<Record<string, AgentEventsResponse['events']>> {
    const res = await fetch(`${API_BASE}/api/agent-events/by-messages`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message_ids: messageIds }),
    });
    if (!res.ok) throw new Error('Failed to fetch events for messages');
    const data = await res.json();
    return data.events_by_message;
  },

  async getJournal(date?: string): Promise<JournalDayResponse> {
    const params = date ? `?date=${date}` : '';
    const res = await fetch(`${API_BASE}/api/journal${params}`);
    if (!res.ok) throw new Error('Failed to fetch journal');
    return res.json();
  },

  async getJournalDates(): Promise<JournalDatesResponse> {
    const res = await fetch(`${API_BASE}/api/journal/dates`);
    if (!res.ok) throw new Error('Failed to fetch journal dates');
    return res.json();
  },

  async searchJournal(query: string, limit = 20): Promise<JournalSearchResponse> {
    const params = new URLSearchParams({ q: query, limit: String(limit) });
    const res = await fetch(`${API_BASE}/api/journal/search?${params}`);
    if (!res.ok) throw new Error('Failed to search journal');
    return res.json();
  },

  async addJournalEntry(entry: { title: string; content: string }): Promise<{ success: boolean }> {
    const res = await fetch(`${API_BASE}/api/journal/entry`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(entry),
    });
    if (!res.ok) throw new Error('Failed to add journal entry');
    return res.json();
  },

  async getFilesystem(path?: string): Promise<FilesystemResponse> {
    const params = path ? `?path=${encodeURIComponent(path)}` : '';
    const res = await fetch(`${API_BASE}/api/filesystem${params}`);
    if (!res.ok) throw new Error('Failed to fetch filesystem');
    return res.json();
  },

  async getFileContent(path: string): Promise<string> {
    const res = await fetch(`${API_BASE}/api/filesystem/content?path=${encodeURIComponent(path)}`);
    if (!res.ok) throw new Error('Failed to fetch file content');
    const data = await res.json();
    return data.content;
  },

  // Session API
  async getSessions(): Promise<SessionListResponse> {
    const res = await fetch(`${API_BASE}/api/sessions`);
    if (!res.ok) throw new Error('Failed to fetch sessions');
    return res.json();
  },

  async getSession(id: string): Promise<Session> {
    const res = await fetch(`${API_BASE}/api/sessions/${id}`);
    if (!res.ok) throw new Error('Failed to fetch session');
    return res.json();
  },

  async createSession(data: SessionCreateRequest): Promise<Session> {
    const res = await fetch(`${API_BASE}/api/sessions`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    if (!res.ok) throw new Error('Failed to create session');
    return res.json();
  },

  async terminateSession(id: string): Promise<void> {
    const res = await fetch(`${API_BASE}/api/sessions/${id}`, {
      method: 'DELETE',
    });
    if (!res.ok) {
      if (res.status === 403) throw new Error('Cannot terminate main session');
      throw new Error('Failed to terminate session');
    }
  },

  async pauseSession(id: string): Promise<void> {
    const res = await fetch(`${API_BASE}/api/sessions/${id}/pause`, {
      method: 'POST',
    });
    if (!res.ok) throw new Error('Failed to pause session');
  },

  async resumeSession(id: string): Promise<void> {
    const res = await fetch(`${API_BASE}/api/sessions/${id}/resume`, {
      method: 'POST',
    });
    if (!res.ok) throw new Error('Failed to resume session');
  },

  async clearSession(id: string): Promise<void> {
    const res = await fetch(`${API_BASE}/api/sessions/${id}/clear`, {
      method: 'POST',
    });
    if (!res.ok) throw new Error('Failed to clear session');
  },

  async sendMessageToSession(id: string, content: string): Promise<void> {
    const res = await fetch(`${API_BASE}/api/sessions/${id}/message`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ content }),
    });
    if (!res.ok) throw new Error('Failed to send message to session');
  },

  // Archived agents API
  async getArchivedAgents(): Promise<ArchivedAgentSummary[]> {
    const res = await fetch(`${API_BASE}/api/agents/archived`);
    if (!res.ok) throw new Error('Failed to fetch archived agents');
    return res.json();
  },

  async getArchivedAgent(archiveId: string): Promise<ArchivedAgent> {
    const res = await fetch(`${API_BASE}/api/agents/archived/${archiveId}`);
    if (!res.ok) throw new Error('Failed to fetch archived agent');
    return res.json();
  },

  async archiveAgent(agentId: string): Promise<{ archive_id: string }> {
    const res = await fetch(`${API_BASE}/api/agents/${agentId}/archive`, {
      method: 'POST',
    });
    if (!res.ok) throw new Error('Failed to archive agent');
    return res.json();
  },

  // Project API
  async getProjects(): Promise<ProjectList> {
    const res = await fetch(`${API_BASE}/api/projects`);
    if (!res.ok) throw new Error('Failed to fetch projects');
    return res.json();
  },

  async createProject(data: ProjectCreate): Promise<Project> {
    const res = await fetch(`${API_BASE}/api/projects`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data),
    });
    if (!res.ok) throw new Error('Failed to create project');
    return res.json();
  },

  async getProjectAgents(projectId: string): Promise<ProjectAgentsResponse> {
    const res = await fetch(`${API_BASE}/api/projects/${encodeURIComponent(projectId)}/agents`);
    if (!res.ok) throw new Error('Failed to fetch project agents');
    return res.json();
  },

  async activateProject(projectId: string): Promise<{ success: boolean }> {
    const res = await fetch(`${API_BASE}/api/projects/${encodeURIComponent(projectId)}/activate`, {
      method: 'POST',
    });
    if (!res.ok) throw new Error('Failed to activate project');
    return res.json();
  },

  async getJournalForProject(date?: string, projectId?: string): Promise<JournalDayResponse> {
    const params = new URLSearchParams();
    if (date) params.set('date', date);
    if (projectId) params.set('project', projectId);
    const qs = params.toString();
    const res = await fetch(`${API_BASE}/api/journal${qs ? `?${qs}` : ''}`);
    if (!res.ok) throw new Error('Failed to fetch journal');
    return res.json();
  },

  async getThoughts(limit = 200, agentName?: string): Promise<{ thoughts: Array<{
    id: string;
    agent_name: string;
    thought_type: string;
    content?: string | null;
    tool_name?: string | null;
    tool_input?: string | null;
    tool_response?: string | null;
    timestamp: string;
  }>; count: number }> {
    const params = new URLSearchParams({ limit: String(limit) });
    if (agentName) params.set('agent_name', agentName);
    const res = await fetch(`${API_BASE}/api/thoughts?${params}`);
    if (!res.ok) throw new Error('Failed to fetch thoughts');
    return res.json();
  },

  // Tasks API
  async getTasks(params?: { project?: string; status?: string; assigned_to?: string; include_done?: boolean }): Promise<TaskListResponse> {
    const qs = new URLSearchParams();
    if (params?.project) qs.set('project', params.project);
    if (params?.status) qs.set('status', params.status);
    if (params?.assigned_to) qs.set('assigned_to', params.assigned_to);
    if (params?.include_done) qs.set('include_done', 'true');
    const query = qs.toString();
    const res = await fetch(`${API_BASE}/api/tasks${query ? `?${query}` : ''}`);
    if (!res.ok) throw new Error('Failed to fetch tasks');
    return res.json();
  },

  async getTaskTree(params?: { project?: string; include_done?: boolean }): Promise<TaskTreeResponse> {
    const qs = new URLSearchParams();
    if (params?.project) qs.set('project', params.project);
    if (params?.include_done) qs.set('include_done', 'true');
    const query = qs.toString();
    const res = await fetch(`${API_BASE}/api/tasks/tree${query ? `?${query}` : ''}`);
    if (!res.ok) throw new Error('Failed to fetch task tree');
    return res.json();
  },

  async getTask(taskId: string): Promise<Task> {
    const res = await fetch(`${API_BASE}/api/tasks/${encodeURIComponent(taskId)}`);
    if (!res.ok) throw new Error('Failed to fetch task');
    return res.json();
  },

  async updateTask(taskId: string, update: { status?: string; assigned_to?: string; priority?: string; source?: string }): Promise<Task> {
    const res = await fetch(`${API_BASE}/api/tasks/${encodeURIComponent(taskId)}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(update),
    });
    if (!res.ok) throw new Error('Failed to update task');
    return res.json();
  },

  async createTask(task: { title: string; description?: string; project?: string; priority?: string; source?: string; parent_id?: string; assigned_to?: string; resources?: string[] }): Promise<Task> {
    const res = await fetch(`${API_BASE}/api/tasks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(task),
    });
    if (!res.ok) throw new Error('Failed to create task');
    return res.json();
  },

  async deleteTask(taskId: string): Promise<{ deleted: number; task_id: string }> {
    const res = await fetch(`${API_BASE}/api/tasks/${encodeURIComponent(taskId)}`, {
      method: 'DELETE',
    });
    if (!res.ok) throw new Error('Failed to delete task');
    return res.json();
  },

  async getTaskStats(): Promise<TaskStatsResponse> {
    const res = await fetch(`${API_BASE}/api/tasks/stats`);
    if (!res.ok) throw new Error('Failed to fetch task stats');
    return res.json();
  },
};
