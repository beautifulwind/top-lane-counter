// 상대법·빌드 오류 신고 (043, SPEC 6-30). 권한(정식 회원만·운영진만)과 남발 막기는 DB 함수가 검사한다.
import { db } from './supabase';

// 신고 이유 (보이는 순서). DB 검사(043 report_wiki·wiki_reports.reason)와 같은 키
export const WIKI_REPORT_REASONS = {
  wrong: '내용이 틀림',
  outdated: '패치가 지남',
  vandal: '장난·훼손',
  duplicate: '같은 빌드가 또 있음',
  other: '기타',
};
export const WIKI_REPORT_HINTS = {
  wrong: '룬·아이템·스킬·딜교법 등이 사실과 다름',
  outdated: '지금 패치와 맞지 않음',
  vandal: '장난으로 고쳤거나 내용을 지움',
  duplicate: '이 상대법에 거의 같은 빌드가 또 있음',
};
/** 상대법 전체에 대한 신고에서 고를 수 있는 이유 (패치·중복은 빌드에만) */
export const MATCHUP_REPORT_REASONS = ['wrong', 'vandal', 'other'];
export const WIKI_REPORT_MEMO_MAX = 200;

function friendly(error, fallback) {
  const msg = error?.message ?? '';
  if (/permission denied/i.test(msg)) return new Error('권한이 없습니다. 로그인했는지 확인해 주세요.');
  if (/[가-힣]/.test(msg)) return new Error(msg);
  return new Error(`${fallback} (${msg})`);
}

async function rpc(name, args, fallback) {
  const { data, error } = await db().rpc(name, args);
  if (error) throw friendly(error, fallback);
  return data;
}

/** 오류 신고 보내기 (빌드를 비우면 상대법 전체). 돌려주는 값: 신고 번호 */
export const reportWiki = ({ counterId, buildId = null, reason, memo = '' }) =>
  rpc('report_wiki', { p_counter: counterId, p_build: buildId, p_reason: reason, p_memo: memo.trim() || null }, '신고를 보내지 못했습니다.');

/**
 * 운영진 목록. status: 'open'(처리 전, 오래된 순) | 'handled'(처리됨·기각, 최근 처리 순)
 * 돌려주는 값: { total, page, size, reports: [{ id, counter_id, target_champion, counter_champion, counter_status, build_id, build_seq,
 *   build_name, build_status, reason, memo, status, created_at, handled_at, handled_note, handler, reporter(운영자에게만), mine, same_open }] }
 */
export const getWikiReports = (status = 'open', page = 1, size = 20) =>
  rpc('staff_wiki_reports', { p_status: status, p_page: page, p_size: size }, '오류 신고를 불러오지 못했습니다.');

/** 처리: status 'resolved'(처리됨) | 'dismissed'(기각), 메모 필수. sameTarget = 같은 대상의 처리 전 신고도 함께. 돌려주는 값: 처리한 수 */
export const handleWikiReport = (id, status, note, sameTarget = false) =>
  rpc('handle_wiki_report', { p_id: id, p_status: status, p_note: note, p_same_target: sameTarget }, '신고를 처리하지 못했습니다.');
