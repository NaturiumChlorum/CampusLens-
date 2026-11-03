/**
 * ProfilePage.ets
 * 我的：数据概览、快捷入口与可交互偏好设置。
 */

import { Theme, TITLE_BAR_HEIGHT } from '../common/Theme';
import { Task, TaskStatus, resolveExpired } from '../models/TaskModel';
import { TaskRepository } from '../repositories/TaskRepository';
import { AgentConfig } from '../common/AgentConfig';

@Component
export struct ProfilePage {
  @Prop isDesktop: boolean = false;
  @StorageLink('tabIndex') currentTab: number = 0;
  @StorageLink('autoAddCalendar') autoAddCalendar: boolean = true;
  @State taskCount: number = 0;
  @State pendingCount: number = 0;
  @State syncedCount: number = 0;
  @State showTips: boolean = false;
  @State showAbout: boolean = false;
  @State feedback: string = '';
  @State showGateway: boolean = false;
  @State gatewayUrl: string = AgentConfig.gatewayUrl;
  @State gatewayToken: string = '';

  async aboutToAppear(): Promise<void> {
    await this.refreshStats();
  }

  async onPageShow(): Promise<void> {
    await this.refreshStats();
  }

  private async refreshStats(): Promise<void> {
    try {
      const tasks: Task[] = await TaskRepository.getInstance().getAllTasks();
      this.taskCount = tasks.length;
      let pending: number = 0;
      let synced: number = 0;
      for (const task of tasks) {
        if (resolveExpired(task) === TaskStatus.PENDING) {
          pending++;
        }
        if (task.calendarActivityEventId.length > 0 || task.calendarDeadlineEventId.length > 0) {
          synced++;
        }
      }
      this.pendingCount = pending;
      this.syncedCount = synced;
    } catch (e) {
      this.taskCount = 0;
      this.pendingCount = 0;
      this.syncedCount = 0;
    }
  }

  private showFeedback(message: string): void {
    this.feedback = message;
    setTimeout((): void => {
      this.feedback = '';
    }, 2200);
  }

  build() {
    Column() {
      this.buildHeader();
      Scroll() {
        Column() {
          if (this.isDesktop) {
            Row({ space: Theme.space.xl }) {
              Column() {
                this.buildProfileCard();
                this.buildStats();
                this.buildDesktopSummary();
              }
              .width('42%')
              .alignItems(HorizontalAlign.Start)

              Column() {
                this.buildQuickActions();
                this.buildSettingsGroup();
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            Column() {
              this.buildProfileCard();
              this.buildStats();
              this.buildQuickActions();
              this.buildSettingsGroup();
            }
            .width('100%')
          }
          if (this.feedback.length > 0) {
            Text(this.feedback)
              .fontSize(Theme.font.bodySm)
              .fontColor(Theme.color.success)
              .margin({ top: Theme.space.md })
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
  buildDesktopSummary() {
    Column() {
      Text('工作台概览')
        .fontSize(Theme.font.titleSm)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.color.textPrimary)
      Text(`当前共有 ${this.taskCount} 项任务，其中 ${this.pendingCount} 项等待处理，${this.syncedCount} 项已经同步到系统日历。`)
        .fontSize(Theme.font.bodySm)
        .fontColor(Theme.color.textSecondary)
        .lineHeight(22)
        .margin({ top: Theme.space.sm })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Theme.space.lg)
    .backgroundColor(Theme.color.primaryLight)
    .borderRadius(Theme.radius.lg)
  }

  @Builder
  buildHeader() {
    Row() {
      Text($r('app.string.profile_title'))
        .fontSize(Theme.font.titleLg)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.color.textPrimary)
      Blank()
      Text('拾讯助手')
        .fontSize(Theme.font.caption)
        .fontColor(Theme.color.primary)
        .backgroundColor(Theme.color.primaryLight)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .borderRadius(Theme.space.xl2)
    }
    .width('100%')
    .height(TITLE_BAR_HEIGHT)
    .padding({ left: Theme.space.lg, right: Theme.space.lg })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildProfileCard() {
    Row() {
      Text('讯')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.color.textInverse)
        .width(56)
        .height(56)
        .textAlign(TextAlign.Center)
        .backgroundColor(Theme.color.primary)
        .borderRadius(28)
      Column() {
        Text('我的校园助手')
          .fontSize(Theme.font.titleMd)
          .fontWeight(FontWeight.Bold)
          .fontColor(Theme.color.textPrimary)
        Text('把通知变成清晰可执行的安排')
          .fontSize(Theme.font.bodySm)
          .fontColor(Theme.color.textSecondary)
          .margin({ top: 5 })
        Text($r('app.string.profile_version'))
          .fontSize(Theme.font.caption)
          .fontColor(Theme.color.textTertiary)
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: Theme.space.md })
    }
    .width('100%')
    .padding(Theme.space.lg)
    .borderRadius(Theme.radius.lg)
    .backgroundColor(Theme.color.bgCard)
    .margin({ bottom: Theme.space.md })
  }

  @Builder
  buildStats() {
    Row({ space: Theme.space.sm }) {
      Column() {
        Text(`${this.taskCount}`).fontSize(Theme.font.titleMd).fontWeight(FontWeight.Bold).fontColor(Theme.color.primary)
        Text('全部任务').fontSize(Theme.font.caption).fontColor(Theme.color.textTertiary).margin({ top: 3 })
      }
      .layoutWeight(1).padding({ top: Theme.space.md, bottom: Theme.space.md })
      .backgroundColor(Theme.color.bgCard).borderRadius(Theme.radius.md)
      Column() {
        Text(`${this.pendingCount}`).fontSize(Theme.font.titleMd).fontWeight(FontWeight.Bold).fontColor(Theme.color.warning)
        Text('待处理').fontSize(Theme.font.caption).fontColor(Theme.color.textTertiary).margin({ top: 3 })
      }
      .layoutWeight(1).padding({ top: Theme.space.md, bottom: Theme.space.md })
      .backgroundColor(Theme.color.bgCard).borderRadius(Theme.radius.md)
      Column() {
        Text(`${this.syncedCount}`).fontSize(Theme.font.titleMd).fontWeight(FontWeight.Bold).fontColor(Theme.color.success)
        Text('已同步').fontSize(Theme.font.caption).fontColor(Theme.color.textTertiary).margin({ top: 3 })
      }
      .layoutWeight(1).padding({ top: Theme.space.md, bottom: Theme.space.md })
      .backgroundColor(Theme.color.bgCard).borderRadius(Theme.radius.md)
    }
    .width('100%')
    .margin({ bottom: Theme.space.lg })
  }

  @Builder
  buildQuickActions() {
    Column() {
      Text('快捷操作')
        .fontSize(Theme.font.titleSm)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.color.textPrimary)
        .width('100%')
        .textAlign(TextAlign.Start)
      Row({ space: Theme.space.sm }) {
        this.buildQuickAction('✦', '开始识别', '文字或照片', 1)
        this.buildQuickAction('☰', '查看任务', '活动与日历', 2)
      }
      .width('100%')
      .margin({ top: Theme.space.sm })
    }
    .width('100%')
    .margin({ bottom: Theme.space.lg })
  }

  @Builder
  buildQuickAction(icon: string, title: string, subtitle: string, tab: number) {
    Row() {
      Text(icon)
        .fontSize(22)
        .fontColor(Theme.color.primary)
      Column() {
        Text(title)
          .fontSize(Theme.font.bodyMd)
          .fontWeight(FontWeight.Medium)
          .fontColor(Theme.color.textPrimary)
        Text(subtitle)
          .fontSize(Theme.font.caption)
          .fontColor(Theme.color.textTertiary)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: Theme.space.sm })
    }
    .layoutWeight(1)
    .padding({ top: Theme.space.md, bottom: Theme.space.md, left: Theme.space.md, right: Theme.space.sm })
    .backgroundColor(Theme.color.bgCard)
    .borderRadius(Theme.radius.md)
    .onClick(() => {
      this.currentTab = tab;
    })
  }

  @Builder
  buildSettingsGroup() {
    Column() {
      Text('偏好设置')
        .fontSize(Theme.font.titleSm)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.color.textPrimary)
        .width('100%')
        .textAlign(TextAlign.Start)
        .margin({ bottom: Theme.space.sm })
      Column() {
        Row() {
          Column() {
            Text('自动加入系统日历')
              .fontSize(Theme.font.bodyMd)
              .fontColor(Theme.color.textPrimary)
            Text('识别到活动时间后默认勾选')
              .fontSize(Theme.font.caption)
              .fontColor(Theme.color.textTertiary)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Text(this.autoAddCalendar ? '已开启' : '已关闭')
            .fontSize(Theme.font.caption)
            .fontColor(this.autoAddCalendar ? Theme.color.textInverse : Theme.color.textSecondary)
            .backgroundColor(this.autoAddCalendar ? Theme.color.primary : Theme.color.bgSection)
            .padding({ left: 10, right: 10, top: 6, bottom: 6 })
            .borderRadius(Theme.space.xl2)
        }
        .width('100%')
        .height(62)
        .onClick(() => {
          this.autoAddCalendar = !this.autoAddCalendar;
          this.showFeedback(this.autoAddCalendar ? '已开启自动日历同步' : '已关闭自动日历同步');
        })
        this.buildDivider()
        this.buildExpandableItem('智能处理连接设置', this.showGateway, () => {
          this.showGateway = !this.showGateway;
        })
        if (this.showGateway) {
          TextInput({ text: this.gatewayUrl, placeholder: '网关地址' })
            .onChange((value: string) => { this.gatewayUrl = value; })
          TextInput({ text: this.gatewayToken, placeholder: '网关访问凭据（非模型 Key）' })
            .type(InputType.Password).onChange((value: string) => { this.gatewayToken = value; })
          Button('应用连接设置').onClick(() => {
            try {
              AgentConfig.configure(this.gatewayUrl, this.gatewayToken);
              this.showFeedback('连接设置已应用');
            } catch (e) {
              this.showFeedback(e instanceof Error ? e.message : '地址无效');
            }
          }).margin({ bottom: Theme.space.md })
        }
        this.buildDivider()
        this.buildExpandableItem('识别小技巧', this.showTips, () => {
          this.showTips = !this.showTips;
        })
        if (this.showTips) {
          Text('照片尽量拍正、保持光线均匀，并让时间和地点完整出现在画面中。')
            .fontSize(Theme.font.bodySm)
            .fontColor(Theme.color.textSecondary)
            .lineHeight(21)
            .padding({ bottom: Theme.space.md })
        }
        this.buildDivider()
        this.buildExpandableItem('关于拾讯', this.showAbout, () => {
          this.showAbout = !this.showAbout;
        })
        if (this.showAbout) {
          Text('拾讯会把校园通知整理为活动时间、结束时间、地点和材料，并可同步到系统日历。')
            .fontSize(Theme.font.bodySm)
            .fontColor(Theme.color.textSecondary)
            .lineHeight(21)
            .padding({ bottom: Theme.space.md })
        }
      }
      .width('100%')
      .borderRadius(Theme.radius.md)
      .backgroundColor(Theme.color.bgCard)
      .padding({ left: Theme.space.lg, right: Theme.space.lg })
    }
    .width('100%')
  }

  @Builder
  buildExpandableItem(label: string, expanded: boolean, onClick: () => void) {
    Row() {
      Text(label)
        .fontSize(Theme.font.bodyMd)
        .fontColor(Theme.color.textPrimary)
      Blank()
      Text(expanded ? '⌃' : '⌄')
        .fontSize(18)
        .fontColor(Theme.color.textTertiary)
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .onClick(onClick)
  }

  @Builder
  buildDivider() {
    Divider()
      .color(Theme.color.divider)
      .width('100%')
  }
}
