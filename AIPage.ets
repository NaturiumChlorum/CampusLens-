/**
 * AIPage.ets
 * AI识别：粘贴 / 输入通知文字 → AIService → 跳转结果确认页
 * 阶段3：接入 MockAIService，打通 AIPage → 分析 → 确认页 → 保存为 Task。
 */

import { router } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { Theme, TITLE_BAR_HEIGHT } from '../common/Theme';
import { AIServiceProvider } from '../services/AIService';
import { OCRServiceProvider, OCRError, OCRErrorType } from '../services/OCRService';
import { TaskAnalysisResult, AIAnalysisError, AIErrorType } from '../models/AIModel';
import { ANALYSIS_RESULT_KEY } from './AnalysisResultPage';
import { ANALYSIS_ORIGINAL_KEY, ANALYSIS_SOURCE_KEY, ANALYSIS_DRAFT_KEY } from '../common/AnalysisContext';
import { SourceType } from '../models/TaskModel';
import { AgentRuntime } from '../services/AgentRuntime';
import { TaskDraftService } from '../services/TaskDraftService';
import { ToolTrace, ToolExecution, TaskQueryResult, TaskStatistics } from '../models/AgentModel';

/** OCR 流程阶段，用于 UI 文案切换 */
enum OCRStage {
  IDLE = 0,
  PICKING = 1,
  RECOGNIZING = 2,
  ANALYZING = 3,
  DONE = 4,
  FAILED = 5,
  CANCELLED = 6
}

@Component
export struct AIPage {
  @Prop isDesktop: boolean = false;
  @State inputText: string = '';
  @State isAnalyzing: boolean = false;
  @State errorMsg: string = '';
  @State statusHint: Resource = $r('app.string.ai_status_idle');
  @State ocrStage: OCRStage = OCRStage.IDLE;
  @State lastPickedUri: string = '';
  @State inputSource: SourceType = SourceType.TEXT;
  @State agentBusy: boolean = false;
  @State resultTitle: string = '';
  @State resultText: string = '';
  @State modelReply: string = '';
  @State toolLines: string[] = [];
  @State draftIds: string[] = [];
  @State showTools: boolean = false;
  private latestTraceStart: number = 0;
  private latestLineStart: number = 0;

  aboutToAppear(): void { this.refreshAgent(); }

  private refreshAgent(): void {
    const agent = AgentRuntime.get();
    this.agentBusy = agent.busy;
    this.modelReply = '';
    for (let i = agent.lines.length - 1; i >= this.latestLineStart; i--) {
      if (agent.lines[i].role === 'assistant' || agent.lines[i].role === 'error') {
        this.modelReply = agent.lines[i].text;
        break;
      }
    }
    this.resultTitle = '';
    this.resultText = '';
    for (let i = this.latestTraceStart; i < agent.traces.length; i++) {
      const trace = agent.traces[i];
      if (trace.result.length === 0) { continue; }
      try {
        const result = JSON.parse(trace.result) as ToolExecution;
        if (!result.ok || result.data === undefined) { continue; }
        if (trace.name === 'query_tasks') {
          const data = result.data as TaskQueryResult;
          this.resultTitle = '处理结果';
          this.resultText += `${this.resultText.length > 0 ? '\n\n' : ''}任务查询：找到 ${data.totalMatched} 项任务`;
          for (const task of data.tasks) {
            this.resultText += `\n${task.title} · ${task.status}${task.deadline === null ? '' : ' · 截止 ' + task.deadline}`;
          }
          continue;
        }
        if (trace.name === 'get_task_statistics') {
          const data = result.data as TaskStatistics;
          this.resultTitle = '处理结果';
          this.resultText += `${this.resultText.length > 0 ? '\n\n' : ''}任务统计：总数 ${data.total} · 未完成 ${data.unfinished} · 即将到期 ${data.dueSoon}\n统计区间：${data.windowStart} 至 ${data.windowEnd}`;
          continue;
        }
        if (trace.name === 'create_task_draft') {
          this.resultTitle = '处理结果';
          this.resultText += `${this.resultText.length > 0 ? '\n\n' : ''}任务草稿：尚未保存，请核对后确认。`;
        }
      } catch (e) { continue; }
    }
    this.toolLines = agent.traces.map((trace: ToolTrace): string =>
      `${trace.name} · ${trace.state}\n调用 ID：${trace.id}\n参数：${trace.arguments}\n执行结果：${trace.result}`);
    this.draftIds = agent.draftIds.filter((id: string): boolean =>
      TaskDraftService.getInstance().get(id)?.state === 'pending_confirmation');
  }

  private async sendAgent(): Promise<void> {
    try {
      this.latestTraceStart = AgentRuntime.get().traces.length;
      this.latestLineStart = AgentRuntime.get().lines.length;
      await AgentRuntime.get().send(this.inputText, this.inputSource, (): void => { this.refreshAgent(); });
      this.errorMsg = '';
    } catch (e) { this.errorMsg = e instanceof Error ? e.message : '请求失败'; }
  }

  private openDraft(id: string): void {
    const draft = TaskDraftService.getInstance().get(id);
    if (draft === undefined || draft.state !== 'pending_confirmation') { return; }
    const input = draft.input;
    const result: TaskAnalysisResult = {
      title: input.title, description: input.description, category: input.category, deadline: input.deadline,
      eventTime: input.eventTime, eventEndTime: input.eventEndTime, location: input.location, materials: input.materials,
      contact: input.contact, notes: input.notes, priority: input.priority, confidence: 0, matchedKeywords: []
    };
    AppStorage.setOrCreate<string>(ANALYSIS_DRAFT_KEY, id);
    AppStorage.setOrCreate<string>(ANALYSIS_ORIGINAL_KEY, input.originalText);
    AppStorage.setOrCreate<SourceType>(ANALYSIS_SOURCE_KEY, input.sourceType);
    AppStorage.setOrCreate<TaskAnalysisResult>(ANALYSIS_RESULT_KEY, result);
    router.pushUrl({ url: 'pages/AnalysisResultPage' });
  }

  @Builder
  buildAgentResults(): void {
    Column({ space: 12 }) {
      if (this.resultTitle.length > 0 || this.modelReply.length > 0) {
        Text(this.resultTitle.length > 0 ? this.resultTitle : '处理结果')
          .fontSize(Theme.font.titleSm).fontColor(Theme.color.textPrimary)
        if (this.resultText.length > 0) {
          Text(this.resultText).width('100%').fontSize(Theme.font.bodyMd).fontColor(Theme.color.textPrimary)
        }
        if (this.modelReply.length > 0) {
          Text(this.modelReply).width('100%').fontSize(Theme.font.bodySm)
            .fontColor(Theme.color.textSecondary)
        }
      }
      if (this.toolLines.length > 0) {
        Button(this.showTools ? '收起工具调用记录' : '显示工具调用记录').onClick(() => { this.showTools = !this.showTools; })
        if (this.showTools) {
          ForEach(this.toolLines, (line: string) => {
            Text(line).width('100%').fontSize(Theme.font.caption).fontColor(Theme.color.textSecondary)
              .padding(10).backgroundColor(Theme.color.bgSection).borderRadius(Theme.radius.sm)
          })
        }
      }
      ForEach(this.draftIds, (id: string) => {
        Row({ space: 8 }) {
          Button(`确认草稿：${TaskDraftService.getInstance().get(id)?.input.title ?? ''}`)
            .layoutWeight(1).enabled(!this.agentBusy).onClick(() => { this.openDraft(id); })
          Button('取消').enabled(!this.agentBusy).onClick(() => {
            TaskDraftService.getInstance().cancel(id); this.refreshAgent();
          })
        }
      }, (id: string) => id)
      if (this.agentBusy) { LoadingProgress().width(24).height(24) }
      if (this.errorMsg.length > 0) { Text(this.errorMsg).fontColor(Theme.color.danger).fontSize(Theme.font.bodySm) }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }

  build(): void {
    Column() {
      this.buildHeader()
      Scroll() {
        Column() {
          if (this.isDesktop) {
            Row({ space: Theme.space.xl }) {
              Column() {
                this.buildDesktopSectionTitle('粘贴或输入通知', 'AI 会提取标题、地点与活动起止时间')
                this.buildInputArea()
                this.buildClearButton()
                this.buildAnalyzeButton()
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .padding(Theme.space.lg)
              .backgroundColor(Theme.color.bgCard)
              .borderRadius(Theme.radius.lg)

              Column() {
                this.buildDesktopSectionTitle('照片与识别状态', '可从相册读取通知，识别后进入确认页面')
                this.buildImageSection()
                this.buildStatusCard()
                this.buildDesktopTips()
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)
              .padding(Theme.space.lg)
              .backgroundColor(Theme.color.bgCard)
              .borderRadius(Theme.radius.lg)
            }
            .width('100%')
            .alignItems(VerticalAlign.Top)
          } else {
            Column() {
              this.buildInputArea()
              this.buildClearButton()
              this.buildAnalyzeButton()
              this.buildImageSection()
              this.buildStatusCard()
            }
            .width('100%')
          }
          this.buildAgentResults()
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
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Theme.color.bgPage)
  }

  @Builder
  buildDesktopSectionTitle(title: string, subtitle: string): void {
    Column() {
      Text(title)
        .fontSize(Theme.font.titleMd)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.color.textPrimary)
      Text(subtitle)
        .fontSize(Theme.font.bodySm)
        .fontColor(Theme.color.textSecondary)
        .margin({ top: 4, bottom: Theme.space.lg })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  buildDesktopTips(): void {
    Column() {
      Text('识别建议')
        .fontSize(Theme.font.titleSm)
        .fontWeight(FontWeight.Medium)
        .fontColor(Theme.color.textPrimary)
      Text('使用完整自然语言，例如：明天下午两点到四点在教室4309开会。')
        .fontSize(Theme.font.bodySm)
        .fontColor(Theme.color.textSecondary)
        .lineHeight(21)
        .margin({ top: Theme.space.sm })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(Theme.space.md)
    .backgroundColor(Theme.color.bgSection)
    .borderRadius(Theme.radius.md)
    .margin({ top: Theme.space.lg })
  }

  @Builder
  buildHeader(): void {
    Row() {
      Text($r('app.string.ai_title'))
        .fontSize(Theme.font.titleLg)
        .fontWeight(FontWeight.Bold)
        .fontColor(Theme.color.textPrimary)
      Blank()
      Text($r('app.string.ai_status_idle'))
        .fontSize(Theme.font.caption)
        .fontColor(Theme.color.textTertiary)
    }
    .width('100%')
    .height(TITLE_BAR_HEIGHT)
    .padding({ left: Theme.space.lg, right: Theme.space.lg })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildInputArea(): void {
    Column() {
      TextArea({ placeholder: $r('app.string.ai_input_placeholder'), text: this.inputText })
        .fontSize(Theme.font.bodyMd)
        .fontColor(Theme.color.textPrimary)
        .backgroundColor(Theme.color.bgCard)
        .borderRadius(Theme.radius.md)
        .constraintSize({ minHeight: 160 })
        .onChange((val: string) => {
          this.inputText = val;
          this.errorMsg = '';
          this.statusHint = val.trim().length > 0 ? $r('app.string.ai_status_ready') : $r('app.string.ai_status_idle');
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: Theme.space.md })
  }

  @Builder
  buildClearButton(): void {
    if (this.inputText.length > 0) {
      Row() {
        Text($r('app.string.ai_clear_input'))
          .fontSize(Theme.font.bodySm)
          .fontColor(Theme.color.textTertiary)
          .padding({ left: Theme.space.sm, right: Theme.space.sm, top: 4, bottom: 4 })
          .borderRadius(Theme.space.xl2)
          .backgroundColor(Theme.color.bgCard)
          .onClick(() => {
            this.confirmClear();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .margin({ bottom: Theme.space.md })
    }
  }

  private confirmClear(): void {
    AlertDialog.show({
      message: $r('app.string.ai_clear_input_confirm'),
      alignment: DialogAlignment.Center,
      primaryButton: {
        value: $r('app.string.ai_cancel'),
        action: () => {}
      },
      secondaryButton: {
        value: $r('app.string.common_confirm'),
        fontColor: Theme.color.primary,
        action: (): void => {
          this.inputText = '';
          this.errorMsg = '';
          this.statusHint = $r('app.string.ai_status_idle');
        }
      }
    });
  }

  @Builder
  buildAnalyzeButton(): void {
    Row({ space: Theme.space.sm }) {
      Button('查询任务').onClick(() => { this.inputText = '查询我的未完成任务'; this.inputSource = SourceType.TEXT; })
      Button('任务统计').onClick(() => { this.inputText = '统计我的任务总数、未完成数和未来七天内到期数'; this.inputSource = SourceType.TEXT; })
    }.width('100%').margin({ bottom: Theme.space.sm })
    Button(this.agentBusy ? '正在处理…' : '智能处理')
      .width('100%').height(48).enabled(!this.isAnalyzing && !this.agentBusy && this.inputText.trim().length > 0)
      .onClick(() => { this.sendAgent(); })
      .margin({ bottom: Theme.space.sm })
    Button($r('app.string.ai_analyze'))
      .width('100%')
      .height(48)
      .fontSize(Theme.font.titleSm)
      .fontColor(Theme.color.textInverse)
      .backgroundColor(Theme.color.primary)
      .borderRadius(Theme.radius.md)
      .margin({ bottom: Theme.space.lg })
      .enabled(this.inputText.trim().length > 0 && !this.isAnalyzing)
      .opacity(this.inputText.trim().length > 0 && !this.isAnalyzing ? 1 : 0.5)
      .onClick(() => { this.analyze(); })
  }

  private async analyze(): Promise<void> {
    if (this.inputText.trim().length === 0) {
      this.errorMsg = '请先粘贴或输入校园通知文字';
      this.statusHint = $r('app.string.ai_status_idle');
      return;
    }
    this.isAnalyzing = true;
    this.errorMsg = '';
    this.statusHint = $r('app.string.ai_status_analyzing');
    try {
      const result: TaskAnalysisResult = await AIServiceProvider.get().analyzeCampusNotice(this.inputText);
      AppStorage.delete(ANALYSIS_DRAFT_KEY);
      AppStorage.setOrCreate<string>(ANALYSIS_ORIGINAL_KEY, this.inputText);
      AppStorage.setOrCreate<SourceType>(ANALYSIS_SOURCE_KEY, this.inputSource);
      AppStorage.setOrCreate<TaskAnalysisResult>(ANALYSIS_RESULT_KEY, result);
      this.statusHint = $r('app.string.ai_status_done');
      router.pushUrl({ url: 'pages/AnalysisResultPage' });
    } catch (e) {
      const err: AIAnalysisError | Error = e instanceof Error ? e : new Error(String(e));
      if (err instanceof AIAnalysisError && err.type === AIErrorType.EMPTY_INPUT) {
        this.errorMsg = err.message;
      } else {
        this.errorMsg = 'AI 识别失败，请重试';
      }
      this.statusHint = $r('app.string.ai_status_failed');
    } finally {
      this.isAnalyzing = false;
    }
  }

  @Builder
  buildImageSection(): void {
    Divider()
      .color(Theme.color.divider)
      .strokeWidth(0.5)
      .margin({ top: Theme.space.md, bottom: Theme.space.md })

    Text($r('app.string.ai_ocr_section_image'))
      .fontSize(Theme.font.bodySm)
      .fontColor(Theme.color.textSecondary)
      .margin({ bottom: Theme.space.sm })
      .width('100%')
      .textAlign(TextAlign.Start)

    Button($r('app.string.ai_pick_image'))
      .width('100%')
      .height(48)
      .fontSize(Theme.font.titleSm)
      .fontColor(Theme.color.primary)
      .backgroundColor(Theme.color.bgCard)
      .borderRadius(Theme.radius.md)
      .margin({ bottom: Theme.space.md })
      .enabled(!this.isAnalyzing && this.ocrStage !== OCRStage.PICKING)
      .opacity(this.isAnalyzing ? 0.5 : 1)
      .onClick(() => { this.pickImageAndRecognize(); })

    Text('模拟器没有照片？试用示例流程')
      .fontSize(Theme.font.bodySm)
      .fontColor(Theme.color.primary)
      .width('100%')
      .textAlign(TextAlign.Center)
      .margin({ bottom: Theme.space.md })
      .enabled(!this.isAnalyzing)
      .opacity(this.isAnalyzing ? 0.5 : 1)
      .onClick(() => {
        this.recognizeSampleImage();
      })

    if (this.lastPickedUri.length > 0 && this.ocrStage !== OCRStage.PICKING) {
      Text(`已选图：${this.lastPickedUri}`)
        .fontSize(Theme.font.caption)
        .fontColor(Theme.color.textTertiary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ bottom: Theme.space.sm })
    }
  }

  private async pickImageAndRecognize(): Promise<void> {
    this.isAnalyzing = true;
    this.errorMsg = '';
    this.ocrStage = OCRStage.PICKING;
    this.statusHint = $r('app.string.ai_status_picking');

    let imageUri: string = '';
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const options: photoAccessHelper.PhotoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
      options.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = 1;
      const result: photoAccessHelper.PhotoSelectResult = await picker.select(options);
      if (result.photoUris.length === 0) {
        this.ocrStage = OCRStage.CANCELLED;
        this.statusHint = $r('app.string.ai_status_cancelled');
        this.isAnalyzing = false;
        return;
      }
      imageUri = result.photoUris[0];
      this.lastPickedUri = imageUri;
    } catch (e) {
      this.ocrStage = OCRStage.CANCELLED;
      this.statusHint = $r('app.string.ai_status_cancelled');
      this.isAnalyzing = false;
      return;
    }

    await this.recognizeImageUri(imageUri);
  }

  /** 内置示例图片同样走 CoreVisionKit，用于空相册的模拟器和首次体验。 */
  private async recognizeSampleImage(): Promise<void> {
    if (this.isAnalyzing) {
      return;
    }
    this.isAnalyzing = true;
    this.errorMsg = '';
    this.lastPickedUri = '示例校园通知';
    await this.recognizeImageUri('rawfile://ocr_test_notice.jpeg');
  }

  /** 选图与示例图共用的真实 OCR -> 结构化分析流程。 */
  private async recognizeImageUri(imageUri: string): Promise<void> {
    this.ocrStage = OCRStage.RECOGNIZING;
    this.statusHint = $r('app.string.ai_status_ocr');
    let recognizedText: string = '';
    try {
      recognizedText = await OCRServiceProvider.get().recognizeText(imageUri);
    } catch (e) {
      const err: OCRError | Error = e instanceof Error ? e : new Error(String(e));
      this.ocrStage = OCRStage.FAILED;
      this.statusHint = $r('app.string.ai_status_failed');
      this.errorMsg = err instanceof OCRError ? this.mapOCRErrorMessage(err) : 'OCR 识别失败，请重试';
      this.isAnalyzing = false;
      return;
    }

    if (recognizedText.trim().length === 0) {
      this.ocrStage = OCRStage.FAILED;
      this.statusHint = $r('app.string.ai_status_empty_text');
      this.errorMsg = '未识别到文字，请换一张图片';
      this.isAnalyzing = false;
      return;
    }

    this.inputText = recognizedText;
    this.inputSource = SourceType.IMAGE;

    // OCR text remains in the shared input field for optional natural-language processing.

    this.ocrStage = OCRStage.ANALYZING;
    this.statusHint = $r('app.string.ai_status_analyzing_ocr');
    try {
      const analysisResult: TaskAnalysisResult = await AIServiceProvider.get().analyzeCampusNotice(recognizedText);
      AppStorage.delete(ANALYSIS_DRAFT_KEY);
      AppStorage.setOrCreate<string>(ANALYSIS_ORIGINAL_KEY, recognizedText);
      AppStorage.setOrCreate<SourceType>(ANALYSIS_SOURCE_KEY, SourceType.IMAGE);
      AppStorage.setOrCreate<TaskAnalysisResult>(ANALYSIS_RESULT_KEY, analysisResult);
      this.ocrStage = OCRStage.DONE;
      this.statusHint = $r('app.string.ai_status_done');
      router.pushUrl({ url: 'pages/AnalysisResultPage' });
    } catch (e) {
      const err: AIAnalysisError | Error = e instanceof Error ? e : new Error(String(e));
      this.ocrStage = OCRStage.FAILED;
      this.statusHint = $r('app.string.ai_status_failed');
      this.errorMsg = err instanceof AIAnalysisError ? err.message : 'AI 识别失败，请重试';
    } finally {
      this.isAnalyzing = false;
    }
  }

  /** OCR 错误类型 -> 用户可读文案 */
  private mapOCRErrorMessage(err: OCRError): string {
    switch (err.type) {
      case OCRErrorType.READ_FAILED:
        return '图片读取失败';
      case OCRErrorType.UNAVAILABLE:
        return 'OCR 引擎不可用';
      case OCRErrorType.EMPTY_TEXT:
        return '未识别到文字，请换一张图片';
      case OCRErrorType.CANCELLED:
        return '已取消选择图片';
      default:
        return err.message;
    }
  }

  @Builder
  buildStatusCard(): void {
    Column() {
      Row() {
        Column() {
          Text('识别状态')
            .fontSize(Theme.font.bodySm)
            .fontColor(Theme.color.textSecondary)
            .margin({ bottom: 4 })
          Text(this.statusHint)
            .fontSize(Theme.font.bodyMd)
            .fontColor(this.isAnalyzing ? Theme.color.primary : Theme.color.textPrimary)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')

      if (this.isAnalyzing) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(Theme.color.primary)
          .margin({ top: Theme.space.xs })
      }

      if (this.errorMsg.length > 0) {
        Text(this.errorMsg)
          .fontSize(Theme.font.bodySm)
          .fontColor(Theme.color.danger)
          .margin({ top: Theme.space.sm })
      }
    }
    .width('100%')
    .padding(Theme.space.lg)
    .borderRadius(Theme.radius.md)
    .backgroundColor(Theme.color.bgCard)
  }
}
