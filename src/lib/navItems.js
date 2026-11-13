// 사이트 메뉴 항목 (SPEC 3장 상단 바·메뉴): 여기 한 곳에서만 정한다.
// 지금은 ☰ 메뉴 패널(menu)이 읽고, 나중에 앱으로 낼 때 아래 탭 바(tab)도 같은 목록을 읽는다.
// 상단 바 밖으로 꺼내 보일 항목은 bar: true (지금은 없음 — 상단 바는 로고와 ☰만).
// needs: 'any'(누구나) | 'signedIn'(로그인 — 비회원·닉네임 전 포함) | 'staff'(운영자·감독관)
// 로그인·로그아웃은 페이지 이동이 아니라 계정 동작이라 이 목록 밖(SiteMenu)에서 처리한다.
export const NAV_ITEMS = [
  { key: 'home', to: '/', label: '챔피언 선택', icon: 'shield', needs: 'any', menu: false, tab: true, bar: false },
  { key: 'me', to: '/me', label: '마이페이지', icon: 'user', needs: 'signedIn', menu: true, tab: true, bar: false },
  // 새 알림 빨간 점은 [알림] 옆 (☰에도). 로그인한 사람 모두 (비회원·닉네임 전·운영자 포함)
  { key: 'notifications', to: '/notifications', label: '알림', icon: 'bell', needs: 'signedIn', menu: true, tab: true, bar: false, dot: 'unread' },
  // 장인찾기 (050): 이동이 아니라 펼침 — 누르면 바로 아래에 검색 칸(InfluencerSearch). 누구나 (로그인 전 포함)
  { key: 'influencers', to: null, panel: 'influencerSearch', label: '장인찾기', icon: 'search', needs: 'any', menu: true, tab: false, bar: false },
  { key: 'board', to: '/board', label: '자유게시판', icon: 'message', needs: 'any', menu: true, tab: true, bar: false },
  // 문의하기 (032): 로그인한 사람 모두 (비회원·닉네임 전 포함). 답변은 알림과 이 화면으로
  { key: 'inquiries', to: '/inquiries', label: '문의하기', icon: 'help', needs: 'signedIn', menu: true, tab: false, bar: false },
  // 처리 대기 건수(033)는 [관리] 옆 숫자로 (count: 'pending')
  { key: 'admin', to: '/admin', label: '관리', icon: 'shield', needs: 'staff', menu: true, tab: false, bar: false, tone: 'op', count: 'pending' },
];

const ALLOWED = {
  any: () => true,
  signedIn: (kind) => ['guest', 'noNickname', 'member', 'moderator', 'operator'].includes(kind),
  staff: (kind) => kind === 'moderator' || kind === 'operator',
};

/** where('menu' | 'tab' | 'bar')에 보일 항목 — kind는 accountKind(auth) */
export const navItemsFor = (where, kind) =>
  kind === 'loading' ? [] : NAV_ITEMS.filter((it) => it[where] && ALLOWED[it.needs](kind));

/** 지금 보고 있는 항목인가: 홈은 정확히 '/', 나머지는 그 주소와 그 아래 */
export const isCurrentNav = (item, pathname) =>
  !item.to ? false : item.to === '/' ? pathname === '/' : pathname === item.to || pathname.startsWith(`${item.to}/`);
