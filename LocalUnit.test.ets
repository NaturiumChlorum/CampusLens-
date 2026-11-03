import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { MockAIService } from '../main/ets/services/AIService';
import {
  Task,
  TaskPriority,
  TaskStatus,
  SourceType,
  resolveExpired
} from '../main/ets/models/TaskModel';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });
    it('extractClassroomLocation', 0, async () => {
      const service: MockAIService = new MockAIService();
      const direct = await service.analyzeCampusNotice('明天早上六点在教室4309');
      const reverse = await service.analyzeCampusNotice('明天上午八点去4309教室上课');
      const labeled = await service.analyzeCampusNotice('地点：第二教学楼A309');
      const meeting = await service.analyzeCampusNotice('明天上午十点去教室4309开会');
      expect(direct.location).assertEqual('教室4309');
      expect(reverse.location).assertEqual('4309教室');
      expect(labeled.location).assertEqual('第二教学楼A309');
      expect(meeting.title).assertEqual('开会');
      expect(meeting.location).assertEqual('教室4309');
    });
    it('resolveActivityExpiration', 0, () => {
      const now: number = Date.now();
      const futureTask: Task = {
        id: 'future-task',
        title: '未来活动',
        description: '',
        category: '活动',
        deadline: now - 60 * 60 * 1000,
        eventTime: now + 60 * 60 * 1000,
        eventEndTime: now + 2 * 60 * 60 * 1000,
        location: '',
        materials: [],
        contact: '',
        notes: '',
        priority: TaskPriority.MEDIUM,
        status: TaskStatus.PENDING,
        createdAt: now,
        updatedAt: now,
        sourceType: SourceType.TEXT,
        originalText: '',
        calendarDeadlineEventId: '',
        calendarActivityEventId: ''
      };
      expect(resolveExpired(futureTask)).assertEqual(TaskStatus.PENDING);
      futureTask.eventEndTime = now - 1;
      expect(resolveExpired(futureTask)).assertEqual(TaskStatus.EXPIRED);
    });
  });
}
