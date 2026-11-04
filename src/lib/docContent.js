// 매치업 문서 내용 {summary, level_notes, lane_cautions} 규칙. lane_cautions의 화면 이름은 "특이사항" (011).
// DB(011_special_notes_label.sql의 clean_doc_content)와 같은 규칙 — 화면에서 먼저 알려 주고, DB가 한 번 더 막는다.
export const REQUIRED_LEVELS = [1, 2, 3, 6];  // 9·11은 010부터 필수 아님 (원하면 추가 레벨로)
export const ALL_LEVELS = Array.from({ length: 18 }, (_, i) => i + 1);
export const LIMITS = { summary: 100, level: 1000, lane_cautions: 3000 };

/** 앞뒤 공백 정리, 빈 추가 레벨 제거, 키를 숫자 문자열로 */
export function cleanDoc(c) {
  const notes = {};
  for (const [lv, text] of Object.entries(c?.level_notes ?? {})) {
    const t = String(text ?? '').trim();
    if (t) notes[String(Number(lv))] = t;
  }
  return {
    summary: String(c?.summary ?? '').trim(),
    level_notes: notes,
    lane_cautions: String(c?.lane_cautions ?? '').trim(),
  };
}

/** 문제가 있으면 안내 문구, 없으면 null */
export function docProblem(c) {
  const d = cleanDoc(c);
  if (!d.summary) return '한 줄 요약을 적어 주세요.';
  if ([...d.summary].length > LIMITS.summary) return `한 줄 요약은 ${LIMITS.summary}자 이하로 적어 주세요.`;
  for (const lv of REQUIRED_LEVELS) if (!d.level_notes[lv]) return `${lv}레벨 딜교법은 꼭 적어야 합니다.`;
  for (const [lv, t] of Object.entries(d.level_notes)) {
    if (!ALL_LEVELS.includes(Number(lv))) return `레벨은 1~18 사이 숫자만 쓸 수 있습니다. (${lv})`;
    if ([...t].length > LIMITS.level) return `${lv}레벨 내용은 ${LIMITS.level}자 이하로 적어 주세요.`;
  }
  if ([...d.lane_cautions].length > LIMITS.lane_cautions) return `특이사항은 ${LIMITS.lane_cautions}자 이하로 적어 주세요.`;
  return null;
}

/** 정리한 뒤 두 문서가 같은가 */
export function sameDoc(a, b) {
  const x = cleanDoc(a);
  const y = cleanDoc(b);
  if (x.summary !== y.summary || x.lane_cautions !== y.lane_cautions) return false;
  const kx = Object.keys(x.level_notes);
  return kx.length === Object.keys(y.level_notes).length && kx.every((k) => x.level_notes[k] === y.level_notes[k]);
}

export const sortedLevels = (notes) => Object.keys(notes ?? {}).map(Number).sort((a, b) => a - b);
