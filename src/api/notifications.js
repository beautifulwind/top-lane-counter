// 알림 접근 계층 (SPEC 6-17, 027). 알림은 DB 함수만 만든다 — 화면은 읽기와 읽음 처리만.
// /notifications를 열면 그 화면 맨 위 알림까지 한 번에 읽음 처리 → ☰·[알림]의 빨간 점이 꺼진다.
import { db } from './supabase';

function friendly(error, fallback) {
  const msg = error?.message ?? '';
  if (/[가-힣]/.test(msg)) return new Error(msg);
  return new Error(`${fallback} (${msg})`);
}

const NOTIFICATIONS_CHANGED = 'tlc:notifications-changed';
/** 읽음 처리 등으로 알림 개수가 바뀌었을 때 빨간 점이 다시 세도록 */
export function onNotificationsChanged(cb) {
  window.addEventListener(NOTIFICATIONS_CHANGED, cb);
  return () => window.removeEventListener(NOTIFICATIONS_CHANGED, cb);
}

/** 안 읽은 내 알림 개수 (빨간 점·마이페이지 [알림 보기]). RLS가 내 것만 돌려준다 */
export async function getUnreadCount(userId) {
  const { data, error } = await db().from('notifications').select('id').eq('user_id', userId).is('read_at', null);
  if (error) throw friendly(error, '알림을 불러오지 못했습니다.');
  return data.length;
}

export const NOTIFICATIONS_PAGE = 20;
const FIELDS = [
  'id, kind, message, created_at, read_at, proposal_id, build_id, post_id, counter_id',
  'counter:counters!notifications_counter_id_fkey(target_champion, counter_champion, status)',
  'proposal:edit_proposals!notifications_proposal_id_fkey(type, target_champion, counter_champion)',
  'build:builds!notifications_build_id_fkey(counter:counters!builds_counter_id_fkey(target_champion, counter_champion))',
  'post:posts!notifications_post_id_fkey(title)',
].join(', ');

/**
 * 내 알림 최신순(번호 큰 순) NOTIFICATIONS_PAGE개. before = 지금 화면 맨 아래 알림 번호 (더 보기).
 * 돌려주는 값: { rows, more } — more = 더 오래된 알림이 남았는가
 */
export async function getNotifications(userId, before = null) {
  let q = db().from('notifications').select(FIELDS).eq('user_id', userId);
  if (before != null) q = q.lt('id', before);
  const { data, error } = await q.order('id', { ascending: false }).limit(NOTIFICATIONS_PAGE + 1);
  if (error) throw friendly(error, '알림을 불러오지 못했습니다.');
  return { rows: data.slice(0, NOTIFICATIONS_PAGE), more: data.length > NOTIFICATIONS_PAGE };
}

/** upto 번호까지 내 안 읽은 알림을 모두 읽음 처리. 처리한 시각(read_at에 들어간 값)을 돌려준다 */
export async function markAllNotificationsRead(upto) {
  const { data, error } = await db().rpc('mark_all_notifications_read', { p_upto: upto });
  if (error) throw friendly(error, '알림을 확인 처리하지 못했습니다.');
  window.dispatchEvent(new Event(NOTIFICATIONS_CHANGED));
  return data;
}
