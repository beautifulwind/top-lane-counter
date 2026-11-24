// 장인 목록의 「사진 없는 장인은 맨 뒤」 규칙 (1.3 패치 1-B2 보완, SPEC 6-95). 메인 장인 줄과 /influencers가 같이 쓴다.
// 지금은 웹에서 나누지만, 나중에 DB 정렬(influencer_directory)에 사진 유무를 넣으면 이 파일만 없애거나 바꾸면 된다.

/** 프로필 사진이 있는가 (photo_path가 비었거나 공백뿐이면 없음) */
export const hasPhoto = (p) => typeof p?.photo_path === 'string' && p.photo_path.trim() !== '';

/**
 * 사진 있는 장인 → 사진 없는 장인 순으로 나눈다. 각 묶음 안의 순서는 받은 순서(서버의 최근 활동순) 그대로(안정적으로 분리).
 * 받은 배열은 건드리지 않고 새 배열을 돌려준다.
 */
export function photoFirst(items) {
  const list = items ?? [];
  return [...list.filter(hasPhoto), ...list.filter((p) => !hasPhoto(p))];
}
