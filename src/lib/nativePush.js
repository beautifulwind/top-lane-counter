import { Capacitor } from '@capacitor/core';
import { isNativeApp } from './native';
import { registerAppToken, unregisterAppToken } from '../api/push';
import { announceNotificationsChanged } from '../api/notifications';

// 앱(iOS·Android) 휴대폰 알림 (1.3 패치 P-3, SPEC 6-103). 웹(브라우저·PWA)은 이 파일을 쓰지 않는다 — 웹 푸시는 api/push.js 그대로.
// - 권한: 로그인 직후(앱을 열었을 때 로그인돼 있어도) 이 기기에서 한 번만 묻는다. 설정 화면의 [이 기기에서 알림 켜기]에서도 묻는다.
//   거절해도 앱은 그대로 쓸 수 있다(알림만 안 옴).
// - 토큰: @capacitor/push-notifications register() → 'registration' 이벤트(iOS = APNs 기기 토큰 16진수, Android = FCM 토큰)
//   → DB 함수 register_device_push_token(platform, token, 앱 버전). 앱을 열 때마다 다시 등록(같은 줄 갱신, 마지막 확인 시각).
// - 끄기·로그아웃: unregister_device_push_token(token). 다른 계정으로 로그인하면 같은 토큰이 새 계정으로 옮겨진다(DB 함수).
// - 알림을 누르면: 서버가 data.url에 담은 사이트 안 주소로 이동(Layout이 onPushOpen을 받아 navigate).
// - 플러그인은 처음 쓸 때 불러온다(웹 화면·검사에서 불러오지 않게). Capacitor 플러그인 객체는 Promise로 넘기지 않는다(then 문제, SPEC 6-64).

const KEY_DEVICE = 'tsb.appPush.device'; // { platform, token, userId|null } — 이 기기 토큰과 지금 등록된 계정
const KEY_ASKED = 'tsb.appPush.asked'; // '1' = 로그인 직후 권한을 이미 물어봄 (이 기기에서 한 번만)
const offKey = (userId) => `tsb.appPush.off.${userId}`; // '1' = 이 계정이 이 기기에서 알림을 끔
const TOKEN_WAIT_MS = 15000;

export const APP_PUSH_DENIED = '휴대폰 설정에서 탑신병자 알림이 꺼져 있습니다. 설정 → 탑신병자 → 알림에서 허용한 뒤 다시 눌러 주세요.';
const APP_PUSH_NOT_ALLOWED = '알림 허용 창에서 [허용]을 눌러야 켤 수 있습니다.';
const APP_PUSH_REGISTER_FAILED = '이 기기를 알림에 등록하지 못했습니다. 잠시 뒤 다시 시도해 주세요.';

// ---------------- 바꿔 끼울 수 있는 것 (검사용) ----------------
const realPlugins = async () => {
  const [{ PushNotifications }, { App }] = await Promise.all([import('@capacitor/push-notifications'), import('@capacitor/app')]);
  return { push: PushNotifications, app: App }; // 플러그인 객체를 그대로 resolve하지 않고 감싸서 넘긴다
};
const realPlatform = () => {
  try {
    return Capacitor.getPlatform?.() ?? 'web';
  } catch {
    return 'web';
  }
};
let deps = { plugins: realPlugins, platform: realPlatform, native: isNativeApp, register: registerAppToken, unregister: unregisterAppToken, storage: () => window.localStorage };
let pluginsP = null;
const plugins = () => (pluginsP ??= deps.plugins().catch((e) => { pluginsP = null; throw e; }));

/** 검사용: 플러그인·DB 함수·저장소를 바꿔 끼우고 상태를 처음으로 */
export function setNativePushDepsForTest(next) {
  deps = { ...deps, ...next };
  resetNativePushForTest();
}
export function resetNativePushForTest() {
  pluginsP = null;
  started = false;
  listenersP = null;
  currentUser = null;
  waiters = [];
  openSubs.clear();
  unreadOpen = null;
}

// ---------------- 이 기기에 남기는 값 ----------------
function store() {
  try {
    return deps.storage();
  } catch {
    return null;
  }
}
const readJson = (k) => {
  try {
    return JSON.parse(store()?.getItem(k) ?? 'null');
  } catch {
    return null;
  }
};
const write = (k, v) => {
  try {
    if (v == null) store()?.removeItem(k);
    else store()?.setItem(k, typeof v === 'string' ? v : JSON.stringify(v));
  } catch { /* 저장소를 못 쓰면 다음에 다시 */ }
};
const readDevice = () => {
  const d = readJson(KEY_DEVICE);
  return d && typeof d.token === 'string' && typeof d.platform === 'string' ? d : null;
};
const isOff = (userId) => store()?.getItem(offKey(userId)) === '1';

// ---------------- 권한·토큰 ----------------
async function permission() {
  const { push } = await plugins();
  return (await push.checkPermissions())?.receive ?? 'prompt';
}
async function askPermission() {
  const { push } = await plugins();
  write(KEY_ASKED, '1');
  return (await push.requestPermissions())?.receive ?? 'denied';
}
const promptable = (p) => p === 'prompt' || p === 'prompt-with-rationale';

let waiters = []; // register() 뒤 'registration'을 기다리는 쪽
let currentUser = null; // 지금 로그인한 사람 (토큰이 저절로 바뀌었을 때 누구로 등록할지)

function settleWaiters(token, error) {
  const list = waiters;
  waiters = [];
  list.forEach((w) => (error ? w.reject(error) : w.resolve(token)));
}

/** register()를 부르고 'registration'으로 오는 토큰을 받는다 (15초) */
function obtainToken() {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      waiters = waiters.filter((w) => w !== entry);
      reject(new Error(APP_PUSH_REGISTER_FAILED));
    }, TOKEN_WAIT_MS);
    const entry = {
      resolve: (t) => { clearTimeout(timer); resolve(t); },
      reject: (e) => { clearTimeout(timer); reject(e); },
    };
    waiters.push(entry);
    // 'registration' 리스너가 붙은 뒤에 register()를 부른다 (먼저 부르면 토큰 이벤트를 놓칠 수 있음)
    listening(true)
      .then(() => plugins())
      .then(({ push }) => push.register())
      .catch(() => settleWaiters(null, new Error(APP_PUSH_REGISTER_FAILED)));
  });
}

async function appVersion() {
  try {
    const { app } = await plugins();
    const v = (await app.getInfo())?.version;
    return typeof v === 'string' && /^[A-Za-z0-9.+_-]{1,32}$/.test(v) ? v : null;
  } catch {
    return null;
  }
}

/** 토큰을 내 계정에 등록. 이 기기 토큰이 바뀌었으면 옛 토큰은 내 계정에서 지운다 */
async function saveToken(userId, token) {
  const platform = deps.platform();
  const prev = readDevice();
  if (prev && prev.token !== token && prev.userId === userId) await deps.unregister(prev.token).catch(() => {});
  await deps.register(platform, token, await appVersion());
  write(KEY_DEVICE, { platform, token, userId });
}

// 토큰이 저절로 바뀜(Android FCM 갱신 등) — 로그인돼 있고 이 기기에서 켜 둔 사람이면 새 토큰으로 다시 등록
function onToken(token) {
  if (typeof token !== 'string' || !token) return;
  if (waiters.length) {
    settleWaiters(token);
    return;
  }
  const userId = currentUser;
  if (userId && !isOff(userId)) saveToken(userId, token).catch(() => {});
}

// ---------------- 알림을 눌렀을 때 ----------------
const openSubs = new Set();
let unreadOpen = null;

/** 서버가 data.url에 담은 주소. 사이트 안 주소(/로 시작, //·\ 없음)만, 아니면 알림 목록 */
export function pushPath(data) {
  const url = data?.url;
  if (typeof url !== 'string' || !url.startsWith('/') || url.startsWith('//') || url.includes('\\') || url.length > 500) return '/notifications';
  return url;
}

/** 알림을 눌러 앱이 열렸을 때 갈 주소를 받는다 (Layout). 앱이 꺼져 있다가 알림으로 켜졌으면 처음 구독할 때 넘긴다 */
export function onPushOpen(cb) {
  openSubs.add(cb);
  if (unreadOpen) {
    const p = unreadOpen;
    unreadOpen = null;
    cb(p);
  }
  return () => { openSubs.delete(cb); };
}
function emitOpen(path) {
  if (openSubs.size === 0) {
    unreadOpen = path;
    return;
  }
  openSubs.forEach((cb) => cb(path));
}

// ---------------- 바깥에서 부르는 것 ----------------
let started = false;
let listenersP = null;
const listening = (native) => {
  startNativePush(native);
  return listenersP ?? Promise.reject(new Error('not native'));
};

/** 앱에서만: 토큰·알림 누름·앱이 열려 있을 때 온 알림 리스너를 한 번 등록 (index.jsx). 등록했으면 true */
export function startNativePush(native = deps.native()) {
  if (!native || started) return false;
  started = true;
  listenersP = plugins().then(({ push }) => Promise.all([
    push.addListener('registration', (t) => onToken(t?.value)),
    push.addListener('registrationError', () => settleWaiters(null, new Error(APP_PUSH_REGISTER_FAILED))),
    push.addListener('pushNotificationActionPerformed', (a) => emitOpen(pushPath(a?.notification?.data))),
    // 앱을 보고 있을 때 온 알림: 화면 위에 보이고(capacitor.config presentationOptions), 상단 빨간 점을 다시 센다
    push.addListener('pushNotificationReceived', () => announceNotificationsChanged()),
  ])).then(() => undefined, (e) => {
    started = false;
    listenersP = null;
    throw e;
  });
  listenersP.catch(() => {}); // 실패는 토큰을 기다리는 쪽이 받는다
  return true;
}

/**
 * 로그인 확인 뒤(로그인 직후·앱을 열었을 때) 한 번: 이 기기에서 끄지 않았으면
 *   권한이 있으면 토큰을 다시 등록(갱신), 아직 묻지 않았으면 한 번 묻고 허용하면 등록, 거절이면 아무것도 안 함.
 * 돌려주는 값: 'skip' | 'off' | 'registered' | 권한 상태('denied' 등). 실패는 던진다(부르는 쪽이 조용히 무시).
 */
export async function syncAppPush(userId) {
  currentUser = userId ?? null;
  if (!userId || !deps.native()) return 'skip';
  if (isOff(userId)) return 'off';
  let p = await permission();
  if (promptable(p) && store()?.getItem(KEY_ASKED) !== '1') p = await askPermission();
  if (p !== 'granted') return p;
  await saveToken(userId, await obtainToken());
  return 'registered';
}

/** 설정 화면 표시용: { permission, on } — on = 이 계정이 이 기기에서 켜 둠 + 권한 허용 + 이 계정으로 등록됨 */
export async function getAppPushState(userId) {
  const p = await permission();
  const d = readDevice();
  return { permission: p, on: !isOff(userId) && p === 'granted' && d?.userId === userId };
}

/** 설정 화면 [이 기기에서 알림 켜기] */
export async function enableAppPush(userId) {
  let p = await permission();
  if (p === 'denied') throw new Error(APP_PUSH_DENIED);
  if (p !== 'granted') p = await askPermission();
  if (p !== 'granted') throw new Error(p === 'denied' ? APP_PUSH_DENIED : APP_PUSH_NOT_ALLOWED);
  const token = await obtainToken();
  currentUser = userId;
  await saveToken(userId, token);
  write(offKey(userId), null);
}

/** 설정 화면 [이 기기에서 알림 끄기]: 내 계정에서 이 기기 토큰을 지운 뒤 "끔"으로 기억 (지우기에 실패하면 켜진 채로) */
export async function disableAppPush(userId) {
  const d = readDevice();
  if (d && d.userId === userId) {
    await deps.unregister(d.token);
    write(KEY_DEVICE, { ...d, userId: null });
  }
  write(offKey(userId), '1');
}

/**
 * 로그아웃 직전: 이 기기 토큰을 지금 계정에서 지운다 (로그인이 남아 있을 때만 지울 수 있다).
 * 로그아웃을 막지 않도록 실패해도 조용히, 길어도 3초까지만 기다린다. 이 기기 기록은 먼저 비운다.
 */
export async function forgetAppPush() {
  const d = readDevice();
  currentUser = null;
  if (!deps.native() || !d?.userId) return;
  write(KEY_DEVICE, { ...d, userId: null });
  const work = deps.unregister(d.token).catch(() => {});
  await Promise.race([work, new Promise((r) => setTimeout(r, 3000))]);
}

/** 탈퇴한 뒤: 토큰 줄은 계정과 함께 DB에서 지워졌다 — 이 기기 기록만 비운다 */
export function dropAppPush() {
  const d = readDevice();
  currentUser = null;
  if (d?.userId) write(KEY_DEVICE, { ...d, userId: null });
}
