export interface Project {
  id: string;
  name: string;
  path: string;
  is_self: boolean;
  active: boolean;
  supervisor_agent_id: string | null;
  hooks_installed: boolean;
  added_at: string | null;
  git_remote: string | null;
  language: string | null;
  description: string | null;
}

export interface ProjectList {
  projects: Project[];
  total: number;
}

export interface ProjectCreate {
  path: string;
  name?: string;
  description?: string;
}

export interface ProjectAgentsResponse {
  project_id: string;
  agents: string[];
  total: number;
}
