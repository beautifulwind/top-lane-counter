import { Link, Navigate, Outlet, useLocation } from 'react-router-dom';
import ErrorBoundary from './ErrorBoundary';
import AuthBar from './AuthBar';
import { needsNickname, useAuth } from '../lib/auth';

export const RIOT_NOTICE =
  '이 사이트는 Riot Games가 보증하거나 후원하지 않으며, Riot Games 또는 League of Legends 제작·관리에 공식적으로 관여한 사람의 견해를 반영하지 않습니다. League of Legends 및 Riot Games는 Riot Games, Inc.의 상표 또는 등록 상표입니다.';

export default function Layout() {
  const { pathname, search } = useLocation();
  const auth = useAuth();
  // 로그인했는데 닉네임이 없으면 어느 페이지에서든 닉네임 설정으로 보낸다
  if (needsNickname(auth) && pathname !== '/welcome') {
    return <Navigate to="/welcome" replace state={{ from: pathname + search }} />;
  }
  return (
    <div className="app">
      <header className="topbar">
        <Link to="/" className="brand">
          탑 카운터 위키
        </Link>
        <AuthBar />
      </header>
      {auth.loginError && (
        <div className="login-error" role="alert">
          <p><strong>로그인하지 못했어요.</strong> {auth.loginError.message}</p>
          {auth.loginError.detail && <small>상세: {auth.loginError.detail}</small>}
          <div className="login-error-actions">
            <Link to="/login" className="btn" onClick={auth.clearLoginError}>다시 로그인</Link>
            <button type="button" className="btn" onClick={auth.clearLoginError}>닫기</button>
          </div>
        </div>
      )}
      <main className="content">
        {/* 페이지마다 새 경계: 한 페이지에서 오류가 나도 머리말·고지 문구는 남고, 이동하면 초기화 */}
        <ErrorBoundary key={pathname}>
          <Outlet />
        </ErrorBoundary>
      </main>
      <footer className="footer">
        <p>{RIOT_NOTICE}</p>
      </footer>
    </div>
  );
}
