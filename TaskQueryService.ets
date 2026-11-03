import { Task, TaskStatus, resolveExpired } from '../models/TaskModel';
import { TaskQueryResult, TaskStatistics, TaskSummary, ToolArguments } from '../models/AgentModel';
import { formatCampusDate, parseCampusDate } from '../common/DateTimeUtils';

export function summarizeTask(task: Task, now: number): TaskSummary {
  return {
    id: task.id, title: task.title, status: resolveExpired(task, now),
    deadline: task.deadline === null ? null : formatCampusDate(task.deadline),
    eventTime: task.eventTime === null ? null : formatCampusDate(task.eventTime),
    eventEndTime: task.eventEndTime === null ? null : formatCampusDate(task.eventEndTime),
    location: task.location
  };
}

/** Pure business functions; callers provide a fresh full database snapshot. */
export function queryTasks(tasks: Task[], args: ToolArguments, now: number): TaskQueryResult {
  const from = args.from ? parseCampusDate(args.from) : null;
  const to = args.to ? parseCampusDate(args.to) : null;
  if (from !== null && to !== null && from > to) { throw new Error('查询起始时间不能晚于结束时间'); }
  const status = args.status ?? 'all';
  const field = args.timeField ?? 'deadline';
  const limit = args.limit ?? 20;
  const offset = args.offset ?? 0;
  const matched = tasks.filter((task: Task): boolean => {
    const resolved = resolveExpired(task, now);
    if (status === 'unfinished' && resolved === TaskStatus.COMPLETED) { return false; }
    if (status !== 'all' && status !== 'unfinished' && status !== resolved) { return false; }
    const time = field === 'eventTime' ? task.eventTime : task.deadline;
    if ((from !== null || to !== null) && time === null) { return false; }
    if (time !== null && ((from !== null && time < from) || (to !== null && time > to))) { return false; }
    return true;
  });
  matched.sort((a: Task, b: Task): number => {
    const at = (field === 'eventTime' ? a.eventTime : a.deadline) ?? Number.MAX_SAFE_INTEGER;
    const bt = (field === 'eventTime' ? b.eventTime : b.deadline) ?? Number.MAX_SAFE_INTEGER;
    return at - bt || a.createdAt - b.createdAt || a.id.localeCompare(b.id);
  });
  return {
    tasks: matched.slice(offset, offset + limit).map((task: Task): TaskSummary => summarizeTask(task, now)),
    totalMatched: matched.length, offset, limit, hasMore: offset + limit < matched.length,
    queriedAt: formatCampusDate(now), timezone: 'Asia/Shanghai'
  };
}

export function getTaskStatistics(tasks: Task[], days: number, now: number): TaskStatistics {
  let completed = 0;
  let pending = 0;
  let expired = 0;
  let dueSoon = 0;
  const end = now + days * 86400000;
  for (const task of tasks) {
    const status = resolveExpired(task, now);
    if (status === TaskStatus.COMPLETED) { completed++; }
    else if (status === TaskStatus.EXPIRED) { expired++; }
    else { pending++; }
    if (status !== TaskStatus.COMPLETED && task.deadline !== null && task.deadline >= now && task.deadline <= end) { dueSoon++; }
  }
  return {
    total: tasks.length, unfinished: tasks.length - completed, pending, expired, completed, dueSoon,
    windowStart: formatCampusDate(now), windowEnd: formatCampusDate(end), timezone: 'Asia/Shanghai',
    definition: '未完成包含已过期；即将到期只统计窗口内有截止时间且未完成的任务，包含两端边界。活动时间不作为截止时间。'
  };
}
