// 장인 목록의 「사진 없는 장인은 맨 뒤」 규칙 (1.3 패치 1-B2 보완, SPEC 6-95). 메인 장인 줄과 /influencers가 같이 쓴다.
// 078(SPEC 6-113)부터 DB(influencer_directory)가 같은 규칙으로 먼저 정렬해 주므로 여기서 다시 나눠도 순서가 바뀌지 않는다(받은 순서 그대로).
// 078을 실행하기 전 DB에서도 화면이 같게 보이도록 남겨 둔다. 판정(비었거나 공백뿐이면 없음)은 078과 같다.

/** 프로필 사진이 있는가 (photo_path가 비었거나 공백뿐이면 없음) */
export const hasPhoto = (p) => typeof p?.photo_path === 'string' && p.photo_path.trim() !== '';

/**
 * 사진 있는 장인 → 사진 없는 장인 순으로 나눈다. 각 묶음 안의 순서는 받은 순서(서버의 정렬) 그대로(안정적으로 분리).
 * 받은 배열은 건드리지 않고 새 배열을 돌려준다.
 */
export function photoFirst(items) {
  const list = items ?? [];
  return [...list.filter(hasPhoto), ...list.filter((p) => !hasPhoto(p))];
}
