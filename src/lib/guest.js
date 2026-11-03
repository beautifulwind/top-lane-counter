// 비회원(Supabase 익명 로그인) 규칙과 문구 — 화면(웹)과 나중에 앱(Expo)이 같이 쓴다. DOM·Supabase를 부르지 않는다.
// 실제 권한 검사는 DB(020_guest.sql)가 한다: 따봉/비추·추천·신고는 막고, 글·댓글·제안·빌드는 회원과 같다.

/** 비회원으로 시작할 때 보여 줄 안내 (platform: 'web' | 'app') */
export function guestNotice(platform = 'web') {
  if (platform === 'app') {
    return '이 기기에만 저장돼요. 앱을 지우거나 기기를 바꾸면 사라질 수 있어요. 구글·카카오를 연결하면 유지돼요.';
  }
  return '이 기기·브라우저에만 저장돼요. 다른 브라우저, 시크릿 창, 기록 삭제, 오래 접속 안 함(아이폰 사파리는 7일)이면 사라질 수 있어요. 구글·카카오를 연결하면 유지돼요.';
}

/** 마이페이지 연결 권유 문구 */
export const GUEST_UPGRADE_TEXT = '비회원 기록은 이 브라우저에만 있어요. 구글·카카오를 연결하면 어디서든 이어지고, 따봉·추천·신고도 할 수 있어요.';

/** 오래 안 쓴 비회원 정리 기준 (DB xp_rules guest_empty_days·guest_idle_days와 같은 값, 안내 문구용) */
export const GUEST_CLEANUP_DAYS = { empty: 30, idle: 90 };

/** 비회원인가 (프로필 값이 우선, 아직 못 불러왔으면 세션의 익명 표시) */
export const isGuest = (auth) => auth.status === 'signedIn' && (auth.profile?.is_guest ?? auth.user?.is_anonymous ?? false) === true;

/** 비회원이 구글·카카오를 고를 때 고르는 창의 선택지 */
export const LINK_CHOICES = {
  link: {
    label: '지금 계정에 연결하기',
    hint: '지금 비회원 계정에 붙여요. 글·제안·경험치·닉네임이 그대로 이어져요.',
  },
  fresh: {
    label: '새 계정으로 시작하기',
    hint: '구글·카카오로 다른 계정을 써요.',
    warn: `지금 비회원 계정에는 다시 들어올 수 없어요. 그 계정의 글·댓글은 남지만, ${GUEST_CLEANUP_DAYS.idle}일 뒤 탈퇴처럼 정리돼요.`,
  },
};

/** 연결하려는 구글·카카오가 이미 다른 회원 계정에 붙어 있을 때 */
export const ALREADY_MEMBER_TEXT = '이미 가입된 계정이에요. 기존 계정으로 로그인할까요? 비회원 기록은 넘어가지 않아요.';
