import { Link, useLocation } from 'react-router-dom';
import { signOut } from '../api/auth';
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
  return (
    <div className="auth-bar">
      {auth.profile?.nickname && (
        <Link to="/me" className="me" title="내 활동">
          {/* 운영자도 역할 글자 없이 "Lv.0 닉네임"으로만 표시 (SPEC 3장) */}
          <UserName profile={auth.profile} />
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
