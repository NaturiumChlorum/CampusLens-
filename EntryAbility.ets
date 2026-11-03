import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { TaskRepository } from '../repositories/TaskRepository';
import { TaskSeeder } from '../services/TaskSeeder';
import { CalendarServiceProvider, RealCalendarService } from '../services/CalendarService';
import { OCRServiceProvider, RealOCRService } from '../services/OCRService';
import { AgentConfig } from '../common/AgentConfig';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  /** 界面加载必须等待数据库完成初始化，避免首次进入读取到空列表。 */
  private dataReady: Promise<void> = Promise.resolve();

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 启用真实 CalendarKit 实现；此前默认 Mock 只返回假 eventId，不会写入系统日历。
    CalendarServiceProvider.changeImpl(RealCalendarService.create(this.context));
    // 启用 CoreVisionKit 真实图片文字识别，禁止用固定测试文字冒充识别结果。
    OCRServiceProvider.changeImpl(new RealOCRService(this.context.resourceManager));
    // 初始化本地数据库 + 注入测试任务（仅首次）
    this.dataReady = TaskRepository.getInstance()
      .init(this.context)
      .then(async (): Promise<void> => {
        if (AgentConfig.seedDemoOnEmpty) { await TaskSeeder.seedIfEmpty(); }
        hilog.info(DOMAIN, 'testTag', '%{public}s', 'Task DB & seeder ready');
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, 'testTag', 'Task init failed: %{public}s', err.message);
      });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    this.loadContentWhenReady(windowStage);

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  private async loadContentWhenReady(windowStage: window.WindowStage): Promise<void> {
    await this.dataReady;
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
