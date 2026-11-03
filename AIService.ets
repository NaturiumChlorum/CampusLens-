/**
 * AIService.ets
 * AI 识别服务统一接口与实现路由。
 * 职责：
 *  - 对外暴露 analyzeCampusNotice(text) 单一入口
 *  - 屏蔽 Mock / Remote 实现差异
 *  - 页面与 Repository 不直接接触具体实现
 *
 * 数据流：
 *   AIPage -> AIService.analyzeCampusNotice -> TaskAnalysisResult
 *          -> AnalysisResultPage -> TaskRepository.createTask
 */

import { TaskAnalysisResult, AIAnalysisError, AIErrorType } from '../models/AIModel';
import { TaskPriority } from '../models/TaskModel';
import { http } from '@kit.NetworkKit';
import { AgentMessage, AgentRequest, AgentResponse, AgentModelClient } from '../models/AgentModel';
import { AgentConfig } from '../common/AgentConfig';
import { formatCampusDate } from '../common/DateTimeUtils';

/**
 * AI 服务接口：所有实现（Mock / Remote / 本地离线模型）均需满足此契约。
 */
export interface AIService {
  /** 分析校园通知文本，返回结构化任务预览 */
  analyzeCampusNotice(text: string): Promise<TaskAnalysisResult>;
}

/**
 * MockAIService：本地规则匹配实现，无网络依赖、无 API Key。
 * 阶段3 用于打通 AIPage -> 确认页 -> TaskRepository 全流程演示。
 * 阶段4+ 接入真实 OCR / LLM 后，可保留作为离线降级方案。
 */
export class MockAIService implements AIService {
  /** 模拟网络/模型延迟，单位毫秒 */
  private static readonly MOCK_LATENCY_MS: number = 700;

  async analyzeCampusNotice(text: string): Promise<TaskAnalysisResult> {
    // 1. 校验输入
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      throw new AIAnalysisError(AIErrorType.EMPTY_INPUT, '通知内容不能为空');
    }
    if (trimmed.length < 4) {
      throw new AIAnalysisError(AIErrorType.EMPTY_INPUT, '通知内容过短，无法识别');
    }

    // 2. 模拟延迟
    await this.delay(MockAIService.MOCK_LATENCY_MS);

    // 3. 规则匹配：在测试文本中抽取字段
    return this.ruleBasedAnalyze(trimmed);
  }

  /**
   * 基于关键词与正则的规则识别：
   * - 在阶段3测试通知上能复现期望结果
   * - 对常见"截止 / 时间 / 地点 / 材料"句式具备基本鲁棒性
   */
  private ruleBasedAnalyze(text: string): TaskAnalysisResult {
    const matchedKeywords: string[] = [];

    // 4.1 标题：优先匹配「xxx大赛」「xxx讲座」「xxx作业」「xxx活动」
    const titlePatterns: RegExp[] = [
      /([^\s,，。；;]{2,12}大赛)/,
      /([^\s,，。；;]{2,12}讲座)/,
      /([^\s,，。；;]{2,12}作业)/,
      /([^\s,，。；;]{2,12}活动)/,
      /([^\s,，。；;]{2,12}征集)/,
      /([^\s,，。；;]{2,12}比赛)/
    ];
    let title: string = '';
    for (const p of titlePatterns) {
      const m: RegExpMatchArray | null = text.match(p);
      if (m !== null && m.length > 1) {
        title = m[1];
        matchedKeywords.push(`title:${title}`);
        break;
      }
    }
    // 没有明确活动名称时，用句子中的核心动作作为标题，
    // 避免把“明天上午十点去…”这类时间地点文字当成标题。
    if (title.length === 0) {
      const actionTitles: string[] = [
        '开会', '上课', '考试', '答辩', '面试', '培训', '排练', '集合', '报到', '签到'
      ];
      for (const action of actionTitles) {
        if (text.includes(action)) {
          title = action;
          matchedKeywords.push(`title:${title}`);
          break;
        }
      }
    }
    if (title.length === 0) {
      // 退化：取前 12 字符
      title = text.slice(0, Math.min(12, text.length));
    }

    // 4.2 分类：根据标题或文本内容推断
    let category: string = '通知';
    if (text.includes('大赛') || text.includes('比赛')) {
      category = '比赛';
    } else if (text.includes('讲座') || text.includes('分享')) {
      category = '讲座';
    } else if (text.includes('作业') || text.includes('提交')) {
      category = '作业';
    } else if (text.includes('活动') || text.includes('征集')) {
      category = '活动';
    } else if (title === '开会' || title === '上课' || title === '考试' || title === '答辩' ||
      title === '面试' || title === '培训' || title === '排练' || title === '集合' || title === '报到' || title === '签到') {
      category = '活动';
    }
    matchedKeywords.push(`category:${category}`);

    // 4.3 时间：支持绝对日期，以及“明天早上六点”等相对时间
    // 产品只保留活动开始/结束时间，截止时间字段不再生成。
    const deadline: number | null = null;
    const eventTime: number | null = this.extractEventTime(text, matchedKeywords);
    const eventEndTime: number | null = this.extractEventEndTime(text, eventTime, matchedKeywords);

    // 4.4 地点：匹配"在xxx举行 / 于xxx"
    const location: string = this.extractLocation(text, matchedKeywords);

    // 4.5 材料：匹配"提交 xxx 和 xxx" / "携带 xxx"
    const materials: string[] = this.extractMaterials(text, matchedKeywords);

    // 4.6 联系人：匹配"联系人xxx / 联系电话xxx"
    const contact: string = this.extractContact(text, matchedKeywords);

    // 4.7 优先级：含"截止/截止日/截止时间"提升为 high
    let priority: TaskPriority = TaskPriority.MEDIUM;
    if (text.includes('截止') || text.includes('决赛') || text.includes('紧急')) {
      priority = TaskPriority.HIGH;
    } else if (text.includes('可选') || text.includes('自由')) {
      priority = TaskPriority.LOW;
    }

    // 4.8 描述：用原文前 60 字作为简要描述
    const description: string = text.length > 60 ? `${text.slice(0, 60)}…` : text;

    return {
      title,
      description,
      category,
      deadline,
      eventTime,
      eventEndTime,
      location,
      materials,
      contact,
      notes: '',
      priority,
      confidence: 0.85,
      matchedKeywords
    };
  }

  /** 从 "于9月28日17:00前提交" 抽取截止时间 */
  private extractDeadlineTime(text: string, matched: string[]): number | null {
    // 匹配 "X月X日 HH:mm 前" / "截止 X月X日 HH:mm"
    const patterns: RegExp[] = [
      /(\d{1,2})月(\d{1,2})日\s*(\d{1,2}):(\d{2})\s*前/,
      /(?:截止|截止时间|截止日期)[：:\s]*(\d{1,2})月(\d{1,2})日\s*(\d{1,2}):(\d{2})/,
      /(\d{1,2})月(\d{1,2})日\s*(\d{1,2}):(\d{2})/
    ];
    for (const p of patterns) {
      const m: RegExpMatchArray | null = text.match(p);
      if (m !== null && m.length >= 5) {
        const ts: number = this.toTimestamp(m[1], m[2], m[3], m[4]);
        if (ts > 0) {
          matched.push(`deadline:${m[0]}`);
          return ts;
        }
      }
    }
    return null;
  }

  /** 从 "将于10月10日14:00" 抽取活动时间 */
  private extractEventTime(text: string, matched: string[]): number | null {
    // 排除已被 deadline 使用的部分：先去掉"截止"相关句
    const cleaned: string = text.replace(/(?:截止|截止时间|截止日期)[：:\s]*\d{1,2}月\d{1,2}日\s*\d{1,2}:\d{2}\s*前?/g, '');
    const patterns: RegExp[] = [
      /(?:将于|将于当日|活动时间|活动时间：)\s*(\d{1,2})月(\d{1,2})日\s*(\d{1,2}):(\d{2})/,
      /(?:举行|举办)[，,]?\s*时间\s*(\d{1,2})月(\d{1,2})日\s*(\d{1,2}):(\d{2})/,
      /(\d{1,2})月(\d{1,2})日\s*(\d{1,2}):(\d{2})/
    ];
    for (const p of patterns) {
      const m: RegExpMatchArray | null = cleaned.match(p);
      if (m !== null && m.length >= 5) {
        const ts: number = this.toTimestamp(m[1], m[2], m[3], m[4]);
        if (ts > 0) {
          matched.push(`eventTime:${m[0]}`);
          return ts;
        }
      }
    }
    const relativeTime: number | null = this.extractRelativeTime(cleaned, matched);
    if (relativeTime !== null) {
      return relativeTime;
    }
    return null;
  }

  /**
   * 抽取活动结束时间。通知只写开始时间时，默认按 1 小时活动生成结束时间；
   * “六点到八点”或“持续两小时”会覆盖默认时长。
   */
  private extractEventEndTime(text: string, eventTime: number | null, matched: string[]): number | null {
    if (eventTime === null) {
      return null;
    }
    const endPattern: RegExp = /(?:到|至|—|-|~|～)\s*(凌晨|早上|上午|中午|下午|傍晚|晚上)?\s*([0-9零〇一二两三四五六七八九十]{1,3})\s*(?:点|时)(?:钟)?\s*(?:(半)|([0-9零〇一二两三四五六七八九十]{1,3})分?)?/;
    const endMatch: RegExpMatchArray | null = text.match(endPattern);
    if (endMatch !== null && endMatch.length >= 3) {
      const rawHour: number = this.parseChineseNumber(endMatch[2]);
      const minute: number = endMatch[3] === '半' ? 30 : this.parseChineseNumber(endMatch[4] ?? '0');
      if (rawHour >= 0 && rawHour <= 23 && minute >= 0 && minute <= 59) {
        const start: Date = new Date(eventTime);
        let hour: number = this.applyPeriod(rawHour, endMatch[1] ?? '');
        if ((endMatch[1] ?? '').length === 0 && start.getHours() >= 12 && hour < 12) {
          hour += 12;
        }
        const end: Date = new Date(start.getFullYear(), start.getMonth(), start.getDate(), hour, minute, 0, 0);
        if (end.getTime() <= eventTime) {
          end.setDate(end.getDate() + 1);
        }
        matched.push(`eventEndTime:${endMatch[0]}`);
        return end.getTime();
      }
    }

    const durationMatch: RegExpMatchArray | null = text.match(/(?:持续|时长)\s*([0-9零〇一二两三四五六七八九十]{1,3})\s*(?:小时|个小时)/);
    if (durationMatch !== null && durationMatch.length > 1) {
      const hours: number = this.parseChineseNumber(durationMatch[1]);
      if (hours > 0 && hours <= 24) {
        matched.push(`eventEndTime:${durationMatch[0]}`);
        return eventTime + hours * 60 * 60 * 1000;
      }
    }

    matched.push('eventEndTime:默认1小时');
    return eventTime + 60 * 60 * 1000;
  }

  /** 把“明天早上六点/后天下午3点半”转换为本地时间戳 */
  private extractRelativeTime(text: string, matched: string[]): number | null {
    const pointPattern: RegExp = /(今天|明天|后天)\s*(凌晨|早上|上午|中午|下午|傍晚|晚上)?\s*([0-9零〇一二两三四五六七八九十]{1,3})\s*(?:点|时)(?:钟)?\s*(?:(半)|([0-9零〇一二两三四五六七八九十]{1,3})分?)?/;
    const pointMatch: RegExpMatchArray | null = text.match(pointPattern);
    if (pointMatch !== null && pointMatch.length >= 4) {
      const rawHour: number = this.parseChineseNumber(pointMatch[3]);
      const minute: number = pointMatch[4] === '半' ? 30 : this.parseChineseNumber(pointMatch[5] ?? '0');
      const dayOffset: number = pointMatch[1] === '后天' ? 2 : (pointMatch[1] === '明天' ? 1 : 0);
      const hour: number = this.applyPeriod(rawHour, pointMatch[2] ?? '');
      if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
        const now: Date = new Date();
        const d: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate() + dayOffset, hour, minute, 0, 0);
        matched.push(`eventTime:${pointMatch[0]}`);
        return d.getTime();
      }
    }

    const colonPattern: RegExp = /(今天|明天|后天)\s*(凌晨|早上|上午|中午|下午|傍晚|晚上)?\s*(\d{1,2}):(\d{2})/;
    const colonMatch: RegExpMatchArray | null = text.match(colonPattern);
    if (colonMatch !== null && colonMatch.length >= 5) {
      const rawHour: number = parseInt(colonMatch[3], 10);
      const minute: number = parseInt(colonMatch[4], 10);
      const dayOffset: number = colonMatch[1] === '后天' ? 2 : (colonMatch[1] === '明天' ? 1 : 0);
      const hour: number = this.applyPeriod(rawHour, colonMatch[2] ?? '');
      if (hour >= 0 && hour <= 23 && minute >= 0 && minute <= 59) {
        const now: Date = new Date();
        const d: Date = new Date(now.getFullYear(), now.getMonth(), now.getDate() + dayOffset, hour, minute, 0, 0);
        matched.push(`eventTime:${colonMatch[0]}`);
        return d.getTime();
      }
    }
    return null;
  }

  private applyPeriod(hour: number, period: string): number {
    if ((period === '下午' || period === '傍晚' || period === '晚上') && hour < 12) {
      return hour + 12;
    }
    if (period === '中午' && hour < 11) {
      return hour + 12;
    }
    if (period === '凌晨' && hour === 12) {
      return 0;
    }
    return hour;
  }

  /** 支持 0-59 的阿拉伯数字和常用中文数字 */
  private parseChineseNumber(value: string): number {
    if (value.length === 0) {
      return 0;
    }
    if (/^\d+$/.test(value)) {
      return parseInt(value, 10);
    }
    if (value === '十') {
      return 10;
    }
    const tenIndex: number = value.indexOf('十');
    if (tenIndex >= 0) {
      const tens: number = tenIndex === 0 ? 1 : this.parseChineseDigit(value.charAt(tenIndex - 1));
      const ones: number = tenIndex === value.length - 1 ? 0 : this.parseChineseDigit(value.charAt(tenIndex + 1));
      return tens * 10 + Math.max(ones, 0);
    }
    return this.parseChineseDigit(value);
  }

  private parseChineseDigit(value: string): number {
    switch (value) {
      case '零':
      case '〇':
        return 0;
      case '一':
        return 1;
      case '二':
      case '两':
        return 2;
      case '三':
        return 3;
      case '四':
        return 4;
      case '五':
        return 5;
      case '六':
        return 6;
      case '七':
        return 7;
      case '八':
        return 8;
      case '九':
        return 9;
      default:
        return -1;
    }
  }

  /** 抽取地点 */
  private extractLocation(text: string, matched: string[]): string {
    const patterns: RegExp[] = [
      /地点[：:]\s*([\u4e00-\u9fa5a-zA-Z0-9]{2,15})/,
      // 具体场所优先：无需后缀“集合/举行”，也能识别“在教室4309”。
      /(?:在|到|去|前往)\s*((?:[\u4e00-\u9fa5a-zA-Z]{0,10})?(?:教室|实验室|会议室|报告厅|活动室|研讨室|办公室|体育馆|操场|图书馆|礼堂|食堂|宿舍|教学楼|综合楼)(?:[-\s]?[a-zA-Z]?\d{1,5})?)/,
      /(?:在|到|去|前往)\s*([a-zA-Z]?\d{2,5}(?:教室|室))/,
      /在([\u4e00-\u9fa5a-zA-Z0-9]{2,15})(?:举行|举办|集合|见面|报到|上课|开会)/,
      /于([\u4e00-\u9fa5a-zA-Z0-9]{2,15})(?:举办|举行|集合)/,
      /[，,\s]([\u4e00-\u9fa5a-zA-Z0-9]{2,15})(?:集合|见面|报到)/,
      // 通用兜底：句末或标点前的“在xxx”。
      /(?:在|到|去|前往)\s*([\u4e00-\u9fa5a-zA-Z0-9]{2,20})(?=[，,。；;！!？?\s]|$)/
    ];
    for (const p of patterns) {
      const m: RegExpMatchArray | null = text.match(p);
      if (m !== null && m.length > 1) {
        const loc: string = m[1].trim().replace(/\s+/g, '');
        matched.push(`location:${loc}`);
        return loc;
      }
    }
    return '';
  }

  /** 抽取材料 */
  private extractMaterials(text: string, matched: string[]): string[] {
    // "提交 xxx 和 xxx" / "携带 xxx"
    const m1: RegExpMatchArray | null = text.match(/(?:提交|携带|准备)\s*([\u4e00-\u9fa5a-zA-Z0-9、和\s]{2,40})/);
    if (m1 !== null && m1.length > 1) {
      const raw: string = m1[1];
      const parts: string[] = raw.split(/[、和和\s,，]+/).filter((s: string) => s.length > 0);
      if (parts.length > 0) {
        matched.push(`materials:${raw}`);
        return parts;
      }
    }
    return [];
  }

  /** 抽取联系人 */
  private extractContact(text: string, matched: string[]): string {
    const m: RegExpMatchArray | null = text.match(/(?:联系人|联系|咨询电话|电话)[：:]\s*([\u4e00-\u9fa5a-zA-Z0-9\s]{2,20})/);
    if (m !== null && m.length > 1) {
      const c: string = m[1].trim();
      matched.push(`contact:${c}`);
      return c;
    }
    return '';
  }

  /** 月/日 时:分 -> 当年毫秒时间戳 */
  private toTimestamp(monthStr: string, dayStr: string, hourStr: string, minuteStr: string): number {
    const month: number = parseInt(monthStr, 10);
    const day: number = parseInt(dayStr, 10);
    const hour: number = parseInt(hourStr, 10);
    const minute: number = parseInt(minuteStr, 10);
    if (month < 1 || month > 12 || day < 1 || day > 31 || hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return 0;
    }
    const year: number = new Date().getFullYear();
    const d: Date = new Date(year, month - 1, day, hour, minute, 0, 0);
    return d.getTime();
  }

  private delay(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), ms);
    });
  }
}

/**
 * RemoteAIService.complete：真实模型回合通信，只请求服务端网关。
 * 原 analyzeCampusNotice 单结果接口保留兼容；智能助手使用 complete + AgentService。
 */
export class RemoteAIService implements AIService, AgentModelClient {
  async complete(messages: AgentMessage[]): Promise<AgentMessage> {
    const request = http.createHttp();
    const body: AgentRequest = { messages, currentTime: formatCampusDate(Date.now()) };
    const headers: Record<string, string> = {
      'Content-Type': 'application/json'
    };
    if (AgentConfig.gatewayToken.length > 0) { headers['Authorization'] = `Bearer ${AgentConfig.gatewayToken}`; }
    try {
      const response = await request.request(`${AgentConfig.gatewayUrl}/api/agent/turn`, {
        method: http.RequestMethod.POST, header: headers, extraData: JSON.stringify(body),
        expectDataType: http.HttpDataType.STRING, connectTimeout: 10000, readTimeout: 55000
      });
      if (typeof response.result !== 'string') { throw new Error('网关响应格式无效'); }
      const parsed = JSON.parse(response.result) as AgentResponse;
      if (response.responseCode !== 200) {
        throw new Error(parsed.error ?? `网关请求失败（HTTP ${response.responseCode}）`);
      }
      if (parsed.message === undefined || parsed.message.role !== 'assistant') { throw new Error('网关没有返回有效模型消息'); }
      return parsed.message;
    } catch (e) {
      throw new Error(e instanceof Error ? e.message : '无法连接模型网关，请检查服务与模拟器端口转发');
    } finally { request.destroy(); }
  }

  async analyzeCampusNotice(text: string): Promise<TaskAnalysisResult> {
    throw new AIAnalysisError(AIErrorType.NETWORK, '远程模型请通过智能助手入口使用；本地通知识别仍为规则模式');
  }
}

/**
 * AIServiceProvider：全局单例访问入口。
 * 通过 changeImpl 可在线切换 Mock / Remote 实现，不影响调用方。
 */
export class AIServiceProvider {
  private static instance: AIService = new MockAIService();

  static get(): AIService {
    return AIServiceProvider.instance;
  }

  static changeImpl(impl: AIService): void {
    AIServiceProvider.instance = impl;
  }
}
