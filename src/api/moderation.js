// 감독관 관리 (030, SPEC 6-18). 운영자만 쓰는 화면이고, 실제 권한 검사는 DB 함수·RLS가 한다.
import { db } from './supabase';

const COLUMNS = 'id, nickname, role, level, main_title, is_guest';

async function run(query, fallback) {
  const { data, error } = await query;
  if (error) throw new Error(`${fallback} (${error.message})`);
  return data;
}

/** LIKE 특수문자를 글자 그대로 찾게 한다 */
const likeText = (s) => s.replace(/[\\%_]/g, (c) => `\\${c}`);

/** 지금 감독관들 */
export const getModerators = () =>
  run(db().from('profiles').select(COLUMNS).eq('role', 'moderator').order('nickname', { ascending: true }), '감독관 목록을 불러오지 못했습니다.');

/** 닉네임으로 회원 찾기 (일부만 적어도 됨, 최대 10명) */
export const searchMembers = (q) =>
  run(
    db().from('profiles').select(COLUMNS).ilike('nickname', `%${likeText(q.trim())}%`).order('nickname', { ascending: true }).limit(10),
    '회원을 찾지 못했습니다.',
  );

/** 지정(on = true)·해제. 메모 필수, 그 사람에게 알림이 가고 처리 기록에 남는다 */
export async function setModerator(userId, on, note) {
  const { error } = await db().rpc('set_moderator', { p_user: userId, p_on: on, p_note: note });
  if (error) {
    const msg = error.message ?? '';
    throw new Error(/[가-힣]/.test(msg) ? msg : `처리하지 못했습니다. (${msg})`);
  }
}

/** 운영진 처리 기록 (최근 순). 운영자만 읽을 수 있다 */
export const getModerationLog = (limit = 50) =>
  run(
    db().from('moderation_log')
      .select('id, actor_nickname, actor_role, action, target_kind, target_id, target_nickname, note, created_at')
      .order('created_at', { ascending: false }).limit(limit),
    '처리 기록을 불러오지 못했습니다.',
  );
