// 활동 제한 (068, SPEC 6-85) 접근 계층. 화면은 이 모듈만 부른다.
// 막는 일은 DB가 한다(쓰기 함수 맨 앞 검사 + 표 트리거). 화면은 띠·흐린 버튼·운영자 칸만 그린다.
import { db } from './supabase';

/** 068 전 DB (함수가 없음) */
export function isMissingRestrictions(error) {
  const text = `${error?.message ?? ''} ${error?.code ?? ''}`;
  return /could not find the function|PGRST202|42883|does not exist/i.test(text) && /restrict/i.test(text);
}

export const RESTRICTIONS_NOT_READY = '활동 제한 기능을 준비하고 있습니다. (DB 068 실행 전)';
/** 제한 중 쓰기를 시도했을 때 DB가 주는 오류 코드 */
export const RESTRICTED_CODE = 'TL423';
/** 운영자가 고르는 기간 (일) — 직접 입력은 1~365 */
export const RESTRICT_DAY_PRESETS = [1, 3, 7, 30];
export const RESTRICT_DAYS_MIN = 1;
export const RESTRICT_DAYS_MAX = 365;
export const RESTRICT_REASON_MAX = 500;

function friendly(error, fallback) {
  if (isMissingRestrictions(error)) return Object.assign(new Error(RESTRICTIONS_NOT_READY), { code: 'NOT_READY' });
  const msg = error?.message ?? '';
  const err = (text) => Object.assign(new Error(text), { code: error?.code ?? null });
  if (/[가-힣]/.test(msg)) return err(msg); // DB가 주는 한국어 사유 (운영자만·자기 자신·감독관·기간·사유·이미 제한 중)
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

/**
 * 내 제한 (띠용). { ready, restriction } — restriction = { id, reason, ends_at, message } 또는 null.
 * 068 전 DB면 ready: false (띠 없음, 「이의 제기」 분류도 숨김). 그 밖의 오류는 던진다(호출하는 쪽이 조용히 넘김).
 */
export async function getMyRestriction() {
  const { data, error } = await db().rpc('my_restriction');
  if (error) {
    if (isMissingRestrictions(error)) return { ready: false, restriction: null };
    throw friendly(error, '활동 제한 상태를 불러오지 못했습니다.');
  }
  return { ready: true, restriction: data ?? null };
}

/** 운영자: 제한 걸기 → { id, ends_at } */
export const restrictUser = (userId, days, reason) =>
  rpc('restrict_user', { p_user: userId, p_days: days, p_reason: reason }, '활동 제한을 걸지 못했습니다.');

/** 운영자: 제한 풀기 (메모는 선택) */
export const liftRestriction = (id, note) =>
  rpc('lift_restriction', { p_id: id, p_note: note || null }, '활동 제한을 풀지 못했습니다.');

/** 운영자: 그 회원의 제한 기록 (최근 것부터) [{ id, reason, days, starts_at, ends_at, created_by, lifted_at, lifted_by, lift_note, state }] */
export const getMemberRestrictions = (userId) =>
  rpc('admin_member_restrictions', { p_user: userId }, '활동 제한 기록을 불러오지 못했습니다.');
