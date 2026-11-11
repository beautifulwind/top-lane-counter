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

/**
 * 관리 메뉴의 처리 대기 건수 (033): { proposals, builds, inquiries, wiki_reports(043 오류 신고) }. 운영진만 부를 수 있고, 건수는 역할에 맞게 DB가 센다
 * (감독관은 자기가 처리할 수 있는 것만). 못 불러오면(아직 033 전이거나 네트워크) null — 메뉴는 숫자 없이 그대로 보여 준다
 */
export async function getPendingCounts() {
  try {
    const { data, error } = await db().rpc('admin_pending_counts');
    if (error || !data) return null;
    return { proposals: Number(data.proposals) || 0, builds: Number(data.builds) || 0, inquiries: Number(data.inquiries) || 0, wiki_reports: Number(data.wiki_reports) || 0 };
  } catch {
    return null;
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

const korean = (error, fallback) => {
  const msg = error.message ?? '';
  return new Error(/[가-힣]/.test(msg) ? msg : `${fallback} (${msg})`);
};

/**
 * 가입자 현황 (036, 운영자 전용): { total, members, guests, google, kakao, both, new_7d, new_7d_members }.
 * 숫자만 온다. 운영자가 아니거나 운영자 모드가 꺼져 있으면 DB가 거부한다
 */
export async function getMemberStats() {
  const { data, error } = await db().rpc('admin_member_stats');
  if (error) throw korean(error, '가입자 수를 불러오지 못했습니다.');
  return data;
}

/** 닉네임 부분 일치 검색 (036, 운영자 전용): 최대 10명, 이메일·로그인 ID는 오지 않는다 */
export async function findMembers(q) {
  const { data, error } = await db().rpc('admin_search_members', { p_query: q });
  if (error) throw korean(error, '회원을 찾지 못했습니다.');
  return data ?? [];
}

/** 선택한 회원의 가입일·가입 방식·레벨·칭호·활동 수 (036, 운영자 전용). 이메일·로그인 ID는 오지 않는다 */
export async function getMemberInfo(userId) {
  const { data, error } = await db().rpc('admin_member_info', { p_user: userId });
  if (error) throw korean(error, '회원 정보를 불러오지 못했습니다.');
  return data;
}

const withCode = (error, fallback) => Object.assign(korean(error, fallback), { code: error.code });

/**
 * 회원 목록 (042, 운영자 전용): { total, page, size, members: [{ id, nickname, role, level, main_title, is_guest, created_at }] }.
 * 최근 가입 순. query = 닉네임 일부(비우면 전체), role = 'user' | 'moderator' | 'admin' | 없음. 이메일·로그인 ID는 오지 않는다
 */
export async function getMemberList({ query = '', role = null, page = 1, size = 20 } = {}) {
  const { data, error } = await db().rpc('admin_member_list', { p_query: query.trim() || null, p_role: role || null, p_page: page, p_size: size });
  if (error) throw korean(error, '회원 목록을 불러오지 못했습니다.');
  return data;
}

/**
 * 회원 정보 페이지 (042, 운영자 전용): { info, posts, comments, edited_builds, moderation }.
 * 탈퇴했거나 없는 회원이면 code가 'P0002'인 오류 — 화면은 "탈퇴한 이용자"로 보여 준다
 */
export async function getMemberDetail(userId) {
  const { data, error } = await db().rpc('admin_member_detail', { p_user: userId, p_limit: 50 });
  if (error) throw withCode(error, '회원 정보를 불러오지 못했습니다.');
  return data;
}

/** 그 회원이 지운 글·댓글과 내용 (040, 운영자 전용, 1년 보관): { keep_days, posts, comments, doc_comments } */
export async function getDeletedWritings(userId) {
  const { data, error } = await db().rpc('admin_deleted_writings', { p_user: userId });
  if (error) throw korean(error, '지운 글·댓글을 불러오지 못했습니다.');
  return data;
}
