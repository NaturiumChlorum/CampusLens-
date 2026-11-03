/**
 * HomePage.ets
 * 首页：今日待办 / 即将截止 / 最近活动 + 统计卡片
 * 阶段6：接入 TaskRepository，数据完全真实，禁止写死测试数据。
 *
 * 数据流：
 *   aboutToAppear -> TaskRepository.getAllTasks -> 派生 today/upcoming/activity 三个列表
 *   点击识别入口 -> 切 Tab 到 AI
 *   点击任务卡片 -> 跳 Tab 到任务并打开详情（通过 AppStorage 桥接）
 */

import { Theme, TITLE_BAR_HEIGHT } from '../common/Theme';
import { EmptyState } from '../components/EmptyState';
import { TaskRepository } from '../repositories/TaskRepository';
import {
  Task,
  TaskStatus,
  resolveExpired,
  statusLabel
} from '../models/TaskModel';

/** 首页任务卡片 ViewModel */
interface HomeTaskVM {
  task: Task;
  displayStatus: TaskStatus;
  /** 副标题：分类 + 时间 */
  subtitle: string;
}

@Component
export struct HomePage {
  @Prop isDesktop: boolean = false;
  /** 通过 AppStorage 与 Index 共享当前 Tab */
  @StorageLink('tabIndex') currentTab: number = 0;

  @State allTasks: Task[] = [];
  @State loading: boolean = true;

  /** 派生数据：由 allTasks 计算得出 */
  @State todayList: HomeTaskVM[] = [];
  @State upcomingList: HomeTaskVM[] = [];
  @State activityList: HomeTaskVM[] = [];
  @State todayCountValue: number = 0;
  @State pendingCountValue: number = 0;
  @State upcomingCountValue: number = 0;

  /** 详情桥接：HomePage 触发后由 TaskPage 监听打开 */
  @StorageLink('homeOpenTaskId') homeOpenTaskId: string = '';

  async aboutToAppear(): Promise<void> {
    await this.refresh();
  }

  /** 页面再次显示时刷新（Tab 切回首页） */
  async onPageShow(): Promise<void> {
    await this.refresh();
  }

  private async refresh(): Promise<void> {
    this.loading = true;
    try {
      this.allTasks = await TaskRepository.getInstance().getAllTasks();
    } catch (e) {
      this.allTasks = [];
    }
    this.rebuildDerived();
    this.loading = false;
  }

  /** 由 allTasks 派生三类列表与统计 */
  private rebuildDerived(): void {
    const now: Date = new Date();
    const startOfToday: number = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0, 0).getTime();
    const endOfToday: number = startOfToday + 24 * 60 * 60 * 1000 - 1;
    const in7Days: number = startOfToday + 7 * 24 * 60 * 60 * 1000;

    const todayArr: HomeTaskVM[] = [];
    const upcomingArr: HomeTaskVM[] = [];
    const activityArr: HomeTaskVM[] = [];

    for (const t of this.allTasks) {
      const displayStatus: TaskStatus = resolveExpired(t);
      // 首页只围绕活动开始时间展示，不再使用截止时间。
      const isTodayActivity: boolean = t.eventTime !== null && t.eventTime >= startOfToday && t.eventTime <= endOfToday;
      if (isTodayActivity) {
        todayArr.push(this.toVM(t, displayStatus));
      }
      // 未来 7 天活动（不与今日重复）
      if (t.eventTime !== null && t.eventTime > endOfToday && t.eventTime <= in7Days) {
        upcomingArr.push(this.toVM(t, displayStatus));
      }
      // 稍后活动：7 天以后
      if (t.eventTime !== null && t.eventTime > in7Days) {
        activityArr.push(this.toVM(t, displayStatus));
      }
    }

    todayArr.sort((a: HomeTaskVM, b: HomeTaskVM): number => {
      return (a.task.eventTime ?? Number.MAX_SAFE_INTEGER) - (b.task.eventTime ?? Number.MAX_SAFE_INTEGER);
    });
    // 未来活动按 eventTime 升序
    upcomingArr.sort((a: HomeTaskVM, b: HomeTaskVM): number => {
      const ea: number = a.task.eventTime ?? Number.MAX_SAFE_INTEGER;
      const eb: number = b.task.eventTime ?? Number.MAX_SAFE_INTEGER;
      return ea - eb;
    });
    // 最近活动按 eventTime 升序
    activityArr.sort((a: HomeTaskVM, b: HomeTaskVM): number => {
      const ea: number = a.task.eventTime ?? Number.MAX_SAFE_INTEGER;
      const eb: number = b.task.eventTime ?? Number.MAX_SAFE_INTEGER;
      return ea - eb;
    });

    this.todayList = todayArr;
    this.upcomingList = upcomingArr;
    this.activityList = activityArr;
    this.todayCountValue = todayArr.length;
    this.upcomingCountValue = upcomingArr.length;
    let pending: number = 0;
    for (const task of this.allTasks) {
      if (resolveExpired(task) === TaskStatus.PENDING) {
        pending++;
      }
    }
    this.pendingCountValue = pending;
  }

  private toVM(task: Task, displayStatus: TaskStatus): HomeTaskVM {
    const parts: string[] = [task.category];
    if (task.eventTime !== null) {
      parts.push(`活动 ${formatShortDate(task.eventTime)}`);
    }
    return {
      task,
      displayStatus,
      subtitle: parts.join(' · ')
    };
  }

  build() {
    Column() {
      this.buildHeader();
      Scroll() {
        Column() {
          if (this.isDesktop) {
            Row({ space: Theme.space.lg }) {
              Column() {
                this.buildStatsRow();
                this.buildRecognizeEntry();
                this.buildTodaySection();
              }
              .width('42%')
              .alignItems(HorizontalAlign.Start)

              Column() {
                this.buildDesktopOverviewHeader();
                this.buildUpcomingSection();
                this.buildActivitySection();
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            Column() {
              this.buildStatsRow();
              this.buildRecognizeEntry();
              this.buildTodaySection();
              this.buildUpcomingSection();
              this.buildActivitySection();
            }
            .width('100%')
          }
        }
        .width('100%')
        .padding({
          left: this.isDesktop ? Theme.space.xl : Theme.space.lg,
          right: this.isDesktop ? Theme.space.xl : Theme.space.lg,
          bottom: 32
        })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.color.bgPage)
  }

  @Builder
  buildDesktopOverviewHeader() {
    Row() {
      Column() {
        Text('活动总览')
          .fontSize(Theme.font.titleMd)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.color.textPrimary)
        Text('在同一页面查看近期与稍后安排')
          .fontSize(Theme.font.bodySm)
          .fontColor(Theme.color.textSecondary)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      Text(`${this.allTasks.length} 项`)
        .fontSize(Theme.font.caption)
        .fontColor(Theme.color.primary)
        .backgroundColor(Theme.color.primaryLight)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(Theme.space.xl2)
    }
    .width('100%')
    .padding(Theme.space.lg)
    .backgroundColor(Theme.color.bgCard)
    .borderRadius(Theme.radius.lg)
    .margin({ bottom: Theme.space.lg })
  }

  @Builder
  buildHeader() {
    Row() {
      Column() {
        Text($r('app.string.home_title'))
          .fontSize(Theme.font.titleLg)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.color.textPrimary)
        Text($r('app.string.home_subtitle'))
          .fontSize(Theme.font.bodySm)
          .fontColor(Theme.color.textSecondary)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(TITLE_BAR_HEIGHT)
    .padding({ left: Theme.space.lg, right: Theme.space.lg })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildStatsRow() {
    Row({ space: Theme.space.sm }) {
      Column() {
        Text(`${this.todayCountValue}`)
          .fontSize(Theme.font.titleLg)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.color.primary)
        Text($r('app.string.home_stat_today'))
          .fontSize(Theme.font.caption)
          .fontColor(Theme.color.textTertiary)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: Theme.space.md, bottom: Theme.space.md })
      .backgroundColor(Theme.color.bgCard)
      .borderRadius(Theme.radius.md)
      Column() {
        Text(`${this.pendingCountValue}`)
          .fontSize(Theme.font.titleLg)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.color.warning)
        Text($r('app.string.home_stat_pending'))
          .fontSize(Theme.font.caption)
          .fontColor(Theme.color.textTertiary)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: Theme.space.md, bottom: Theme.space.md })
      .backgroundColor(Theme.color.bgCard)
      .borderRadius(Theme.radius.md)
      Column() {
        Text(`${this.upcomingCountValue}`)
          .fontSize(Theme.font.titleLg)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.color.danger)
        Text($r('app.string.home_stat_upcoming'))
          .fontSize(Theme.font.caption)
          .fontColor(Theme.color.textTertiary)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: Theme.space.md, bottom: Theme.space.md })
      .backgroundColor(Theme.color.bgCard)
      .borderRadius(Theme.radius.md)
    }
    .width('100%')
    .margin({ bottom: Theme.space.lg })
  }

  @Builder
  buildRecognizeEntry() {
    Row() {
      Column() {
        Text($r('app.string.home_recognize_entry'))
          .fontSize(Theme.font.titleSm)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.color.textInverse)
        Text($r('app.string.home_recognize_hint'))
          .fontSize(Theme.font.bodySm)
          .fontColor(Theme.color.textInverse)
          .opacity(0.85)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text('›')
        .fontSize(24)
        .fontColor(Theme.color.textInverse)
    }
    .width('100%')
    .padding({ top: Theme.space.lg, bottom: Theme.space.lg, left: Theme.space.lg, right: Theme.space.lg })
    .margin({ bottom: Theme.space.lg })
    .borderRadius(Theme.radius.lg)
    .backgroundColor(Theme.color.primary)
    .onClick(() => {
      this.currentTab = 1;
    })
  }

  @Builder
  buildTodaySection() {
    this.buildSectionHeader($r('app.string.home_today_todo'), this.todayList.length, true);
    if (this.todayList.length === 0) {
      Column() {
        EmptyState({ message: $r('app.string.home_empty_today'), hint: '今天可以喘口气啦' })
      }
      .width('100%')
      .borderRadius(Theme.radius.md)
      .backgroundColor(Theme.color.bgCard)
      .padding({ left: Theme.space.lg, right: Theme.space.lg })
      .margin({ bottom: Theme.space.lg })
    } else {
      Column() {
        ForEach(this.todayList, (vm: HomeTaskVM) => {
          this.buildTaskCard(vm)
        }, (vm: HomeTaskVM) => vm.task.id)
      }
      .width('100%')
      .margin({ bottom: Theme.space.lg })
    }
  }

  @Builder
  buildUpcomingSection() {
    this.buildSectionHeader($r('app.string.home_upcoming_deadline'), this.upcomingList.length, false);
    if (this.upcomingList.length === 0) {
      Column() {
        EmptyState({ message: $r('app.string.home_empty_upcoming'), hint: '识别新的通知后会出现在这里' })
      }
      .width('100%')
      .borderRadius(Theme.radius.md)
      .backgroundColor(Theme.color.bgCard)
      .padding({ left: Theme.space.lg, right: Theme.space.lg })
      .margin({ bottom: Theme.space.lg })
    } else {
      Column() {
        ForEach(this.upcomingList, (vm: HomeTaskVM) => {
          this.buildTaskCard(vm)
        }, (vm: HomeTaskVM) => vm.task.id)
      }
      .width('100%')
      .margin({ bottom: Theme.space.lg })
    }
  }

  @Builder
  buildActivitySection() {
    this.buildSectionHeader($r('app.string.home_recent_activity'), this.activityList.length, false);
    if (this.activityList.length === 0) {
      Column() {
        EmptyState({ message: $r('app.string.home_empty_activity'), hint: '识别新的通知后会出现在这里' })
      }
      .width('100%')
      .borderRadius(Theme.radius.md)
      .backgroundColor(Theme.color.bgCard)
      .padding({ left: Theme.space.lg, right: Theme.space.lg })
    } else {
      Column() {
        ForEach(this.activityList, (vm: HomeTaskVM) => {
          this.buildTaskCard(vm)
        }, (vm: HomeTaskVM) => vm.task.id)
      }
      .width('100%')
    }
  }

  @Builder
  buildSectionHeader(title: Resource, count: number, isToday: boolean) {
    Row() {
      Text(title)
        .fontSize(Theme.font.titleSm)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.color.textPrimary)
      if (count > 0) {
        Text('·')
          .fontSize(Theme.font.bodySm)
          .fontColor(Theme.color.textTertiary)
          .margin({ left: 6, right: 6 })
        Text(`${count}`)
          .fontSize(Theme.font.bodySm)
          .fontColor(Theme.color.primary)
      }
      Blank()
      Text($r('app.string.home_view_all'))
        .fontSize(Theme.font.bodySm)
        .fontColor(Theme.color.textTertiary)
        .onClick(() => {
          this.currentTab = 2;
        })
    }
    .width('100%')
    .margin({ bottom: Theme.space.sm })
  }

  @Builder
  buildTaskCard(vm: HomeTaskVM) {
    Row() {
      Column() {
        Text(vm.task.title)
          .fontSize(Theme.font.bodyMd)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.color.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(vm.subtitle)
          .fontSize(Theme.font.caption)
          .fontColor(Theme.color.textSecondary)
          .margin({ top: 4 })
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 状态标签
      Text(statusLabel(vm.displayStatus))
        .fontSize(Theme.font.caption)
        .fontColor(
          vm.displayStatus === TaskStatus.EXPIRED ? Theme.color.danger
            : vm.displayStatus === TaskStatus.COMPLETED ? Theme.color.success
            : Theme.color.primary
        )
        .backgroundColor(
          vm.displayStatus === TaskStatus.EXPIRED ? Theme.color.bgSection
            : vm.displayStatus === TaskStatus.COMPLETED ? Theme.color.bgSection
            : Theme.color.primaryLight
        )
        .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        .borderRadius(Theme.radius.sm)
    }
    .width('100%')
    .padding({ left: Theme.space.md, right: Theme.space.md, top: Theme.space.md, bottom: Theme.space.md })
    .backgroundColor(Theme.color.bgCard)
    .borderRadius(Theme.radius.md)
    .margin({ bottom: Theme.space.sm })
    .onClick(() => {
      // 桥接到 TaskPage 打开详情
      this.homeOpenTaskId = vm.task.id;
      this.currentTab = 2;
    })
  }
}

/** 时间戳 -> "MM-dd HH:mm" 简短展示 */
function formatShortDate(ts: number): string {
  const d: Date = new Date(ts);
  const mm: string = (d.getMonth() + 1).toString().padStart(2, '0');
  const dd: string = d.getDate().toString().padStart(2, '0');
  const hh: string = d.getHours().toString().padStart(2, '0');
  const mi: string = d.getMinutes().toString().padStart(2, '0');
  return `${mm}-${dd} ${hh}:${mi}`;
}
