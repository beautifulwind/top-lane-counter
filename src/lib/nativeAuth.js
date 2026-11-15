import { App } from '@capacitor/app';
import { Browser } from '@capacitor/browser';

// 앱(Capacitor)에서 구글·카카오 로그인 (SPEC 6-57). 웹(브라우저·PWA)은 이 파일을 쓰지 않는다.
// 앱 화면(WebView) 안에서는 구글이 로그인을 막으므로, 로그인 주소를 시스템 브라우저(안드로이드 Custom Tab, iOS Safari 창)로 열고
// Supabase가 com.topsinbyeongja.app://auth-callback?code=… 로 돌려보내면 앱이 그 주소(appUrlOpen)를 받아 code를 세션으로 바꾼다.

export const NATIVE_SCHEME = 'com.topsinbyeongja.app';
export const NATIVE_REDIRECT = `${NATIVE_SCHEME}://auth-callback`;

/**
 * 앱으로 돌아온 주소를 읽는다. 로그인 콜백이 아니면 null.
 * 돌려주는 값: { code, flowId, error, errorCode, errorDescription } (없는 값은 null). 오류는 ?와 # 둘 다 본다.
 */
export function parseAuthCallback(url) {
  let u;
  try {
    u = new URL(url);
  } catch {
    return null;
  }
  if (u.protocol !== `${NATIVE_SCHEME}:` || u.hostname !== 'auth-callback') return null;
  const hash = new URLSearchParams(u.hash.slice(1));
  const get = (k) => u.searchParams.get(k) ?? hash.get(k);
  return {
    code: get('code'),
    flowId: get('sb_flow_id'),
    error: get('error'),
    errorCode: get('error_code'),
    errorDescription: get('error_description'),
  };
}

// ---------------- 결과 전달 (AuthProvider가 받는다) ----------------
// 결과: { type: 'success', notice, returnTo } | { type: 'error', error } | { type: 'cancelled', error }
// 받는 쪽이 아직 없으면(앱이 꺼져 있다가 딥링크로 켜진 경우) 마지막 결과를 들고 있다가 처음 구독할 때 넘긴다.
const subscribers = new Set();
let unread = null;

export function onNativeAuth(cb) {
  subscribers.add(cb);
  if (unread) {
    const r = unread;
    unread = null;
    cb(r);
  }
  return () => { subscribers.delete(cb); };
}

export function emitNativeAuth(result) {
  if (subscribers.size === 0) {
    unread = result;
    return;
  }
  subscribers.forEach((cb) => cb(result));
}

// ---------------- 시스템 브라우저 열기 ----------------
// 열린 로그인 한 번 = waiter 하나. 콜백을 받거나(finished) 그냥 닫혀서(cancelled) 끝나면 풀린다.
let waiter = null;
let handling = false; // 콜백을 처리하는 중 (그사이 browserFinished가 와도 취소로 보지 않는다)

function settle(result) {
  const w = waiter;
  waiter = null;
  w?.(result);
}

/**
 * 로그인 주소를 시스템 브라우저로 연다. 로그인이 끝나면(돌아옴 'finished' / 그냥 닫음 'cancelled') 풀리는 Promise.
 * (그동안 로그인 버튼은 "이동 중…"으로 막아 둔다)
 */
export function openAuthBrowser(url, browser = Browser) {
  settle('cancelled'); // 앞에 열어 둔 것이 있으면 정리
  return new Promise((resolve, reject) => {
    waiter = resolve;
    browser.open({ url }).catch((e) => {
      waiter = null;
      reject(new Error(`로그인 창을 열지 못했습니다. (${e?.message ?? e})`));
    });
  });
}

// ---------------- 같은 code 두 번 교환 막기 ----------------
// 같은 콜백이 appUrlOpen과 getLaunchUrl(앱이 딥링크로 켜졌을 때)로 두 번 오거나, 화면을 다시 불러와도 한 번만 바꾼다.
const USED_KEY = 'auth:native-used-codes';
const memoryUsed = new Set();

function readUsed() {
  try {
    return JSON.parse(localStorage.getItem(USED_KEY) ?? '[]');
  } catch {
    return [];
  }
}

/** 처음 보는 code면 기록하고 true, 이미 쓴 code면 false */
export function claimCode(code) {
  if (memoryUsed.has(code)) return false;
  const used = readUsed();
  if (used.includes(code)) return false;
  memoryUsed.add(code);
  try {
    localStorage.setItem(USED_KEY, JSON.stringify([...used, code].slice(-5)));
  } catch { /* 메모리 기록으로만 막는다 */ }
  return true;
}

// ---------------- 리스너 (앱 시작 때 한 번) ----------------
let started = false;

/** 콜백이 늦게 오는 경우(브라우저가 먼저 닫힘 이벤트를 보냄)를 기다리는 시간 */
export const CANCEL_GRACE_MS = 1500;

/**
 * appUrlOpen·getLaunchUrl·browserFinished를 한 번만 등록한다. 등록했으면 true (두 번째부터 false).
 * onCallback(parsed) → 결과 객체 Promise (실패는 throw) / onCancel() → 취소 결과
 */
export function listenAuthCallbacks({ onCallback, onCancel, app = App, browser = Browser, graceMs = CANCEL_GRACE_MS }) {
  if (started) return false;
  started = true;

  const handleUrl = async (url) => {
    const parsed = parseAuthCallback(url);
    if (!parsed) return; // 로그인 콜백이 아닌 딥링크
    if (parsed.code && !claimCode(parsed.code)) return; // 이미 처리한 code
    handling = true;
    browser.close().catch(() => {}); // iOS는 창을 닫는다 (안드로이드는 앱이 앞으로 오면서 이미 닫혀 있음)
    try {
      emitNativeAuth(await onCallback(parsed));
    } catch (error) {
      emitNativeAuth({ type: 'error', error });
    } finally {
      handling = false;
      settle('finished');
    }
  };

  app.addListener('appUrlOpen', ({ url }) => handleUrl(url));
  // 앱이 꺼져 있다가 딥링크로 켜진 경우
  app.getLaunchUrl?.().then((r) => r?.url && handleUrl(r.url), () => {});
  // 사용자가 로그인 창을 그냥 닫음 → 잠시 기다려도 콜백이 없으면 취소
  browser.addListener('browserFinished', () => {
    setTimeout(() => {
      if (!waiter || handling) return;
      settle('cancelled');
      emitNativeAuth(onCancel());
    }, graceMs);
  });
  return true;
}

/** 테스트용: 모듈 상태 초기화 */
export function resetNativeAuthForTest() {
  started = false;
  waiter = null;
  handling = false;
  unread = null;
  subscribers.clear();
  memoryUsed.clear();
  try { localStorage.removeItem(USED_KEY); } catch { /* 무시 */ }
}
