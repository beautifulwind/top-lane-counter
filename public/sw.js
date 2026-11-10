/* 탑신병자 서비스 워커 (SPEC 2장 PWA)
 * 저장하는 것: 이 사이트의 화면 파일(/assets/* 의 JS·CSS·글꼴, /icons/*)과 오프라인 안내 화면뿐.
 * 저장하지 않는 것: Supabase 통신, 로그인(OAuth) 흐름, 비공개 사진의 서명 주소 등 다른 출처 요청 전부,
 *   그리고 모든 페이지 이동(index.html 포함 — 항상 네트워크). 이런 요청은 respondWith를 부르지 않고 브라우저에 맡긴다.
 * 웹 푸시(037, SPEC 6-24): push가 오면 잠금 화면 알림을 띄우고, 누르면 그 알림의 사이트 안 주소로 간다.
 *   (아래 캐시 규칙과는 따로 — 알림 때문에 저장하는 것은 없다)
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

// ---------------------------------------------------------------------
// 웹 푸시 (037). 보내는 쪽: Supabase Edge Function web-push — { title, body, url, tag }
// ---------------------------------------------------------------------

/** 누르면 갈 주소: 이 사이트 안의 경로만 (다른 사이트 주소·이상한 값이면 알림 화면) */
function pushPath(url) {
  return typeof url === 'string' && url.startsWith('/') && !url.startsWith('//') ? url : '/notifications';
}

self.addEventListener('push', (event) => {
  let data = {};
  try {
    data = event.data ? event.data.json() : {};
  } catch {
    data = { body: event.data ? event.data.text() : '' };
  }
  const title = typeof data.title === 'string' && data.title ? data.title : '탑신병자';
  event.waitUntil(Promise.all([
    self.registration.showNotification(title, {
      body: typeof data.body === 'string' ? data.body : '',
      icon: '/icons/icon-192.png',
      tag: typeof data.tag === 'string' ? data.tag : undefined,
      data: { url: pushPath(data.url) },
    }),
    // 열려 있는 화면은 빨간 점(안 읽은 알림)을 다시 센다
    self.clients.matchAll({ type: 'window' }).then((list) => list.forEach((c) => c.postMessage({ type: 'PUSH_RECEIVED' }))),
  ]));
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const path = pushPath(event.notification.data && event.notification.data.url);
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      const open = list.find((c) => new URL(c.url).origin === self.location.origin);
      if (open) {
        // 열려 있는 사이트 화면을 앞으로 가져와 그 안에서 이동 (화면이 react-router로 이동한다)
        open.postMessage({ type: 'OPEN_PATH', path });
        return open.focus();
      }
      return self.clients.openWindow(path);
    }),
  );
});
