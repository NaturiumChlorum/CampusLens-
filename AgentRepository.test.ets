import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { TaskRepository } from '../../../main/ets/repositories/TaskRepository';
import { TaskDraftService } from '../../../main/ets/services/TaskDraftService';
import { TaskToolExecutor } from '../../../main/ets/services/TaskToolExecutor';
import { DraftResult, TaskStatistics, TaskQueryResult } from '../../../main/ets/models/AgentModel';
import { formatCampusDate } from '../../../main/ets/common/DateTimeUtils';

export default function agentRepositoryTest(): void {
  describe('AgentRepository', (): void => {
    it('realSqliteDraftConfirmAndCancel', 0, async (): Promise<void> => {
      const repo = TaskRepository.getInstance();
      const delegator = abilityDelegatorRegistry.getAbilityDelegator();
      const monitor: abilityDelegatorRegistry.AbilityMonitor = { abilityName: 'EntryAbility' };
      await delegator.addAbilityMonitor(monitor);
      await delegator.startAbility({ bundleName: 'com.example.campuslens', abilityName: 'EntryAbility' });
      const ability = await delegator.waitAbilityMonitor(monitor, 10000);
      await delegator.removeAbilityMonitor(monitor);
      await repo.init(ability.context);
      const before = await repo.count();
      const drafts = new TaskDraftService(repo);
      const executor = new TaskToolExecutor(repo, drafts);
      let createdId = '';
      try {
        const query = await executor.execute('query_tasks', '{"limit":1}', '测试查询');
        expect(query.ok).assertTrue();
        expect((query.data as TaskQueryResult).totalMatched).assertEqual(before);
        const args = JSON.stringify({ title: `验收临时任务_${Date.now()}`, deadline: formatCampusDate(Date.now() + 86400000) });
        const cancelled = await executor.execute('create_task_draft', args, '验收测试原文');
        expect(cancelled.ok).assertTrue();
        const cancelledData = cancelled.data as DraftResult;
        expect(await repo.count()).assertEqual(before);
        drafts.cancel(cancelledData.draftId);
        expect(await repo.count()).assertEqual(before);

        const generated = await executor.execute('create_task_draft', args, '验收测试原文');
        const data = generated.data as DraftResult;
        expect(await repo.count()).assertEqual(before);
        const task = await drafts.confirm(data.draftId, data.draft);
        createdId = task.id;
        expect(await repo.count()).assertEqual(before + 1);
        const readBack = await repo.getTask(createdId);
        expect(readBack?.originalText).assertEqual('验收测试原文');
        expect(readBack?.deadline).assertEqual(data.draft.deadline);
        const stats = await executor.execute('get_task_statistics', '{}', '测试统计');
        expect(stats.ok).assertTrue();
        expect((stats.data as TaskStatistics).total).assertEqual(before + 1);
        let duplicateRejected = false;
        try { await drafts.confirm(data.draftId, data.draft); } catch { duplicateRejected = true; }
        expect(duplicateRejected).assertTrue();
        expect(await repo.count()).assertEqual(before + 1);
      } finally {
        // Only delete the unique row created by this test; never reset the user's table.
        if (createdId.length > 0) { await repo.deleteTask(createdId); }
      }
      expect(await repo.count()).assertEqual(before);
    });
  });
}
