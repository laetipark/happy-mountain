import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createAppServer } from '../src/server.mjs';

test('optional live public history discovery and CSV retrieval', { skip: process.env.RUN_LIVE_HISTORY_TEST !== '1', timeout: 30_000 }, async t => {
  const server = createAppServer({ env: {} });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  const response = await fetch(`http://127.0.0.1:${server.address().port}/api/history`);
  assert.equal(response.status, 200);
  const bytes = Buffer.from(await response.arrayBuffer());
  assert.ok(bytes.length > 100);
  const text = new TextDecoder('euc-kr', { fatal: true }).decode(bytes);
  assert.match(text.split(/\r?\n/)[0], /예보일시/);
  assert.match(text.split(/\r?\n/)[0], /시도명/);
  assert.match(text.split(/\r?\n/)[0], /등급/);
});
