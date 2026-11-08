import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import vm from 'node:vm';
import { describe, expect, it, vi } from 'vitest';

// public/sw.js를 가짜 환경에서 실행해, 어떤 요청을 가로채고(저장) 어떤 요청은 그냥 지나가는지 확인한다.
const code = readFileSync(join(process.cwd(), 'public/sw.js'), 'utf8');

function load() {
  const handlers = {};
  const store = new Map();
  const cache = {
    match: async (r) => store.get(typeof r === 'string' ? r : r.url),
    put: vi.fn(async (r, res) => { store.set(r.url, res); }),
    add: async (u) => { store.set(u, new Response('offline')); },
  };
  const fetchMock = vi.fn(async () => new Response('x', { status: 200, headers: { 'content-type': 'text/javascript' } }));
  const self = {
    location: { origin: 'https://site.test' },
    addEventListener: (type, fn) => { handlers[type] = fn; },
    clients: { claim: async () => {} },
    skipWaiting: vi.fn(),
  };
  const ctx = vm.createContext({
    self, URL, Response, fetch: fetchMock,
    caches: { open: async () => cache, keys: async () => [], delete: async () => true },
  });
  vm.runInContext(code.replaceAll('__BUILD_ID__', 'test'), ctx);
  return { handlers, cache, fetchMock, self };
}

function run(handlers, url, { method = 'GET', mode = 'cors' } = {}) {
  let handled = false;
  let promise;
  handlers.fetch({
    request: { url, method, mode },
    respondWith: (p) => { handled = true; promise = p; },
  });
  return { handled, promise };
}

describe('서비스 워커 캐시 규칙', () => {
  it('같은 출처 /assets 파일은 저장한다', async () => {
    const { handlers, cache } = load();
    const r = run(handlers, 'https://site.test/assets/index-abc.js');
    expect(r.handled).toBe(true);
    await r.promise;
    expect(cache.put).toHaveBeenCalledTimes(1);
  });
  it('Supabase·로그인 서버·Data Dragon 등 다른 출처는 건드리지 않는다', () => {
    const { handlers } = load();
    for (const u of [
      'https://abc.supabase.co/rest/v1/profiles?select=*',
      'https://abc.supabase.co/auth/v1/token',
      'https://abc.supabase.co/storage/v1/object/sign/board/a.png?token=t',
      'https://accounts.google.com/o/oauth2/v2/auth',
      'https://ddragon.leagueoflegends.com/cdn/16.21.1/img/champion/Quinn.png',
    ]) expect(run(handlers, u).handled, u).toBe(false);
  });
  it('같은 출처라도 /assets·/icons가 아니면 저장하지 않는다 (API·서명 주소 등)', () => {
    const { handlers } = load();
    expect(run(handlers, 'https://site.test/manifest.json').handled).toBe(false);
    expect(run(handlers, 'https://site.test/api/anything').handled).toBe(false);
  });
  it('GET이 아니면 지나간다', () => {
    const { handlers } = load();
    expect(run(handlers, 'https://site.test/assets/a.js', { method: 'POST' }).handled).toBe(false);
  });
  it('HTML이 돌아오면(없는 파일에 index.html) 저장하지 않는다', async () => {
    const { handlers, cache, fetchMock } = load();
    fetchMock.mockResolvedValueOnce(new Response('<html>', { status: 200, headers: { 'content-type': 'text/html' } }));
    await run(handlers, 'https://site.test/assets/old-chunk.js').promise;
    expect(cache.put).not.toHaveBeenCalled();
  });
  it('오류 응답은 저장하지 않는다', async () => {
    const { handlers, cache, fetchMock } = load();
    fetchMock.mockResolvedValueOnce(new Response('no', { status: 404, headers: { 'content-type': 'text/plain' } }));
    await run(handlers, 'https://site.test/assets/missing.js').promise;
    expect(cache.put).not.toHaveBeenCalled();
  });
  it('페이지 이동은 항상 네트워크, 연결이 없을 때만 오프라인 안내 (로그인 돌아오기 주소도 저장 안 함)', async () => {
    const { handlers, cache, fetchMock } = load();
    await cache.add('/offline.html');
    const online = run(handlers, 'https://site.test/me?code=abc', { mode: 'navigate' });
    expect(online.handled).toBe(true);
    await online.promise;
    expect(cache.put).not.toHaveBeenCalled();
    fetchMock.mockRejectedValueOnce(new TypeError('offline'));
    const res = await run(handlers, 'https://site.test/', { mode: 'navigate' }).promise;
    expect(await res.text()).toBe('offline');
  });
  it('새 버전은 SKIP_WAITING 메시지를 받아야 교체된다 (설치만으로는 안 바뀐다)', () => {
    const { handlers, self } = load();
    handlers.install({ waitUntil: () => {} });
    expect(self.skipWaiting).not.toHaveBeenCalled();
    handlers.message({ data: { type: 'SKIP_WAITING' } });
    expect(self.skipWaiting).toHaveBeenCalled();
  });
});
