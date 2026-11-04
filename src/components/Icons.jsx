/** X 아이콘 (빼기 버튼 — 빌드 아이템, 첨부 사진) */
export const XIcon = () => (
  <svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true" focusable="false">
    <path d="M4 4l8 8M12 4l-8 8" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
  </svg>
);

/*
 * 선 아이콘 (예전 앱의 lucide 아이콘 느낌을 직접 그림 — 패키지 없이). 글자 색을 따른다(currentColor).
 * 꾸밈용이라 화면 읽기에서는 건너뛴다(aria-hidden). 크기는 size로.
 */
const Line = ({ size = 18, className, children }) => (
  <svg
    width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"
    strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false" className={className}
  >
    {children}
  </svg>
);

/** 방패 (상단 로고) */
export const ShieldIcon = (p) => <Line {...p}><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z" /></Line>;
/** 반짝 (추천·카운터 목록) */
export const SparklesIcon = (p) => (
  <Line {...p}>
    <path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z" />
    <path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z" />
  </Line>
);
/** 조준 (상대 챔피언) */
export const CrosshairIcon = (p) => (
  <Line {...p}><circle cx="12" cy="12" r="9" /><path d="M22 12h-4M6 12H2M12 6V2M12 22v-4" /></Line>
);
/** 칼 두 개 (딜교) */
export const SwordsIcon = (p) => (
  <Line {...p}>
    <path d="M14.5 17.5L3 6V3h3l11.5 11.5" /><path d="M13 19l6-6M16 16l4 4M19 21l2-2" />
    <path d="M14.5 6.5L18 3h3v3l-3.5 3.5" /><path d="M5 14l4 4M7 17l-3 3M3 19l2 2" />
  </Line>
);
/** 오르는 선 (레벨별) */
export const TrendingUpIcon = (p) => <Line {...p}><path d="M22 7l-8.5 8.5-5-5L2 17" /><path d="M16 7h6v6" /></Line>;
/** 깃발 (요약·특이사항) */
export const FlagIcon = (p) => <Line {...p}><path d="M4 22V4" /><path d="M4 4h13l-2 4 2 4H4" /></Line>;
/** 말풍선 (댓글·노가리방) */
export const MessageIcon = (p) => <Line {...p}><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" /></Line>;
/** 돋보기 (검색) */
export const SearchIcon = (p) => <Line {...p}><circle cx="11" cy="11" r="7" /><path d="M21 21l-4.3-4.3" /></Line>;
/** 더하기 (추가 칸) */
export const PlusIcon = (p) => <Line {...p}><path d="M12 5v14M5 12h14" /></Line>;
/** 사람 (마이페이지) */
export const UserIcon = (p) => <Line {...p}><circle cx="12" cy="8" r="4" /><path d="M4 21a8 8 0 0 1 16 0" /></Line>;
