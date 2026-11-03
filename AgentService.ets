import { AgentMessage, AgentModelClient, ChatLine, DraftResult, ToolTrace } from '../models/AgentModel';
import { SourceType } from '../models/TaskModel';
import { TaskToolExecutor } from './TaskToolExecutor';
import { TaskDraftService } from './TaskDraftService';

/** One conversation survives tab recreation. No keyword-based intent routing. */
export class AgentService {
  messages: AgentMessage[] = [];
  lines: ChatLine[] = [];
  traces: ToolTrace[] = [];
  draftIds: string[] = [];
  busy: boolean = false;
  private client: AgentModelClient;
  private executor: TaskToolExecutor;
  private drafts: TaskDraftService;
  constructor(client: AgentModelClient, executor: TaskToolExecutor, drafts: TaskDraftService) {
    this.client = client; this.executor = executor; this.drafts = drafts;
  }

  clear(): void {
    if (this.busy) { throw new Error('请等待当前请求完成'); }
    for (const id of this.draftIds) { this.drafts.cancel(id); }
    this.messages = []; this.lines = []; this.traces = []; this.draftIds = [];
  }

  async send(text: string, source: SourceType, onChange: () => void): Promise<void> {
    if (this.busy) { throw new Error('正在处理上一条消息'); }
    if (text.trim().length === 0 || text.length > 6000) { throw new Error('请输入 1 至 6000 字的内容'); }
    if (this.messages.length > 30) { throw new Error('会话较长，请点击新会话后继续'); }
    this.busy = true;
    this.lines.push({ role: 'user', text });
    const next = this.messages.slice();
    next.push({ role: 'user', content: text });
    let calls = 0;
    let draftCreated = false;
    const seen: string[] = [];
    for (const previous of this.messages) {
      for (const call of previous.tool_calls ?? []) { seen.push(call.id); }
    }
    try {
      onChange();
      for (let round = 0; round < 4; round++) {
        if (next.length > 48) { throw new Error('会话达到长度限制，请新建会话'); }
        const message = await this.client.complete(next);
        if (message.role !== 'assistant') { throw new Error('模型响应角色无效'); }
        const toolCalls = message.tool_calls ?? [];
        if (toolCalls.length === 0) {
          if (typeof message.content !== 'string' || message.content.trim().length === 0) { throw new Error('模型返回空内容，请重试'); }
          next.push(message); this.messages = next;
          this.lines.push({ role: 'assistant', text: message.content });
          return;
        }
        if (toolCalls.length > 8 || calls + toolCalls.length > 8) { throw new Error('工具调用次数达到上限，请缩小问题范围'); }
        for (const call of toolCalls) {
          if (typeof call.id !== 'string' || call.id.length === 0 || seen.includes(call.id) || call.type !== 'function' ||
            call.function === undefined || typeof call.function.name !== 'string' || typeof call.function.arguments !== 'string') {
            throw new Error('模型返回了无效或重复的工具调用');
          }
          seen.push(call.id);
        }
        next.push(message);
        for (const call of toolCalls) {
          calls++;
          const trace: ToolTrace = { id: call.id, name: call.function.name, arguments: call.function.arguments, result: '', state: '执行中' };
          this.traces.push(trace); onChange();
          if (call.function.name === 'create_task_draft' && draftCreated) {
            trace.result = JSON.stringify({ ok: false, error: '本轮已经生成草稿，请等待用户确认，不要重复生成' });
            trace.state = '已阻止重复草稿';
          } else {
            const result = await this.executor.execute(call.function.name, call.function.arguments, text, source);
            trace.result = JSON.stringify(result);
            trace.state = result.ok ? '成功' : '失败';
            if (result.ok && call.function.name === 'create_task_draft' && result.data !== undefined) {
              const draft = result.data as DraftResult;
              this.draftIds.push(draft.draftId); draftCreated = true;
            }
          }
          next.push({ role: 'tool', tool_call_id: call.id, content: trace.result });
          onChange();
        }
      }
      throw new Error('模型连续调用工具未结束，请简化问题后重试；已生成草稿可在下方确认');
    } catch (e) {
      const message = e instanceof Error ? e.message : '智能助手请求失败';
      this.lines.push({ role: 'error', text: message });
      // Do not commit incomplete tool protocol history. Visible traces/drafts remain available.
      throw new Error(message);
    } finally { this.busy = false; onChange(); }
  }
}
