// 운영자 화면의 "기존 내용 ↔ 바뀐 내용" 비교
import { cleanDoc, sortedLevels } from './docContent';

/** 줄 단위 비교 (LCS). [{ type: 'same' | 'del' | 'add', text }] */
export function lineDiff(before, after) {
  const a = before ? before.split('\n') : [];
  const b = after ? after.split('\n') : [];
  const n = a.length;
  const m = b.length;
  // lcs[i][j] = a[i..], b[j..]의 최장 공통 부분 길이
  const lcs = Array.from({ length: n + 1 }, () => new Array(m + 1).fill(0));
  for (let i = n - 1; i >= 0; i -= 1) {
    for (let j = m - 1; j >= 0; j -= 1) {
      lcs[i][j] = a[i] === b[j] ? lcs[i + 1][j + 1] + 1 : Math.max(lcs[i + 1][j], lcs[i][j + 1]);
    }
  }
  const out = [];
  let i = 0;
  let j = 0;
  while (i < n && j < m) {
    if (a[i] === b[j]) { out.push({ type: 'same', text: a[i] }); i += 1; j += 1; }
    else if (lcs[i + 1][j] >= lcs[i][j + 1]) { out.push({ type: 'del', text: a[i] }); i += 1; }
    else { out.push({ type: 'add', text: b[j] }); j += 1; }
  }
  while (i < n) out.push({ type: 'del', text: a[i++] });
  while (j < m) out.push({ type: 'add', text: b[j++] });
  return out;
}

/**
 * 문서 전체 비교. before가 null이면 새 문서(전부 추가).
 * [{ key, label, before, after, changed }] — 요약, 레벨들(합친 목록), 라인전 주의사항 순서
 */
export function docDiff(before, after) {
  const x = before ? cleanDoc(before) : null;
  const y = cleanDoc(after);
  const field = (key, label, b, a) => ({ key, label, before: b ?? '', after: a ?? '', changed: (b ?? '') !== (a ?? '') });
  const levels = [...new Set([...sortedLevels(x?.level_notes), ...sortedLevels(y.level_notes)])].sort((p, q) => p - q);
  return [
    field('summary', '한 줄 요약', x?.summary, y.summary),
    ...levels.map((lv) => field(`lv${lv}`, `${lv}레벨`, x?.level_notes[lv], y.level_notes[lv])),
    field('lane_cautions', '라인전 주의사항', x?.lane_cautions, y.lane_cautions),
  ];
}
