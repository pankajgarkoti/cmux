export interface Task {
  id: string;
  title: string;
  description: string;
  project: string;
  assigned_to: string;
  status: string;
  parent_id: string;
  resources: string[];
  created_at: string;
  updated_at: string;
  completed_at: string;
  children?: Task[];
}

export interface TaskListResponse {
  tasks: Task[];
  total: number;
}

export interface TaskTreeResponse {
  tasks: Task[];
  total: number;
}

export type TaskStatus = 'pending' | 'assigned' | 'in-progress' | 'done' | 'blocked';
