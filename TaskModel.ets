/**
 * TaskModel.ets
 * 任务领域模型与枚举，定义 CampusLens 任务数据的统一形态。
 * 页面 / 仓库 / 服务均通过此文件访问任务结构，禁止散落定义。
 */

/** 任务优先级 */
export enum TaskPriority {
  /** 低 */
  LOW = 'low',
  /** 中 */
  MEDIUM = 'medium',
  /** 高 */
  HIGH = 'high'
}

/** 任务状态 */
export enum TaskStatus {
  /** 待完成 */
  PENDING = 'pending',
  /** 已完成 */
  COMPLETED = 'completed',
  /** 已过期 */
  EXPIRED = 'expired'
}

/** 任务来源类型 */
export enum SourceType {
  /** 文本输入 */
  TEXT = 'text',
  /** 图片识别 */
  IMAGE = 'image',
  /** PDF 解析 */
  PDF = 'pdf'
}

/**
 * 任务实体：贯穿 UI / Repository / Storage 的统一结构。
 * - 时间字段使用 number（毫秒时间戳）便于序列化与排序
 * - 数组字段（materials）以 JSON 字符串持久化
 * - 预留 calendar 字段以支持后续日历同步
 */
export interface Task {
  /** 主键，UUID */
  id: string;
  /** 标题 */
  title: string;
  /** 描述 */
  description: string;
  /** 分类：比赛 / 讲座 / 作业 / 活动 等 */
  category: string;
  /** 截止时间（毫秒时间戳），可空 */
  deadline: number | null;
  /** 活动开始时间（毫秒时间戳），可空 */
  eventTime: number | null;
  /** 活动结束时间（毫秒时间戳），可空 */
  eventEndTime: number | null;
  /** 地点 */
  location: string;
  /** 携带材料清单 */
  materials: string[];
  /** 联系人 */
  contact: string;
  /** 备注 */
  notes: string;
  /** 优先级 */
  priority: TaskPriority;
  /** 状态 */
  status: TaskStatus;
  /** 创建时间 */
  createdAt: number;
  /** 更新时间 */
  updatedAt: number;
  /** 来源类型 */
  sourceType: SourceType;
  /** 原文（识别来源文本，可空） */
  originalText: string;
  /** 预留：日历截止事件 ID */
  calendarDeadlineEventId: string;
  /** 预留：日历活动事件 ID */
  calendarActivityEventId: string;
}

/** 创建任务时的入参：可选字段由仓库补齐默认值 */
export interface TaskInput {
  title: string;
  description: string;
  category: string;
  deadline: number | null;
  eventTime: number | null;
  eventEndTime: number | null;
  location: string;
  materials: string[];
  contact: string;
  notes: string;
  priority: TaskPriority;
  sourceType: SourceType;
  originalText: string;
}

/**
 * 工具：根据活动时间与状态判定是否过期（仅对 pending 任务生效）。
 * 产品已以活动开始/结束时间为主，因此优先使用结束时间，其次开始时间；
 * 仅在旧数据没有活动时间时，才回退使用 deadline。
 */
export function resolveExpired(task: Task, now: number = Date.now()): TaskStatus {
  if (task.status === TaskStatus.COMPLETED) {
    return TaskStatus.COMPLETED;
  }
  let expiresAt: number | null = null;
  if (task.eventEndTime !== null && task.eventEndTime > 0) {
    expiresAt = task.eventEndTime;
  } else if (task.eventTime !== null && task.eventTime > 0) {
    expiresAt = task.eventTime;
  } else if (task.deadline !== null && task.deadline > 0) {
    expiresAt = task.deadline;
  }
  if (expiresAt !== null && expiresAt < now) {
    return TaskStatus.EXPIRED;
  }
  return TaskStatus.PENDING;
}

/** 工具：返回优先级展示文案 */
export function priorityLabel(priority: TaskPriority): string {
  switch (priority) {
    case TaskPriority.HIGH:
      return '高';
    case TaskPriority.MEDIUM:
      return '中';
    case TaskPriority.LOW:
      return '低';
    default:
      return '中';
  }
}

/** 工具：返回状态展示文案 */
export function statusLabel(status: TaskStatus): string {
  switch (status) {
    case TaskStatus.PENDING:
      return '待完成';
    case TaskStatus.COMPLETED:
      return '已完成';
    case TaskStatus.EXPIRED:
      return '已过期';
    default:
      return '待完成';
  }
}
