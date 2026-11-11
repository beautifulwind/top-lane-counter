// 상대법의 빌드 = 공략 한 벌 (038): 빌드 이름(선택) + 한 줄 요약 + 룬·주문·아이템·선마 + 레벨별 딜교법 + 특이사항.
// DB clean_wiki_build(= clean_build + clean_doc_content + 이름)와 같은 규칙을 화면에서 먼저 알려 준다. DB가 한 번 더 막는다.
import { buildProblem, buildToForm, emptyBuild, sameBuild, toRow } from './buildContent';
import { REQUIRED_LEVELS, cleanDoc, docProblem, sameDoc } from './docContent';

/** 빌드 이름 최대 글자 수 (DB builds_name_len: 1~20자, 비우면 "빌드 N") */
export const BUILD_NAME_MAX = 20;

const docForm = (b) => {
  const notes = {};
  for (const [lv, t] of Object.entries(b?.level_notes ?? {})) notes[Number(lv)] = t ?? '';
  for (const lv of REQUIRED_LEVELS) notes[lv] ??= '';
  return { summary: b?.summary ?? '', level_notes: notes, lane_cautions: b?.lane_cautions ?? '' };
};

/** 빈 빌드 (새 상대법·새 빌드 시작값) */
export const emptyWikiBuild = () => ({ ...emptyBuild(), name: '', ...docForm(null) });

/** 저장된 빌드 → 입력 값 ([빌드 수정], [지금 빌드 내용 가져오기]) */
export const wikiBuildToForm = (b) => ({ ...buildToForm(b), name: b?.name ?? '', ...docForm(b) });

/** 고쳐야 할 점 (없으면 null). 화면 순서대로: 이름 → 한 줄 요약 → 빌드 → 딜교법·특이사항 */
export function wikiBuildProblem(v, game) {
  const name = String(v.name ?? '').trim();
  if ([...name].length > BUILD_NAME_MAX) return `빌드 이름은 ${BUILD_NAME_MAX}자 이하로 적어 주세요.`;
  const doc = docProblem(v);
  if (doc === '한 줄 요약을 적어 주세요.' || doc?.startsWith('한 줄 요약은')) return doc;
  return buildProblem(v, game) ?? doc;
}

/** DB에 보내는 모양 (create_matchup·create_build·edit_build의 p_build) */
export function toWikiPayload(v, patch) {
  const name = String(v.name ?? '').trim();
  return { ...toRow(v), patch, name: name || null, ...cleanDoc(v) };
}

/** 이름·빌드·글이 모두 같은가 ([빌드 수정]에서 바뀐 것이 없으면 막는다) */
export const sameWikiBuild = (a, b) =>
  String(a.name ?? '').trim() === String(b.name ?? '').trim() && sameBuild(a, b) && sameDoc(a, b);

/** 탭·제목에 보일 빌드 이름: 이름이 없으면 "빌드 N" (N = 상대법 안 번호) */
export const buildLabel = (b, index = 0) => b.name || `빌드 ${b.seq ?? index + 1}`;
