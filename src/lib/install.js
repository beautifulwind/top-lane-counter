import { useSyncExternalStore } from 'react';

// 홈 화면에 앱처럼 설치 (SPEC 3장 ☰ 메뉴 [앱 설치])
// - 안드로이드 크롬: beforeinstallprompt 이벤트를 앱 시작 때 잡아 두었다가 [앱 설치]에서 설치 창을 띄운다
// - 아이폰·아이패드: 설치 창이 없어 "공유 → 홈 화면에 추가" 안내
// - 이미 설치된 상태(standalone)나 설치할 수 없는 환경에서는 항목을 숨긴다

/** 순수 판정: 'installed'(숨김) | 'prompt'(설치 창) | 'ios'(안내) | 'none'(숨김) */
export function installKind({ standalone, hasPrompt, ios }) {
  if (standalone) return 'installed';
  if (hasPrompt) return 'prompt';
  if (ios) return 'ios';
  return 'none';
}

let deferred = null; // 잡아 둔 beforeinstallprompt 이벤트
let installed = false;
const listeners = new Set();
let snapshot = 'none';

const isStandalone = () => {
  try {
    return window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
  } catch {
    return false;
  }
};
const isIos = () => {
  const ua = window.navigator.userAgent || '';
  // 아이패드는 맥으로 위장하므로 터치 지점 수로 구분
  return /iPhone|iPad|iPod/.test(ua) || (window.navigator.platform === 'MacIntel' && window.navigator.maxTouchPoints > 1);
};

function refresh() {
  const next = installKind({ standalone: installed || isStandalone(), hasPrompt: deferred !== null, ios: isIos() });
  if (next === snapshot) return;
  snapshot = next;
  listeners.forEach((l) => l());
}

/** 앱 시작 때 한 번 (index.jsx). 메뉴가 열리기 전에 이벤트가 와도 놓치지 않는다 */
export function captureInstallPrompt() {
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault(); // 크롬 기본 안내 대신 [앱 설치]로
    deferred = e;
    refresh();
  });
  window.addEventListener('appinstalled', () => {
    installed = true;
    deferred = null;
    refresh();
  });
  try { window.matchMedia('(display-mode: standalone)').addEventListener('change', refresh); } catch { /* 옛 브라우저 */ }
  refresh();
}

/** 설치 창을 띄운다. 한 번 쓰면 이벤트는 다시 못 쓴다 */
export async function promptInstall() {
  if (!deferred) return;
  const e = deferred;
  deferred = null;
  refresh();
  try { await e.prompt(); } catch { /* 이미 띄웠거나 막힘 */ }
}

const subscribe = (l) => { listeners.add(l); return () => listeners.delete(l); };
export const useInstallKind = () => useSyncExternalStore(subscribe, () => snapshot, () => 'none');
