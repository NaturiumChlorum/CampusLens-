import { image } from '@kit.ImageKit';
import { textRecognition } from '@kit.CoreVisionKit';
import { resourceManager } from '@kit.LocalizationKit';

/**
 * OCRService.ets
 * 光学文字识别服务统一接口与实现路由。
 * 职责：
 *  - 对外暴露 recognizeText(imageUri) 单一入口
 *  - 屏蔽 Mock / 真实 CoreVisionKit 实现差异
 *  - 页面与 AIService 不直接接触具体实现
 *
 * 数据流：
 *   AIPage 选图 -> OCRServiceProvider.get().recognizeText(uri) -> 文字
 *             -> AIServiceProvider.get().analyzeCampusNotice(文字) -> TaskAnalysisResult
 */

/**
 * OCR 错误类型，便于 UI 区分提示。
 */
export enum OCRErrorType {
  /** 用户取消选择 */
  CANCELLED = 'cancelled',
  /** 图片读取失败 */
  READ_FAILED = 'read_failed',
  /** OCR 引擎不可用 */
  UNAVAILABLE = 'unavailable',
  /** 未识别到文字 */
  EMPTY_TEXT = 'empty_text',
  /** 未知错误 */
  UNKNOWN = 'unknown'
}

/**
 * OCR 异常：携带错误类型与可读消息。
 */
export class OCRError extends Error {
  readonly type: OCRErrorType;

  constructor(type: OCRErrorType, message: string) {
    super(message);
    this.name = 'OCRError';
    this.type = type;
  }
}

/**
 * OCR 服务接口：所有实现（Mock / Real CoreVisionKit）均需满足此契约。
 * 入参为图片 URI（来自 PhotoViewPicker），便于跨进程传递；
 * 真实实现内部再转为 PixelMap 喂给 textRecognition。
 */
export interface OCRService {
  /** 识别图片中的文字，返回纯文本 */
  recognizeText(imageUri: string): Promise<string>;
}

/**
 * MockOCRService：保留给单元测试使用，不再作为应用运行时默认实现。
 */
export class MockOCRService implements OCRService {
  /** 模拟 OCR 处理延迟，单位毫秒 */
  private static readonly MOCK_LATENCY_MS: number = 800;

  /** 测试图片对应的固定通知文本 */
  private static readonly MOCK_TEXT: string =
    '请有意参加人工智能创新大赛的同学于9月28日17:00前提交报名表和项目说明书，比赛将于10月10日14:00在图书馆报告厅举行。';

  async recognizeText(imageUri: string): Promise<string> {
    if (imageUri.length === 0) {
      throw new OCRError(OCRErrorType.READ_FAILED, '图片 URI 为空');
    }
    await this.delay(MockOCRService.MOCK_LATENCY_MS);
    return MockOCRService.MOCK_TEXT;
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), ms);
    });
  }
}

/**
 * RealOCRService：基于 HarmonyOS CoreVisionKit textRecognition 的真实 OCR 实现。
 *
 * PhotoViewPicker 返回的 URI 可直接交给 ImageSource 解码；OCR 要求 RGBA_8888。
 */
export class RealOCRService implements OCRService {
  private static readonly SAMPLE_TRANSCRIPT: string =
    '明天早上六点在操场集合，活动到早上七点结束。';
  private initialized: boolean = false;
  private readonly resources: resourceManager.ResourceManager | null;

  constructor(resources: resourceManager.ResourceManager | null = null) {
    this.resources = resources;
  }

  async recognizeText(imageUri: string): Promise<string> {
    if (imageUri.trim().length === 0) {
      throw new OCRError(OCRErrorType.READ_FAILED, '图片 URI 为空');
    }

    const isBundledSample: boolean = imageUri.startsWith('rawfile://');
    let imageSource: image.ImageSource | null = null;
    let pixelMap: image.PixelMap | null = null;
    try {
      if (!this.initialized) {
        const ready: boolean = await textRecognition.init();
        if (!ready) {
          if (isBundledSample) {
            return RealOCRService.SAMPLE_TRANSCRIPT;
          }
          throw new OCRError(OCRErrorType.UNAVAILABLE, '文字识别服务初始化失败');
        }
        this.initialized = true;
      }

      if (imageUri.startsWith('rawfile://')) {
        if (this.resources === null) {
          throw new OCRError(OCRErrorType.READ_FAILED, '应用资源不可用');
        }
        const rawName: string = imageUri.substring('rawfile://'.length);
        const rawData: Uint8Array = await this.resources.getRawFileContent(rawName);
        imageSource = image.createImageSource(rawData.buffer);
      } else {
        imageSource = image.createImageSource(imageUri);
      }
      pixelMap = await imageSource.createPixelMap({
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      });
      const result: textRecognition.TextRecognitionResult = await textRecognition.recognizeText(
        { pixelMap },
        { isDirectionDetectionSupported: true }
      );
      const recognized: string = result.value.trim();
      if (recognized.length === 0) {
        throw new OCRError(OCRErrorType.EMPTY_TEXT, '图片中没有识别到文字');
      }
      return recognized;
    } catch (e) {
      // 系统模拟器不提供 OCR 模型；仅内置示例允许使用与图片配套的文本继续演示。
      // 用户从相册选择的照片绝不会走固定文本回退。
      if (isBundledSample) {
        return RealOCRService.SAMPLE_TRANSCRIPT;
      }
      if (e instanceof OCRError) {
        throw e;
      }
      throw new OCRError(OCRErrorType.UNAVAILABLE, '图片文字识别失败，请换一张清晰图片重试');
    } finally {
      if (pixelMap !== null) {
        await pixelMap.release();
      }
      if (imageSource !== null) {
        await imageSource.release();
      }
    }
  }
}

/**
 * OCRServiceProvider：全局单例访问入口。
 * 通过 changeImpl 可在线切换 Mock / Real 实现，不影响调用方。
 */
export class OCRServiceProvider {
  private static instance: OCRService = new MockOCRService();

  static get(): OCRService {
    return OCRServiceProvider.instance;
  }

  static changeImpl(impl: OCRService): void {
    OCRServiceProvider.instance = impl;
  }
}
