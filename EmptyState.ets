/**
 * EmptyState.ets
 * 空状态占位组件，统一展示「无数据」场景，避免页面空白。
 */

import { Theme } from '../common/Theme';

@Component
export struct EmptyState {
  @Prop message: string | Resource = '暂无内容';
  @Prop hint: string = '';
  private symbol: string = '◌';

  build() {
    Column() {
      Text(this.symbol)
        .fontSize(40)
        .fontColor(Theme.color.textTertiary)
        .margin({ bottom: Theme.space.md })

      Text(this.message)
        .fontSize(Theme.font.bodyMd)
        .fontColor(Theme.color.textSecondary)

      if (this.hint.length > 0) {
        Text(this.hint)
          .fontSize(Theme.font.bodySm)
          .fontColor(Theme.color.textTertiary)
          .margin({ top: Theme.space.xs })
      }
    }
    .width('100%')
    .padding({ top: 48, bottom: 48 })
    .justifyContent(FlexAlign.Center)
  }
}
