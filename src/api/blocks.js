// 사용자 차단 접근 계층 (061, SPEC 6-67). 차단 목록은 본인 것만 읽고·넣고·지운다 (RLS).
// 061을 실행하기 전 DB(차단 표가 없음)에서도 앱이 죽지 않게: 목록은 빈 목록 + available false, 차단·해제만 "준비 중" 오류.
import { db } from './supabase';

const PERSON = 'nickname, role, level, main_title, is_guest, influencer, nickname_state';
export const BLOCKS_NOT_READY = '차단 기능을 준비하고 있습니다. 잠시 뒤 다시 시도해 주세요.';

/** 차단 표가 아직 없다는 오류인가 (Postgres 42P01, PostgREST PGRST205·PGRST200 — 표·관계를 못 찾음) */
export function isMissingBlocks(error) {
  if (!error) return false;
  if (['42P01', 'PGRST205', 'PGRST200'].includes(error.code)) return true;
  return /user_blocks/.test(error.message ?? '') && /does not exist|schema cache|could not find/i.test(error.message ?? '');
}

function friendly(error, fallback) {
  if (isMissingBlocks(error)) return new Error(BLOCKS_NOT_READY);
  const msg = error?.message ?? '';
  if (/[가-힣]/.test(msg)) return new Error(msg);
  if (error?.code === '23514' || /user_blocks_not_self/.test(msg)) return new Error('자기 자신은 차단할 수 없습니다.');
  if (error?.code === '42501' || /row-level security|permission denied/i.test(msg)) return new Error('로그인한 뒤 차단할 수 있습니다.');
  return new Error(`${fallback} (${msg})`);
}

/**
 * 내 차단 목록 (최근에 차단한 순). 돌려주는 값: { available, rows: [{ blocked_id, created_at, blocked: { nickname, … } }] }
 * 차단 표가 아직 없으면 { available: false, rows: [] } — 화면은 아무것도 숨기지 않고 그대로 동작한다
 */
export async function getMyBlocks(userId) {
  const { data, error } = await db().from('user_blocks')
    .select(`blocked_id, created_at, blocked:profiles!user_blocks_blocked_id_fkey(${PERSON})`)
    .eq('blocker_id', userId).order('created_at', { ascending: false });
  if (error) {
    if (isMissingBlocks(error)) return { available: false, rows: [] };
    throw friendly(error, '차단 목록을 불러오지 못했습니다.');
  }
  return { available: true, rows: data ?? [] };
}

/** 차단. 이미 차단한 사람이면 그대로 성공 (기본 키 중복) */
export async function blockUser(userId, targetId) {
  const { error } = await db().from('user_blocks').insert({ blocker_id: userId, blocked_id: targetId });
  if (error && error.code !== '23505') throw friendly(error, '차단하지 못했습니다.');
}

/** 차단 해제 */
export async function unblockUser(userId, targetId) {
  const { error } = await db().from('user_blocks').delete().eq('blocker_id', userId).eq('blocked_id', targetId);
  if (error) throw friendly(error, '차단을 해제하지 못했습니다.');
}
