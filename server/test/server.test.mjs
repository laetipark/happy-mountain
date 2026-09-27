import assert from 'node:assert/strict';
import { request } from 'node:http';
import { mkdtemp, mkdir, writeFile, rm, symlink } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { createAppServer } from '../src/server.mjs';

const sampleEnv = { KAKAO_JAVASCRIPT_APP_KEY: 'public-js-fixture', KAKAO_REST_API_KEY: 'private-rest-fixture', WEATHER_API_KEY: 'private-weather-fixture' };
const csvUrl = 'https://www.data.go.kr/cmm/cmm/fileDownload.do?atchFileId=fixture';
const metadata = (url = csvUrl) => `<html><script type="application/ld+json">${JSON.stringify({ '@type': 'Dataset', dateModified: '2026-09-03', distribution: [{ encodingFormat: 'CSV', contentUrl: url }] })}</script></html>`;
const jsonResponse = value => new Response(JSON.stringify(value), { headers: { 'content-type': 'application/json' } });

async function app(t, options = {}) {
  const server = createAppServer({ env: sampleEnv, ...options });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => { server.closeAllConnections(); server.close(resolve); }));
  return `http://127.0.0.1:${server.address().port}`;
}

async function rawRequest(origin, pathname, method = 'GET') {
  const url = new URL(origin);
  return new Promise((resolve, reject) => {
    const req = request({ hostname: url.hostname, port: url.port, path: pathname, method }, res => {
      const chunks = [];
      res.on('data', chunk => chunks.push(chunk));
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks).toString('utf8') }));
    });
    req.on('error', reject);
    req.end();
  });
}

test('config exposes only the browser key and capability flags', async t => {
  const origin = await app(t, { fetchImpl: () => { throw new Error('No upstream expected'); } });
  const response = await fetch(`${origin}/api/config`);
  assert.deepEqual(await response.json(), { kakaoJavascriptKey: 'public-js-fixture', placesEnabled: true, weatherEnabled: true });
  const unconfigured = await app(t, { env: {} });
  assert.deepEqual(await (await fetch(`${unconfigured}/api/config`)).json(), { kakaoJavascriptKey: '', placesEnabled: false, weatherEnabled: false });
  const missing = await fetch(`${unconfigured}/api/places/mountains?x=127&y=37`);
  assert.equal(missing.status, 503);
  assert.equal((await missing.json()).error.code, 'NOT_CONFIGURED');
});

test('mountain proxy fixes search parameters and preserves raw JSON', async t => {
  const raw = '{ "documents": [], "meta": {"is_end": true} }';
  let captured;
  const origin = await app(t, { fetchImpl: async (url, options) => { captured = { url: new URL(url), options }; return new Response(raw); } });
  const response = await fetch(`${origin}/api/places/mountains?x=127.04&y=37.51&page=3`);
  assert.equal(response.status, 200);
  assert.equal(await response.text(), raw);
  assert.equal(captured.url.origin, 'https://dapi.kakao.com');
  assert.equal(captured.url.pathname, '/v2/local/search/keyword.json');
  assert.deepEqual(Object.fromEntries(captured.url.searchParams), { query: '산', category_group_code: 'AT4', radius: '10000', sort: 'distance', size: '15', x: '127.04', y: '37.51', page: '3' });
  assert.equal(captured.options.headers.Authorization, 'KakaoAK private-rest-fixture');
  assert.equal(captured.options.redirect, 'manual');
});

test('address query is encoded and cannot change the upstream destination', async t => {
  let target;
  const origin = await app(t, { fetchImpl: async url => { target = new URL(url); return jsonResponse({ documents: [] }); } });
  const query = '강원특별자치도 인제군 북면 & x=1';
  const response = await fetch(`${origin}/api/places/address?${new URLSearchParams({ query })}`);
  assert.equal(response.status, 200);
  assert.equal(target.searchParams.get('query'), query);
  assert.equal(target.searchParams.get('analyze_type'), 'similar');
  assert.equal(target.searchParams.has('x'), false);
});

test('weather proxy encodes an already encoded key once and fixes row count', async t => {
  let target;
  const origin = await app(t, { env: { WEATHER_API_KEY: 'fixture%2Bkey%2F%3D' }, fetchImpl: async url => { target = new URL(url); return jsonResponse({ response: { body: { items: { item: [] } } } }); } });
  const response = await fetch(`${origin}/api/weather?nx=60&ny=127&base_date=20260927&base_time=0200`);
  assert.equal(response.status, 200);
  assert.equal(target.origin, 'https://apis.data.go.kr');
  assert.equal(target.searchParams.get('serviceKey'), 'fixture+key/=');
  assert.equal(target.searchParams.get('numOfRows'), '1000');
  assert.equal(target.searchParams.get('pageNo'), '1');
  assert.equal(target.searchParams.get('dataType'), 'JSON');
});

test('invalid coordinates, pagination, dates, duplicate and arbitrary URL params never fetch', async t => {
  let calls = 0;
  const origin = await app(t, { fetchImpl: () => { calls++; throw new Error('No upstream expected'); } });
  const invalidPaths = [
    '/api/places/mountains?x=Infinity&y=37', '/api/places/mountains?x=181&y=37',
    '/api/places/mountains?x=127&y=37&page=4', '/api/places/mountains?x=127&y=37&page=1.5',
    '/api/places/mountains?x=127&x=128&y=37', '/api/places/mountains?x=127&y=37&url=https://example.com',
    '/api/places/address?query=', '/api/places/address?query=%00',
    '/api/weather?nx=0&ny=127&base_date=20260927&base_time=0200',
    '/api/weather?nx=60&ny=127&base_date=20260230&base_time=0200',
    '/api/weather?nx=60&ny=127&base_date=20260927&base_time=0300',
    '/api/history?forceRefresh=maybe', '/api/config?key=x',
  ];
  for (const pathname of invalidPaths) assert.equal((await fetch(origin + pathname)).status, 400, pathname);
  assert.equal(calls, 0);
});

test('history discovers JSON-LD and forwards CP949 bytes without transcoding', async t => {
  const csv = Buffer.from([0xbf, 0xb9, 0xba, 0xb8, 0xc0, 0xcf, 0xbd, 0xc3, 0x2c, 0x31, 0x0d, 0x0a]);
  const requests = [];
  const origin = await app(t, { fetchImpl: async url => {
    requests.push(String(url));
    return String(url) === csvUrl ? new Response(csv, { headers: { 'content-type': 'application/octet-stream; charset=UTF-8' } }) : new Response(metadata());
  } });
  const response = await fetch(`${origin}/api/history`);
  assert.equal(response.status, 200);
  assert.equal(response.headers.get('x-data-modified-at'), '2026-09-03T00:00:00.000Z');
  assert.equal(response.headers.get('content-type'), 'text/csv');
  assert.deepEqual(Buffer.from(await response.arrayBuffer()), csv);
  assert.deepEqual(requests, ['https://www.data.go.kr/data/15092027/fileData.do', csvUrl]);
});

test('history caches by KST date, refreshes explicitly, and coalesces concurrent requests', async t => {
  let clock = 1_000_000;
  let requests = 0;
  let release;
  let reached;
  const gate = new Promise(resolve => { release = resolve; });
  const arrived = new Promise(resolve => { reached = resolve; });
  const origin = await app(t, { now: () => clock, fetchImpl: async url => {
    requests++;
    if (requests === 1) { reached(); await gate; }
    return new Response(String(url) === csvUrl ? 'date,value\n2026,1' : metadata());
  } });
  const first = fetch(`${origin}/api/history`);
  await arrived;
  const second = fetch(`${origin}/api/history?forceRefresh=true`);
  // Wait until the second local request has had a chance to join the shared promise.
  await new Promise(resolve => setTimeout(resolve, 15));
  release();
  assert.equal((await first).status, 200);
  assert.equal((await second).status, 200);
  assert.equal(requests, 2);
  await fetch(`${origin}/api/history`);
  assert.equal(requests, 2);
  await fetch(`${origin}/api/history?forceRefresh=true`);
  assert.equal(requests, 4);
  clock += 24 * 60 * 60 * 1000;
  await fetch(`${origin}/api/history`);
  assert.equal(requests, 6);
});

test('history refreshes across Korean midnight even if only two minutes elapsed', async t => {
  let clock = Date.parse('2026-09-26T14:59:00Z'); // KST 23:59
  let requests = 0;
  const origin = await app(t, { now: () => clock, fetchImpl: async url => {
    requests++;
    return new Response(String(url) === csvUrl ? `date,value\n2026,${requests}` : metadata());
  } });
  const first = await (await fetch(`${origin}/api/history`)).text();
  assert.equal(requests, 2);
  clock += 30_000;
  assert.equal(await (await fetch(`${origin}/api/history`)).text(), first);
  assert.equal(requests, 2);
  clock += 90_000;
  assert.notEqual(await (await fetch(`${origin}/api/history`)).text(), first);
  assert.equal(requests, 4);
});

test('failed forced or next-day history refresh returns an error instead of stale success', async t => {
  let clock = Date.parse('2026-09-26T14:59:00Z');
  let fail = false;
  const origin = await app(t, { now: () => clock, fetchImpl: async url => {
    if (fail) return new Response('upstream unavailable', { status: 500 });
    return new Response(String(url) === csvUrl ? 'date,value\n2026,cached' : metadata());
  } });
  assert.equal((await fetch(`${origin}/api/history`)).status, 200);
  fail = true;
  const forced = await fetch(`${origin}/api/history?forceRefresh=true`);
  assert.equal(forced.status, 502);
  assert.equal((await forced.json()).error.code, 'UPSTREAM_ERROR');
  // A failed forced refresh preserves the cache but does not return it for that request.
  assert.match(await (await fetch(`${origin}/api/history`)).text(), /cached/);
  clock += 120_000;
  assert.equal((await fetch(`${origin}/api/history`)).status, 502);
  assert.equal((await fetch(`${origin}/api/history`)).status, 502);
});

test('history accepts JSON-LD graph and relative safe redirects', async t => {
  let requests = 0;
  const document = { '@graph': [{ '@type': ['Dataset'], distribution: { encodingFormat: 'text/csv', contentUrl: csvUrl } }] };
  const origin = await app(t, { fetchImpl: async url => {
    requests++;
    if (requests === 1) return new Response(`<script type='application/ld+json'>${JSON.stringify(document)}</script>`);
    if (requests === 2) return new Response(null, { status: 302, headers: { location: '/files/actual.csv' } });
    assert.equal(String(url), 'https://www.data.go.kr/files/actual.csv');
    return new Response('date,value\n2026,1');
  } });
  assert.equal((await fetch(`${origin}/api/history`)).status, 200);
  assert.equal(requests, 3);
});

test('untrusted CSV URLs and redirects are rejected before contacting that destination', async t => {
  for (const forbidden of ['http://www.data.go.kr/a.csv', 'https://www.data.go.kr.evil.example/a.csv', 'https://localhost/a.csv', 'https://user:password@www.data.go.kr/a.csv', 'https://www.data.go.kr:8443/a.csv']) {
    let calls = 0;
    const origin = await app(t, { fetchImpl: async () => { calls++; return new Response(metadata(forbidden)); } });
    assert.equal((await fetch(`${origin}/api/history`)).status, 502, forbidden);
    assert.equal(calls, 1);
  }
  let calls = 0;
  const origin = await app(t, { fetchImpl: async () => {
    calls++;
    return calls === 1 ? new Response(metadata()) : new Response(null, { status: 302, headers: { location: 'https://evil.example/file.csv' } });
  } });
  assert.equal((await fetch(`${origin}/api/history`)).status, 502);
  assert.equal(calls, 2);
});

test('upstream errors use safe Korean messages without credentials or request details', async t => {
  for (const status of [401, 403, 429, 500]) {
    const origin = await app(t, { fetchImpl: async () => new Response('private-rest-fixture 서울특별시 secret-url', { status }) });
    const response = await fetch(`${origin}/api/places/address?query=서울특별시`);
    assert.equal(response.status, status === 500 ? 502 : status);
    const body = await response.text();
    assert.doesNotMatch(body, /private-rest|서울특별시|secret-url/);
    assert.match(JSON.parse(body).error.message, /[가-힣]/);
  }
});

test('timeout applies to the full upstream request', async t => {
  const origin = await app(t, { timeoutMs: 20, fetchImpl: async (_url, { signal }) => new Promise((resolve, reject) => {
    signal.addEventListener('abort', () => reject(new Error('sensitive URL in internal exception')), { once: true });
  }) });
  const response = await fetch(`${origin}/api/places/mountains?x=127&y=37`);
  assert.equal(response.status, 504);
  assert.equal((await response.json()).error.code, 'UPSTREAM_TIMEOUT');
});

test('missing metadata, HTML download, oversized file and invalid JSON fail cleanly', async t => {
  for (const mode of ['metadata', 'html', 'oversized', 'json']) {
    let calls = 0;
    const origin = await app(t, { fetchImpl: async () => {
      calls++;
      if (mode === 'json') return new Response('<html>upstream unavailable</html>');
      if (mode === 'metadata') return new Response('<script type="application/ld+json">{broken</script>');
      if (calls === 1) return new Response(metadata());
      if (mode === 'oversized') return new Response('abc', { headers: { 'content-length': String(33 * 1024 * 1024) } });
      return new Response('<!DOCTYPE html><html>login</html>');
    } });
    const endpoint = mode === 'json' ? '/api/places/mountains?x=127&y=37' : '/api/history';
    assert.equal((await fetch(origin + endpoint)).status, 502, mode);
  }
});

test('static assets use MIME types and reject traversal, dotfiles, directories and unknown API', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'happy-mountain-server-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await writeFile(path.join(directory, 'index.html'), '<html>mountain</html>');
  await writeFile(path.join(directory, 'main.dart.js'), 'console.log("fixture");');
  await writeFile(path.join(directory, '.env.local'), 'REST_KEY=do-not-expose');
  await mkdir(path.join(directory, 'assets'));
  const origin = await app(t, { env: { STATIC_ROOT: directory }, fetchImpl: () => { throw new Error('No upstream expected'); } });
  const index = await fetch(origin);
  assert.equal(index.status, 200);
  assert.equal(await index.text(), '<html>mountain</html>');
  const script = await fetch(`${origin}/main.dart.js`, { method: 'HEAD' });
  assert.equal(script.status, 200);
  assert.equal(script.headers.get('content-type'), 'text/javascript; charset=utf-8');
  assert.equal(await script.text(), '');
  for (const pathname of ['/.env.local', '/%2eenv.local', '/assets', '/missing.js', '/api/unknown']) {
    const response = await rawRequest(origin, pathname);
    assert.equal(response.status, 404, pathname);
    assert.doesNotMatch(response.body, /do-not-expose/);
  }
  for (const pathname of ['/../.env.local', '/%2e%2e/.env.local', '/assets/%2e%2e/.env.local', '/%xx']) {
    assert.equal((await rawRequest(origin, pathname)).status, 400, pathname);
  }
  for (const pathname of ['/..%5c.env.local', '/C:%5csecret', '//../.env.local']) {
    assert.notEqual((await rawRequest(origin, pathname)).status, 200, pathname);
  }
  assert.equal((await rawRequest(origin, '/api/config', 'POST')).status, 405);
});

test('static files cannot escape through a directory symlink', async t => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'happy-mountain-links-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const web = path.join(directory, 'web');
  const secret = path.join(directory, 'outside');
  await mkdir(web);
  await mkdir(secret);
  await writeFile(path.join(secret, 'key.txt'), 'secret-fixture');
  await symlink(secret, path.join(web, 'escape'), process.platform === 'win32' ? 'junction' : 'dir');
  const origin = await app(t, { env: { STATIC_ROOT: web } });
  const response = await fetch(`${origin}/escape/key.txt`);
  assert.equal(response.status, 404);
  assert.doesNotMatch(await response.text(), /secret-fixture/);
});
