import { useEffect, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { signOut } from '../api/auth';
import { getMyUnreadNotifications, onNotificationsChanged } from '../api/proposals';
import { isGuest, useAuth } from '../lib/auth';
import UserName from './UserName';

/**
 * 상단 바의 계정 종류. 상단 바·마이페이지 계정 줄이 이 값 하나로 버튼을 정한다.
 * 'loading' | 'signedOut' | 'guest'(비회원: [마이페이지]만, 로그아웃 없음) | 'noNickname'(로그인했지만 닉네임 전) | 'member' | 'operator'
 */
export function accountKind(auth) {
  if (auth.status === 'loading') return 'loading';
  if (auth.status !== 'signedIn') return 'signedOut';
  if (isGuest(auth)) return 'guest';
  if (!auth.profile?.nickname) return 'noNickname';
  return auth.isOperator ? 'operator' : 'member';
}

export const logout = () => signOut().catch((e) => alert(e.message));

/** 상단 바 [노가리방]: 마이페이지·로그인 버튼 바로 왼쪽 (022) */
const BoardLink = () => <Link to="/board" className="top-link">노가리방</Link>;

/**
 * 상단 바 오른쪽 (SPEC 3장 상단 바):
 * - 어느 상태든 맨 왼쪽에 [노가리방] (022: 사이트 이름 옆에서 옮김)
 * - 로그인 전: [로그인 · 가입]
 * - 비회원: [마이페이지●] + 넓은 화면에서 닉네임(비회원 표시)만. 로그아웃은 어디에도 없다 (같이 쓰는 기기는 [비회원 기록 지우기])
 * - 로그인 후: [마이페이지●](새 알림 빨간 점) + 넓은 화면에서만 닉네임(글자만, 누르면 아무 동작 없음)·[관리](운영자)·[로그아웃]
 *   휴대폰 폭에서는 [관리]·[로그아웃]이 마이페이지 맨 위(AccountRow)로 간다.
 */
export default function AuthBar() {
  const auth = useAuth();
  const { pathname, search } = useLocation();
  const kind = accountKind(auth);

  if (kind === 'loading') return <div className="auth-bar"><BoardLink /></div>;
  if (kind === 'signedOut') {
    return (
      <div className="auth-bar">
        <BoardLink />
        <Link to="/login" state={{ from: pathname + search }} className="top-btn">
          로그인 · 가입
        </Link>
      </div>
    );
  }
  return <SignedIn auth={auth} kind={kind} pathname={pathname} />;
}

/**
 * 안 읽은 알림 개수 (빨간 점). 페이지를 옮길 때와 읽음 처리했을 때 다시 센다.
 * 마이페이지에서 알림을 확인하면 꺼진다.
 */
function useUnreadCount(userId, pathname) {
  const [count, setCount] = useState(0);
  const [changed, setChanged] = useState(0);
  useEffect(() => {
    const off = onNotificationsChanged(() => setChanged((n) => n + 1));
    return off; // 구독 해제
  }, []);
  useEffect(() => {
    if (!userId) return undefined;
    let alive = true;
    getMyUnreadNotifications(userId).then((rows) => alive && setCount(rows.length), () => {}); // 알림은 실패해도 조용히
    return () => { alive = false; };
  }, [userId, pathname, changed]);
  return userId ? count : 0;
}

function SignedIn({ auth, kind, pathname }) {
  const named = !!auth.profile?.nickname;
  const count = useUnreadCount(named ? auth.user.id : null, pathname);
  const here = pathname === '/me' || pathname.startsWith('/me/');
  return (
    <div className="auth-bar">
      <BoardLink />
      {named && (
        // 운영자도 역할 글자 없이 "Lv.0 닉네임"으로만 표시 (SPEC 3장). 글자만 — 누르는 동작 없음
        <span className="me-name wide-only"><UserName profile={auth.profile} /></span>
      )}
      <Link
        to="/me"
        className={here ? 'top-btn mypage on' : 'top-btn mypage'}
        aria-current={here ? 'page' : undefined}
        aria-label={count > 0 ? `마이페이지, 새 알림 ${count}개` : '마이페이지'}
      >
        마이페이지
        {count > 0 && <span className="alert-dot" aria-hidden="true" title={`새 알림 ${count}개`} />}
      </Link>
      {kind === 'operator' && (
        <Link to="/admin" className="top-btn op wide-only">관리</Link>
      )}
      {kind !== 'guest' && (
        <button type="button" className="top-btn wide-only" onClick={logout}>
          로그아웃
        </button>
      )}
    </div>
  );
}

/** 마이페이지 맨 위 계정 줄: 휴대폰 폭에서만 보이는 [관리](운영자)·[로그아웃] (상단 바에서 빠진 것) */
export function AccountRow() {
  const auth = useAuth();
  const kind = accountKind(auth);
  if (kind !== 'member' && kind !== 'operator') return null;
  return (
    <div className="account-row narrow-only">
      {kind === 'operator' && <Link to="/admin" className="btn btn-small btn-op">관리</Link>}
      <button type="button" className="btn btn-small" onClick={logout}>로그아웃</button>
    </div>
  );
}
