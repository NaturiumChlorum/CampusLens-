/**
 * Theme.ets
 * 拾讯 CampusLens 主题设计令牌
 * 统一管理颜色 / 间距 / 圆角 / 字号，所有页面通过 Theme 引用，禁止散落硬编码。
 */

/** 颜色令牌：通过资源引用，支持浅色 / 深色自动切换 */
export interface ColorTokens {
  primary: Resource;
  primaryPressed: Resource;
  primaryLight: Resource;
  accent: Resource;
  bgPage: Resource;
  bgCard: Resource;
  bgSection: Resource;
  textPrimary: Resource;
  textSecondary: Resource;
  textTertiary: Resource;
  textInverse: Resource;
  divider: Resource;
  success: Resource;
  warning: Resource;
  danger: Resource;
  tabInactive: Resource;
}

/** 字号令牌 */
export interface FontTokens {
  titleLg: Resource;
  titleMd: Resource;
  titleSm: Resource;
  bodyMd: Resource;
  bodySm: Resource;
  caption: Resource;
}

/** 圆角令牌 */
export interface RadiusTokens {
  sm: Resource;
  md: Resource;
  lg: Resource;
}

/** 间距令牌 */
export interface SpaceTokens {
  xs: Resource;
  sm: Resource;
  md: Resource;
  lg: Resource;
  xl: Resource;
  xl2: Resource;
}

export class Theme {
  /** 颜色：通过资源引用，支持浅色 / 深色自动切换 */
  static readonly color: ColorTokens = {
    primary: $r('app.color.primary'),
    primaryPressed: $r('app.color.primary_pressed'),
    primaryLight: $r('app.color.primary_light'),
    accent: $r('app.color.accent'),
    bgPage: $r('app.color.bg_page'),
    bgCard: $r('app.color.bg_card'),
    bgSection: $r('app.color.bg_section'),
    textPrimary: $r('app.color.text_primary'),
    textSecondary: $r('app.color.text_secondary'),
    textTertiary: $r('app.color.text_tertiary'),
    textInverse: $r('app.color.text_inverse'),
    divider: $r('app.color.divider'),
    success: $r('app.color.success'),
    warning: $r('app.color.warning'),
    danger: $r('app.color.danger'),
    tabInactive: $r('app.color.tab_inactive')
  };

  /** 字号 */
  static readonly font: FontTokens = {
    titleLg: $r('app.float.title_lg'),
    titleMd: $r('app.float.title_md'),
    titleSm: $r('app.float.title_sm'),
    bodyMd: $r('app.float.body_md'),
    bodySm: $r('app.float.body_sm'),
    caption: $r('app.float.caption')
  };

  /** 圆角 */
  static readonly radius: RadiusTokens = {
    sm: $r('app.float.radius_sm'),
    md: $r('app.float.radius_md'),
    lg: $r('app.float.radius_lg')
  };

  /** 间距 */
  static readonly space: SpaceTokens = {
    xs: $r('app.float.space_xs'),
    sm: $r('app.float.space_sm'),
    md: $r('app.float.space_md'),
    lg: $r('app.float.space_lg'),
    xl: $r('app.float.space_xl'),
    xl2: $r('app.float.space_2xl')
  };
}

/** 标题栏高度（vp） */
export const TITLE_BAR_HEIGHT = 56;
/** 底部 Tab 栏高度（vp） */
export const TAB_BAR_HEIGHT = 56;
