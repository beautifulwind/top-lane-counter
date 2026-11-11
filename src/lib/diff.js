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
 * [{ key, label, before, after, changed }] — 요약, 레벨들(합친 목록), 특이사항 순서
 */
export function docDiff(before, after) {
  const x = before ? cleanDoc(before) : null;
  const y = cleanDoc(after);
  const field = (key, label, b, a) => ({ key, label, before: b ?? '', after: a ?? '', changed: (b ?? '') !== (a ?? '') });
  const levels = [...new Set([...sortedLevels(x?.level_notes), ...sortedLevels(y.level_notes)])].sort((p, q) => p - q);
  return [
    field('summary', '한 줄 요약', x?.summary, y.summary),
    ...levels.map((lv) => field(`lv${lv}`, `${lv}레벨`, x?.level_notes[lv], y.level_notes[lv])),
    field('lane_cautions', '특이사항', x?.lane_cautions, y.lane_cautions),
  ];
}

/**
 * 빌드 한 벌(043 수정 기록의 전후 내용 = wiki_snapshot 모양) 비교. before가 null이면 처음 등록(전부 추가).
 * game = { items, runes, spells } (Data Dragon) — 아이디 대신 이름으로 보여 준다 (게임 데이터에 없으면 아이디 그대로).
 * [{ key, label, before, after, changed }] — 이름, 패치, 특성, 주문, 시작 아이템, 템트리, 선마, 그다음 글(요약·레벨·특이사항)
 */
export function buildDiff(before, after, game = {}) {
  const field = (key, label, b, a) => ({ key, label, before: b ?? '', after: a ?? '', changed: (b ?? '') !== (a ?? '') });
  const names = (ids, map) => (ids ?? []).map((id) => map?.[id]?.name ?? String(id));
  const runeText = (r) => {
    if (!r) return '';
    const rn = (id) => game.runes?.runes?.[id]?.name ?? game.runes?.shards?.[id]?.name ?? String(id ?? '');
    const pn = (id) => game.runes?.paths?.[id]?.name ?? String(id ?? '');
    return [
      `주 경로: ${pn(r.primaryPath)}`,
      `핵심 룬: ${rn(r.keystone)}`,
      `주 룬: ${(r.primary ?? []).map(rn).join(', ')}`,
      `보조 경로: ${pn(r.secondaryPath)}`,
      `보조 룬: ${(r.secondary ?? []).map(rn).join(', ')}`,
      `파편: ${(r.shards ?? []).map(rn).join(', ')}`,
    ].join('\n');
  };
  const parts = (s) => (s ? {
    name: s.name ?? '',
    patch: s.patch ?? '',
    runes: runeText(s.runes),
    spells: names(s.summoner_spells, game.spells).join('\n'),
    starting: names(s.starting_items, game.items).join('\n'),
    core: names(s.core_items, game.items).join('\n'),
    skill: s.max_skill ?? '',
  } : null);
  const x = parts(before);
  const y = parts(after) ?? {};
  const doc = (s) => s && { summary: s.summary ?? '', level_notes: s.level_notes ?? {}, lane_cautions: s.lane_cautions ?? '' };
  return [
    field('name', '빌드 이름', x?.name, y.name),
    field('patch', '패치', x?.patch, y.patch),
    field('runes', '특성', x?.runes, y.runes),
    field('spells', '소환사 주문', x?.spells, y.spells),
    field('starting', '시작 아이템', x?.starting, y.starting),
    field('core', '템트리', x?.core, y.core),
    field('skill', '선마', x?.skill, y.skill),
    ...docDiff(doc(before), doc(after) ?? { summary: '', level_notes: {}, lane_cautions: '' }),
  ];
}
