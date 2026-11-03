/**
 * TaskSeeder.ets
 * 测试数据注入服务：仅当任务表为空时，注入若干示例任务用于阶段2功能验证。
 * 后续接入 AI 识别后，真实数据将替代测试数据，可整体删除此文件。
 */

import { TaskRepository } from '../repositories/TaskRepository';
import { TaskInput, TaskPriority, SourceType } from '../models/TaskModel';

/** 通过 date 字符串转毫秒时间戳 */
function ts(dateStr: string): number {
  return Date.parse(dateStr);
}

export class TaskSeeder {
  /**
   * 若数据库为空则注入测试任务。
   * 在 Ability 启动时调用，幂等。
   */
  static async seedIfEmpty(): Promise<void> {
    const repo: TaskRepository = TaskRepository.getInstance();
    const count: number = await repo.count();
    if (count > 0) {
      return;
    }
    const seeders: TaskInput[] = [
      {
        title: '人工智能创新大赛',
        description: '校园 AI 创新大赛报名，需提交项目说明书与报名表。',
        category: '比赛',
        deadline: ts('2026-09-28T17:00:00'),
        eventTime: ts('2026-10-10T14:00:00'),
        eventEndTime: ts('2026-10-10T16:00:00'),
        location: '图书馆报告厅',
        materials: ['报名表', '项目说明书'],
        contact: '李老师 13800000000',
        notes: '组队 3 人以内，提交电子版与纸质版。',
        priority: TaskPriority.HIGH,
        sourceType: SourceType.TEXT,
        originalText: '关于举办人工智能创新大赛的通知：报名截止 9 月 28 日 17:00，决赛 10 月 10 日 14:00 于图书馆报告厅。'
      },
      {
        title: '操作系统课程作业',
        description: '完成第三章调度算法习题，提交 PDF。',
        category: '作业',
        deadline: ts('2026-09-30T23:59:00'),
        eventTime: null,
        eventEndTime: null,
        location: '在线提交',
        materials: ['作业题'],
        contact: '',
        notes: '上传至教学平台，命名格式：学号_姓名_作业3。',
        priority: TaskPriority.MEDIUM,
        sourceType: SourceType.TEXT,
        originalText: ''
      },
      {
        title: '迎新晚会节目征集',
        description: '面向全体在校生征集歌舞、语言类节目。',
        category: '活动',
        deadline: ts('2026-10-05T20:00:00'),
        eventTime: ts('2026-10-20T19:00:00'),
        eventEndTime: ts('2026-10-20T21:00:00'),
        location: '大学生活动中心',
        materials: ['节目报名表', '伴奏音频'],
        contact: '校学生会文艺部',
        notes: '初选视频提交邮箱：arts@campus.edu',
        priority: TaskPriority.MEDIUM,
        sourceType: SourceType.TEXT,
        originalText: ''
      },
      {
        title: '图书馆读书分享会',
        description: '《思考，快与慢》共读分享。',
        category: '讲座',
        deadline: null,
        eventTime: ts('2026-09-29T15:00:00'),
        eventEndTime: ts('2026-09-29T16:30:00'),
        location: '图书馆三楼研讨室',
        materials: [],
        contact: '',
        notes: '无需报名，免费参加。',
        priority: TaskPriority.LOW,
        sourceType: SourceType.TEXT,
        originalText: ''
      }
    ];
    for (const input of seeders) {
      await repo.createTask(input);
    }
  }
}
