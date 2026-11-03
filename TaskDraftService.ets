import { Task, TaskInput } from '../models/TaskModel';
import { TaskDraft, TaskStore } from '../models/AgentModel';
import { TaskRepository } from '../repositories/TaskRepository';

export class TaskDraftService {
  private static instance: TaskDraftService | null = null;
  private drafts: Map<string, TaskDraft> = new Map<string, TaskDraft>();
  private sequence: number = 0;
  private store: TaskStore;
  constructor(store: TaskStore) { this.store = store; }

  static getInstance(): TaskDraftService {
    if (TaskDraftService.instance === null) { TaskDraftService.instance = new TaskDraftService(TaskRepository.getInstance()); }
    return TaskDraftService.instance;
  }

  create(input: TaskInput): TaskDraft {
    if (this.drafts.size >= 32) { throw new Error('草稿数量已达上限，请重启应用后继续'); }
    const id = `draft_${Date.now()}_${++this.sequence}`;
    const draft: TaskDraft = { id, input, state: 'pending_confirmation', createdAt: Date.now(), taskId: '' };
    this.drafts.set(id, draft);
    return draft;
  }

  get(id: string): TaskDraft | undefined { return this.drafts.get(id); }

  cancel(id: string): void {
    const draft = this.drafts.get(id);
    if (draft !== undefined && draft.state === 'pending_confirmation') { draft.state = 'cancelled'; }
  }

  /** Only the confirmation page calls this method. It is never registered as a model tool. */
  async confirm(id: string, input: TaskInput): Promise<Task> {
    const draft = this.drafts.get(id);
    if (draft === undefined || draft.state !== 'pending_confirmation') { throw new Error('草稿已处理或不存在，请重新生成'); }
    if (Date.now() - draft.createdAt > 30 * 60000) { throw new Error('草稿已超过 30 分钟，请重新生成'); }
    if (input.title.trim().length === 0 || input.title.length > 120) { throw new Error('标题应为 1 至 120 个字符'); }
    if (input.eventEndTime !== null && (input.eventTime === null || input.eventEndTime <= input.eventTime)) {
      throw new Error('活动结束时间必须晚于开始时间');
    }
    input.originalText = draft.input.originalText;
    input.sourceType = draft.input.sourceType;
    draft.state = 'saving';
    try {
      const task = await this.store.createTask(input);
      draft.state = 'saved';
      draft.taskId = task.id;
      return task;
    } catch (e) {
      draft.state = 'pending_confirmation';
      throw new Error(e instanceof Error ? e.message : '数据库写入失败');
    }
  }
}
