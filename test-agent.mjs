// Executes the actual non-UI ETS business code on Node; NOT a device/RDB test.
import { createRequire } from 'node:module';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { resolve, dirname } from 'node:path';
import { pathToFileURL } from 'node:url';
import assert from 'node:assert/strict';
import { test } from 'node:test';

const root = resolve(import.meta.dirname, '..');
const require = createRequire(import.meta.url);
const ts = require(process.env.TYPESCRIPT_PATH || resolve(dirname(process.execPath), '../hvigor/hvigor/node_modules/typescript'));
const out = resolve(root, '.test/agent-host');
const sources = ['models/TaskModel', 'models/AgentModel', 'common/DateTimeUtils',
  'services/TaskQueryService', 'services/TaskDraftService', 'services/TaskToolExecutor', 'services/AgentService'];
for (const name of sources) {
  const source = await readFile(resolve(root, `entry/src/main/ets/${name}.ets`), 'utf8');
  const js = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText
    .replace(/(from\s+['"])(\.\.?\/[^'"]+)(['"])/g, '$1$2.mjs$3');
  const target = resolve(out, `${name}.mjs`);
  await mkdir(dirname(target), { recursive: true });
  await writeFile(target, js);
}
await mkdir(resolve(out, 'repositories'), { recursive: true });
await writeFile(resolve(out, 'repositories/TaskRepository.mjs'),
  'export class TaskRepository { static getInstance() { throw new Error("Host tests must inject an explicit fake store; no RDB available"); } }');
const load = name => import(pathToFileURL(resolve(out, `${name}.mjs`)).href);
const { TaskToolExecutor } = await load('services/TaskToolExecutor');
const { AgentService } = await load('services/AgentService');
const { TaskDraftService } = await load('services/TaskDraftService');
const { getTaskStatistics, queryTasks } = await load('services/TaskQueryService');
const { parseCampusDate, formatCampusDate } = await load('common/DateTimeUtils');
const now = parseCampusDate('2026-10-27 12:00');
const input = { title: '报告', description: '', category: '作业', deadline: now + 3600000,
  eventTime: null, eventEndTime: null, location: '', materials: [], contact: '', notes: '',
  priority: 'medium', sourceType: 'text', originalText: '用户原文' };
const task = (id, fields = {}) => ({ ...input, id, status: 'pending', createdAt: now, updatedAt: now,
  calendarDeadlineEventId: '', calendarActivityEventId: '', ...fields });
function fixture(rows = []) {
  const store = { rows, writes: 0, fail: false,
    async getAllTasks() { if (this.fail) throw new Error('数据库不可用'); return this.rows; },
    async createTask(value) { if (this.fail) throw new Error('写入失败'); this.writes++; const row = task(`saved-${this.writes}`, value); this.rows.push(row); return row; } };
  const drafts = new TaskDraftService(store);
  return { store, drafts, executor: new TaskToolExecutor(store, drafts) };
}

test('strict China date round-trip, leap year and invalid dates', () => {
  assert.equal(formatCampusDate(now), '2026-10-27 12:00');
  assert.equal(parseCampusDate(''), null);
  assert.doesNotThrow(() => parseCampusDate('2028-02-29 23:59'));
  for (const invalid of ['2026-02-29 10:00', '2026-13-01 10:00', '2026-10-27 24:00', '明天', '2026-10-27 10:60']) {
    assert.throws(() => parseCampusDate(invalid));
  }
});
test('statistics count full snapshot, unfinished includes expired, activity is not deadline', () => {
  const rows = [task('1'), task('2', { deadline: now - 1 }), task('3', { status: 'completed' }),
    task('4', { deadline: null, eventTime: now + 1 }), task('5', { deadline: now + 7 * 86400000 })];
  const result = getTaskStatistics(rows, 7, now);
  assert.deepEqual([result.total, result.unfinished, result.pending, result.expired, result.completed, result.dueSoon], [5, 4, 3, 1, 1, 2]);
});
test('query filters dynamic status/time, excludes null time, reports total before pagination', () => {
  const rows = [task('a'), task('b'), task('c', { deadline: null }), task('d', { deadline: now - 1 })];
  const result = queryTasks(rows, { status: 'unfinished', from: '2026-10-27 12:00', limit: 1 }, now);
  assert.equal(result.totalMatched, 2); assert.equal(result.tasks.length, 1); assert.equal(result.hasMore, true);
  assert.equal(queryTasks(rows, { status: 'expired' }, now).tasks[0].id, 'd');
});
test('empty database returns real zeros', async () => {
  const f = fixture(); const r = await f.executor.execute('get_task_statistics', '{}', '统计');
  assert.equal(r.ok, true); assert.equal(r.data.total, 0); assert.equal(f.store.writes, 0);
});
test('unknown tools, extra fields and malformed parameters are rejected', async () => {
  const f = fixture();
  for (const [name, args] of [['delete_task', '{}'], ['query_tasks', 'null'], ['query_tasks', '[]'], ['query_tasks', '{'],
    ['query_tasks', '{"limit":0}'], ['query_tasks', '{"limit":"2"}'], ['query_tasks', '{"status":"bogus"}'],
    ['query_tasks', '{"sql":"DROP TABLE task"}'], ['get_task_statistics', '{"dueWithinDays":31}'],
    ['create_task_draft', '{"title":"报告","confirmed":true}'], ['create_task_draft', '{"title":42}'],
    ['create_task_draft', '{"title":"报告","materials":[null]}']]) {
    assert.equal((await f.executor.execute(name, args, 'test')).ok, false, `${name} ${args}`);
  }
  assert.equal(f.store.writes, 0);
});
test('database failures stay errors, never invented empty results', async () => {
  const f = fixture(); f.store.fail = true;
  const r = await f.executor.execute('get_task_statistics', '{}', '统计');
  assert.equal(r.ok, false); assert.equal(r.data, undefined); assert.match(r.error, /数据库/);
});
test('draft creation/cancellation never writes; cancelled drafts cannot commit', async () => {
  const f = fixture();
  const r = await f.executor.execute('create_task_draft', '{"title":"报告","deadline":"2026-11-02 21:00"}', '完整原文', 'image');
  assert.equal(r.ok, true); assert.equal(f.store.writes, 0);
  assert.equal(r.data.draft.originalText, '完整原文'); assert.equal(r.data.draft.sourceType, 'image');
  f.drafts.cancel(r.data.draftId);
  await assert.rejects(f.drafts.confirm(r.data.draftId, { ...input })); assert.equal(f.store.writes, 0);
});
test('confirmation saves edited fields once and preserves trusted original source', async () => {
  const f = fixture(); const draft = f.drafts.create({ ...input });
  const edited = { ...input, title: '用户修改的标题', originalText: '伪造原文' };
  const [a, b] = await Promise.allSettled([f.drafts.confirm(draft.id, edited), f.drafts.confirm(draft.id, edited)]);
  assert.equal(a.status, 'fulfilled'); assert.equal(b.status, 'rejected'); assert.equal(f.store.writes, 1);
  assert.equal(f.store.rows[0].title, '用户修改的标题'); assert.equal(f.store.rows[0].originalText, '用户原文');
  assert.equal(draft.state, 'saved');
});
test('failed confirmation permits retry, expired draft cannot save', async () => {
  const f = fixture(); const d = f.drafts.create({ ...input }); f.store.fail = true;
  await assert.rejects(f.drafts.confirm(d.id, { ...input })); assert.equal(d.state, 'pending_confirmation');
  f.store.fail = false; d.createdAt = Date.now() - 31 * 60000;
  await assert.rejects(f.drafts.confirm(d.id, { ...input })); assert.equal(f.store.writes, 0);
});

const toolCall = (id, name, args = {}) => ({ id, type: 'function', function: { name, arguments: JSON.stringify(args) } });
test('agent executes model-selected tools and sends matching actual results back before Chinese reply', async () => {
  const f = fixture([task('a'), task('b')]); let round = 0;
  const client = { async complete(messages) {
    round++;
    if (round === 1) return { role: 'assistant', content: null, tool_calls: [toolCall('c1', 'get_task_statistics'), toolCall('c2', 'query_tasks', { limit: 1 })] };
    assert.equal(messages.at(-2).tool_call_id, 'c1'); assert.equal(JSON.parse(messages.at(-2).content).data.total, 2);
    assert.equal(messages.at(-1).tool_call_id, 'c2'); assert.equal(JSON.parse(messages.at(-1).content).data.totalMatched, 2);
    return { role: 'assistant', content: '你共有 2 项任务。' };
  } };
  const agent = new AgentService(client, f.executor, f.drafts);
  await agent.send('给我一个概览', 'text', () => {});
  assert.equal(round, 2); assert.equal(agent.traces.length, 2); assert.equal(agent.lines.at(-1).text, '你共有 2 项任务。');
  assert.equal(f.store.writes, 0);
});
test('agent does not map keywords to tools and returns parameter errors to model', async () => {
  const f = fixture(); let round = 0;
  const agent = new AgentService({ async complete(messages) {
    if (++round === 1) return { role: 'assistant', content: null, tool_calls: [toolCall('invalid', 'query_tasks', { limit: -1 })] };
    assert.equal(JSON.parse(messages.at(-1).content).ok, false);
    return { role: 'assistant', content: '参数不正确，请重新说明范围。' };
  } }, f.executor, f.drafts);
  await agent.send('创建任务，统计，查询', 'text', () => {});
  assert.equal(agent.traces[0].name, 'query_tasks'); assert.equal(agent.draftIds.length, 0);
});
test('duplicate model calls fail before execution and incomplete history is rolled back', async () => {
  const f = fixture(); const duplicate = toolCall('same', 'create_task_draft', { title: '报告' });
  const agent = new AgentService({ async complete() { return { role: 'assistant', content: null, tool_calls: [duplicate, duplicate] }; } }, f.executor, f.drafts);
  await assert.rejects(agent.send('创建', 'text', () => {}));
  assert.equal(agent.messages.length, 0); assert.equal(agent.draftIds.length, 0); assert.equal(agent.busy, false);
});
test('only one draft per turn and new conversation cancels pending drafts without writing', async () => {
  const f = fixture(); let round = 0;
  const agent = new AgentService({ async complete() {
    if (++round === 1) return { role: 'assistant', content: null, tool_calls: [toolCall('d1', 'create_task_draft', { title: '报告' }), toolCall('d2', 'create_task_draft', { title: '报告' })] };
    return { role: 'assistant', content: '草稿待确认，尚未保存。' };
  } }, f.executor, f.drafts);
  await agent.send('创建报告', 'text', () => {}); const id = agent.draftIds[0];
  assert.equal(agent.draftIds.length, 1); assert.equal(agent.traces[1].state, '已阻止重复草稿');
  agent.clear(); assert.equal(f.drafts.get(id).state, 'cancelled'); assert.equal(f.store.writes, 0);
});
