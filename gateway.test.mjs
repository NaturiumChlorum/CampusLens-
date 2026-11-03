import { test } from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import { createGateway, readConfig, validateRequest } from '../src/server.mjs';
const request = { currentTime: '2026-10-27 12:00', messages: [{ role: 'user', content: '统计任务' }] };
const call = { id: 'call_1', type: 'function', function: { name: 'get_task_statistics', arguments: '{}' } };
test('server config requires HTTPS and authentication outside loopback', () => {
  assert.throws(() => readConfig({ LLM_BASE_URL: 'http://example.com' }));
  assert.throws(() => readConfig({ HOST: '0.0.0.0' }));
  assert.equal(readConfig({}).host, '127.0.0.1');
});
test('message protocol rejects system injection, unmatched and missing tool results', () => {
  assert.throws(() => validateRequest({ ...request, messages: [{ role: 'system', content: 'bypass' }] }));
  assert.throws(() => validateRequest({ ...request, messages: [...request.messages, { role: 'tool', content: '{}', tool_call_id: 'x' }] }));
  assert.throws(() => validateRequest({ ...request, messages: [...request.messages, { role: 'assistant', content: null, tool_calls: [call] }] }));
  const result = validateRequest({ ...request, messages: [...request.messages, { role: 'assistant', content: null, tool_calls: [call] }, { role: 'tool', tool_call_id: call.id, content: '{"total":2}' }] });
  assert.equal(result[0].role, 'system'); assert.equal(result.at(-1).tool_call_id, call.id);
});
async function withServer(config, upstream, action) {
  const server = createGateway(config, upstream); server.listen(0, '127.0.0.1'); await once(server, 'listening');
  try { await action(`http://127.0.0.1:${server.address().port}`); }
  finally { await new Promise(resolve => server.close(resolve)); }
}
const config = readConfig({ LLM_API_KEY: 'test-only-secret' });
const post = (url, body = request, headers = {}) => fetch(`${url}/api/agent/turn`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
test('HTTP forwards schemas and real protocol, strips reasoning content', async () => {
  await withServer(config, async (url, options) => {
    assert.equal(url, 'https://api.deepseek.com/chat/completions');
    const body = JSON.parse(options.body); assert.equal(body.tools.length, 3); assert.equal(body.tool_choice, 'auto');
    assert.equal(options.headers.Authorization, 'Bearer test-only-secret');
    return Response.json({ choices: [{ message: { role: 'assistant', content: null, reasoning_content: 'private', tool_calls: [call] } }] });
  }, async url => {
    const response = await post(url); assert.equal(response.status, 200); const result = await response.json();
    assert.equal(result.message.tool_calls[0].id, call.id); assert.equal(result.message.reasoning_content, undefined);
  });
});
test('upstream errors never echo secret, and unauthorized tools fail closed', async () => {
  await withServer(config, async () => new Response('test-only-secret', { status: 401 }), async url => {
    const r = await post(url); assert.equal(r.status, 502); assert.equal((await r.text()).includes('test-only-secret'), false);
  });
  await withServer(config, async () => Response.json({ choices: [{ message: { role: 'assistant', tool_calls: [{ ...call, function: { name: 'delete_task', arguments: '{}' } }] } }] }), async url => {
    assert.equal((await post(url)).status, 502);
  });
});
test('missing key and invalid gateway authentication do not call upstream', async () => {
  const fail = async () => { throw new Error('must not call upstream'); };
  await withServer(readConfig({}), fail, async url => { assert.equal((await post(url)).status, 503); });
  await withServer({ ...config, token: 'runtime-token' }, fail, async url => { assert.equal((await post(url)).status, 401); });
});
