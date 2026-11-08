import { useRef } from 'react';
import { Link, Navigate, Outlet, useLocation } from 'react-router-dom';
import ErrorBoundary from './ErrorBoundary';
import { ShieldIcon } from './Icons';
import SiteMenu from './SiteMenu';
import UpdateBanner from './UpdateBanner';
import { needsNickname, needsNicknameFor, useAuth } from '../lib/auth';
import { noticeText, startFresh } from '../api/auth';
import { usePageTitle } from '../lib/pageTitle';
import { SITE_NAME, SITE_TAGLINE } from '../lib/legal';

export const RIOT_NOTICE =
  '이 사이트는 Riot Games가 보증하거나 후원하지 않으며, Riot Games 또는 League of Legends 제작·관리에 공식적으로 관여한 사람의 견해를 반영하지 않습니다. League of Legends 및 Riot Games는 Riot Games, Inc.의 상표 또는 등록 상표입니다.';

export default function Layout() {
  const { pathname, search, state } = useLocation();
  const siteNotice = typeof state?.siteNotice === 'string' ? state.siteNotice : null; // 예: 탈퇴한 뒤 홈에서 한 번
  const auth = useAuth();
  const mainRef = useRef(null);
  usePageTitle(mainRef, pathname); // 탭 제목 = 본문 첫 h1 (SPEC 3장)
  // 로그인했는데 닉네임이 없으면: 읽기는 어디서나, 쓰기 화면·/me에 오면 닉네임 정하기로 (정하면 돌아온다).
  // 막 가입하고 돌아온 때도 한 번 보여 준다 ([나중에 정하기]로 건너뜀)
  const noNickname = needsNickname(auth);
  if (noNickname && pathname !== '/welcome' && (needsNicknameFor(pathname) || auth.cameBack)) {
    return <Navigate to="/welcome" replace state={{ from: pathname + search }} />;
  }
  return (
    <div className="app">
      <header className="topbar">
        <nav className="top-nav" aria-label="사이트">
          <span className="brand-wrap">
            <Link to="/" className="brand">
              <span className="brand-logo"><ShieldIcon size={18} /></span>
              {SITE_NAME}
            </Link>
            <span className="tagline">{SITE_TAGLINE}</span>
          </span>
        </nav>
        <SiteMenu />
      </header>
      {auth.loginError && (
        <div className="login-error" role="alert">
          <p><strong>{auth.loginError.title ?? '로그인하지 못했습니다.'}</strong> {auth.loginError.message}</p>
          {auth.loginError.detail && <small>상세: {auth.loginError.detail}</small>}
          <div className="login-error-actions">
            {auth.loginError.existing ? (
              // 비회원이 연결하려던 구글·카카오가 이미 다른 회원 것: 합치지 않고, 원하면 그 계정으로 로그인 (비회원 기록은 넘어가지 않음)
              <button
                type="button"
                className="btn btn-primary"
                onClick={() => startFresh(auth.loginError.existing, pathname + search).catch((e) => alert(e.message))}
              >
                기존 계정으로 로그인
              </button>
            ) : (
              <Link to={auth.loginError.retryTo ?? '/login'} className="btn" onClick={auth.clearLoginError}>
                {auth.loginError.retryTo === '/login' || !auth.loginError.retryTo ? '다시 로그인' : '다시 연결하기'}
              </Link>
            )}
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
      {siteNotice && (
        <div className="login-notice" role="status">
          <p>{siteNotice}</p>
        </div>
      )}
      {noNickname && pathname !== '/welcome' && (
        <div className="login-notice nickname-band" role="status">
          <p>닉네임을 정하면 제안·빌드·투표·글·댓글을 쓸 수 있습니다. 둘러보기는 지금도 됩니다.</p>
          <div className="login-error-actions">
            <Link to="/welcome" state={{ from: pathname + search }} className="btn">닉네임 정하기</Link>
          </div>
        </div>
      )}
      <main className="content" ref={mainRef}>
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
      <UpdateBanner />
    </div>
  );
}
