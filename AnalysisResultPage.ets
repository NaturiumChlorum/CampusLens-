/**
 * AnalysisResultPage.ets
 * AI 识别结果确认页：用户核对并编辑 AIService 返回的结构化字段后保存为 Task。
 * 数据流：上一页将 TaskAnalysisResult 写入 AppStorage 后跳转此页，
 *       此页读取 -> 编辑 -> 调 TaskRepository.createTask -> 返回。
 */

import { router } from '@kit.ArkUI';
import { Theme, TITLE_BAR_HEIGHT } from '../common/Theme';
import { EmptyState } from '../components/EmptyState';
import { TaskAnalysisResult, AIErrorType, AIAnalysisError } from '../models/AIModel';
import { TaskPriority, Task, TaskInput } from '../models/TaskModel';
import { parseCampusDate, formatCampusDate } from '../common/DateTimeUtils';
import { ANALYSIS_ORIGINAL_KEY, ANALYSIS_SOURCE_KEY, ANALYSIS_DRAFT_KEY } from '../common/AnalysisContext';
import { TaskDraftService } from '../services/TaskDraftService';
import { TaskRepository } from '../repositories/TaskRepository';
import { SourceType } from '../models/TaskModel';
import { CalendarServiceProvider, CalendarReminder, CalendarResult } from '../services/CalendarService';

/** AppStorage 桥接 key：AIPage 写入，本页读取 */
export const ANALYSIS_RESULT_KEY: string = 'analysisResult';

@Entry
@Component
export struct AnalysisResultPage {
  @StorageLink('tabIndex') currentTab: number = 0;
  @StorageLink('autoAddCalendar') autoAddCalendar: boolean = true;
  @State result: TaskAnalysisResult | null = null;
  @State originalText: string = '';
  @State saving: boolean = false;
  @State saveSuccess: boolean = false;
  @State errorMsg: string = '';

  /** 日历同步选项 */
  @State addActivityToCalendar: boolean = false;
  @State reminder: CalendarReminder = CalendarReminder.DAY_1;
  @State calendarHint: string = '';

  /** 可编辑字段（独立 @State 便于双向绑定） */
  @State title: string = '';
  @State description: string = '';
  @State category: string = '';
  @State deadlineText: string = '';
  private draftId: string = '';
  private sourceType: SourceType = SourceType.TEXT;
  @State eventTimeText: string = '';
  @State eventEndTimeText: string = '';
  @State location: string = '';
  @State materialsText: string = '';
  @State contact: string = '';
  @State notes: string = '';
  @State priority: TaskPriority = TaskPriority.MEDIUM;

  aboutToAppear(): void {
    this.draftId = AppStorage.get<string>(ANALYSIS_DRAFT_KEY) ?? '';
    this.originalText = AppStorage.get<string>(ANALYSIS_ORIGINAL_KEY) ?? '';
    this.sourceType = AppStorage.get<SourceType>(ANALYSIS_SOURCE_KEY) ?? SourceType.TEXT;
    const stored: TaskAnalysisResult | undefined = AppStorage.get<TaskAnalysisResult>(ANALYSIS_RESULT_KEY);
    if (stored !== undefined) {
      this.result = stored;
      this.title = stored.title;
      this.description = stored.description;
      this.category = stored.category;
      this.deadlineText = stored.deadline === null ? '' : formatCampusDate(stored.deadline);
      this.eventTimeText = stored.eventTime === null ? '' : formatTimestamp(stored.eventTime);
      this.eventEndTimeText = stored.eventEndTime === null ? '' : formatTimestamp(stored.eventEndTime);
      this.addActivityToCalendar = this.draftId.length === 0 && stored.eventTime !== null && this.autoAddCalendar;
      this.location = stored.location;
      this.materialsText = stored.materials.join('、');
      this.contact = stored.contact;
      this.notes = stored.notes;
      this.priority = stored.priority;
    }
  }

  private parseDatetime(text: string): number | null {
    return parseCampusDate(text);
  }

  aboutToDisappear(): void {
    if (this.draftId.length > 0) { TaskDraftService.getInstance().cancel(this.draftId); }
    AppStorage.delete(ANALYSIS_DRAFT_KEY);
    AppStorage.delete(ANALYSIS_ORIGINAL_KEY);
    AppStorage.delete(ANALYSIS_SOURCE_KEY);
    AppStorage.delete(ANALYSIS_RESULT_KEY);
  }

  private async save(): Promise<void> {
    if (this.saving || this.saveSuccess) { return; }
    if (this.title.trim().length === 0) {
      this.errorMsg = '标题不能为空';
      return;
    }
    this.saving = true;
    this.errorMsg = '';
    this.calendarHint = '';
    try {
      const deadline = this.parseDatetime(this.deadlineText);
      const eventTime: number | null = this.parseDatetime(this.eventTimeText);
      const eventEndTime: number | null = this.parseDatetime(this.eventEndTimeText);
      if (eventEndTime !== null && (eventTime === null || eventEndTime <= eventTime)) {
        this.errorMsg = '活动结束时间必须晚于开始时间';
        this.saving = false;
        return;
      }
      const materials: string[] = this.materialsText
        .split(/[、,，\s]+/)
        .map((s: string) => s.trim())
        .filter((s: string) => s.length > 0);
      const input: TaskInput = {
        title: this.title.trim(),
        description: this.description,
        category: this.category.trim().length > 0 ? this.category.trim() : '通知',
        deadline,
        eventTime,
        eventEndTime,
        location: this.location,
        materials,
        contact: this.contact,
        notes: this.notes,
        priority: this.priority,
        sourceType: this.sourceType,
        originalText: this.originalText
      };
      const task: Task = this.draftId.length > 0
        ? await TaskDraftService.getInstance().confirm(this.draftId, input)
        : await TaskRepository.getInstance().createTask(input);
      // 日历同步（失败不影响 Task 保存成功状态）
      const calendarFailed: boolean = await this.syncCalendarAfterSave(task, eventTime);
      this.saveSuccess = true;
      if (calendarFailed) {
        this.calendarHint = '任务已保存，但日历同步未完成';
      } else if (this.addActivityToCalendar) {
        this.calendarHint = '已添加到系统日历';
      } else {
        this.calendarHint = '任务已保存';
      }
      // 清理 AppStorage 桥
      AppStorage.delete(ANALYSIS_RESULT_KEY);
      // 保存完成后直接展示任务页；TaskPage 会重新创建并从数据库读取最新数据。
      this.currentTab = 2;
      setTimeout(() => {
        router.back();
      }, 800);
    } catch (e) {
      this.errorMsg = e instanceof Error ? e.message : '保存失败，请重试';
    } finally {
      this.saving = false;
    }
  }

  /**
   * 任务保存成功后处理日历同步。
   * 返回 true 表示有失败项；返回 false 表示全部成功或未勾选。
   * 任何异常都被捕获，绝不阻断 Task 已保存的成功状态。
   */
  private async syncCalendarAfterSave(task: Task, eventTime: number | null): Promise<boolean> {
    const wantActivity: boolean = this.addActivityToCalendar && eventTime !== null;
    if (!wantActivity) {
      return false;
    }
    let failed: boolean = false;
    if (wantActivity) {
      try {
        const r: CalendarResult = await CalendarServiceProvider.get().addActivityEvent(task, this.reminder);
        if (r.success) {
          await TaskRepository.getInstance().updateCalendarEventId(task.id, 'activity', r.eventId);
        } else {
          failed = true;
        }
      } catch (e) {
        failed = true;
      }
    }
    return failed;
  }

  build(): void {
    Column() {
      this.buildHeader()
      if (this.result === null) {
        Column() {
          EmptyState({ message: '识别结果为空', hint: '请返回重新输入' })
        }
        .layoutWeight(1)
        .width('100%')
      } else {
        this.buildBody()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.color.bgPage)
  }

  @Builder
  buildHeader(): void {
    Row() {
      Text('←')
        .fontSize(22)
        .fontColor(Theme.color.textPrimary)
        .onClick(() => {
          router.back();
        })
      Text($r('app.string.ai_result_title'))
        .fontSize(Theme.font.titleMd)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.color.textPrimary)
        .margin({ left: Theme.space.sm })
      Blank()
      Text($r('app.string.ai_result_hint'))
        .fontSize(Theme.font.caption)
        .fontColor(Theme.color.textTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(0)
    }
    .width('100%')
    .height(TITLE_BAR_HEIGHT)
    .padding({ left: Theme.space.lg, right: Theme.space.lg })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildBody(): void {
    Scroll() {
      Column() {
        this.buildFieldText($r('app.string.ai_field_title'), this.title, (v: string) => { this.title = v; })
        this.buildFieldText($r('app.string.ai_field_category'), this.category, (v: string) => { this.category = v; })
        this.buildFieldText($r('app.string.ai_field_deadline'), this.deadlineText, (v: string) => { this.deadlineText = v; }, '可选：YYYY-MM-DD HH:mm（北京时间）')
        this.buildFieldText($r('app.string.ai_field_event_time'), this.eventTimeText, (v: string) => { this.eventTimeText = v; }, 'YYYY-MM-DD HH:mm')
        this.buildFieldText($r('app.string.ai_field_event_end_time'), this.eventEndTimeText, (v: string) => { this.eventEndTimeText = v; }, 'YYYY-MM-DD HH:mm')
        this.buildFieldText($r('app.string.ai_field_location'), this.location, (v: string) => { this.location = v; })
        this.buildFieldText($r('app.string.ai_field_materials'), this.materialsText, (v: string) => { this.materialsText = v; })
        this.buildFieldText($r('app.string.ai_field_contact'), this.contact, (v: string) => { this.contact = v; })
        this.buildFieldText($r('app.string.ai_field_notes'), this.notes, (v: string) => { this.notes = v; })
        this.buildFieldText($r('app.string.ai_field_description'), this.description, (v: string) => { this.description = v; })
        this.buildFieldPriority()
        this.buildCalendarSection()

        if (this.errorMsg.length > 0) {
          Text(this.errorMsg)
            .fontSize(Theme.font.bodySm)
            .fontColor(Theme.color.danger)
            .margin({ top: Theme.space.sm })
        }

        if (this.calendarHint.length > 0) {
          Text(this.calendarHint)
            .fontSize(Theme.font.bodySm)
            .fontColor(Theme.color.success)
            .margin({ top: Theme.space.sm })
        }

        if (this.saveSuccess) {
          Text($r('app.string.ai_save_success'))
            .fontSize(Theme.font.bodySm)
            .fontColor(Theme.color.success)
            .margin({ top: Theme.space.sm })
        }

        Button($r('app.string.save_and_calendar'))
          .width('100%')
          .height(48)
          .fontSize(Theme.font.titleSm)
          .fontColor(Theme.color.textInverse)
          .backgroundColor(Theme.color.primary)
          .borderRadius(Theme.radius.md)
          .margin({ top: Theme.space.md, bottom: Theme.space.sm })
          .enabled(!this.saving && !this.saveSuccess)
          .opacity(this.saving || this.saveSuccess ? 0.5 : 1)
          .onClick(() => { this.saveWithCalendar(); })

        if (this.saving) {
          Row() {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(Theme.color.primary)
            Text($r('app.string.common_loading_default'))
              .fontSize(Theme.font.caption)
              .fontColor(Theme.color.textTertiary)
              .margin({ left: Theme.space.xs })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ bottom: Theme.space.sm })
        }

        Button($r('app.string.ai_save_task'))
          .width('100%')
          .height(48)
          .fontSize(Theme.font.titleSm)
          .fontColor(Theme.color.primary)
          .backgroundColor(Theme.color.bgCard)
          .borderRadius(Theme.radius.md)
          .margin({ bottom: 32 })
          .enabled(!this.saving && !this.saveSuccess)
          .opacity(this.saving || this.saveSuccess ? 0.5 : 1)
          .onClick(() => { this.addActivityToCalendar = false; this.save(); })
      }
      .width('100%')
      .padding({ left: Theme.space.lg, right: Theme.space.lg, top: Theme.space.sm })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Start)
  }

  /** 保存并加入日历：勾选日历选项后保存 */
  private async saveWithCalendar(): Promise<void> {
    try {
    // 自动根据输入的时间勾选日历项
    const hasActivity: boolean = this.parseDatetime(this.eventTimeText) !== null;
    if (hasActivity) {
      this.addActivityToCalendar = true;
    }
    await this.save();
    } catch (e) { this.errorMsg = e instanceof Error ? e.message : '时间格式无效'; }
  }

  @Builder
  buildCalendarSection(): void {
    Column() {
      Text($r('app.string.calendar_section'))
        .fontSize(Theme.font.caption)
        .fontColor(Theme.color.textTertiary)
        .margin({ bottom: Theme.space.sm })

      // 活动时间勾选
      Row() {
        Checkbox()
          .select(this.addActivityToCalendar)
          .onChange((v: boolean) => { this.addActivityToCalendar = v; })
        Text($r('app.string.calendar_add_activity'))
          .fontSize(Theme.font.bodySm)
          .fontColor(Theme.color.textSecondary)
          .margin({ left: Theme.space.xs })
      }
      .width('100%')
      .margin({ bottom: Theme.space.sm })

      // 提醒选择
      Text($r('app.string.calendar_reminder_title'))
        .fontSize(Theme.font.caption)
        .fontColor(Theme.color.textTertiary)
      Row({ space: Theme.space.xs }) {
        this.buildReminderOption($r('app.string.calendar_reminder_none'), CalendarReminder.NONE)
        this.buildReminderOption($r('app.string.calendar_reminder_10min'), CalendarReminder.MIN_10)
        this.buildReminderOption($r('app.string.calendar_reminder_30min'), CalendarReminder.MIN_30)
        this.buildReminderOption($r('app.string.calendar_reminder_1hour'), CalendarReminder.HOUR_1)
        this.buildReminderOption($r('app.string.calendar_reminder_1day'), CalendarReminder.DAY_1)
      }
      .margin({ top: 6 })
      .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: Theme.space.md })
    .padding({ top: Theme.space.md, bottom: Theme.space.md, left: Theme.space.md, right: Theme.space.md })
    .backgroundColor(Theme.color.bgCard)
    .borderRadius(Theme.radius.md)
  }

  @Builder
  buildReminderOption(label: Resource, value: CalendarReminder): void {
    Text(label)
      .fontSize(Theme.font.caption)
      .fontColor(this.reminder === value ? Theme.color.textInverse : Theme.color.textSecondary)
      .backgroundColor(this.reminder === value ? Theme.color.primary : Theme.color.bgPage)
      .padding({ left: Theme.space.sm, right: Theme.space.sm, top: 4, bottom: 4 })
      .borderRadius(Theme.space.xl2)
      .onClick(() => { this.reminder = value; })
  }

  @Builder
  buildFieldText(label: Resource, value: string, onChange: (v: string) => void, placeholder: string = ''): void {
    Column() {
      Text(label)
        .fontSize(Theme.font.caption)
        .fontColor(Theme.color.textTertiary)
      TextInput({ text: value, placeholder: placeholder })
        .fontSize(Theme.font.bodyMd)
        .fontColor(Theme.color.textPrimary)
        .backgroundColor(Theme.color.bgCard)
        .borderRadius(Theme.radius.md)
        .margin({ top: 4 })
        .onChange((v: string) => { onChange(v); })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: Theme.space.md })
  }

  @Builder
  buildFieldPriority(): void {
    Column() {
      Text($r('app.string.ai_field_priority'))
        .fontSize(Theme.font.caption)
        .fontColor(Theme.color.textTertiary)
      Row({ space: Theme.space.sm }) {
        this.buildPriorityOption($r('app.string.ai_priority_high'), TaskPriority.HIGH)
        this.buildPriorityOption($r('app.string.ai_priority_medium'), TaskPriority.MEDIUM)
        this.buildPriorityOption($r('app.string.ai_priority_low'), TaskPriority.LOW)
      }
      .margin({ top: 6 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: Theme.space.md })
  }

  @Builder
  buildPriorityOption(label: Resource, value: TaskPriority): void {
    Text(label)
      .fontSize(Theme.font.bodySm)
      .fontColor(this.priority === value ? Theme.color.textInverse : Theme.color.textSecondary)
      .backgroundColor(this.priority === value ? Theme.color.primary : Theme.color.bgCard)
      .padding({ left: Theme.space.md, right: Theme.space.md, top: 6, bottom: 6 })
      .borderRadius(Theme.space.xl2)
      .onClick(() => { this.priority = value; })
  }
}

/** 时间戳 -> "YYYY-MM-DD HH:mm" */
function formatTimestamp(ts: number): string {
  return formatCampusDate(ts);
}
