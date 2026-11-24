// 전체 장인 목록 /influencers (1.3 패치 1-B1, SPEC 6-93) 설정. 화면 배치만 정하고 DB는 모른다.

/** 한 쪽에 보이는 장인 수 (influencer_directory의 p_size) — 이 한 곳만 고치면 된다 */
export const INFLUENCER_PAGE_SIZE = 10;

/** 정렬 칩 (주소 ?sort=). 첫 값이 기본이고 기본일 때는 주소에 남기지 않는다 */
export const INFLUENCER_SORTS = [
  { key: 'followers', label: '팔로워 많은 순' },
  { key: 'recent', label: '최신순' },
];

/** 검색어 길이 상한 (DB가 20자를 넘으면 거부하므로 입력칸에서 막는다) */
export const INFLUENCER_QUERY_MAX = 20;
