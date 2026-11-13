import { useEffect, useSyncExternalStore } from 'react';
import { getPublicTitleInfo } from '../api/rewards';

// 칭호 목록 (SPEC 6-3). DB의 user_titles.title_key / profiles.main_title 값 → 화면 이름.
// 조건·숫자는 DB(xp_rules, sync_rewards)가 정한다. 여기는 이름과 보여 줄 순서·설명만.
// "운영자"·"관리자"라는 단어는 칭호에 쓰지 않는다.
export const TITLES = {
  top_addict: '탑신병자',
  tool_hater: '도구혐오자',
  solid_heavy: '단단묵직',
  butcher_owner: '백정주인',
  general: '장군',
  offmeta: '비주류',
};

/** /me 칭호판 말풍선의 조건 설명 — 괄호 설명 없이 짧게 (2026-11-04). 자세한 기준은 SPEC 6-3. rules = xp_rules 값 { title_tool_hater: 10, ... } */
export const titleCondition = (key, rules = {}) => ({
  top_addict: '처음으로 승인받은 기여 1개 또는 탑신병자 커뮤니티 글·댓글·문서 댓글 1개',
  tool_hater: `상대법 관련 승인 ${rules.title_tool_hater ?? 10}개`,
  solid_heavy: `상대법 관련 승인 ${rules.title_solid_heavy ?? 25}개`,
  butcher_owner: `상대법 관련 승인 ${rules.title_butcher_owner ?? 50}개`,
  general: `공개 중인 내 빌드들의 추천 합계 ${rules.title_general ?? 100}`,
  offmeta: `비주류 픽 매치업 기여 승인 ${rules.title_offmeta ?? 5}개`,
})[key] ?? '';

// ---------------- 닉네임 옆 배지용 칭호 정보 (054 public_title_info, SPEC 6-41) ----------------
// 앱이 켜질 때 한 번 읽어서 모든 화면이 재사용한다. 읽기 전·실패해도 기존 6개 활동 칭호는 위 TITLES 이름으로 나온다.
// 모르는 키(새로 장착된 한정판·비밀 칭호)가 보이면 5분에 한 번까지 다시 읽는다.
const REFETCH_MS = 5 * 60 * 1000;
let infoMap = null; // null = 아직 안 읽음, Map(key → { key, kind, name, icon, color })
let infoLoading = null;
let lastFetch = 0;
let version = 0;
const listeners = new Set();
const emit = () => { version += 1; listeners.forEach((l) => l()); };

/** 칭호 정보 읽기 (이미 읽었으면 그대로, force면 다시). 실패해도 화면은 기존 6개 이름으로 */
export function loadTitleInfo({ force = false } = {}) {
  if (infoLoading) return infoLoading;
  if (infoMap && !force) return Promise.resolve();
  lastFetch = Date.now();
  infoLoading = Promise.resolve()
    .then(getPublicTitleInfo)
    .then(
      (rows) => { infoMap = new Map(rows.map((r) => [r.key, r])); },
      () => { infoMap = infoMap ?? new Map(); },
    )
    .finally(() => { infoLoading = null; emit(); });
  return infoLoading;
}

/** 대표 칭호를 막 고른 한 줄(도감 my_title_book의 칭호)을 바로 기억한다 — 비밀 칭호도 다시 읽지 않고 상단 배지에 나온다 */
export function rememberTitle(item) {
  if (!item?.key || !item.name) return;
  infoMap = new Map(infoMap ?? []);
  infoMap.set(item.key, { key: item.key, kind: item.kind, name: item.name, icon: item.icon ?? null, color: item.color ?? null });
  emit();
}

/** 테스트용: 읽은 칭호 정보 지우기 */
export function resetTitleInfo() {
  infoMap = null;
  infoLoading = null;
  lastFetch = 0;
  emit();
}

/** 칭호 한 개의 배지 정보 { key, kind, name, icon, color } 또는 null (모르는 키·숨김·키 없음) */
export function titleInfo(key) {
  if (!key) return null;
  const hit = infoMap?.get(key);
  if (hit) return hit;
  if (key in TITLES) return { key, kind: 'activity', name: TITLES[key], icon: null, color: null };
  if (infoMap && !infoLoading && Date.now() - lastFetch > REFETCH_MS) setTimeout(() => loadTitleInfo({ force: true }), 0);
  return null;
}

/** 칭호 정보가 바뀌면 다시 그린다 (아직 안 읽었으면 읽기 시작) */
export function useTitleInfo() {
  useEffect(() => { loadTitleInfo(); }, []);
  return useSyncExternalStore(
    (cb) => { listeners.add(cb); return () => listeners.delete(cb); },
    () => version,
  );
}

/** 칭호 이름 (회원 관리 목록·문장용). 모르는 키는 키 그대로 */
export const titleName = (key) => (key ? titleInfo(key)?.name ?? key : null);
