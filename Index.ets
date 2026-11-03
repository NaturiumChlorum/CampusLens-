/**
 * Index.ets
 * 应用根页面：底部 4 Tab 导航容器。
 * 通过 AppStorage('tabIndex') 与子页面共享当前 Tab，支持首页入口一键跳转 AI 识别。
 */

import { Theme, TAB_BAR_HEIGHT } from '../common/Theme';
import { HomePage } from './HomePage';
import { AIPage } from './AIPage';
import { TaskPage } from './TaskPage';
import { ProfilePage } from './ProfilePage';

/** 宽度达到该值后启用电脑端工作区。 */
const DESKTOP_BREAKPOINT: number = 840;
const DESKTOP_NAV_WIDTH: number = 196;

@Entry
@Component
struct Index {
  @StorageLink('tabIndex') currentIndex: number = 0;
  @State isDesktop: boolean = false;

  build() {
    Stack() {
      if (this.isDesktop) {
        this.buildDesktopShell()
      } else {
        this.buildPhoneShell()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.color.bgPage)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width: number = Number(newArea.width);
      if (!Number.isNaN(width)) {
        this.isDesktop = width >= DESKTOP_BREAKPOINT;
      }
    })
  }

  @Builder
  buildPhoneShell() {
    Column() {
      Tabs({ barPosition: BarPosition.End, index: this.currentIndex }) {
        TabContent() {
          if (this.currentIndex === 0) {
            HomePage({ isDesktop: false })
          }
        }
        TabContent() {
          if (this.currentIndex === 1) {
            AIPage({ isDesktop: false })
          }
        }
        TabContent() {
          if (this.currentIndex === 2) {
            TaskPage({ isDesktop: false })
          }
        }
        TabContent() {
          if (this.currentIndex === 3) {
            ProfilePage({ isDesktop: false })
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .barHeight(0)
      .barMode(BarMode.Fixed)
      .onChange((index: number) => {
        this.currentIndex = index;
      })
      this.buildTabBar()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildDesktopShell() {
    Row() {
      Column() {
        Row() {
          Text('讯')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(Theme.color.textInverse)
            .width(40)
            .height(40)
            .textAlign(TextAlign.Center)
            .backgroundColor(Theme.color.primary)
            .borderRadius(12)
          Column() {
            Text('拾讯')
              .fontSize(Theme.font.titleMd)
              .fontWeight(FontWeight.Bold)
              .fontColor(Theme.color.textPrimary)
            Text('CampusLens')
              .fontSize(Theme.font.caption)
              .fontColor(Theme.color.textTertiary)
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: Theme.space.sm })
        }
        .width('100%')
        .padding({ left: Theme.space.lg, right: Theme.space.lg, top: 24, bottom: 28 })

        this.buildDesktopNavItem($r('app.media.nav_home'), $r('app.string.tab_home'), 0)
        this.buildDesktopNavItem($r('app.media.nav_ai'), $r('app.string.tab_ai'), 1)
        this.buildDesktopNavItem($r('app.media.nav_task'), $r('app.string.tab_task'), 2)
        this.buildDesktopNavItem($r('app.media.nav_profile'), $r('app.string.tab_profile'), 3)
        Blank()
        Text('让校园通知更清晰')
          .fontSize(Theme.font.caption)
          .fontColor(Theme.color.textTertiary)
          .padding({ left: Theme.space.lg, right: Theme.space.lg, bottom: Theme.space.lg })
      }
      .width(DESKTOP_NAV_WIDTH)
      .height('100%')
      .backgroundColor(Theme.color.bgCard)
      .border({ width: { right: 0.5 }, color: Theme.color.divider })

      Column() {
        this.buildCurrentPage()
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildCurrentPage() {
    if (this.currentIndex === 0) {
      HomePage({ isDesktop: true })
    } else if (this.currentIndex === 1) {
      AIPage({ isDesktop: true })
    } else if (this.currentIndex === 2) {
      TaskPage({ isDesktop: true })
    } else {
      ProfilePage({ isDesktop: true })
    }
  }

  @Builder
  buildDesktopNavItem(icon: Resource, label: Resource, idx: number) {
    Row() {
      Image(icon)
        .width(21)
        .height(21)
        .fillColor(this.currentIndex === idx ? Theme.color.primary : Theme.color.tabInactive)
      Text(label)
        .fontSize(Theme.font.bodyMd)
        .fontWeight(this.currentIndex === idx ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.currentIndex === idx ? Theme.color.primary : Theme.color.textSecondary)
        .margin({ left: Theme.space.md })
    }
    .width('100%')
    .height(48)
    .padding({ left: Theme.space.lg, right: Theme.space.md })
    .backgroundColor(this.currentIndex === idx ? Theme.color.primaryLight : Theme.color.bgCard)
    .borderRadius(Theme.radius.md)
    .margin({ left: Theme.space.sm, right: Theme.space.sm, bottom: Theme.space.xs })
    .onClick(() => {
      this.currentIndex = idx;
    })
  }

  @Builder
  buildTabBar() {
    Row() {
      this.buildTabItem($r('app.media.nav_home'), $r('app.string.tab_home'), 0)
      this.buildTabItem($r('app.media.nav_ai'), $r('app.string.tab_ai'), 1)
      this.buildTabItem($r('app.media.nav_task'), $r('app.string.tab_task'), 2)
      this.buildTabItem($r('app.media.nav_profile'), $r('app.string.tab_profile'), 3)
    }
    .width('100%')
    .height(TAB_BAR_HEIGHT)
    .backgroundColor(Theme.color.bgCard)
    .border({ width: { top: 0.5 }, color: Theme.color.divider })
  }

  @Builder
  buildTabItem(icon: Resource, label: Resource, idx: number) {
    Column() {
      Image(icon)
        .width(22)
        .height(22)
        .fillColor(this.currentIndex === idx ? Theme.color.primary : Theme.color.tabInactive)
      Text(label)
        .fontSize(Theme.font.caption)
        .fontColor(this.currentIndex === idx ? Theme.color.primary : Theme.color.tabInactive)
        .margin({ top: 2 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentIndex = idx;
    })
  }
}
