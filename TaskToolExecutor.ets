import { SourceType, TaskInput, TaskPriority } from '../models/TaskModel';
import { ToolArguments, ToolExecution, TaskStore, DraftResult } from '../models/AgentModel';
import { TaskRepository } from '../repositories/TaskRepository';
import { TaskDraftService } from './TaskDraftService';
import { queryTasks, getTaskStatistics } from './TaskQueryService';
import { parseCampusDate } from '../common/DateTimeUtils';

export const TASK_TOOL_NAMES: string[] = ['query_tasks', 'get_task_statistics', 'create_task_draft'];

function textValue(value: string | undefined, max: number, fallback: string = ''): string {
  if (value === undefined) { return fallback; }
  if (typeof value !== 'string' || value.length > max) { throw new Error(`文本参数必须是字符串，长度不超过 ${max}`); }
  return value.trim();
}
function dateValue(value: string | null | undefined): number | null {
  if (value === undefined || value === null) { return null; }
  if (typeof value !== 'string') { throw new Error('时间参数必须是字符串或 null'); }
  return parseCampusDate(value);
}
function integerValue(value: number | undefined, min: number, max: number): void {
  if (value !== undefined && (typeof value !== 'number' || !Number.isInteger(value) || value < min || value > max)) {
    throw new Error(`整数参数必须在 ${min} 至 ${max} 之间`);
  }
}

export class TaskToolExecutor {
  private store: TaskStore;
  private drafts: TaskDraftService;
  constructor(store: TaskStore = TaskRepository.getInstance(),
    drafts: TaskDraftService = TaskDraftService.getInstance()) {
    this.store = store;
    this.drafts = drafts;
  }

  async execute(name: string, json: string, originalText: string, source: SourceType = SourceType.TEXT): Promise<ToolExecution> {
    try {
      if (!TASK_TOOL_NAMES.includes(name)) { throw new Error('工具不在允许列表中'); }
      if (typeof json !== 'string' || json.length > 16000) { throw new Error('工具参数过长或格式错误'); }
      const args = JSON.parse(json) as ToolArguments;
      if (args === null || typeof args !== 'object' || Array.isArray(args)) { throw new Error('工具参数必须是 JSON 对象'); }
      let allowed: string[];
      if (name === 'query_tasks') { allowed = ['status', 'timeField', 'from', 'to', 'limit', 'offset']; }
      else if (name === 'get_task_statistics') { allowed = ['dueWithinDays']; }
      else { allowed = ['title', 'description', 'category', 'deadline', 'eventTime', 'eventEndTime', 'location', 'materials', 'contact', 'notes', 'priority']; }
      for (const key of Object.keys(args)) {
        if (!allowed.includes(key)) { throw new Error(`不支持的参数：${key}`); }
      }
      const now = Date.now();
      // Dispatch uses ONLY the tool name returned by the model, never user keywords.
      if (name === 'query_tasks') {
        if (args.status !== undefined && !['all', 'unfinished', 'pending', 'completed', 'expired'].includes(args.status)) { throw new Error('状态参数无效'); }
        if (args.timeField !== undefined && !['deadline', 'eventTime'].includes(args.timeField)) { throw new Error('时间字段无效'); }
        dateValue(args.from); dateValue(args.to);
        integerValue(args.limit, 1, 50); integerValue(args.offset, 0, 100000);
        return { ok: true, data: queryTasks(await this.store.getAllTasks(), args, now) };
      }
      if (name === 'get_task_statistics') {
        integerValue(args.dueWithinDays, 1, 30);
        return { ok: true, data: getTaskStatistics(await this.store.getAllTasks(), args.dueWithinDays ?? 7, now) };
      }
      const title = textValue(args.title, 120);
      if (title.length === 0) { throw new Error('草稿标题不能为空'); }
      const priority = args.priority ?? 'medium';
      if (!['low', 'medium', 'high'].includes(priority)) { throw new Error('优先级无效'); }
      const materials: string[] = [];
      if (args.materials !== undefined) {
        if (!Array.isArray(args.materials) || args.materials.length > 20) { throw new Error('材料必须为不超过 20 项的数组'); }
        for (const item of args.materials) { materials.push(textValue(item, 100)); }
      }
      const input: TaskInput = {
        title, description: textValue(args.description, 2000), category: textValue(args.category, 40, '通知'),
        deadline: dateValue(args.deadline), eventTime: dateValue(args.eventTime), eventEndTime: dateValue(args.eventEndTime),
        location: textValue(args.location, 200), materials, contact: textValue(args.contact, 200), notes: textValue(args.notes, 2000),
        priority: priority === 'high' ? TaskPriority.HIGH : priority === 'low' ? TaskPriority.LOW : TaskPriority.MEDIUM,
        sourceType: source, originalText
      };
      if (input.eventEndTime !== null && (input.eventTime === null || input.eventEndTime <= input.eventTime)) {
        throw new Error('活动结束时间必须晚于开始时间');
      }
      const draft = this.drafts.create(input);
      const data: DraftResult = { draftId: draft.id, state: draft.state, draft: input, message: '仅生成草稿，尚未入库。请用户在确认页核对后保存。' };
      return { ok: true, data };
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : '工具执行失败，请重试' };
    }
  }
}
