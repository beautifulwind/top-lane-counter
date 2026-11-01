// 빌드 내용 규칙. DB 검사 트리거(008_builds.sql check_new_build)와 같은 규칙을 화면에서 먼저 확인한다.
import { SHARD_ROWS } from '../api/ddragon';

export const SKILLS = ['Q', 'W', 'E'];
export const SKILL_ORDERS = [
  ['Q', 'W', 'E'], ['Q', 'E', 'W'], ['W', 'Q', 'E'], ['W', 'E', 'Q'], ['E', 'Q', 'W'], ['E', 'W', 'Q'],
];
export const ITEM_LIMITS = { starting: [1, 4], core: [3, 6] };

/** 빈 빌드 (등록 화면 시작값) */
export function emptyBuild() {
  return {
    runes: { primaryPath: null, keystone: null, primary: [null, null, null], secondaryPath: null, secondary: [], shards: [null, null, null] },
    summoner_spells: [],
    starting_items: [],
    core_items: [],
    skill_order: null,
    early_skills: [null, null, null],
  };
}

/** 저장된 빌드 → 등록 화면 값 ([이 빌드로 다시 쓰기]) */
export function buildToForm(b) {
  const r = b.runes ?? {};
  return {
    runes: {
      primaryPath: r.primaryPath ?? null,
      keystone: r.keystone ?? null,
      primary: [0, 1, 2].map((i) => r.primary?.[i] ?? null),
      secondaryPath: r.secondaryPath ?? null,
      secondary: [...(r.secondary ?? [])],
      shards: [0, 1, 2].map((i) => r.shards?.[i] ?? null),
    },
    summoner_spells: [...(b.summoner_spells ?? [])],
    starting_items: [...(b.starting_items ?? [])],
    core_items: [...(b.core_items ?? [])],
    skill_order: b.skill_order ? [...b.skill_order] : null,
    early_skills: [0, 1, 2].map((i) => b.early_skills?.[i] ?? null),
  };
}

const sameSet = (a, b) => a.length === b.length && [...a].sort().join() === [...b].sort().join();

/**
 * 고쳐야 할 점 (없으면 null). game = { items, runes, spells } (Data Dragon)를 주면 실제로 있는 값인지,
 * 룬이 경로·줄에 맞는지도 본다.
 */
export function buildProblem(b, game) {
  const r = b.runes;
  if (!r.primaryPath) return '주 경로를 골라 주세요.';
  if (!r.keystone) return '핵심 룬을 골라 주세요.';
  if (r.primary.some((x) => !x)) return '주 경로 룬을 줄마다 하나씩 골라 주세요.';
  if (!r.secondaryPath) return '보조 경로를 골라 주세요.';
  if (r.secondaryPath === r.primaryPath) return '보조 경로는 주 경로와 달라야 해요.';
  if (r.secondary.length !== 2) return '보조 룬을 2개 골라 주세요.';
  if (r.shards.some((x, i) => !SHARD_ROWS[i].includes(x))) return '능력치 파편을 줄마다 하나씩 골라 주세요.';
  const all = [r.keystone, ...r.primary, ...r.secondary];
  if (new Set(all).size !== all.length) return '같은 룬을 두 번 고를 수 없어요.';
  if (b.summoner_spells.length !== 2) return '소환사 주문을 2개 골라 주세요.';
  if (b.summoner_spells[0] === b.summoner_spells[1]) return '같은 소환사 주문을 두 번 고를 수 없어요.';
  const [sMin, sMax] = ITEM_LIMITS.starting;
  if (b.starting_items.length < sMin || b.starting_items.length > sMax) return `시작 아이템은 ${sMin}~${sMax}개 골라 주세요.`;
  const [cMin, cMax] = ITEM_LIMITS.core;
  if (b.core_items.length < cMin || b.core_items.length > cMax) return `핵심 템트리는 ${cMin}~${cMax}개 골라 주세요.`;
  if (new Set(b.core_items).size !== b.core_items.length) return '핵심 템트리에 같은 아이템이 두 번 들어 있어요.';
  if (!b.skill_order || !sameSet(b.skill_order, SKILLS)) return '스킬 선마 순서를 골라 주세요.';
  if (b.early_skills.some((x) => !SKILLS.includes(x))) return '1·2·3레벨에 찍는 스킬을 골라 주세요.';
  if (game) {
    const unknown = unknownParts(b, game);
    if (unknown) return unknown;
    const wrong = runeLayoutProblem(r, game.runes);
    if (wrong) return wrong;
  }
  return null;
}

/** Data Dragon에 없는 값 (없으면 null) */
export function unknownParts(b, { items, runes, spells }) {
  const r = b.runes;
  if (!runes.paths[r.primaryPath] || !runes.paths[r.secondaryPath]) return '게임 데이터에 없는 룬 경로가 있어요.';
  if ([r.keystone, ...r.primary, ...r.secondary].some((id) => !runes.runes[id])) return '게임 데이터에 없는 룬이 있어요.';
  if (b.summoner_spells.some((id) => !spells[id])) return '게임 데이터에 없는 소환사 주문이 있어요.';
  if ([...b.starting_items, ...b.core_items].some((id) => !items[id])) return '게임 데이터에 없는 아이템이 있어요.';
  return null;
}

/** 룬이 고른 경로·줄과 맞는지 (없으면 null) */
export function runeLayoutProblem(r, runes) {
  const rune = (id) => runes.runes[id];
  if (rune(r.keystone)?.path !== r.primaryPath || rune(r.keystone)?.row !== 0) return '핵심 룬이 주 경로의 것이 아니에요.';
  if (r.primary.some((id, i) => rune(id)?.path !== r.primaryPath || rune(id)?.row !== i + 1)) {
    return '주 경로 룬이 줄에 맞지 않아요.';
  }
  const rows = r.secondary.map((id) => rune(id)?.row);
  if (r.secondary.some((id) => rune(id)?.path !== r.secondaryPath) || rows.some((x) => !(x >= 1)) || rows[0] === rows[1]) {
    return '보조 룬은 보조 경로의 서로 다른 줄에서 골라야 해요.';
  }
  return null;
}

/** DB에 넣는 모양 */
export function toRow(b) {
  return {
    runes: {
      primaryPath: b.runes.primaryPath, keystone: b.runes.keystone, primary: [...b.runes.primary],
      secondaryPath: b.runes.secondaryPath, secondary: [...b.runes.secondary], shards: [...b.runes.shards],
    },
    summoner_spells: [...b.summoner_spells],
    starting_items: [...b.starting_items],
    core_items: [...b.core_items],
    skill_order: [...b.skill_order],
    early_skills: [...b.early_skills],
  };
}

/** 같은 빌드인지 비교하는 값 (패치·작성자 제외, DB build_signature와 같은 기준) */
export function buildSignature(b) {
  return JSON.stringify([
    b.runes.primaryPath, b.runes.keystone, b.runes.primary, b.runes.secondaryPath, b.runes.secondary, b.runes.shards,
    b.summoner_spells, b.starting_items, b.core_items, b.skill_order, b.early_skills,
  ]);
}

/** 패치 앞 두 자리 ("16.21.1" → "16.21") */
export const patchMinor = (patch) => String(patch ?? '').split('.').slice(0, 2).join('.');

/** 구버전 빌드인가: 앞 두 자리만 비교 (16.21.1과 16.21.3은 같은 패치) */
export const isOutdated = (patch, latest) => !!latest && patchMinor(patch) !== patchMinor(latest);

/** 정렬: 점수(따봉 − 비추) 높은 순 → 투표 수 많은 순 → 최신순 */
export function compareBuilds(a, b) {
  return (b.up - b.down) - (a.up - a.down) || (b.up + b.down) - (a.up + a.down) || String(b.created_at).localeCompare(String(a.created_at));
}

/**
 * 운영자가 승인 전에 알아야 할 것.
 * game = { items, runes, spells, latest }, approved = 같은 카운터의 공개 빌드들
 */
export function buildReviewFlags(build, game, approved = []) {
  const hiddenCounter = build.counter?.status === 'hidden';
  const unknown = unknownParts(build, game);
  const layout = unknown ? null : runeLayoutProblem(build.runes, game.runes);
  const outdated = isOutdated(build.patch, game.latest);
  const sig = buildSignature(build);
  const duplicate = approved.some((x) => x.id !== build.id && x.counter_id === build.counter_id && buildSignature(x) === sig);
  return { hiddenCounter, unknown, layout, outdated, duplicate };
}

/** 목록에서 바로 승인하면 위험한 이유 (없으면 null) → 줄에서 [승인]을 잠그고 [자세히]로 보낸다 */
export function quickBuildBlock(flags, build, latest) {
  if (flags.hiddenCounter) return '숨긴 카운터의 빌드예요.';
  if (flags.duplicate) return '똑같은 빌드가 이미 공개돼 있어요.';
  if (flags.unknown) return flags.unknown;
  if (flags.layout) return flags.layout;
  if (flags.outdated) return `지금 패치(${patchMinor(latest)})와 다른 패치(${patchMinor(build.patch)})로 등록됐어요.`;
  return null;
}
