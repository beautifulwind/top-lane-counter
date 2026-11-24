// 전체 장인 목록 /influencers (1.3 패치 1-B1·1-B2 보완·정정, SPEC 6-93·6-95·6-96) 설정. 화면 배치만 정하고 DB는 모른다.

/** 한 쪽에 보이는 장인 수 (웹에서 나눠 보여 준다) */
export const INFLUENCER_PAGE_SIZE = 10;

/** 한 번에 받아 오는 장인 수 상한 (influencer_directory의 p_size 최대). 전체가 이보다 많으면 서버 쪽 나누기로 되돌린다 */
export const INFLUENCER_FETCH_MAX = 50;

/** 정렬 (influencer_directory의 p_sort): 기본은 팔로워 많은 순(같으면 최신순), 「최신순」 칩을 켜면 최근 활동순. 칩 상태는 주소 ?sort=recent */
export const INFLUENCER_SORT_DEFAULT = 'followers';
export const INFLUENCER_SORT_RECENT = 'recent';

/** 검색어 길이 상한 (DB가 20자를 넘으면 거부하므로 입력칸에서 막는다) */
export const INFLUENCER_QUERY_MAX = 20;
