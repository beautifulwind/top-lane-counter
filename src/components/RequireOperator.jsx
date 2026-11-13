import { Link, Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../lib/auth';
import { Loading } from './Status';

/** 운영자 화면 입구. 화면만 가리는 것이고, 실제 권한은 DB(운영자 전용 함수·RLS)가 막는다. */
export default function RequireOperator({ children }) {
  return <Gate allowed={(auth) => auth.isOperator}>{children}</Gate>;
}

/** 운영자·감독관 화면 입구 (/admin, /admin/reports, /admin/proposals/:id). 감독관이 무엇을 할 수 있는지는 DB가 정한다. */
export function RequireStaff({ children }) {
  return <Gate allowed={(auth) => auth.isStaff}>{children}</Gate>;
}

function Gate({ allowed, children }) {
  const auth = useAuth();
  const { pathname } = useLocation();
  if (auth.status === 'loading') return <Loading />;
  if (auth.status === 'signedOut') return <Navigate to="/login" replace state={{ from: pathname }} />;
  if (auth.profile === undefined) return <Loading />;
  if (!allowed(auth)) {
    return (
      <article>
        <h1 className="doc-title">운영자 페이지</h1>
        <p className="empty">운영자만 볼 수 있습니다.</p>
        {/* 050: 운영자 계정인데 운영자 모드를 꺼 둔 경우 — 어디서 켜는지 안내 */}
        {auth.isOperatorAccount && !auth.isOperator && (
          <p className="hint">운영자 모드가 꺼져 있습니다. <Link to="/me/settings">계정 설정</Link>에서 운영자 모드를 켜면 볼 수 있습니다.</p>
        )}
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
