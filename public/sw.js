/* 탑신병자 서비스 워커 (SPEC 2장 PWA)
 * 저장하는 것: 이 사이트의 화면 파일(/assets/* 의 JS·CSS·글꼴, /icons/*)과 오프라인 안내 화면뿐.
 * 저장하지 않는 것: Supabase 통신, 로그인(OAuth) 흐름, 비공개 사진의 서명 주소 등 다른 출처 요청 전부,
 *   그리고 모든 페이지 이동(index.html 포함 — 항상 네트워크). 이런 요청은 respondWith를 부르지 않고 브라우저에 맡긴다.
 * __BUILD_ID__ 는 빌드할 때 바뀐다 → 배포마다 이 파일 내용이 달라져 브라우저가 새 버전을 알아챈다. */
const BUILD_ID = '__BUILD_ID__';
const CACHE = `tlc-static-${BUILD_ID}`;
const OFFLINE_URL = '/offline.html';

self.addEventListener('install', (event) => {
  // 새 버전은 설치만 하고 기다린다 — 화면의 [새로고침]을 누르면(SKIP_WAITING) 그때 바뀐다
  event.waitUntil(caches.open(CACHE).then((cache) => cache.add(OFFLINE_URL)));
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith('tlc-static-') && k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('message', (event) => {
  if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

/** 저장해도 되는 요청인가: 같은 출처 GET 중 해시 붙은 화면 파일과 아이콘만 */
function isStaticFile(url) {
  return url.pathname.startsWith('/assets/') || url.pathname.startsWith('/icons/');
}

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // Supabase·구글·카카오·Data Dragon 등은 건드리지 않는다

  if (req.mode === 'navigate') {
    // 페이지 이동은 항상 네트워크(로그인 돌아오기 주소 포함). 연결이 없을 때만 안내 화면
    event.respondWith(
      fetch(req).catch(() => caches.open(CACHE).then((c) => c.match(OFFLINE_URL)).then((r) => r || Response.error())),
    );
    return;
  }

  if (!isStaticFile(url)) return;

  event.respondWith(
    caches.open(CACHE).then((cache) => cache.match(req).then((hit) => {
      if (hit) return hit;
      return fetch(req).then((res) => {
        // 정상 응답이면서 HTML이 아닐 때만 저장 (없는 파일에 index.html이 200으로 오는 경우를 막는다)
        const type = res.headers.get('content-type') || '';
        if (res.ok && !type.includes('text/html')) cache.put(req, res.clone());
        return res;
      });
    })),
  );
});
