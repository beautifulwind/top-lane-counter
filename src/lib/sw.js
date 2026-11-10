import { useSyncExternalStore } from 'react';
import { CHUNK_RELOAD_KEY } from './reloadGuard';
import { announceNotificationsChanged } from '../api/notifications';

// 서비스 워커 등록과 새 버전 알림 (SPEC 2장 PWA). 개발 서버에서는 등록하지 않는다 (프로덕션 빌드에서만).
// 새 버전이 설치되어 기다리는 중이면 화면에 "새 버전이 있습니다. [새로고침]" → applyUpdate()

const CHECK_EVERY = 60 * 60 * 1000; // 1시간마다 새 버전 확인 (앱을 다시 열 때도 확인)
let registration = null;
let waiting = false;
let applying = false; // [새로고침]을 눌렀을 때만 true — 처음 설치·자동 교체로는 새로고침하지 않는다
const listeners = new Set();
const emit = () => listeners.forEach((l) => l());

function watch(reg) {
  const check = () => {
    // 이미 이 화면을 조종하는 워커가 있을 때만 "새 버전" (맨 처음 설치는 알리지 않는다)
    if (reg.waiting && navigator.serviceWorker.controller) { waiting = true; emit(); }
  };
  check();
  reg.addEventListener('updatefound', () => {
    const worker = reg.installing;
    worker?.addEventListener('statechange', () => { if (worker.state === 'installed') check(); });
  });
}

export function registerServiceWorker() {
  if (!import.meta.env.PROD || !('serviceWorker' in navigator)) return;
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('/sw.js').then((reg) => {
      registration = reg;
      watch(reg);
      const update = () => reg.update().catch(() => {});
      document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') update(); });
      setInterval(update, CHECK_EVERY);
    }).catch(() => { /* 등록하지 못해도 사이트는 그대로 */ });
  });
  // 웹 푸시 (037): 서비스 워커가 보내는 신호 — 알림이 왔다(빨간 점 다시 세기) / 알림을 눌렀다(그 주소로 이동)
  navigator.serviceWorker.addEventListener('message', (e) => handleWorkerMessage(e.data));
  // 새 워커가 일을 넘겨받으면(= [새로고침]을 눌러 교체됨) 새 화면으로
  navigator.serviceWorker.addEventListener('controllerchange', () => {
    if (!applying) return;
    window.location.reload();
  });
}

const OPEN_PATH = 'tlc:open-path';

/** 서비스 워커 메시지 처리 (테스트에서도 부른다) */
export function handleWorkerMessage(data) {
  if (data?.type === 'PUSH_RECEIVED') announceNotificationsChanged();
  if (data?.type === 'OPEN_PATH' && typeof data.path === 'string' && data.path.startsWith('/') && !data.path.startsWith('//')) {
    window.dispatchEvent(new CustomEvent(OPEN_PATH, { detail: data.path }));
  }
}

/** 알림을 눌러 이 화면으로 돌아왔을 때 cb(사이트 안 주소). 해제 함수를 돌려준다 (Layout이 react-router로 이동) */
export function onOpenPath(cb) {
  const h = (e) => cb(e.detail);
  window.addEventListener(OPEN_PATH, h);
  return () => window.removeEventListener(OPEN_PATH, h);
}

/** [새로고침]: 기다리는 새 버전으로 바꾸고 다시 불러온다 */
export function applyUpdate() {
  applying = true;
  try { sessionStorage.removeItem(CHUNK_RELOAD_KEY); } catch { /* 저장소를 못 써도 괜찮음 */ }
  const worker = registration?.waiting;
  if (worker) worker.postMessage({ type: 'SKIP_WAITING' });
  else window.location.reload();
}

const subscribe = (l) => { listeners.add(l); return () => listeners.delete(l); };
export const useUpdateAvailable = () => useSyncExternalStore(subscribe, () => waiting, () => false);
