import { Link, Navigate, Outlet, useLocation } from 'react-router-dom';
import ErrorBoundary from './ErrorBoundary';
import AuthBar from './AuthBar';
import { needsNickname, useAuth } from '../lib/auth';
import { noticeText } from '../api/auth';

export const RIOT_NOTICE =
  '이 사이트는 Riot Games가 보증하거나 후원하지 않으며, Riot Games 또는 League of Legends 제작·관리에 공식적으로 관여한 사람의 견해를 반영하지 않습니다. League of Legends 및 Riot Games는 Riot Games, Inc.의 상표 또는 등록 상표입니다.';

const NICKNAME_FREE = ['/welcome', '/privacy', '/terms'];

export default function Layout() {
  const { pathname, search } = useLocation();
  const auth = useAuth();
  // 로그인했는데 닉네임이 없으면 어느 페이지에서든 닉네임 설정으로 보낸다
  // (개인정보처리방침·이용약관은 닉네임을 정하기 전에도 읽을 수 있어야 해서 뺀다)
  if (needsNickname(auth) && !NICKNAME_FREE.includes(pathname)) {
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
          <p><strong>{auth.loginError.title ?? '로그인하지 못했어요.'}</strong> {auth.loginError.message}</p>
          {auth.loginError.detail && <small>상세: {auth.loginError.detail}</small>}
          <div className="login-error-actions">
            <Link to={auth.loginError.retryTo ?? '/login'} className="btn" onClick={auth.clearLoginError}>
              {auth.loginError.retryTo === '/me' ? '다시 연결하기' : '다시 로그인'}
            </Link>
            <button type="button" className="btn" onClick={auth.clearLoginError}>닫기</button>
          </div>
        </div>
      )}
      {auth.notice && (
        <div className="login-notice" role="status">
          <p>{noticeText(auth.notice)}</p>
          <div className="login-error-actions">
            {auth.notice.type === 'merged' && (
              <Link to="/me" className="btn" onClick={auth.clearNotice}>연결된 로그인 보기</Link>
            )}
            <button type="button" className="btn" onClick={auth.clearNotice}>닫기</button>
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
        <nav className="footer-links" aria-label="사이트 정책">
          <Link to="/privacy" className="footer-privacy">개인정보처리방침</Link>
          <span aria-hidden="true"> · </span>
          <Link to="/terms">이용약관</Link>
        </nav>
        <p>{RIOT_NOTICE}</p>
      </footer>
    </div>
  );
}
