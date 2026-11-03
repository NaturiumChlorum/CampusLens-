import { createServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { tools, toolNames, systemPrompt } from './tool-schemas.mjs';

export function readConfig(env = process.env) {
  const config = { baseUrl: env.LLM_BASE_URL || 'https://api.deepseek.com', model: env.LLM_MODEL || 'deepseek-flash',
    apiKey: env.LLM_API_KEY || '', host: env.HOST || '127.0.0.1', port: Number(env.PORT || 3000), token: env.GATEWAY_TOKEN || '' };
  const url = new URL(config.baseUrl);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash) throw new Error('LLM_BASE_URL 必须为不带凭据的 HTTPS 地址');
  if (!Number.isInteger(config.port) || config.port < 1 || config.port > 65535) throw new Error('PORT 无效');
  if (!['127.0.0.1', '::1', 'localhost'].includes(config.host) && config.token.length < 24) throw new Error('非本机监听必须设置至少 24 字符的 GATEWAY_TOKEN');
  return config;
}

export function validateRequest(body) {
  if (!body || typeof body !== 'object' || !Array.isArray(body.messages) || body.messages.length < 1 || body.messages.length > 48) throw new Error('会话必须包含 1 至 48 条消息');
  if (typeof body.currentTime !== 'string' || !/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$/.test(body.currentTime)) throw new Error('当前时间格式无效');
  const pending = new Set(); const seen = new Set();
  const messages = body.messages.map((m, i) => {
    if (!m || !['user', 'assistant', 'tool'].includes(m.role)) throw new Error('消息角色不在允许列表中');
    if (m.content !== null && (typeof m.content !== 'string' || m.content.length > 60000)) throw new Error('消息内容无效或过长');
    if (i === 0 && m.role !== 'user') throw new Error('会话必须从用户消息开始');
    if (pending.size && m.role !== 'tool') throw new Error('必须先回传所有工具结果');
    const clean = { role: m.role, content: m.content };
    if (m.role === 'assistant' && m.tool_calls !== undefined) {
      if (!Array.isArray(m.tool_calls) || m.tool_calls.length < 1 || m.tool_calls.length > 8) throw new Error('工具调用数量无效');
      clean.tool_calls = m.tool_calls.map(call => {
        validateCall(call);
        if (seen.has(call.id)) throw new Error('重复工具调用 ID');
        pending.add(call.id); seen.add(call.id);
        return { id: call.id, type: 'function', function: { name: call.function.name, arguments: call.function.arguments } };
      });
    } else if (m.tool_calls !== undefined) throw new Error('只有 assistant 可以调用工具');
    if (m.role === 'tool') {
      if (typeof m.content !== 'string' || !pending.delete(m.tool_call_id)) throw new Error('工具结果没有匹配的调用 ID');
      clean.tool_call_id = m.tool_call_id;
    } else if (m.tool_call_id !== undefined) throw new Error('非法工具结果 ID');
    return clean;
  });
  if (pending.size) throw new Error('缺少工具结果');
  return [{ role: 'system', content: systemPrompt(body.currentTime) }, ...messages];
}
function validateCall(call) {
  if (!call || call.type !== 'function' || typeof call.id !== 'string' || call.id.length < 1 || call.id.length > 200 ||
    !toolNames.includes(call.function?.name) || typeof call.function.arguments !== 'string' || call.function.arguments.length > 16000) throw new Error('模型返回了无效或未授权的工具调用');
}
function authorized(header, token) {
  if (!token) return true;
  const a = Buffer.from(header || ''); const b = Buffer.from(`Bearer ${token}`);
  return a.length === b.length && timingSafeEqual(a, b);
}
function reply(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(data));
}
async function readBody(req) {
  let length = 0; const chunks = [];
  for await (const chunk of req) { length += chunk.length; if (length > 256000) throw new Error('请求超过 256 KB'); chunks.push(chunk); }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

export function createGateway(config, fetchImpl = fetch) {
  let active = 0; let count = 0; let windowStart = Date.now();
  const server = createServer(async (req, res) => {
    if (req.url === '/health' && req.method === 'GET') return reply(res, 200, { status: 'ok', configured: Boolean(config.apiKey), model: config.model });
    if (req.url !== '/api/agent/turn' || req.method !== 'POST') return reply(res, 404, { error: '接口不存在' });
    if (!authorized(req.headers.authorization, config.token)) return reply(res, 401, { error: '网关访问凭据无效' });
    if (!config.apiKey) return reply(res, 503, { error: '服务端尚未配置 LLM_API_KEY' });
    if (Date.now() - windowStart > 60000) { windowStart = Date.now(); count = 0; }
    if (active >= 2 || count >= 30) return reply(res, 429, { error: '请求过于频繁，请稍后重试' });
    active++; count++;
    try {
      let messages;
      try { messages = validateRequest(await readBody(req)); }
      catch { return reply(res, 400, { error: '请求格式或工具消息顺序无效，请新建会话后重试' }); }
      // The endpoint/key/model/tools are server controlled, never accepted from the client.
      const response = await fetchImpl(`${config.baseUrl.replace(/\/$/, '')}/chat/completions`, {
        method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${config.apiKey}` },
        body: JSON.stringify({ model: config.model, messages, tools, tool_choice: 'auto', stream: false,
          thinking: { type: 'disabled' }, max_tokens: 2048 }), signal: AbortSignal.timeout(45000)
      });
      if (!response.ok) {
        // Do not forward upstream bodies: they may echo credentials or private content.
        const hint = response.status === 401 ? '模型服务鉴权失败，请检查服务端配置' : response.status === 429 ? '模型服务限流或额度不足' : '模型服务请求失败';
        return reply(res, 502, { error: `${hint}（HTTP ${response.status}）` });
      }
      const raw = await response.text();
      if (raw.length > 256000) throw new Error('oversized response');
      const data = JSON.parse(raw); const choice = data.choices?.[0]; const message = choice?.message;
      if (choice?.finish_reason === 'length') return reply(res, 502, { error: '模型输出被截断，请缩短请求后重试' });
      if (!message || message.role !== 'assistant') throw new Error('invalid response');
      const clean = { role: 'assistant', content: typeof message.content === 'string' ? message.content : null };
      if (message.tool_calls?.length) {
        if (!Array.isArray(message.tool_calls) || message.tool_calls.length > 8) throw new Error('invalid calls');
        const ids = new Set();
        clean.tool_calls = message.tool_calls.map(call => {
          validateCall(call); if (ids.has(call.id)) throw new Error('duplicate ID'); ids.add(call.id);
          return { id: call.id, type: 'function', function: { name: call.function.name, arguments: call.function.arguments } };
        });
      } else if (!clean.content?.trim()) throw new Error('empty response');
      reply(res, 200, { message: clean });
    } catch (error) {
      reply(res, 502, { error: error?.name === 'TimeoutError' ? '模型响应超时，请重试' : '模型连接或响应格式异常，请检查网关' });
    } finally { active--; }
  });
  server.requestTimeout = 15000; server.headersTimeout = 10000;
  return server;
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const config = readConfig();
    createGateway(config).listen(config.port, config.host, () => console.log(`CampusLens gateway listening on ${config.host}:${config.port}; model=${config.model}; configured=${Boolean(config.apiKey)}`));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
