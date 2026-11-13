// 웹 푸시 접근 계층 (SPEC 6-24, 037).
// - 기기 알림 주소(push_subscriptions)와 종류별 설정(push_settings)은 RLS로 본인 것만 읽고 쓴다
// - 보내기는 DB 트리거 → Edge Function web-push가 한다. 화면은 켜기·끄기·설정만
// - VAPID 공개 키는 Edge Function web-push(GET)에서 받는다 (코드·환경변수에 넣지 않는다)
import { db } from './supabase';
import { keyBytes } from '../lib/push';

function friendly(error, fallback) {
  const msg = error?.message ?? '';
  if (/[가-힣]/.test(msg)) return new Error(msg);
  return new Error(`${fallback} (${msg})`);
}
// 037을 실행하기 전 DB: 표가 없다 → 꺼진 것으로 본다
const missingTable = (error) => error?.code === '42P01' || error?.code === 'PGRST205' || /push_(subscriptions|settings)/.test(error?.message ?? '');

const canPush = () => typeof navigator !== 'undefined' && 'serviceWorker' in navigator && typeof window !== 'undefined' && 'PushManager' in window;

async function registration() {
  const reg = await navigator.serviceWorker.getRegistration();
  if (!reg) throw new Error('앱이 아직 준비되지 않았습니다. 화면을 새로고침한 뒤 다시 눌러 주세요.');
  return reg;
}

/** 이 브라우저의 지금 구독 (없으면 null) */
async function browserSubscription() {
  if (!canPush()) return null;
  const reg = await navigator.serviceWorker.getRegistration();
  return (await reg?.pushManager.getSubscription()) ?? null;
}

let publicKey = null;
async function getPublicKey() {
  if (publicKey) return publicKey;
  const { data, error } = await db().functions.invoke('web-push', { method: 'GET' });
  if (error || !data?.publicKey) throw new Error('알림 설정을 불러오지 못했습니다. 잠시 뒤 다시 시도해 주세요.');
  publicKey = data.publicKey;
  return publicKey;
}

/** 이 기기에서 지금 알림을 받는가: 브라우저 구독이 있고, 그 주소가 내 계정에 저장돼 있고, 알림이 허용돼 있음 */
export async function getDevicePush() {
  const sub = await browserSubscription();
  if (!sub || Notification.permission !== 'granted') return false;
  const { data, error } = await db().from('push_subscriptions').select('id').eq('endpoint', sub.endpoint).maybeSingle();
  if (error) {
    if (missingTable(error)) return false;
    throw friendly(error, '알림 상태를 불러오지 못했습니다.');
  }
  return Boolean(data);
}

/**
 * 이 기기에서 알림 켜기: 알림 허용 묻기 → 새 구독 → 내 계정에 저장.
 * 예전 구독이 있으면(다른 계정이 쓰던 것 포함) 끊고 새로 만든다 — 남의 줄을 덮어쓰지 않는다.
 */
export async function enableDevicePush(userId) {
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') {
    throw new Error(permission === 'denied'
      ? '알림이 차단됐습니다. 휴대폰 설정(또는 브라우저의 사이트 설정)에서 탑신병자 알림을 허용한 뒤 다시 눌러 주세요.'
      : '알림 허용 창에서 [허용]을 눌러야 켤 수 있습니다.');
  }
  const key = await getPublicKey();
  const reg = await registration();
  const old = await reg.pushManager.getSubscription();
  if (old) {
    await db().from('push_subscriptions').delete().eq('endpoint', old.endpoint);
    await old.unsubscribe().catch(() => {});
  }
  const sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(key) });
  const { endpoint, keys } = sub.toJSON();
  const { error } = await db().from('push_subscriptions').insert({ user_id: userId, endpoint, p256dh: keys.p256dh, auth: keys.auth });
  if (error) {
    await sub.unsubscribe().catch(() => {});
    if (missingTable(error)) throw new Error('알림 기능이 아직 준비 중입니다. 잠시 뒤 다시 시도해 주세요.');
    throw friendly(error, '알림을 켜지 못했습니다.');
  }
}

/** 이 기기에서 알림 끄기: 내 계정의 이 기기 주소를 지우고 브라우저 구독도 끊는다 */
export async function disableDevicePush() {
  const sub = await browserSubscription();
  if (!sub) return;
  const { error } = await db().from('push_subscriptions').delete().eq('endpoint', sub.endpoint);
  await sub.unsubscribe().catch(() => {}); // 끊긴 주소는 다음에 보낼 때 410으로 지워진다 (DB에서 못 지웠어도)
  if (error && !missingTable(error)) throw friendly(error, '알림을 끄지 못했습니다.');
}

/**
 * 로그아웃 직전: 이 기기 주소를 지우고 구독을 끊는다 (다음 사람이 이 기기에서 내 알림을 받지 않게).
 * 로그아웃을 막지 않도록 실패해도 조용히, 길어도 3초까지만 기다린다.
 */
export async function forgetDevicePush() {
  if (!canPush()) return;
  const work = disableDevicePush().catch(() => {});
  await Promise.race([work, new Promise((r) => setTimeout(r, 3000))]);
}

/** 탈퇴한 뒤: DB 줄은 계정과 함께 이미 지워졌으므로 브라우저 구독만 끊는다 */
export async function dropBrowserPush() {
  const sub = await browserSubscription().catch(() => null);
  await sub?.unsubscribe().catch(() => {});
}

// follow_builds: 050 팔로우한 장인의 새 빌드 / notice: 051 공지(기본 켜짐) / new_followers: 052 장인 새 팔로워(기본 꺼짐)
export const PUSH_DEFAULTS = { staff_new: true, my_results: true, follow_builds: true, notice: true, new_followers: false };
const PUSH_KEYS = Object.keys(PUSH_DEFAULTS);
const pick = (row) => Object.fromEntries(PUSH_KEYS.filter((k) => row?.[k] != null).map((k) => [k, row[k]]));

/** 알림 종류별 켜기/끄기 (줄이 없으면 기본값 — 새 팔로워만 꺼짐). 칸 이름을 적지 않고 읽어 051·052 실행 전 DB에서도 오류가 나지 않는다 */
export async function getPushSettings(userId) {
  const { data, error } = await db().from('push_settings').select('*').eq('user_id', userId).maybeSingle();
  if (error) {
    if (missingTable(error)) return { ...PUSH_DEFAULTS };
    throw friendly(error, '알림 설정을 불러오지 못했습니다.');
  }
  return { ...PUSH_DEFAULTS, ...pick(data) };
}

/** settings = { staff_new, my_results, follow_builds, notice, new_followers } 전체. 저장된 값을 돌려준다 */
export async function savePushSettings(userId, settings) {
  const row = {
    user_id: userId, staff_new: settings.staff_new, my_results: settings.my_results,
    follow_builds: settings.follow_builds ?? true, notice: settings.notice ?? true, new_followers: settings.new_followers ?? false,
    updated_at: new Date().toISOString(),
  };
  const { error } = await db().from('push_settings').upsert(row, { onConflict: 'user_id' });
  if (error) {
    if (missingTable(error)) throw new Error('알림 기능이 아직 준비 중입니다. 잠시 뒤 다시 시도해 주세요.');
    throw friendly(error, '알림 설정을 저장하지 못했습니다.');
  }
  return pick(row);
}
