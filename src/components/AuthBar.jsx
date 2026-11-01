import { Link, useLocation } from 'react-router-dom';
import { signOut } from '../api/auth';
import { useAuth } from '../lib/auth';
import UserName from './UserName';

/** 상단 바 오른쪽: 로그인 전 [로그인], 로그인 후 "Lv.1 닉네임" + [로그아웃] */
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
        <span className="me">
          <UserName profile={auth.profile} />
          {auth.isAdmin && <span className="role-badge">관리자</span>}
        </span>
      )}
      <button type="button" className="top-btn" onClick={logout}>
        로그아웃
      </button>
    </div>
  );
}
