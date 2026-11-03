import { Task, TaskInput } from './TaskModel';

export interface TaskStore {
  getAllTasks(): Promise<Task[]>;
  createTask(input: TaskInput): Promise<Task>;
}

export interface ToolFunction { name: string; arguments: string; }
export interface ToolCall { id: string; type: string; function: ToolFunction; }
export interface AgentMessage {
  role: string;
  content: string | null;
  tool_calls?: ToolCall[];
  tool_call_id?: string;
}
export interface AgentRequest { messages: AgentMessage[]; currentTime: string; }
export interface AgentResponse { message: AgentMessage; error?: string; }
export interface AgentModelClient { complete(messages: AgentMessage[]): Promise<AgentMessage>; }
export interface ToolArguments {
  status?: string;
  timeField?: string;
  from?: string | null;
  to?: string | null;
  limit?: number;
  offset?: number;
  dueWithinDays?: number;
  title?: string;
  description?: string;
  category?: string;
  deadline?: string | null;
  eventTime?: string | null;
  eventEndTime?: string | null;
  location?: string;
  materials?: string[];
  contact?: string;
  notes?: string;
  priority?: string;
}
export interface TaskSummary {
  id: string;
  title: string;
  status: string;
  deadline: string | null;
  eventTime: string | null;
  eventEndTime: string | null;
  location: string;
}
export interface TaskQueryResult {
  tasks: TaskSummary[];
  totalMatched: number;
  offset: number;
  limit: number;
  hasMore: boolean;
  queriedAt: string;
  timezone: string;
}
export interface TaskStatistics {
  total: number;
  unfinished: number;
  pending: number;
  expired: number;
  completed: number;
  dueSoon: number;
  windowStart: string;
  windowEnd: string;
  timezone: string;
  definition: string;
}
export interface TaskDraft {
  id: string;
  input: TaskInput;
  state: string;
  createdAt: number;
  taskId: string;
}
export interface DraftResult { draftId: string; state: string; draft: TaskInput; message: string; }
export interface ToolExecution {
  ok: boolean;
  data?: TaskQueryResult | TaskStatistics | DraftResult;
  error?: string;
}
export interface ToolTrace {
  id: string;
  name: string;
  arguments: string;
  result: string;
  state: string;
}
export interface ChatLine { role: string; text: string; }
