/**
 * AIModel.ets
 * AI 识别相关数据模型，定义从通知文本到结构化任务的中间形态。
 * 与 Task 模型字段兼容，便于直接落入 TaskRepository。
 */

import { TaskPriority } from './TaskModel';

/**
 * AI 分析结果：校园通知文本经 AIService 分析后的结构化产物。
 * 字段对齐 Task，但不含主键、状态、时间戳、来源类型等系统字段，
 * 这些字段在保存时由 TaskRepository.createTask 补齐。
 *
 * 时间字段使用 number（毫秒时间戳）便于跨页面传递与序列化，
 * null 表示 AI 未识别出该时间。
 */
export interface TaskAnalysisResult {
  /** 标题 */
  title: string;
  /** 描述 */
  description: string;
  /** 分类 */
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
  /** AI 置信度（0-1），用于在确认页面提示用户复核 */
  confidence: number;
  /** AI 识别出的原文片段，便于用户对照修改 */
  matchedKeywords: string[];
}

/**
 * AI 分析错误类型，区分不同失败原因以便 UI 给出针对性提示。
 */
export enum AIErrorType {
  /** 输入为空或过短 */
  EMPTY_INPUT = 'empty_input',
  /** 网络异常 */
  NETWORK = 'network',
  /** 服务返回不可用结果 */
  PARSE = 'parse',
  /** 未知错误 */
  UNKNOWN = 'unknown'
}

/**
 * AI 分析异常：携带错误类型与可读消息。
 */
export class AIAnalysisError extends Error {
  readonly type: AIErrorType;

  constructor(type: AIErrorType, message: string) {
    super(message);
    this.name = 'AIAnalysisError';
    this.type = type;
  }
}
