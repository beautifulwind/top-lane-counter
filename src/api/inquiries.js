// 문의하기 접근 계층 (SPEC 6-19, 032). 화면은 이 모듈만 부른다.
// 보내기·답변·분류 옮기기·지우기는 모두 DB 함수로만 — 하루 3건·글자 수·권한(감독관은 "계정·탈퇴" 불가)은 DB가 막는다.
// 읽기는 RLS가 정한다 (본인 것 / 운영자 전부 / 감독관은 "계정·탈퇴" 빼고).
import { db } from './supabase';

/** 분류 (보이는 순서). DB 검사(032)와 같은 키 */
export const INQUIRY_CATEGORIES = {
  bug: '오류 신고',
  idea: '건의',
  account: '계정·탈퇴',
  other: '기타',
};
// 글자 수 (화면 안내용 — 실제 검사는 DB, 숫자는 xp_rules: inquiry_min·inquiry_max·inquiry_answer_max·inquiry_daily_max)
export const INQUIRY_MIN = 5;
export const INQUIRY_MAX = 1000;
export const INQUIRY_ANSWER_MAX = 2000;
export const INQUIRY_DAILY_MAX = 3;

const FIELDS = 'id, user_id, category, body, created_at, answer, answered_at';
const STAFF_FIELDS = `${FIELDS}, user:profiles!inquiries_user_id_fkey(nickname, role, level, main_title, is_guest)`;
const STAFF_LIMIT = 200;

function friendly(error, fallback) {
  const msg = error?.message ?? '';
  if (/permission denied|row-level security/i.test(msg)) return new Error('권한이 없습니다. 로그인했는지 확인해 주세요.');
  if (/[가-힣]/.test(msg)) return Object.assign(new Error(msg), { code: error.code });
  return new Error(`${fallback} (${msg})`);
}

async function run(query, fallback) {
  const { data, error } = await query;
  if (error) throw friendly(error, fallback);
  return data;
}

async function rpc(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}

/** 내 문의 (최신순). RLS가 내 것만 돌려준다 */
export const getMyInquiries = (userId) =>
  run(db().from('inquiries').select(FIELDS).eq('user_id', userId).order('id', { ascending: false }), '문의 내역을 불러오지 못했습니다.');

/** 문의 보내기 (분류 + 내용). 새 문의 번호를 돌려준다 */
export const createInquiry = (category, body) =>
  rpc('create_inquiry', { p_category: category, p_body: body }, '문의를 보내지 못했습니다.');

/** 내 문의 지우기 (답변도 함께 사라진다) */
export const deleteMyInquiry = (id) => rpc('delete_my_inquiry', { p_id: id }, '문의를 지우지 못했습니다.');

/**
 * 운영진이 볼 수 있는 문의 (최신순, 최근 STAFF_LIMIT건). 내가 보낸 것은 뺀다.
 * 감독관은 RLS가 "계정·탈퇴"를 빼고 돌려준다. 돌려주는 값: { waiting, answered }
 */
export async function getStaffInquiries(userId) {
  const rows = await run(
    db().from('inquiries').select(STAFF_FIELDS).order('id', { ascending: false }).limit(STAFF_LIMIT),
    '문의 목록을 불러오지 못했습니다.',
  );
  const others = rows.filter((r) => r.user_id !== userId);
  return { waiting: others.filter((r) => r.answer == null), answered: others.filter((r) => r.answer != null) };
}

/** 답변 쓰기 (운영진). 이미 다른 분이 답했으면 오류 코드 TL409 (isAlreadyHandled) */
export const answerInquiry = (id, answer) => rpc('answer_inquiry', { p_id: id, p_answer: answer }, '답변을 보내지 못했습니다.');

/** 분류 옮기기 (운영자만) */
export const setInquiryCategory = (id, category) =>
  rpc('set_inquiry_category', { p_id: id, p_category: category }, '분류를 바꾸지 못했습니다.');
