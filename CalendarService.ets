/**
 * CalendarService.ets
 * 系统日历同步服务：把 CampusLens 任务的关键时间（截止/活动）同步到 HarmonyOS 系统日历。
 *
 * 设计原则：
 *  - 页面禁止直接调用日历 API，全部通过 CalendarServiceProvider 单例
 *  - Task.calendarDeadlineEventId / calendarActivityEventId 用于持久化 eventId，
 *    避免重复添加与支持更新/删除
 *  - 日历失败绝不阻断 Task 保存：调用方捕获异常后只做 UI 提示
 *  - 默认走 Mock 实现，保证本地构建/Preview 可演示；
 *    真机环境在 EntryAbility.onCreate 调 changeImpl(new RealCalendarService()) 切换。
 *
 * 数据流：
 *   AnalysisResultPage / TaskPage
 *     -> CalendarServiceProvider.get().addDeadlineEvent(task)
 *     -> 返回 eventId
 *     -> TaskRepository.updateCalendarEventId(taskId, 'deadline', eventId)
 */

import { calendarManager } from '@kit.CalendarKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Task } from '../models/TaskModel';

/**
 * 日历事件类型，区分截止与活动两种用途。
 */
export enum CalendarEventType {
  DEADLINE = 'deadline',
  ACTIVITY = 'activity'
}

/**
 * 提醒提前量，单位分钟，0 表示不提醒。
 */
export enum CalendarReminder {
  NONE = 0,
  MIN_10 = 10,
  MIN_30 = 30,
  HOUR_1 = 60,
  DAY_1 = 24 * 60
}

/**
 * 日历操作结果：返回创建/更新的 eventId（数字字符串）。
 */
export interface CalendarResult {
  /** 系统日历事件 ID（已转字符串便于存储），失败时为空串 */
  eventId: string;
  /** 是否成功 */
  success: boolean;
  /** 失败原因，成功时为空 */
  message: string;
}

/**
 * 日历服务接口：所有实现（Mock / Real）均需满足此契约。
 */
export interface CalendarService {
  /** 检查日历读写权限是否已授予 */
  checkPermission(): Promise<boolean>;
  /** 申请日历权限（弹窗） */
  requestPermission(): Promise<boolean>;
  /** 添加截止时间到日历 */
  addDeadlineEvent(task: Task, reminder: CalendarReminder): Promise<CalendarResult>;
  /** 添加活动时间到日历 */
  addActivityEvent(task: Task, reminder: CalendarReminder): Promise<CalendarResult>;
  /** 更新已有日历事件（按 eventId），eventId 为空串则视为新增 */
  updateCalendarEvent(task: Task, type: CalendarEventType, reminder: CalendarReminder): Promise<CalendarResult>;
  /** 删除日历事件 */
  deleteCalendarEvent(eventId: string): Promise<CalendarResult>;
}

/**
 * MockCalendarService：本地假实现，模拟日历操作。
 * 阶段5 用于本地/Preview 演示，真机切换 RealCalendarService。
 */
export class MockCalendarService implements CalendarService {
  /** 自增 id 计数器，模拟真实 eventId */
  private static counter: number = 1000;

  async checkPermission(): Promise<boolean> {
    return true;
  }

  async requestPermission(): Promise<boolean> {
    return true;
  }

  async addDeadlineEvent(task: Task, reminder: CalendarReminder): Promise<CalendarResult> {
    await this.delay(400);
    if (task.deadline === null) {
      return { eventId: '', success: false, message: '任务无截止时间' };
    }
    const id: number = ++MockCalendarService.counter;
    return { eventId: String(id), success: true, message: '已添加到日历（Mock）' };
  }

  async addActivityEvent(task: Task, reminder: CalendarReminder): Promise<CalendarResult> {
    await this.delay(400);
    if (task.eventTime === null) {
      return { eventId: '', success: false, message: '任务无活动时间' };
    }
    const id: number = ++MockCalendarService.counter;
    return { eventId: String(id), success: true, message: '已添加到日历（Mock）' };
  }

  async updateCalendarEvent(task: Task, type: CalendarEventType, reminder: CalendarReminder): Promise<CalendarResult> {
    await this.delay(400);
    const existingId: string = type === CalendarEventType.DEADLINE
      ? task.calendarDeadlineEventId
      : task.calendarActivityEventId;
    if (existingId.length === 0) {
      // 视为新增
      return type === CalendarEventType.DEADLINE
        ? this.addDeadlineEvent(task, reminder)
        : this.addActivityEvent(task, reminder);
    }
    return { eventId: existingId, success: true, message: '已更新日历（Mock）' };
  }

  async deleteCalendarEvent(eventId: string): Promise<CalendarResult> {
    await this.delay(300);
    if (eventId.length === 0) {
      return { eventId: '', success: false, message: 'eventId 为空' };
    }
    return { eventId, success: true, message: '已删除日历事件（Mock）' };
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), ms);
    });
  }
}

/**
 * RealCalendarService：基于 @kit.CalendarKit calendarManager 的真实日历实现。
 *
 * 启用方法：
 *   在 EntryAbility.onCreate 调
 *     CalendarServiceProvider.changeImpl(new RealCalendarService(this.context))
 *   真机环境权限申请会由本实现内部触发 requestPermissionsFromUser。
 *
 * 关键 API：
 *  - calendarManager.getCalendarManager(context) 获取管理器
 *  - getCalendar() 获取默认日历
 *  - addEvent(event) 添加，返回 number 类型的 eventId
 *  - updateEvent(event) 更新（event.id 必填）
 *  - deleteEvent(id) 删除
 *  - Event.reminderTime: number[] 提醒提前分钟数数组
 */
export class RealCalendarService implements CalendarService {
  private context: common.Context;
  private static instance: RealCalendarService | null = null;

  private constructor(context: common.Context) {
    this.context = context;
  }

  /** 单例工厂：与 TaskRepository 单例风格保持一致 */
  static create(context: common.Context): RealCalendarService {
    if (RealCalendarService.instance === null) {
      RealCalendarService.instance = new RealCalendarService(context);
    }
    return RealCalendarService.instance;
  }

  private static readonly CALENDAR_PERMISSIONS: Permissions[] = [
    'ohos.permission.READ_CALENDAR',
    'ohos.permission.WRITE_CALENDAR'
  ];

  async checkPermission(): Promise<boolean> {
    // 简化策略：始终返回 false，强制走 requestPermissionsFromUser
    // 原因：ArkTS 严格模式下 checkAccessToken 的 tokenId 获取需要 bundleManager 协同，
    //       复杂度高且权限检查本身非关键路径。
    // 真机首次会弹权限请求，已授权后系统不再弹窗，体验无影响。
    return false;
  }

  async requestPermission(): Promise<boolean> {
    try {
      const uiContext: common.UIAbilityContext = this.context as common.UIAbilityContext;
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(uiContext, RealCalendarService.CALENDAR_PERMISSIONS);
      return result.authResults.length === RealCalendarService.CALENDAR_PERMISSIONS.length &&
        result.authResults.every((value: number) => value === 0);
    } catch (e) {
      return false;
    }
  }

  async addDeadlineEvent(task: Task, reminder: CalendarReminder): Promise<CalendarResult> {
    if (task.deadline === null) {
      return { eventId: '', success: false, message: '任务无截止时间' };
    }
    return this.upsertEvent(task, CalendarEventType.DEADLINE, reminder);
  }

  async addActivityEvent(task: Task, reminder: CalendarReminder): Promise<CalendarResult> {
    if (task.eventTime === null) {
      return { eventId: '', success: false, message: '任务无活动时间' };
    }
    return this.upsertEvent(task, CalendarEventType.ACTIVITY, reminder);
  }

  async updateCalendarEvent(task: Task, type: CalendarEventType, reminder: CalendarReminder): Promise<CalendarResult> {
    return this.upsertEvent(task, type, reminder);
  }

  async deleteCalendarEvent(eventId: string): Promise<CalendarResult> {
    if (eventId.length === 0) {
      return { eventId: '', success: false, message: 'eventId 为空' };
    }
    try {
      const granted: boolean = await this.ensurePermission();
      if (!granted) {
        return { eventId: '', success: false, message: '用户未授权日历权限' };
      }
      const mgr: calendarManager.CalendarManager = calendarManager.getCalendarManager(this.context);
      const calendar: calendarManager.Calendar = await mgr.getCalendar();
      const idNum: number = parseInt(eventId, 10);
      await calendar.deleteEvent(idNum);
      return { eventId, success: true, message: '已删除日历事件' };
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      return { eventId, success: false, message: `删除失败：${err.message}` };
    }
  }

  /** 统一的 upsert：eventId 为空则新增，否则更新 */
  private async upsertEvent(task: Task, type: CalendarEventType, reminder: CalendarReminder): Promise<CalendarResult> {
    try {
      const granted: boolean = await this.ensurePermission();
      if (!granted) {
        return { eventId: '', success: false, message: '用户未授权日历权限' };
      }
      const mgr: calendarManager.CalendarManager = calendarManager.getCalendarManager(this.context);
      const calendar: calendarManager.Calendar = await mgr.getCalendar();
      const startTime: number = type === CalendarEventType.DEADLINE ? (task.deadline as number) : (task.eventTime as number);
      const recognizedEndTime: number | null = type === CalendarEventType.ACTIVITY ? task.eventEndTime : null;
      const endTime: number = recognizedEndTime !== null && recognizedEndTime > startTime
        ? recognizedEndTime
        : startTime + 60 * 60 * 1000;
      const event: calendarManager.Event = {
        type: calendarManager.EventType.NORMAL,
        title: this.buildTitle(task, type),
        description: this.buildDescription(task, type),
        startTime,
        endTime,
        isAllDay: false,
        reminderTime: reminder === CalendarReminder.NONE ? [] : [reminder]
      };
      if (task.location.length > 0) {
        event.location = { location: task.location };
      }
      const existingId: string = type === CalendarEventType.DEADLINE
        ? task.calendarDeadlineEventId
        : task.calendarActivityEventId;
      if (existingId.length > 0) {
        event.id = parseInt(existingId, 10);
        await calendar.updateEvent(event);
        return { eventId: existingId, success: true, message: '已更新日历事件' };
      }
      const newId: number = await calendar.addEvent(event);
      return { eventId: String(newId), success: true, message: '已添加到系统日历' };
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      return { eventId: '', success: false, message: `日历操作失败：${err.message}` };
    }
  }

  /** 先 checkPermission，未授权则 requestPermission */
  private async ensurePermission(): Promise<boolean> {
    const granted: boolean = await this.checkPermission();
    if (granted) {
      return true;
    }
    return this.requestPermission();
  }

  private buildTitle(task: Task, type: CalendarEventType): string {
    return type === CalendarEventType.DEADLINE
      ? `[截止] ${task.title}`
      : `[活动] ${task.title}`;
  }

  private buildDescription(task: Task, type: CalendarEventType): string {
    const lines: string[] = [];
    lines.push(`分类：${task.category}`);
    if (task.description.length > 0) {
      lines.push(task.description);
    }
    if (task.materials.length > 0) {
      lines.push(`材料：${task.materials.join('、')}`);
    }
    if (task.contact.length > 0) {
      lines.push(`联系人：${task.contact}`);
    }
    if (task.location.length > 0) {
      lines.push(`地点：${task.location}`);
    }
    if (task.notes.length > 0) {
      lines.push(`备注：${task.notes}`);
    }
    lines.push('来源：CampusLens AI识别');
    return lines.join('\n');
  }
}

/**
 * CalendarServiceProvider：全局单例访问入口。
 * 默认 Mock 实现；真机环境通过 changeImpl 切换 Real。
 */
export class CalendarServiceProvider {
  private static instance: CalendarService = new MockCalendarService();

  static get(): CalendarService {
    return CalendarServiceProvider.instance;
  }

  static changeImpl(impl: CalendarService): void {
    CalendarServiceProvider.instance = impl;
  }
}
