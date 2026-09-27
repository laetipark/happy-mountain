import { createServer } from 'node:http';
import { readFile, realpath, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SERVER_ROOT = fileURLToPath(new URL('../', import.meta.url));
const HISTORY_PAGE = 'https://www.data.go.kr/data/15092027/fileData.do';
const DATA_HOSTS = new Set(['data.go.kr', 'www.data.go.kr']);
const FORECAST_TIMES = new Set(['0200', '0500', '0800', '1100', '1400', '1700', '2000', '2300']);
const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.wasm': 'application/wasm', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
  '.ttf': 'font/ttf', '.otf': 'font/otf', '.woff': 'font/woff', '.woff2': 'font/woff2',
  '.bin': 'application/octet-stream', '.webp': 'image/webp', '.txt': 'text/plain; charset=utf-8',
};

class AppError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

const invalid = () => new AppError(400, 'INVALID_REQUEST', '요청 조건을 확인해주세요.');
const upstreamFailure = () => new AppError(502, 'UPSTREAM_ERROR', '자료 제공 서버에서 데이터를 가져오지 못했습니다. 잠시 후 다시 시도해주세요.');

function assertAllowedUrl(value, hosts) {
  let url;
  try { url = new URL(value); } catch { throw upstreamFailure(); }
  if (url.protocol !== 'https:' || !hosts.has(url.hostname) ||
      (url.port && url.port !== '443') || url.username || url.password) {
    throw upstreamFailure();
  }
  return url;
}

function numberParam(params, key, min, max, integer = false, fallback) {
  const raw = params.get(key) ?? fallback;
  if (raw === undefined || !/^-?(?:\d+(?:\.\d+)?|\.\d+)$/.test(raw)) throw invalid();
  const value = Number(raw);
  if (!Number.isFinite(value) || value < min || value > max || (integer && !Number.isInteger(value))) throw invalid();
  return String(value);
}

function onlyParams(params, allowed) {
  for (const key of params.keys()) {
    if (!allowed.includes(key) || params.getAll(key).length !== 1) throw invalid();
  }
}

function requireKey(value) {
  if (!value) throw new AppError(503, 'NOT_CONFIGURED', '이 기능의 API 키가 아직 설정되지 않았습니다.');
  return value;
}

function weatherKey(value) {
  const key = requireKey(value);
  try { return decodeURIComponent(key); } catch { return key; }
}

function jsonReply(res, status, value) {
  const body = Buffer.from(JSON.stringify(value));
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Content-Length': body.length, 'Cache-Control': 'no-store' });
  res.end(body);
}

async function readLimited(response, limit) {
  if (Number(response.headers.get('content-length')) > limit) {
    await response.body?.cancel();
    throw upstreamFailure();
  }
  if (!response.body) return Buffer.alloc(0);
  const reader = response.body.getReader();
  const parts = [];
  let length = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > limit) {
        await reader.cancel();
        throw upstreamFailure();
      }
      parts.push(Buffer.from(value));
    }
  } finally {
    reader.releaseLock();
  }
  return Buffer.concat(parts, length);
}

function datasetObjects(value) {
  if (Array.isArray(value)) return value.flatMap(datasetObjects);
  if (!value || typeof value !== 'object') return [];
  const result = [];
  if (value['@type'] === 'Dataset' || value['@type']?.includes?.('Dataset')) result.push(value);
  return result.concat(datasetObjects(value['@graph']));
}

function historyMetadata(html) {
  for (const match of html.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script\s*>/gi)) {
    if (!/\btype\s*=\s*["']application\/ld\+json["']/i.test(match[1])) continue;
    let document;
    try { document = JSON.parse(match[2]); } catch { continue; }
    for (const dataset of datasetObjects(document)) {
      const distributions = Array.isArray(dataset.distribution) ? dataset.distribution : [dataset.distribution];
      for (const item of distributions) {
        if (!item || !/csv/i.test(String(item.encodingFormat)) || typeof item.contentUrl !== 'string') continue;
        const url = assertAllowedUrl(item.contentUrl.replaceAll('&amp;', '&'), DATA_HOSTS);
        const modified = typeof dataset.dateModified === 'string' ? dataset.dateModified : '';
        const modifiedAt = /^\d{4}-\d{2}-\d{2}(?:T.*)?$/.test(modified) && !Number.isNaN(Date.parse(modified))
          ? new Date(modified).toISOString() : undefined;
        return { url, modifiedAt };
      }
    }
  }
  throw new AppError(502, 'HISTORY_SOURCE_CHANGED', '경보 이력 다운로드 주소를 확인할 수 없습니다. 잠시 후 다시 시도해주세요.');
}

function isInside(root, target) {
  const relative = path.relative(root, target);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

function koreaDate(timestamp) {
  return new Date(timestamp + 9 * 60 * 60 * 1000).toISOString().slice(0, 10);
}

/** Dependency injection keeps upstream tests offline and credentials out of fixtures. */
export function createAppServer({ env = process.env, fetchImpl = globalThis.fetch, timeoutMs = 25_000, now = Date.now } = {}) {
  const staticRoot = path.resolve(SERVER_ROOT, env.STATIC_ROOT || '../mobile/build/web');
  const kakaoKey = (env.KAKAO_REST_API_KEY || '').trim();
  const serviceKey = (env.WEATHER_API_KEY || '').trim();
  let historyCache;
  let historyInFlight;

  async function upstream(url, { hosts, headers, limit = 4 * 1024 * 1024, signal }) {
    let target = assertAllowedUrl(url, hosts);
    for (let redirects = 0; redirects <= 3; redirects++) {
      const response = await fetchImpl(target, { method: 'GET', headers, redirect: 'manual', signal });
      if ([301, 302, 303, 307, 308].includes(response.status)) {
        const location = response.headers.get('location');
        await response.body?.cancel();
        if (!location || redirects === 3) throw upstreamFailure();
        target = assertAllowedUrl(new URL(location, target), hosts);
        continue;
      }
      if (!response.ok) {
        await response.body?.cancel();
        if (response.status === 401) throw new AppError(401, 'UPSTREAM_UNAUTHORIZED', 'API 인증에 실패했습니다. 서버 키 설정을 확인해주세요.');
        if (response.status === 403) throw new AppError(403, 'UPSTREAM_FORBIDDEN', '데이터 이용 권한을 확인해주세요.');
        if (response.status === 429) throw new AppError(429, 'UPSTREAM_RATE_LIMIT', '조회 한도를 초과했습니다. 잠시 후 다시 시도해주세요.');
        throw upstreamFailure();
      }
      return readLimited(response, limit);
    }
    throw upstreamFailure();
  }

  async function timed(task) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    timer.unref?.();
    try { return await task(controller.signal); }
    catch (error) {
      if (controller.signal.aborted) throw new AppError(504, 'UPSTREAM_TIMEOUT', '자료 조회 시간이 초과되었습니다. 다시 시도해주세요.');
      if (error instanceof AppError) throw error;
      throw upstreamFailure();
    } finally { clearTimeout(timer); }
  }

  async function rawJson(res, url, hosts, headers) {
    const bytes = await timed(signal => upstream(url, { hosts, headers, signal }));
    try { JSON.parse(bytes.toString('utf8')); } catch { throw upstreamFailure(); }
    res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'Content-Length': bytes.length });
    res.end(bytes);
  }

  async function history(forceRefresh) {
    if (historyInFlight) return historyInFlight;
    if (!forceRefresh && historyCache && koreaDate(now()) === koreaDate(historyCache.fetchedAt)) return historyCache;
    historyInFlight = timed(async signal => {
      const html = await upstream(HISTORY_PAGE, { hosts: DATA_HOSTS, signal });
      const metadata = historyMetadata(html.toString('utf8'));
      const bytes = await upstream(metadata.url, { hosts: DATA_HOSTS, signal, limit: 32 * 1024 * 1024 });
      // Login/error HTML must not replace a good cached CSV.
      if (!bytes.length || /^\s*</.test(bytes.subarray(0, 128).toString('ascii'))) throw upstreamFailure();
      historyCache = { bytes, modifiedAt: metadata.modifiedAt, fetchedAt: now() };
      return historyCache;
    }).finally(() => { historyInFlight = undefined; });
    return historyInFlight;
  }

  async function api(res, url) {
    const params = url.searchParams;
    switch (url.pathname) {
      case '/api/config':
        onlyParams(params, []);
        return jsonReply(res, 200, {
          kakaoJavascriptKey: (env.KAKAO_JAVASCRIPT_APP_KEY || '').trim(),
          placesEnabled: Boolean(kakaoKey), weatherEnabled: Boolean(serviceKey),
        });
      case '/api/places/mountains': {
        onlyParams(params, ['x', 'y', 'page']);
        const target = new URL('https://dapi.kakao.com/v2/local/search/keyword.json');
        target.search = new URLSearchParams({ query: '산', category_group_code: 'AT4', radius: '10000', sort: 'distance', size: '15',
          x: numberParam(params, 'x', -180, 180), y: numberParam(params, 'y', -90, 90), page: numberParam(params, 'page', 1, 3, true, '1') }).toString();
        return rawJson(res, target, new Set(['dapi.kakao.com']), { Authorization: `KakaoAK ${requireKey(kakaoKey)}` });
      }
      case '/api/places/address': {
        onlyParams(params, ['query']);
        const query = params.get('query')?.trim();
        if (!query || query.length > 200 || /[\u0000-\u001f]/.test(query)) throw invalid();
        const target = new URL('https://dapi.kakao.com/v2/local/search/address.json');
        target.search = new URLSearchParams({ query, analyze_type: 'similar' }).toString();
        return rawJson(res, target, new Set(['dapi.kakao.com']), { Authorization: `KakaoAK ${requireKey(kakaoKey)}` });
      }
      case '/api/weather': {
        onlyParams(params, ['nx', 'ny', 'base_date', 'base_time']);
        const date = params.get('base_date') || '';
        const time = params.get('base_time') || '';
        if (!/^\d{8}$/.test(date) || !FORECAST_TIMES.has(time)) throw invalid();
        const isoDate = `${date.slice(0, 4)}-${date.slice(4, 6)}-${date.slice(6, 8)}`;
        const parsed = new Date(`${isoDate}T00:00:00Z`);
        if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== isoDate) throw invalid();
        const target = new URL('https://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getVilageFcst');
        target.search = new URLSearchParams({ serviceKey: weatherKey(serviceKey), pageNo: '1', numOfRows: '1000', dataType: 'JSON',
          nx: numberParam(params, 'nx', 1, 149, true), ny: numberParam(params, 'ny', 1, 253, true), base_date: date, base_time: time }).toString();
        return rawJson(res, target, new Set(['apis.data.go.kr']));
      }
      case '/api/history': {
        onlyParams(params, ['forceRefresh']);
        const force = params.get('forceRefresh');
        if (force !== null && force !== 'true' && force !== 'false') throw invalid();
        const data = await history(force === 'true');
        const headers = { 'Content-Type': 'text/csv', 'Cache-Control': 'no-store', 'Content-Length': data.bytes.length };
        if (data.modifiedAt) headers['X-Data-Modified-At'] = data.modifiedAt;
        res.writeHead(200, headers);
        return res.end(data.bytes);
      }
      default: throw new AppError(404, 'NOT_FOUND', '요청한 API가 없습니다.');
    }
  }

  async function staticFile(req, res, pathname) {
    let decoded;
    try { decoded = decodeURIComponent(pathname); } catch { throw invalid(); }
    if (decoded.includes('\\') || decoded.includes(':') || decoded.includes('\0') ||
        decoded.split('/').some(segment => segment.startsWith('.'))) {
      throw new AppError(404, 'NOT_FOUND', '요청한 파일이 없습니다.');
    }
    const requested = decoded === '/' ? 'index.html' : decoded.replace(/^\/+/, '');
    let file = path.resolve(staticRoot, requested);
    if (!isInside(staticRoot, file)) throw new AppError(404, 'NOT_FOUND', '요청한 파일이 없습니다.');
    let info;
    try {
      const [realRoot, realFile] = await Promise.all([realpath(staticRoot), realpath(file)]);
      if (!isInside(realRoot, realFile) || path.relative(realRoot, realFile).split(path.sep).some(part => part.startsWith('.'))) throw new Error();
      file = realFile;
      info = await stat(file);
      if (!info.isFile()) throw new Error();
    } catch { throw new AppError(404, 'NOT_FOUND', '웹 빌드 파일이 없습니다. Flutter 웹 빌드 경로를 확인해주세요.'); }
    const bytes = req.method === 'HEAD' ? undefined : await readFile(file);
    res.writeHead(200, { 'Content-Type': MIME_TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream', 'Content-Length': info.size, 'Cache-Control': 'no-cache' });
    res.end(bytes);
  }

  return createServer(async (req, res) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer');
    try {
      // Validate the original path before URL normalization can remove dot segments.
      const rawPath = (req.url || '/').split('?')[0];
      const decodedPath = decodeURIComponent(rawPath);
      if (!rawPath.startsWith('/') || decodedPath.split('/').some(part => part === '.' || part === '..')) throw invalid();
      const url = new URL(req.url || '/', 'http://localhost');
      if (url.pathname === '/api' || url.pathname.startsWith('/api/')) {
        if (req.method !== 'GET') throw new AppError(405, 'METHOD_NOT_ALLOWED', 'GET 요청만 지원합니다.');
        await api(res, url);
      } else {
        if (req.method !== 'GET' && req.method !== 'HEAD') throw new AppError(405, 'METHOD_NOT_ALLOWED', 'GET 또는 HEAD 요청만 지원합니다.');
        await staticFile(req, res, rawPath);
      }
    } catch (error) {
      if (res.headersSent) return res.destroy();
      const safeError = error instanceof AppError ? error : error instanceof URIError ? invalid() : upstreamFailure();
      jsonReply(res, safeError.status, { error: { code: safeError.code, message: safeError.message } });
    }
  });
}
