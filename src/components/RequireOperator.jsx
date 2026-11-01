import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../lib/auth';
import { Loading } from './Status';

/** 운영자 화면 입구. 화면만 가리는 것이고, 실제 권한은 DB(운영자 전용 함수·RLS)가 막는다. */
export default function RequireOperator({ children }) {
  const auth = useAuth();
  const { pathname } = useLocation();
  if (auth.status === 'loading') return <Loading />;
  if (auth.status === 'signedOut') return <Navigate to="/login" replace state={{ from: pathname }} />;
  if (auth.profile === undefined) return <Loading />;
  if (!auth.isOperator) {
    return (
      <article>
        <h1 className="doc-title">운영자 페이지</h1>
        <p className="empty">운영자만 볼 수 있어요.</p>
      </article>
    );
  }
  return children;
}

/** 로그인해야 쓸 수 있는 화면 입구 (닉네임 설정은 Layout이 먼저 보낸다) */
export function RequireLogin({ children }) {
  const auth = useAuth();
  const { pathname, search } = useLocation();
  if (auth.status === 'loading') return <Loading />;
  if (auth.status === 'signedOut') return <Navigate to="/login" replace state={{ from: pathname + search }} />;
  if (auth.profile === undefined) return <Loading />;
  return children;
}
