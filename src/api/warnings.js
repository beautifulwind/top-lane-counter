// 운영자 경고 (069, SPEC 6-86) 접근 계층. 화면은 이 모듈만 부른다.
// 내용(메모)은 본인과 운영자만 읽는다(RLS). 알림 문장에는 내용이 없다(휴대폰 잠금 화면에도 보이므로).
import { db } from './supabase';

/** 069 전 DB (함수가 없음) */
export function isMissingWarnings(error) {
  const text = `${error?.message ?? ''} ${error?.code ?? ''}`;
  return /could not find the function|PGRST202|42883|does not exist/i.test(text) && /warn/i.test(text);
}

export const WARNINGS_NOT_READY = '경고 기능을 준비하고 있습니다. (DB 069 실행 전)';
export const WARNING_MEMO_MAX = 500;
/** 알림 종류와 DB 알림 문장 (옛 앱은 이 문장만 그대로 보여 준다) */
export const WARNING_KIND = 'warning_received';
export const WARNING_NOTICE_TITLE = '운영자 경고를 받았습니다';

function friendly(error, fallback) {
  if (isMissingWarnings(error)) return Object.assign(new Error(WARNINGS_NOT_READY), { code: 'NOT_READY' });
  const msg = error?.message ?? '';
  const err = (text) => Object.assign(new Error(text), { code: error?.code ?? null });
  if (/[가-힣]/.test(msg)) return err(msg); // DB가 주는 한국어 사유 (운영자만·자기 자신·운영자·내용·찾지 못함)
  if (/permission denied/i.test(msg)) return err('권한이 없습니다. (운영자만 할 수 있는 작업입니다)');
  if (/failed to fetch|networkerror|load failed|network request failed|fetch failed/i.test(msg)) {
    return err(`${fallback} 인터넷 연결을 확인한 뒤 다시 해 주세요.`);
  }
  return err(`${fallback} (${msg})`);
}

async function rpc(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}

/** 아직 확인하지 않은 내 경고 (오래된 것부터) [{ id, memo, created_at }]. 069 전 DB면 빈 목록. 그 밖의 오류는 던진다 */
export async function getMyWarnings() {
  const { data, error } = await db().rpc('my_warnings');
  if (error) {
    if (isMissingWarnings(error)) return [];
    throw friendly(error, '경고를 불러오지 못했습니다.');
  }
  return Array.isArray(data) ? data : [];
}

/** 본인: [확인했습니다] → { id, acked_at } (이미 확인했으면 그대로 성공) */
export const ackWarning = (id) => rpc('ack_warning', { p_id: id }, '확인을 저장하지 못했습니다.');

/** 운영자: 경고 보내기 → { id, restriction_id } */
export const warnUser = (userId, memo) => rpc('warn_user', { p_user: userId, p_memo: memo }, '경고를 보내지 못했습니다.');

/** 운영자: 그 회원이 받은 경고 (최근 것부터) [{ id, memo, created_at, created_by, restriction_id, notice_read_at, acked_at, state }] */
export const getMemberWarnings = (userId) =>
  rpc('admin_member_warnings', { p_user: userId }, '경고 기록을 불러오지 못했습니다.');
