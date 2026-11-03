/**
 * TaskPage.ets
 * 任务列表：全部 / 待完成 / 已完成 / 已过期
 * 阶段2：接入 TaskRepository，提供列表、详情、完成、删除能力。
 */

import { Theme, TITLE_BAR_HEIGHT } from '../common/Theme';
import { EmptyState } from '../components/EmptyState';
import { parseCampusDate, formatCampusDate } from '../common/DateTimeUtils';
import { TaskRepository } from '../repositories/TaskRepository';
import {
  Task,
  TaskStatus,
  TaskPriority,
  resolveExpired,
  priorityLabel,
  statusLabel
} from '../models/TaskModel';
import {
  CalendarServiceProvider,
  CalendarReminder,
  CalendarEventType,
  CalendarResult
} from '../services/CalendarService';

/** 任务卡片 ViewModel：在原始 Task 基础上派生展示态 */
interface TaskCardVM {
  task: Task;
  /** 展示态状态（pending 可能因过期变为 expired） */
  displayStatus: TaskStatus;
}

@Component
export struct TaskPage {
  @Prop isDesktop: boolean = false;
  @StorageLink('homeOpenTaskId') homeOpenTaskId: string = '';
  @State currentFilter: number = 0;
  @State tasks: Task[] = [];
  @State loading: boolean = true;
  @State selectedTask: Task | null = null;
  @State calendarBusy: boolean = false;
  @State calendarHint: string = '';
  @State editing: boolean = false;
  // 编辑表单字段
  @State editTitle: string = '';
  @State editDescription: string = '';
  @State editCategory: string = '';
  @State editLocation: string = '';
  @State editMaterials: string = '';
  @State editContact: string = '';
  @State editNotes: string = '';
  @State editPriorityIdx: number = 1;
  @State editEventTime: string = '';
  @State editDeadline: string = '';
  @State editEventEndTime: string = '';
  @State editHint: string = '';
  @State editSaving: boolean = false;
  // 全局提示
  @State toastHint: string = '';
  @State toastColor: ResourceColor = Theme.color.success;

  private filters: Resource[] = [
    $r('app.string.task_tab_all'),
    $r('app.string.task_tab_pending'),
    $r('app.string.task_tab_completed'),
    $r('app.string.task_tab_expired')
  ];

  async aboutToAppear(): Promise<void> {
    await this.refresh();
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    try {
      this.tasks = await TaskRepository.getInstance().getAllTasks();
      if (this.homeOpenTaskId.length > 0) {
        const target: Task | undefined = this.tasks.find((task: Task) => task.id === this.homeOpenTaskId);
        if (target !== undefined) {
          this.selectedTask = target;
        }
        this.homeOpenTaskId = '';
      } else if (this.isDesktop && this.selectedTask === null && this.tasks.length > 0) {
        this.selectedTask = this.tasks[0];
      }
    } catch (e) {
      this.tasks = [];
      this.showToast('数据加载失败', Theme.color.danger);
    }
    this.loading = false;
  }

  /** 统一 toast 提示，3 秒后自动清除 */
  private showToast(msg: string, color: ResourceColor = Theme.color.success): void {
    this.toastHint = msg;
    this.toastColor = color;
    setTimeout((): void => {
      this.toastHint = '';
    }, 3000);
  }

  /** 按当前筛选返回展示列表 */
  private getFilteredVMs(): TaskCardVM[] {
    const vms: TaskCardVM[] = [];
    for (const t of this.tasks) {
      const displayStatus: TaskStatus = resolveExpired(t);
      if (this.currentFilter === 0) {
        // 全部
      } else if (this.currentFilter === 1 && displayStatus !== TaskStatus.PENDING) {
        continue;
      } else if (this.currentFilter === 2 && displayStatus !== TaskStatus.COMPLETED) {
        continue;
      } else if (this.currentFilter === 3 && displayStatus !== TaskStatus.EXPIRED) {
        continue;
      }
      vms.push({ task: t, displayStatus });
    }
    // 按活动开始时间升序（无活动时间排后），同时间按创建时间倒序
    vms.sort((a: TaskCardVM, b: TaskCardVM): number => {
      const at: number = a.task.eventTime ?? Number.MAX_SAFE_INTEGER;
      const bt: number = b.task.eventTime ?? Number.MAX_SAFE_INTEGER;
      if (at !== bt) {
        return at - bt;
      }
      return b.task.createdAt - a.task.createdAt;
    });
    return vms;
  }

  private openDetail(task: Task): void {
    this.selectedTask = task;
  }

  private closeDetail(): void {
    this.selectedTask = null;
  }

  private confirmComplete(task: Task): void {
    AlertDialog.show({
      message: $r('app.string.task_confirm_complete'),
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        fontColor: Theme.color.primary,
        action: async (): Promise<void> => {
          try {
            await TaskRepository.getInstance().markCompleted(task.id);
            await this.refresh();
            this.selectedTask = null;
            this.showToast('任务已完成');
          } catch (e) {
            this.showToast('操作失败，请重试', Theme.color.danger);
          }
        }
      }
    });
  }

  private confirmDelete(task: Task): void {
    const hasCalendar: boolean = task.calendarDeadlineEventId.length > 0 || task.calendarActivityEventId.length > 0;
    if (!hasCalendar) {
      // 没有日历事件，直接走原流程
      AlertDialog.show({
        message: $r('app.string.task_confirm_delete'),
        alignment: DialogAlignment.Center,
        primaryButton: {
          value: $r('app.string.common_cancel'),
          action: () => {}
        },
        secondaryButton: {
        value: $r('app.string.common_confirm'),
        fontColor: Theme.color.danger,
        action: async (): Promise<void> => {
          try {
            await TaskRepository.getInstance().deleteTask(task.id);
            await this.refresh();
            this.selectedTask = null;
            this.showToast('任务已删除');
          } catch (e) {
            this.showToast('操作失败，请重试', Theme.color.danger);
          }
        }
      }
    });
    return;
  }
    // 有日历事件：询问是否同步删除
    AlertDialog.show({
      message: $r('app.string.calendar_delete_confirm'),
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.calendar_delete_confirm_no'),
        action: async (): Promise<void> => {
          try {
            await TaskRepository.getInstance().deleteTask(task.id);
            await this.refresh();
            this.selectedTask = null;
            this.showToast('任务已删除');
          } catch (e) {
            this.showToast('操作失败，请重试', Theme.color.danger);
          }
        }
      },
      secondaryButton: {
        value: $r('app.string.calendar_delete_confirm_yes'),
        fontColor: Theme.color.danger,
        action: async (): Promise<void> => {
          try {
            await this.deleteCalendarEventsOfTask(task);
            await TaskRepository.getInstance().deleteTask(task.id);
            await this.refresh();
            this.selectedTask = null;
            this.showToast('任务与日历事件已删除');
          } catch (e) {
            this.showToast('操作失败，请重试', Theme.color.danger);
          }
        }
      }
    });
  }

  /** 删除任务关联的所有日历事件（截止 + 活动） */
  private async deleteCalendarEventsOfTask(task: Task): Promise<void> {
    const failures: string[] = [];
    if (task.calendarDeadlineEventId.length > 0) {
      try {
        const result = await CalendarServiceProvider.get().deleteCalendarEvent(task.calendarDeadlineEventId);
        if (!result.success) { throw new Error(result.message); }
        await TaskRepository.getInstance().updateCalendarEventId(task.id, 'deadline', '');
        task.calendarDeadlineEventId = '';
      } catch (e) {
        failures.push('截止日历事件删除失败');
      }
    }
    if (task.calendarActivityEventId.length > 0) {
      try {
        const result = await CalendarServiceProvider.get().deleteCalendarEvent(task.calendarActivityEventId);
        if (!result.success) { throw new Error(result.message); }
        await TaskRepository.getInstance().updateCalendarEventId(task.id, 'activity', '');
        task.calendarActivityEventId = '';
      } catch (e) {
        failures.push('活动日历事件删除失败');
      }
    }
    if (failures.length > 0) { throw new Error(failures.join('；')); }
  }

  /** 详情页：添加日历事件 */
  private async addToCalendar(task: Task, type: CalendarEventType): Promise<void> {
    if (this.calendarBusy) {
      return;
    }
    this.calendarBusy = true;
    this.calendarHint = '';
    try {
      const result: CalendarResult = await CalendarServiceProvider.get().updateCalendarEvent(task, type, CalendarReminder.DAY_1);
      if (result.success) {
        const field: 'deadline' | 'activity' = type === CalendarEventType.DEADLINE ? 'deadline' : 'activity';
        await TaskRepository.getInstance().updateCalendarEventId(task.id, field, result.eventId);
        if (field === 'deadline') {
          task.calendarDeadlineEventId = result.eventId;
        } else {
          task.calendarActivityEventId = result.eventId;
        }
        this.selectedTask = task;
        this.tasks = this.tasks.slice();
        this.calendarHint = '已添加到系统日历';
        this.showToast('已添加到系统日历');
      } else {
        this.calendarHint = result.message.length > 0 ? result.message : '日历同步失败';
        this.showToast(this.calendarHint, Theme.color.danger);
      }
    } catch (e) {
      this.calendarHint = '日历同步失败';
      this.showToast('日历同步失败', Theme.color.danger);
    } finally {
      this.calendarBusy = false;
    }
  }

  build(): void {
    Stack() {
      if (this.isDesktop) {
        this.buildDesktopPage()
      } else {
        Column() {
          this.buildHeader();
          this.buildFilterBar();
          this.buildBody();
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Theme.color.bgPage)
      }

      if (!this.isDesktop && this.selectedTask !== null) {
        this.buildDetailOverlay()
      }

      if (this.editing && this.selectedTask !== null) {
        this.buildEditOverlay()
      }

      if (this.toastHint.length > 0) {
        Text(this.toastHint)
          .fontSize(Theme.font.bodySm)
          .fontColor(Theme.color.textInverse)
          .backgroundColor(this.toastColor)
          .padding({ left: Theme.space.md, right: Theme.space.md, top: 8, bottom: 8 })
          .borderRadius(Theme.space.xl2)
          .position({ x: '50%', y: '8%' })
          .translate({ x: '-50%' })
          .opacity(0.95)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildDesktopPage(): void {
    Column() {
      this.buildHeader()
      this.buildFilterBar()
      if (this.loading) {
        Column() {
          Text($r('app.string.common_loading'))
            .fontSize(Theme.font.bodyMd)
            .fontColor(Theme.color.textTertiary)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Row({ space: Theme.space.lg }) {
          Column() {
            Row() {
              Text('任务列表')
                .fontSize(Theme.font.titleSm)
                .fontWeight(FontWeight.Medium)
                .fontColor(Theme.color.textPrimary)
              Blank()
              Text(`${this.getFilteredVMs().length} 项`)
                .fontSize(Theme.font.caption)
                .fontColor(Theme.color.textTertiary)
            }
            .width('100%')
            .padding({ left: Theme.space.lg, right: Theme.space.lg, top: Theme.space.md })
            this.buildList()
          }
          .width('42%')
          .height('100%')
          .backgroundColor(Theme.color.bgSection)
          .borderRadius(Theme.radius.lg)

          this.buildDesktopDetailPane()
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: Theme.space.xl, right: Theme.space.xl, bottom: Theme.space.xl })
        .alignItems(VerticalAlign.Top)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.color.bgPage)
  }

  @Builder
  buildDesktopDetailPane(): void {
    Column() {
      if (this.selectedTask === null) {
        Column() {
          Text('选择一项任务')
            .fontSize(Theme.font.titleMd)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.color.textPrimary)
          Text('任务的时间、地点、材料和日历状态会显示在这里')
            .fontSize(Theme.font.bodySm)
            .fontColor(Theme.color.textSecondary)
            .margin({ top: Theme.space.sm })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Row() {
          Text('任务详情')
            .fontSize(Theme.font.titleMd)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.color.textPrimary)
          Blank()
          this.buildStatusBadge(resolveExpired(this.selectedTask))
        }
        .width('100%')
        .padding({ left: Theme.space.lg, right: Theme.space.lg, top: Theme.space.lg, bottom: Theme.space.sm })
        Scroll() {
          Column() {
            this.buildDetailBody()
          }
          .width('100%')
          .padding({ left: Theme.space.lg, right: Theme.space.lg, bottom: Theme.space.lg })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        this.buildDetailActions()
      }
    }
    .layoutWeight(1)
    .height('100%')
    .backgroundColor(Theme.color.bgCard)
    .borderRadius(Theme.radius.lg)
  }

  @Builder
  buildBody(): void {
    if (this.loading) {
      Column() {
        Text($r('app.string.common_loading'))
          .fontSize(Theme.font.bodyMd)
          .fontColor(Theme.color.textTertiary)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      this.buildList()
    }
  }

  @Builder
  buildList(): void {
    if (this.getFilteredVMs().length === 0) {
      Scroll() {
        Column() {
          EmptyState({
            message: $r('app.string.common_empty'),
            hint: '通过 AI 识别生成的任务会显示在这里'
          })
        }
        .width('100%')
        .padding({ top: Theme.space.xl, bottom: 32 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
    } else {
      Scroll() {
        Column() {
          ForEach(this.getFilteredVMs(), (vm: TaskCardVM) => {
            this.buildTaskCard(vm)
          }, (vm: TaskCardVM) => vm.task.id)
        }
        .width('100%')
        .padding({
          left: Theme.space.lg,
          right: Theme.space.lg,
          top: Theme.space.sm,
          bottom: 32
        })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
    }
  }

  @Builder
  buildHeader(): void {
    Row() {
      Text($r('app.string.task_title'))
        .fontSize(Theme.font.titleLg)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.color.textPrimary)
      Blank()
      Text(`${this.tasks.length}`)
        .fontSize(Theme.font.bodySm)
        .fontColor(Theme.color.textTertiary)
    }
    .width('100%')
    .height(TITLE_BAR_HEIGHT)
    .padding({ left: Theme.space.lg, right: Theme.space.lg })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildFilterBar(): void {
    Row({ space: 8 }) {
      ForEach(this.filters, (filter: Resource, idx: number) => {
        Text(filter)
          .fontSize(Theme.font.bodySm)
          .fontColor(this.currentFilter === idx ? Theme.color.textInverse : Theme.color.textSecondary)
          .backgroundColor(this.currentFilter === idx ? Theme.color.primary : Theme.color.bgCard)
          .padding({ left: Theme.space.md, right: Theme.space.md, top: 6, bottom: 6 })
          .borderRadius(Theme.space.xl2)
          .onClick(() => {
            this.currentFilter = idx;
          })
      })
    }
    .width('100%')
    .padding({ left: Theme.space.lg, right: Theme.space.lg, bottom: Theme.space.lg })
  }

  @Builder
  buildTaskCard(vm: TaskCardVM): void {
    Column() {
      Row() {
        Text(vm.task.category)
          .fontSize(Theme.font.caption)
          .fontColor(Theme.color.primary)
          .backgroundColor(Theme.color.primaryLight)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(Theme.radius.sm)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(vm.task.title)
          .fontSize(Theme.font.titleSm)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.color.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ left: Theme.space.sm })
          .layoutWeight(1)
        this.buildStatusBadge(vm.displayStatus)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column({ space: 6 }) {
        this.buildMetaLine(
          $r('app.string.task_label_event_time'),
          vm.task.eventTime === null
            ? $r('app.string.task_no_event_time')
            : formatDateTime(vm.task.eventTime),
          false
        )
        this.buildMetaLine(
          $r('app.string.task_label_location'),
          vm.task.location.length > 0 ? vm.task.location : '—',
          false
        )
      }
      .width('100%')
      .margin({ top: Theme.space.md })
    }
    .width('100%')
    .padding(Theme.space.lg)
    .backgroundColor(Theme.color.bgCard)
    .borderRadius(Theme.radius.lg)
    .margin({ bottom: Theme.space.md })
    .onClick(() => {
      this.openDetail(vm.task);
    })
  }

  @Builder
  buildStatusBadge(status: TaskStatus): void {
    Text(statusLabel(status))
      .fontSize(Theme.font.caption)
      .fontColor(
        status === TaskStatus.PENDING ? Theme.color.warning
          : status === TaskStatus.COMPLETED ? Theme.color.success
          : status === TaskStatus.EXPIRED ? Theme.color.danger
          : Theme.color.textTertiary
      )
      .backgroundColor(
        status === TaskStatus.PENDING ? Theme.color.primaryLight
          : Theme.color.bgSection
      )
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .borderRadius(Theme.radius.sm)
  }

  @Builder
  buildMetaLine(label: Resource, value: string | Resource, danger: boolean): void {
    Row() {
      Text(label)
        .fontSize(Theme.font.caption)
        .fontColor(Theme.color.textTertiary)
        .width(48)
      Text(value)
        .fontSize(Theme.font.bodySm)
        .fontColor(danger ? Theme.color.danger : Theme.color.textSecondary)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
  }

  @Builder
  buildDetailOverlay(): void {
    Stack({ alignContent: Alignment.Bottom }) {
      // 半透明遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.closeDetail();
        })

      Column() {
        this.buildDetailHeader()
        Scroll() {
          Column() {
            this.buildDetailBody()
          }
          .width('100%')
          .padding({ left: Theme.space.lg, right: Theme.space.lg, bottom: Theme.space.xl })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        this.buildDetailActions()
      }
      .width('100%')
      .height('78%')
      .backgroundColor(Theme.color.bgPage)
      .borderRadius({ topLeft: Theme.radius.lg, topRight: Theme.radius.lg })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildDetailHeader(): void {
    Row() {
      Text($r('app.string.task_detail_title'))
        .fontSize(Theme.font.titleMd)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.color.textPrimary)
      Blank()
      Text('×')
        .fontSize(24)
        .fontColor(Theme.color.textTertiary)
        .onClick(() => {
          this.closeDetail();
        })
    }
    .width('100%')
    .padding({ left: Theme.space.lg, right: Theme.space.lg, top: Theme.space.lg, bottom: Theme.space.md })
  }

  @Builder
  buildDetailBody(): void {
    if (this.selectedTask !== null) {
      // 标题 + 状态
      Row() {
        Text(this.selectedTask.category)
          .fontSize(Theme.font.caption)
          .fontColor(Theme.color.primary)
          .backgroundColor(Theme.color.primaryLight)
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(Theme.radius.sm)
        Text(this.selectedTask.title)
          .fontSize(Theme.font.titleLg)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.color.textPrimary)
          .layoutWeight(1)
          .margin({ left: Theme.space.sm })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      this.buildDetailRow($r('app.string.task_label_description'), this.selectedTask.description)
      this.buildDetailRow($r('app.string.task_label_deadline'),
        this.selectedTask.deadline === null ? '—' : formatCampusDate(this.selectedTask.deadline))
      this.buildDetailRow($r('app.string.task_label_event_time'),
        this.selectedTask.eventTime === null
          ? '—'
          : formatDateTime(this.selectedTask.eventTime))
      this.buildDetailRow($r('app.string.task_label_event_end_time'),
        this.selectedTask.eventEndTime === null
          ? '—'
          : formatDateTime(this.selectedTask.eventEndTime))
      this.buildDetailRow($r('app.string.task_label_location'), this.selectedTask.location)
      this.buildDetailRow($r('app.string.task_label_materials'),
        this.selectedTask.materials.length > 0 ? this.selectedTask.materials.join('、') : '—')
      this.buildDetailRow($r('app.string.task_label_contact'),
        this.selectedTask.contact.length > 0 ? this.selectedTask.contact : '—')
      this.buildDetailRow($r('app.string.task_label_notes'),
        this.selectedTask.notes.length > 0 ? this.selectedTask.notes : '—')
      this.buildDetailRow($r('app.string.task_label_priority'), priorityLabel(this.selectedTask.priority))
      if (this.selectedTask.originalText.length > 0) {
        this.buildDetailRow($r('app.string.task_label_original'), this.selectedTask.originalText)
      }
      // 创建时间
      this.buildDetailRow($r('app.string.task_label_created_at'), formatFullDateTime(this.selectedTask.createdAt))
      // 日历同步状态
      this.buildDetailRow(
        $r('app.string.task_label_calendar_status'),
        this.selectedTask.calendarActivityEventId.length > 0
          ? '已同步系统日历'
          : '未同步'
      )
    }
  }

  @Builder
  buildDetailRow(label: Resource, value: string): void {
    Column() {
      Text(label)
        .fontSize(Theme.font.caption)
        .fontColor(Theme.color.textTertiary)
      Text(value)
        .fontSize(Theme.font.bodyMd)
        .fontColor(Theme.color.textPrimary)
        .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: Theme.space.md })
  }

  @Builder
  buildDetailActions(): void {
    Column({ space: Theme.space.sm }) {
      // 日历操作区
      if (this.selectedTask !== null) {
        this.buildCalendarActions()
      }

      Row({ space: Theme.space.md }) {
        Button($r('app.string.task_action_edit'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .backgroundColor(Theme.color.bgCard)
          .fontColor(Theme.color.primary)
          .onClick(() => {
            if (this.selectedTask !== null) {
              this.startEdit(this.selectedTask);
            }
          })
        Button($r('app.string.task_action_complete'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .backgroundColor(Theme.color.primary)
          .fontColor(Theme.color.textInverse)
          .onClick(() => {
            if (this.selectedTask !== null) {
              this.confirmComplete(this.selectedTask);
            }
          })
        Button($r('app.string.task_action_delete'))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .backgroundColor(Theme.color.bgCard)
          .fontColor(Theme.color.danger)
          .onClick(() => {
            if (this.selectedTask !== null) {
              this.confirmDelete(this.selectedTask);
            }
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding({
      left: Theme.space.lg,
      right: Theme.space.lg,
      top: Theme.space.md,
      bottom: Theme.space.lg
    })
  }

  /**
   * 详情页日历操作区：
   *  - 已添加：显示"已添加到系统日历" + "更新日历" + "删除日历事件"
   *  - 未添加：有活动开始时间时显示"添加到日历"
   *
   * 注意：@Builder 内禁止 return 与声明局部变量，所有判断直接访问 this.selectedTask
   */
  @Builder
  buildCalendarActions(): void {
    if (this.selectedTask !== null) {
      Column({ space: Theme.space.xs }) {
        if (this.calendarHint.length > 0) {
          Text(this.calendarHint)
            .fontSize(Theme.font.caption)
            .fontColor(Theme.color.success)
            .margin({ bottom: Theme.space.xs })
        }
        if (this.selectedTask.calendarActivityEventId.length > 0) {
          Text($r('app.string.calendar_added'))
            .fontSize(Theme.font.caption)
            .fontColor(Theme.color.textTertiary)
            .width('100%')
            .textAlign(TextAlign.Start)
          Row({ space: Theme.space.sm }) {
            Button($r('app.string.calendar_update_event'))
              .type(ButtonType.Capsule)
              .layoutWeight(1)
              .backgroundColor(Theme.color.bgCard)
              .fontColor(Theme.color.primary)
              .enabled(!this.calendarBusy)
              .opacity(this.calendarBusy ? 0.5 : 1)
              .onClick(() => {
                if (this.selectedTask !== null) {
                  if (this.selectedTask.eventTime !== null) {
                    this.addToCalendar(this.selectedTask, CalendarEventType.ACTIVITY);
                  }
                }
              })
            Button($r('app.string.calendar_delete_event'))
              .type(ButtonType.Capsule)
              .layoutWeight(1)
              .backgroundColor(Theme.color.bgCard)
              .fontColor(Theme.color.danger)
              .enabled(!this.calendarBusy)
              .opacity(this.calendarBusy ? 0.5 : 1)
              .onClick(() => {
                if (this.selectedTask !== null) {
                  this.confirmDeleteCalendarEvents(this.selectedTask);
                }
              })
          }
          .width('100%')
        } else if (this.selectedTask.eventTime !== null) {
          Button($r('app.string.calendar_add_to_calendar'))
            .type(ButtonType.Capsule)
            .width('100%')
            .backgroundColor(Theme.color.bgCard)
            .fontColor(Theme.color.primary)
            .enabled(!this.calendarBusy)
            .opacity(this.calendarBusy ? 0.5 : 1)
            .onClick(() => {
              if (this.selectedTask !== null) {
                this.addToCalendar(this.selectedTask, CalendarEventType.ACTIVITY);
              }
            })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ bottom: Theme.space.sm })
    }
  }

  /** 确认删除任务关联的日历事件 */
  private confirmDeleteCalendarEvents(task: Task): void {
    AlertDialog.show({
      message: $r('app.string.calendar_delete_confirm'),
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        fontColor: Theme.color.danger,
        action: async (): Promise<void> => {
          this.calendarBusy = true;
          try {
            await this.deleteCalendarEventsOfTask(task);
            // 清除本地 eventId
            task.calendarDeadlineEventId = '';
            task.calendarActivityEventId = '';
            this.selectedTask = task;
            this.tasks = this.tasks.slice();
            this.calendarHint = '日历事件已删除';
          } catch (e) {
            this.calendarHint = '日历事件删除失败';
          } finally {
            this.calendarBusy = false;
          }
        }
      }
    });
  }

  /**
   * 编辑任务：从 selectedTask 初始化表单字段，编辑保存调 TaskRepository.updateTask
   * 不修改 calendar 字段、sourceType、originalText、createdAt，避免破坏已有数据
   */
  private startEdit(task: Task): void {
    this.editTitle = task.title;
    this.editDescription = task.description;
    this.editCategory = task.category;
    this.editLocation = task.location;
    this.editMaterials = task.materials.join('、');
    this.editContact = task.contact;
    this.editNotes = task.notes;
    this.editEventTime = task.eventTime !== null ? formatDateTimeInput(task.eventTime) : '';
    this.editDeadline = task.deadline !== null ? formatCampusDate(task.deadline) : '';
    this.editEventEndTime = task.eventEndTime !== null ? formatDateTimeInput(task.eventEndTime) : '';
    this.editPriorityIdx = task.priority === TaskPriority.HIGH ? 0 : (task.priority === TaskPriority.LOW ? 2 : 1);
    this.editHint = '';
    this.editSaving = false;
    this.editing = true;
  }

  private cancelEdit(): void {
    this.editing = false;
  }

  private async saveEdit(): Promise<void> {
    if (this.editSaving) { return; }
    if (this.selectedTask === null) {
      return;
    }
    if (this.editTitle.trim().length === 0) {
      this.editHint = '标题不能为空';
      return;
    }
    this.editSaving = true;
    this.editHint = '';
    try {
      const task: Task = JSON.parse(JSON.stringify(this.selectedTask)) as Task;
      task.title = this.editTitle.trim();
      task.description = this.editDescription;
      task.category = this.editCategory.length > 0 ? this.editCategory : '其他';
      task.location = this.editLocation;
      task.materials = parseMaterials(this.editMaterials);
      task.contact = this.editContact;
      task.notes = this.editNotes;
      task.eventTime = this.editEventTime.length > 0 ? parseDateTimeInput(this.editEventTime) : null;
      task.deadline = parseCampusDate(this.editDeadline);
      task.eventEndTime = this.editEventEndTime.length > 0 ? parseDateTimeInput(this.editEventEndTime) : null;
      if (task.eventEndTime !== null && (task.eventTime === null || task.eventEndTime <= task.eventTime)) {
        this.editHint = '活动结束时间必须晚于开始时间';
        this.editSaving = false;
        return;
      }
      task.priority = this.editPriorityIdx === 0 ? TaskPriority.HIGH
        : (this.editPriorityIdx === 2 ? TaskPriority.LOW : TaskPriority.MEDIUM);

      const updated: Task = await TaskRepository.getInstance().updateTask(task);
      this.selectedTask = updated;
      // 同步刷新列表
      this.tasks = await TaskRepository.getInstance().getAllTasks();
      this.editing = false;
      this.showToast('任务已保存');
    } catch (e) {
      this.editHint = e instanceof Error ? e.message : '保存失败';
      this.showToast('保存失败，请重试', Theme.color.danger);
    } finally {
      this.editSaving = false;
    }
  }

  @Builder
  buildEditOverlay(): void {
    Stack({ alignContent: Alignment.Bottom }) {
      // 半透明遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#80000000')
        .onClick(() => {
          this.cancelEdit();
        })

      Column() {
        // 头部
        Row() {
          Text($r('app.string.task_edit_title'))
            .fontSize(Theme.font.titleMd)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.color.textPrimary)
          Blank()
          Text('×')
            .fontSize(24)
            .fontColor(Theme.color.textTertiary)
            .onClick(() => {
              this.cancelEdit();
            })
        }
        .width('100%')
        .padding({ left: Theme.space.lg, right: Theme.space.lg, top: Theme.space.lg, bottom: Theme.space.md })

        Scroll() {
          Column() {
            this.buildEditField($r('app.string.task_label_title'), this.editTitle, (v: string) => { this.editTitle = v; }, '请输入标题')
            this.buildEditField($r('app.string.task_label_category'), this.editCategory, (v: string) => { this.editCategory = v; }, '如 比赛/讲座/作业')
            this.buildEditField($r('app.string.task_label_description'), this.editDescription, (v: string) => { this.editDescription = v; }, '描述')
            this.buildEditField($r('app.string.task_label_location'), this.editLocation, (v: string) => { this.editLocation = v; }, '地点')
            this.buildEditField($r('app.string.task_label_materials'), this.editMaterials, (v: string) => { this.editMaterials = v; }, '材料，以、分隔')
            this.buildEditField($r('app.string.task_label_contact'), this.editContact, (v: string) => { this.editContact = v; }, '联系人')
            this.buildEditField($r('app.string.task_label_notes'), this.editNotes, (v: string) => { this.editNotes = v; }, '备注')
            this.buildEditField($r('app.string.task_label_deadline'), this.editDeadline, (v: string) => { this.editDeadline = v; }, '可选：YYYY-MM-DD HH:mm（北京时间）')

            // 活动时间
            Column() {
              Text($r('app.string.task_label_event_time'))
                .fontSize(Theme.font.caption)
                .fontColor(Theme.color.textTertiary)
              TextInput({ text: this.editEventTime, placeholder: 'YYYY-MM-DD HH:mm' })
                .fontSize(Theme.font.bodyMd)
                .fontColor(Theme.color.textPrimary)
                .backgroundColor(Theme.color.bgSection)
                .borderRadius(Theme.radius.sm)
                .margin({ top: 4 })
                .onChange((v: string) => { this.editEventTime = v; })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .margin({ top: Theme.space.md })

            // 活动结束时间
            Column() {
              Text($r('app.string.task_label_event_end_time'))
                .fontSize(Theme.font.caption)
                .fontColor(Theme.color.textTertiary)
              TextInput({ text: this.editEventEndTime, placeholder: 'YYYY-MM-DD HH:mm' })
                .fontSize(Theme.font.bodyMd)
                .fontColor(Theme.color.textPrimary)
                .backgroundColor(Theme.color.bgSection)
                .borderRadius(Theme.radius.sm)
                .margin({ top: 4 })
                .onChange((v: string) => { this.editEventEndTime = v; })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .margin({ top: Theme.space.md })

            // 优先级
            Column() {
              Text($r('app.string.task_label_priority'))
                .fontSize(Theme.font.caption)
                .fontColor(Theme.color.textTertiary)
              Row({ space: Theme.space.sm }) {
                ForEach(['高', '中', '低'], (label: string, idx: number) => {
                  Text(label)
                    .fontSize(Theme.font.caption)
                    .fontColor(this.editPriorityIdx === idx ? Theme.color.textInverse : Theme.color.textSecondary)
                    .backgroundColor(this.editPriorityIdx === idx ? Theme.color.primary : Theme.color.bgSection)
                    .padding({ left: Theme.space.sm, right: Theme.space.sm, top: 4, bottom: 4 })
                    .borderRadius(Theme.space.xl2)
                    .onClick(() => { this.editPriorityIdx = idx; })
                }, (label: string) => label)
              }
              .margin({ top: 4 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .margin({ top: Theme.space.md })

            if (this.editHint.length > 0) {
              Text(this.editHint)
                .fontSize(Theme.font.caption)
                .fontColor(Theme.color.danger)
                .margin({ top: Theme.space.sm })
            }

            // 操作按钮
            Row({ space: Theme.space.md }) {
              Button($r('app.string.task_edit_cancel'))
                .type(ButtonType.Capsule)
                .layoutWeight(1)
                .backgroundColor(Theme.color.bgCard)
                .fontColor(Theme.color.textSecondary)
                .enabled(!this.editSaving)
                .onClick(() => { this.cancelEdit(); })
              Button($r('app.string.task_edit_save'))
                .type(ButtonType.Capsule)
                .layoutWeight(1)
                .backgroundColor(Theme.color.primary)
                .fontColor(Theme.color.textInverse)
                .enabled(!this.editSaving)
                .opacity(this.editSaving ? 0.6 : 1)
                .onClick(() => { this.saveEdit(); })
            }
            .width('100%')
            .margin({ top: Theme.space.lg, bottom: Theme.space.lg })
          }
          .width('100%')
          .padding({ left: Theme.space.lg, right: Theme.space.lg })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('85%')
      .backgroundColor(Theme.color.bgPage)
      .borderRadius({ topLeft: Theme.radius.lg, topRight: Theme.radius.lg })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildEditField(label: Resource, value: string, onChange: (v: string) => void, placeholder: string): void {
    Column() {
      Text(label)
        .fontSize(Theme.font.caption)
        .fontColor(Theme.color.textTertiary)
      TextInput({ text: value, placeholder: placeholder })
        .fontSize(Theme.font.bodyMd)
        .fontColor(Theme.color.textPrimary)
        .backgroundColor(Theme.color.bgSection)
        .borderRadius(Theme.radius.sm)
        .margin({ top: 4 })
        .onChange(onChange)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: Theme.space.md })
  }
}

/** 格式化时间戳为 "MM-dd HH:mm" */
function formatDateTime(ts: number): string {
  const d: Date = new Date(ts);
  const mm: string = (d.getMonth() + 1).toString().padStart(2, '0');
  const dd: string = d.getDate().toString().padStart(2, '0');
  const hh: string = d.getHours().toString().padStart(2, '0');
  const mi: string = d.getMinutes().toString().padStart(2, '0');
  return `${mm}-${dd} ${hh}:${mi}`;
}

/** 格式化时间戳为 "YYYY-MM-DD HH:mm" 用于编辑表单初始值 */
function formatDateTimeInput(ts: number): string {
  return formatCampusDate(ts);
}

/** 解析 "YYYY-MM-DD HH:mm" 为时间戳，解析失败返回 0 */
function parseDateTimeInput(input: string): number | null {
  return parseCampusDate(input);
}

/** 解析 "材料1、材料2" 为数组 */
function parseMaterials(input: string): string[] {
  const trimmed: string = input.trim();
  if (trimmed.length === 0) {
    return [];
  }
  return trimmed.split(/[、,，]/).map((s: string) => s.trim()).filter((s: string) => s.length > 0);
}

/** 格式化时间戳为 "YYYY-MM-DD HH:mm" 用于详情完整展示 */
function formatFullDateTime(ts: number): string {
  return formatDateTimeInput(ts);
}
