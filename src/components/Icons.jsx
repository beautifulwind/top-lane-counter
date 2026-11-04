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
/** 말풍선 (댓글·자유게시판) */
export const MessageIcon = (p) => <Line {...p}><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" /></Line>;
/** 돋보기 (검색) */
export const SearchIcon = (p) => <Line {...p}><circle cx="11" cy="11" r="7" /><path d="M21 21l-4.3-4.3" /></Line>;
/** 더하기 (추가 칸) */
export const PlusIcon = (p) => <Line {...p}><path d="M12 5v14M5 12h14" /></Line>;
/** 사람 (마이페이지) */
export const UserIcon = (p) => <Line {...p}><circle cx="12" cy="8" r="4" /><path d="M4 21a8 8 0 0 1 16 0" /></Line>;
/** 종 (알림) */
export const BellIcon = (p) => (
  <Line {...p}><path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" /><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" /></Line>
);
/** 동그라미 체크 (알림: 승인·공개) */
export const CheckCircleIcon = (p) => <Line {...p}><circle cx="12" cy="12" r="9" /><path d="M8 12.5l2.8 2.8L16 10" /></Line>;
/** 동그라미 금지 (알림: 거절) */
export const BanIcon = (p) => <Line {...p}><circle cx="12" cy="12" r="9" /><path d="M5.6 5.6l12.8 12.8" /></Line>;
/** 눈 (알림: 다시 공개) */
export const EyeIcon = (p) => (
  <Line {...p}><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z" /><circle cx="12" cy="12" r="3" /></Line>
);
/** 눈 가림 (알림: 숨김) */
export const EyeOffIcon = (p) => (
  <Line {...p}>
    <path d="M9.9 5.2A9.7 9.7 0 0 1 12 5c6.5 0 10 7 10 7a17.6 17.6 0 0 1-2.6 3.6M6.6 6.6C3.6 8.4 2 12 2 12s3.5 7 10 7a9.7 9.7 0 0 0 5.4-1.6" />
    <path d="M9.9 9.9a3 3 0 0 0 4.2 4.2" /><path d="M2 2l20 20" />
  </Line>
);
/** 세 줄 (☰ 메뉴) */
export const MenuIcon = (p) => <Line {...p}><path d="M4 6h16M4 12h16M4 18h16" /></Line>;

/*
 * 칭호 훈장 (/me 칭호판): 위 리본 두 갈래 + 둥근 메달 + 칭호마다 다른 그림.
 * 선·점은 글자 색(currentColor), 메달 바탕은 CSS(.medal-disc). 얻은 칭호는 칭호색, 못 얻은 칭호는 회색 — 색은 CSS가 정한다.
 * 카운터 승인 단계 칭호(10 → 25 → 50)는 메달 아래 점 1·2·3개.
 */
const MEDAL_GLYPH = {
  // 탑신병자: 불꽃 (탑 중독의 시작)
  top_addict: <path d="M24 19c1 4 7 6 7 12a7 7 0 0 1-14 0c0-3 2-5 3-6 0 2 1 4 3 4-1-4 0-7 1-10z" />,
  // 도구혐오자: 부러진 렌치
  tool_hater: (
    <>
      <path d="M32.5 20.5a5 5 0 0 1-6.6 6.6l-1.4 1.4" /><path d="M32.5 20.5l-3 3-2-1-1-2 3-3a5 5 0 0 0-3.5 7.6" />
      <path d="M24.5 28.5l-.4 1.6" /><path d="M21.8 31.2l-5.3 5.3" /><path d="M19.5 28l1.2 1.3M27 34.5l-1.3-1.2" />
    </>
  ),
  // 단단묵직: 모루
  solid_heavy: (
    <>
      <path d="M15 23h17c0 3 2 4 4 4h-6c-1 2-2 3-4 3h-6c-2 0-4-2-4-4z" />
      <path d="M21 30l-1 4h9l-1-4" /><path d="M18 37h13" />
    </>
  ),
  // 백정주인: 식칼
  butcher_owner: (
    <>
      <path d="M21 20h12v12.5c0 1-.8 1.5-1.5 1.5H21z" /><path d="M21 22.5h-7.5v3H21" />
      <circle cx="29.5" cy="23.5" r="1.3" fill="currentColor" stroke="none" />
    </>
  ),
  // 장군: 별 단 투구
  general: (
    <>
      <path d="M16 35v-5a8 8 0 0 1 16 0v5z" /><path d="M21 35v-3h6v3" />
      <path d="M24 23.5l1.1 2.2 2.4.3-1.8 1.7.5 2.4-2.2-1.2-2.2 1.2.5-2.4-1.8-1.7 2.4-.3z" fill="currentColor" strokeWidth="1" />
    </>
  ),
  // 비주류: 주사위 (남들이 안 고르는 픽)
  offmeta: (
    <>
      <rect x="17" y="22" width="14" height="14" rx="3" />
      <g fill="currentColor" stroke="none">
        <circle cx="20.8" cy="25.8" r="1.4" /><circle cx="24" cy="29" r="1.4" /><circle cx="27.2" cy="32.2" r="1.4" />
      </g>
    </>
  ),
};
const MEDAL_TIER = { tool_hater: 1, solid_heavy: 2, butcher_owner: 3 };

export const MedalIcon = ({ titleKey, size = 52 }) => {
  const tier = MEDAL_TIER[titleKey] ?? 0;
  return (
    <svg
      width={size} height={size * (54 / 48)} viewBox="0 0 48 54" fill="none" stroke="currentColor" strokeWidth="2"
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false" className="medal-icon"
    >
      <path className="medal-ribbon" d="M14 2h8l4 11h-8zM34 2h-8l-4 11h8z" />
      <circle className="medal-disc" cx="24" cy="29" r="15" />
      {MEDAL_GLYPH[titleKey]}
      {tier > 0 && (
        <g fill="currentColor" stroke="none">
          {Array.from({ length: tier }, (_, i) => <circle key={i} cx={24 + (i - (tier - 1) / 2) * 6} cy="50" r="1.8" />)}
        </g>
      )}
    </svg>
  );
};
