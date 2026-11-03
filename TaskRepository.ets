/**
 * TaskRepository.ets
 * 任务本地持久化仓库，基于 @kit.ArkData relationalStore（SQLite）实现。
 * 职责：
 *  - 建表与版本演进
 *  - 对外提供 CRUD，屏蔽 SQL 细节
 *  - 状态过期自动推导
 * 替换为云数据库时，只需保持方法签名一致即可。
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { TaskStore } from '../models/AgentModel';
import {
  Task,
  TaskInput,
  TaskPriority,
  TaskStatus,
  SourceType,
  resolveExpired
} from '../models/TaskModel';

/** 数据库配置 */
const DB_NAME: string = 'campuslens.db';
const DB_VERSION: number = 1;
const TABLE_NAME: string = 'task';
/** 单例 tag，用于日志 */
const TAG: string = 'TaskRepository';
/** materials 数组的存储分隔符（SOH 控制字符，用户输入几乎不会出现） */
const MATERIALS_SEPARATOR: string = '\u0001';

/** 工具：字符串数组 -> 数据库存储字符串 */
function encodeMaterials(arr: string[]): string {
  return arr.join(MATERIALS_SEPARATOR);
}

/** 工具：数据库字符串 -> 字符串数组 */
function decodeMaterials(text: string): string[] {
  if (text.length === 0) {
    return [];
  }
  return text.split(MATERIALS_SEPARATOR).filter((s: string) => s.length > 0);
}

/**
 * 任务仓库单例。
 * 使用方式：
 *   await TaskRepository.getInstance().init(context);
 *   const list = await TaskRepository.getInstance().getAllTasks();
 */
export class TaskRepository implements TaskStore {
  private static instance: TaskRepository | null = null;
  private store: relationalStore.RdbStore | null = null;

  private constructor() {}

  static getInstance(): TaskRepository {
    if (TaskRepository.instance === null) {
      TaskRepository.instance = new TaskRepository();
    }
    return TaskRepository.instance;
  }

  /** 在 Ability 启动时调用，建库建表 */
  async init(context: common.Context): Promise<void> {
    if (this.store !== null) {
      return;
    }
    const config: relationalStore.StoreConfig = {
      name: DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    this.store = await relationalStore.getRdbStore(context, config);
    const createTableSql: string =
      `CREATE TABLE IF NOT EXISTS ${TABLE_NAME} (` +
      'id TEXT PRIMARY KEY NOT NULL,' +
      'title TEXT NOT NULL,' +
      'description TEXT NOT NULL,' +
      'category TEXT NOT NULL,' +
      'deadline INTEGER,' +
      'event_time INTEGER,' +
      'event_end_time INTEGER,' +
      'location TEXT NOT NULL,' +
      'materials TEXT NOT NULL,' +
      'contact TEXT NOT NULL,' +
      'notes TEXT NOT NULL,' +
      'priority TEXT NOT NULL,' +
      'status TEXT NOT NULL,' +
      'created_at INTEGER NOT NULL,' +
      'updated_at INTEGER NOT NULL,' +
      'source_type TEXT NOT NULL,' +
      'original_text TEXT NOT NULL,' +
      'calendar_deadline_event_id TEXT NOT NULL,' +
      'calendar_activity_event_id TEXT NOT NULL' +
      ');';
    await this.store.executeSql(createTableSql);
    // 兼容已经安装过的旧版数据库：新增活动结束时间列，不删除任何旧数据。
    try {
      await this.store.executeSql(`ALTER TABLE ${TABLE_NAME} ADD COLUMN event_end_time INTEGER`);
    } catch (e) {
      // 列已存在时会进入这里，可安全忽略。
    }
  }

  /** 创建任务：补齐默认字段并写入 */
  async createTask(input: TaskInput): Promise<Task> {
    this.ensureInit();
    const now: number = Date.now();
    const id: string = this.genId();
    const task: Task = {
      id,
      title: input.title,
      description: input.description,
      category: input.category,
      deadline: input.deadline,
      eventTime: input.eventTime,
      eventEndTime: input.eventEndTime,
      location: input.location,
      materials: input.materials,
      contact: input.contact,
      notes: input.notes,
      priority: input.priority,
      status: TaskStatus.PENDING,
      createdAt: now,
      updatedAt: now,
      sourceType: input.sourceType,
      originalText: input.originalText,
      calendarDeadlineEventId: '',
      calendarActivityEventId: ''
    };
    const values = this.taskToValues(task);
    await this.store!.insert(TABLE_NAME, values);
    return task;
  }

  /** 读取单个任务 */
  async getTask(id: string): Promise<Task | null> {
    this.ensureInit();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', id);
    const result = await this.store!.query(predicates);
    const list = this.resultToTasks(result);
    result.close();
    return list.length > 0 ? list[0] : null;
  }

  /** 读取全部任务，按创建时间倒序 */
  async getAllTasks(): Promise<Task[]> {
    this.ensureInit();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.orderByDesc('created_at');
    const result = await this.store!.query(predicates);
    const list = this.resultToTasks(result);
    result.close();
    return list;
  }

  /** 更新任务：自动维护 updatedAt 与状态推导 */
  async updateTask(task: Task): Promise<Task> {
    this.ensureInit();
    const nextStatus: TaskStatus = resolveExpired(task);
    const updated: Task = {
      id: task.id,
      title: task.title,
      description: task.description,
      category: task.category,
      deadline: task.deadline,
      eventTime: task.eventTime,
      eventEndTime: task.eventEndTime,
      location: task.location,
      materials: task.materials,
      contact: task.contact,
      notes: task.notes,
      priority: task.priority,
      status: nextStatus,
      createdAt: task.createdAt,
      updatedAt: Date.now(),
      sourceType: task.sourceType,
      originalText: task.originalText,
      calendarDeadlineEventId: task.calendarDeadlineEventId,
      calendarActivityEventId: task.calendarActivityEventId
    };
    const values = this.taskToValues(updated);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', task.id);
    await this.store!.update(values, predicates);
    return updated;
  }

  /** 删除任务 */
  async deleteTask(id: string): Promise<void> {
    this.ensureInit();
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', id);
    await this.store!.delete(predicates);
  }

  /** 标记任务完成 */
  async markCompleted(id: string): Promise<void> {
    const task: Task | null = await this.getTask(id);
    if (task === null) {
      return;
    }
    task.status = TaskStatus.COMPLETED;
    task.updatedAt = Date.now();
    const values = this.taskToValues(task);
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', id);
    await this.store!.update(values, predicates);
  }

  /**
   * 仅更新任务的两个 calendar eventId 字段。
   * 用于日历同步成功后回写，避免走完整 updateTask 引起的并发覆盖。
   * field 取值 'deadline' / 'activity'，对应 calendarDeadlineEventId / calendarActivityEventId。
   */
  async updateCalendarEventId(taskId: string, field: 'deadline' | 'activity', eventId: string): Promise<void> {
    this.ensureInit();
    let values: relationalStore.ValuesBucket;
    const now: number = Date.now();
    if (field === 'deadline') {
      values = {
        calendar_deadline_event_id: eventId,
        updated_at: now
      };
    } else {
      values = {
        calendar_activity_event_id: eventId,
        updated_at: now
      };
    }
    const predicates: relationalStore.RdbPredicates = new relationalStore.RdbPredicates(TABLE_NAME);
    predicates.equalTo('id', taskId);
    await this.store!.update(values, predicates);
  }

  /** 判空：若任务表为空则注入测试数据 */
  async count(): Promise<number> {
    this.ensureInit();
    const result = await this.store!.querySql(`SELECT COUNT(*) AS c FROM ${TABLE_NAME}`);
    let count: number = 0;
    if (result.goToFirstRow()) {
      count = result.getLong(result.getColumnIndex('c'));
    }
    result.close();
    return count;
  }

  // ===== 内部工具 =====

  private ensureInit(): void {
    if (this.store === null) {
      throw new Error(`[${TAG}] 未初始化，请先调用 init(context)`);
    }
  }

  /** Task -> ValuesBucket */
  private taskToValues(task: Task): relationalStore.ValuesBucket {
    const values: relationalStore.ValuesBucket = {
      id: task.id,
      title: task.title,
      description: task.description,
      category: task.category,
      deadline: task.deadline,
      event_time: task.eventTime,
      event_end_time: task.eventEndTime,
      location: task.location,
      materials: encodeMaterials(task.materials),
      contact: task.contact,
      notes: task.notes,
      priority: task.priority,
      status: task.status,
      created_at: task.createdAt,
      updated_at: task.updatedAt,
      source_type: task.sourceType,
      original_text: task.originalText,
      calendar_deadline_event_id: task.calendarDeadlineEventId,
      calendar_activity_event_id: task.calendarActivityEventId
    };
    return values;
  }

  /** ResultSet -> Task[] */
  private resultToTasks(result: relationalStore.ResultSet): Task[] {
    const list: Task[] = [];
    while (result.goToNextRow()) {
      const materialsStr: string = result.getString(result.getColumnIndex('materials'));
      const task: Task = {
        id: result.getString(result.getColumnIndex('id')),
        title: result.getString(result.getColumnIndex('title')),
        description: result.getString(result.getColumnIndex('description')),
        category: result.getString(result.getColumnIndex('category')),
        deadline: this.getLongOrNullOrZero(result, 'deadline'),
        eventTime: this.getLongOrNullOrZero(result, 'event_time'),
        eventEndTime: this.getLongOrNullOrZero(result, 'event_end_time'),
        location: result.getString(result.getColumnIndex('location')),
        materials: decodeMaterials(materialsStr),
        contact: result.getString(result.getColumnIndex('contact')),
        notes: result.getString(result.getColumnIndex('notes')),
        priority: this.coercePriority(result.getString(result.getColumnIndex('priority'))),
        status: this.coerceStatus(result.getString(result.getColumnIndex('status'))),
        createdAt: result.getLong(result.getColumnIndex('created_at')),
        updatedAt: result.getLong(result.getColumnIndex('updated_at')),
        sourceType: this.coerceSourceType(result.getString(result.getColumnIndex('source_type'))),
        originalText: result.getString(result.getColumnIndex('original_text')),
        calendarDeadlineEventId: result.getString(result.getColumnIndex('calendar_deadline_event_id')),
        calendarActivityEventId: result.getString(result.getColumnIndex('calendar_activity_event_id'))
      };
      list.push(task);
    }
    return list;
  }

  /** NULL 字段（deadline/eventTime/eventEndTime）允许为空 */
  private getLongOrNullOrZero(result: relationalStore.ResultSet, col: string): number | null {
    const idx: number = result.getColumnIndex(col);
    if (idx < 0) {
      return null;
    }
    if (result.isColumnNull(idx)) {
      return null;
    }
    return result.getLong(idx);
  }

  private coercePriority(v: string): TaskPriority {
    if (v === TaskPriority.HIGH) {
      return TaskPriority.HIGH;
    }
    if (v === TaskPriority.LOW) {
      return TaskPriority.LOW;
    }
    return TaskPriority.MEDIUM;
  }

  private coerceStatus(v: string): TaskStatus {
    if (v === TaskStatus.COMPLETED) {
      return TaskStatus.COMPLETED;
    }
    if (v === TaskStatus.EXPIRED) {
      return TaskStatus.EXPIRED;
    }
    return TaskStatus.PENDING;
  }

  private coerceSourceType(v: string): SourceType {
    if (v === SourceType.IMAGE) {
      return SourceType.IMAGE;
    }
    if (v === SourceType.PDF) {
      return SourceType.PDF;
    }
    return SourceType.TEXT;
  }

  /** 简易 UUID（基于时间戳 + 随机数，足够本地场景使用） */
  private genId(): string {
    const ts: string = Date.now().toString(36);
    const rand: string = Math.random().toString(36).slice(2, 10);
    return `t_${ts}_${rand}`;
  }
}
