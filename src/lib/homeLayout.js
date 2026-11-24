// 메인 화면(챔피언 선택) 배치 설정 (1.3 패치 1-B2, SPEC 6-94). 한 곳에서만 정한다.

/** 메인 장인 줄에 보이는 장인 수 (최근 활동순, 사진 없는 장인은 맨 뒤) */
export const HOME_INFLUENCER_COUNT = 8;

/** 사진 없는 장인을 뒤로 보내기 위해 먼저 받아 오는 장인 수 (이 중 사진 있는 순서로 앞 HOME_INFLUENCER_COUNT명만 보인다) */
export const HOME_INFLUENCER_FETCH = 20;

/** 챔피언 격자가 접힌 상태에서 보이는 줄 수 */
export const CHAMP_VISIBLE_ROWS = 4;

/**
 * 격자의 지금 한 줄 칸 수. CSS(auto-fill)가 화면 폭에 따라 정하므로 계산하지 않고 브라우저가 정한 칸 목록(grid-template-columns)을 센다.
 * 못 읽으면(0) 호출한 쪽이 기본값을 쓴다.
 */
export function gridColumnCount(el) {
  if (!el || typeof window === 'undefined' || typeof window.getComputedStyle !== 'function') return 0;
  const cols = window.getComputedStyle(el).gridTemplateColumns;
  if (!cols || cols === 'none') return 0;
  return cols.trim().split(/\s+/).filter((c) => /^[\d.]+px$/.test(c)).length;
}
