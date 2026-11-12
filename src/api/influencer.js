// 장인 인증 (046, SPEC 6-32 · 6-33). 권한(본인·운영자, 운영자 모드)과 규칙은 DB 함수가 검사한다. 화면은 이 모듈만 부른다.
import { db } from './supabase';

function friendly(error, fallback) {
  const msg = error?.message ?? '';
  const err = (text) => Object.assign(new Error(text), { code: error?.code ?? null });
  if (/permission denied/i.test(msg)) return err('권한이 없습니다. (로그인이 필요하거나 운영자만 할 수 있는 작업입니다)');
  if (/[가-힣]/.test(msg)) return err(msg);
  return err(`${fallback} (${msg})`);
}

async function rpc(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}

// ---------------- 신청자 ----------------

/**
 * 내 장인 상태: { influencer, influencer_at, nickname_state, nickname_reset_at, is_guest, next_apply_at,
 *   application: 마지막 신청 { id, kind, nickname, old_nickname, channel_url, official_email, riot_id, opgg_url, status,
 *   created_at, expires_at, ended_at, review_note, retry_now, nickname_reverted, revoked_at, revoke_note } | null }
 */
export const getMyInfluencerStatus = () => rpc('my_influencer_status', {}, '장인 인증 상태를 불러오지 못했습니다.');

/** 신청. v = { kind, nickname, channelUrl, email, riotId, opggUrl } — 유형에 맞는 칸만 보낸다. 돌려주는 값: 신청 번호 */
export function applyInfluencer(v) {
  const mail = v.kind !== 'grandmaster';
  const text = (s) => String(s ?? '').trim() || null;
  return rpc('apply_influencer', {
    p_kind: v.kind,
    p_nickname: String(v.nickname ?? '').trim(),
    p_channel_url: mail ? text(v.channelUrl) : null,
    p_email: mail ? text(v.email) : null,
    p_riot_id: mail ? null : text(v.riotId),
    p_opgg_url: mail ? null : text(v.opggUrl),
  }, '신청을 보내지 못했습니다.');
}

/** 내 신청 취소 (처리 전만). 돌려주는 값: 되돌린 닉네임(안 되돌렸으면 null) */
export const cancelInfluencer = (id) => rpc('cancel_influencer_application', { p_id: id }, '신청을 취소하지 못했습니다.');

// ---------------- 운영자 (운영자 모드를 끄면 DB가 거부) ----------------

/**
 * 신청 목록. status: 'pending'(처리 전, 오래된 순) | 'done'(끝난 것, 최근 순)
 * 돌려주는 값: { total, page, size, items: [{ id, kind, kind_label, nickname, old_nickname, channel_url, official_email, riot_id, opgg_url,
 *   status, created_at, expires_at, extended_count, ended_at, review_note, retry_now, nickname_reverted, revoked_at, revoke_note,
 *   reviewer, user: 사람 | null, overlap: { id, nickname, role } | null, recent_rejections }] }
 */
export const getInfluencerApplications = (status = 'pending', page = 1, size = 20) =>
  rpc('admin_influencer_applications', { p_status: status, p_page: page, p_size: size }, '장인 신청을 불러오지 못했습니다.');

/** 끝난 신청 전부 (승인·반려·만료 걸러 보기용, 50개씩 이어 받음 — 최대 1000개) */
export async function getAllDoneApplications() {
  const items = [];
  for (let page = 1; page <= 20; page += 1) {
    const r = await getInfluencerApplications('done', page, 50);
    items.push(...(r?.items ?? []));
    if (items.length >= (r?.total ?? 0) || (r?.items ?? []).length === 0) break;
  }
  return items;
}

export const approveInfluencer = (id, note) => rpc('approve_influencer', { p_id: id, p_note: note }, '승인하지 못했습니다.');

/** 반려. revertNickname = 닉네임도 되돌리기, retryNow = 바로 다시 신청 허용 */
export const rejectInfluencer = (id, note, { revertNickname = false, retryNow = false } = {}) =>
  rpc('reject_influencer', { p_id: id, p_note: note, p_revert_nickname: revertNickname, p_retry_now: retryNow }, '반려하지 못했습니다.');

/** 만료일 7일 늘리기. 돌려주는 값: 새 만료 시각 */
export const extendInfluencer = (id) => rpc('extend_influencer_application', { p_id: id }, '만료일을 늘리지 못했습니다.');

/**
 * 장인 직접 지정 (049, SPEC 6-35): 신청·확인 절차 없이 정식 회원을 바로 장인으로. kind = 'creator' | 'pro' | 'grandmaster', note 필수.
 * 운영자만(감독관·운영자 모드 꺼짐 거부). 게스트·이미 장인·신청 처리 전인 회원은 DB가 거부. 닉네임은 그대로. 돌려주는 값: 지정 줄 번호
 */
export const grantInfluencer = (userId, kind, note) =>
  rpc('grant_influencer', { p_user: userId, p_kind: kind, p_note: note }, '장인으로 지정하지 못했습니다.');

/** 인증 해제 ("장인" 표시만 없앰, 닉네임은 그대로) */
export const revokeInfluencer = (userId, note) => rpc('revoke_influencer', { p_user: userId, p_note: note }, '인증을 해제하지 못했습니다.');

/** 운영자가 회원 닉네임 바꾸기 (장인은 직접 못 바꾸므로) */
export const adminSetNickname = (userId, nickname, note) =>
  rpc('admin_set_nickname', { p_user: userId, p_nickname: String(nickname ?? '').trim(), p_note: note }, '닉네임을 바꾸지 못했습니다.');
