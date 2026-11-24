// 운영자 페이지(/admin)·회원 상세(/admin/members/:id) 화면 정리용 상수 (1.3 패치 1-A, SPEC 6-89). 화면 배치만 정하고 DB·API는 모른다.

/** 긴 목록의 기본 표시 개수 — 이 한 곳만 고치면 모든 칸이 바뀐다. 「모두 보기」로 나머지를 펼친다 */
export const PREVIEW_COUNT = {
  /** 줄이 큰 목록 (숨긴 상대법·숨긴 빌드·숨긴 글·댓글·삭제 기록) */
  cards: 3,
  /** 줄이 작은 기록 (회원 상세의 글·댓글·고친 빌드·처리 이력·지운 글·경고·제한 기록) */
  logs: 5,
};

/** /admin 탭 (주소 ?tab=). 첫 값이 기본 */
export const ADMIN_TABS = [
  { key: 'content', label: '콘텐츠' },
  { key: 'members', label: '회원·장인' },
  { key: 'settings', label: '설정·운영' },
];

/** 요약 카드 → 이동할 탭과 구역 id */
export const ADMIN_TARGETS = {
  reports: { tab: 'content', id: 'admin-reports' },
  inquiries: { tab: 'members', id: 'admin-inquiries' },
  influencers: { tab: 'members', id: 'admin-influencer' },
};

/** /admin/members/:id 탭 (주소 ?tab=). 첫 값이 기본 */
export const MEMBER_TABS = [
  { key: 'info', label: '정보·조치' },
  { key: 'activity', label: '활동' },
  { key: 'records', label: '기록' },
];
