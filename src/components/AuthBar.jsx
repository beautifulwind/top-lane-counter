import { useEffect, useState } from 'react';
import { Link, useLocation } from 'react-router-dom';
import { signOut } from '../api/auth';
import { getMyRevisionRequestCount } from '../api/proposals';
import { useAuth } from '../lib/auth';
import UserName from './UserName';

/** 상단 바 오른쪽: 로그인 전 [로그인], 로그인 후 "Lv.1 닉네임"(운영자는 "Lv.0 닉네임") + [로그아웃] */
export default function AuthBar() {
  const auth = useAuth();
  const { pathname, search } = useLocation();

  if (auth.status === 'loading') return <div className="auth-bar" aria-hidden="true" />;

  if (auth.status === 'signedOut') {
    return (
      <div className="auth-bar">
        <Link to="/login" state={{ from: pathname + search }} className="top-btn">
          로그인
        </Link>
      </div>
    );
  }

  const logout = () => signOut().catch((e) => alert(e.message));
  return <SignedIn auth={auth} pathname={pathname} logout={logout} />;
}

/**
 * 재검토 요청 알림 개수. 페이지를 옮길 때마다 다시 센다 → 다시 제출하고 /me로 오면 꺼진다.
 * (/me에 들어가는 것만으로는 꺼지지 않는다 — 다시 제출해야 꺼짐)
 */
function useRevisionCount(userId, pathname) {
  const [count, setCount] = useState(0);
  useEffect(() => {
    if (!userId) return undefined;
    let alive = true;
    getMyRevisionRequestCount(userId).then((n) => alive && setCount(n), () => {}); // 알림은 실패해도 조용히
    return () => { alive = false; };
  }, [userId, pathname]);
  return userId ? count : 0;
}

function SignedIn({ auth, pathname, logout }) {
  const count = useRevisionCount(auth.profile?.nickname ? auth.user.id : null, pathname);
  return (
    <div className="auth-bar">
      {auth.profile?.nickname && (
        <Link to="/me" className="me" title="내 활동">
          {/* 운영자도 역할 글자 없이 "Lv.0 닉네임"으로만 표시 (SPEC 3장) */}
          <UserName profile={auth.profile} />
          {count > 0 && (
            <span className="alert-dot" role="img" aria-label={`재검토 요청 ${count}개`} title={`재검토 요청 ${count}개`} />
          )}
        </Link>
      )}
      {auth.isOperator && (
        <Link to="/admin" className="top-btn">관리</Link>
      )}
      <button type="button" className="top-btn" onClick={logout}>
        로그아웃
      </button>
    </div>
  );
}
