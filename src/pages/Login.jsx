import { useRef, useState } from 'react';
import { Link, Navigate, useLocation, useNavigate } from 'react-router-dom';
import { loginProviders, signIn, signInAsGuest } from '../api/auth';
import { isGuest, useAuth } from '../lib/auth';
import { guestNotice } from '../lib/guest';
import { josa } from '../lib/josa';
import { BOARD_NAME } from '../lib/siteNames';
import { Loading } from '../components/Status';
import Captcha, { captchaSiteKey } from '../components/Captcha';
import GuestLinkDialog from '../components/GuestLinkDialog';
import StoreLinks from '../components/StoreLinks';
import { ShieldIcon, UserIcon } from '../components/Icons';

export default function Login() {
  const auth = useAuth();
  const location = useLocation();
  const from = safePath(location.state?.from);
  const navigate = useNavigate();
  const [busy, setBusy] = useState(null); // 이동 중인 provider ('google' | 'kakao' | 'guest')
  const [error, setError] = useState(null);
  const [guestOpen, setGuestOpen] = useState(false); // [비회원으로 시작하기] 안내 칸
  const [choosing, setChoosing] = useState(null); // 비회원이 고른 구글·카카오 → 선택 창
  const guest = isGuest(auth);

  if (auth.status === 'loading') return <Loading />;
  // 이미 로그인했으면 원래 페이지로 (닉네임이 없으면 Layout이 /welcome으로 보낸다). 비회원은 여기서 구글·카카오를 연결할 수 있다
  if (auth.status === 'signedIn' && !guest && busy !== 'guest') return <Navigate to={from} replace />;

  const start = async (provider) => {
    if (guest) {
      setChoosing(provider);
      return;
    }
    setBusy(provider);
    setError(null);
    try {
      // 웹: 구글/카카오 화면으로 이동한다. 앱: 시스템 브라우저에서 끝나고(돌아옴·닫음) 값이 오면 버튼을 다시 연다 (결과 안내는 위 띠)
      if (await signIn(provider, from)) setBusy(null);
    } catch (e) {
      setError(e.message);
      setBusy(null);
    }
  };

  return (
    <article className="login">
      <div className="login-card">
        <span className="login-logo" aria-hidden="true"><ShieldIcon size={30} /></span>
        <h1 className="doc-title">로그인 · 가입</h1>
        <p className="lead">
          로그인하면 상대법·문서 수정·빌드를 제안하고, 빌드에 추천·비추천을 누르고, {josa(BOARD_NAME, '과/와')} 문서에 글·댓글을 쓸 수 있습니다. 보기는 로그인 없이도 됩니다.
        </p>
        {guest ? (
          <p className="notice login-join">지금은 비회원입니다. 구글·카카오를 고르면 지금 기록을 이어 갈지 정할 수 있습니다.</p>
        ) : (
          <p className="notice login-join">처음이면 자동으로 가입됩니다. 따로 회원가입할 필요 없습니다.</p>
        )}
        <div className="login-buttons">
          {loginProviders().map(([provider, name]) => (
            <button
              key={provider}
              type="button"
              className={`btn login-btn ${provider}`}
              onClick={() => start(provider)}
              disabled={busy !== null}
            >
              {provider === 'kakao' && <KakaoSymbol />}
              {provider === 'apple' && <AppleSymbol />}
              {busy === provider ? busyLabel(provider, name) : `${name}로 시작하기`}
            </button>
          ))}
          {!guest && (
            <button
              type="button"
              className="btn login-btn guest"
              onClick={() => setGuestOpen(true)}
              disabled={busy !== null}
              aria-expanded={guestOpen}
            >
              <UserIcon size={18} /> 비회원으로 시작하기
            </button>
          )}
        </div>
        <StoreLinks size="sm" />
        {choosing && <GuestLinkDialog provider={choosing} returnTo={from} onClose={() => setChoosing(null)} />}
        {guestOpen && !guest && (
          <GuestStart
            busy={busy === 'guest'}
            onCancel={() => setGuestOpen(false)}
            onStart={async (token) => {
              setBusy('guest');
              setError(null);
              try {
                await signInAsGuest(token);
                navigate('/welcome', { replace: true, state: { from } }); // 닉네임은 지금 정하거나 나중에
              } catch (e) {
                setError(e.message);
                setBusy(null);
                throw e; // GuestStart가 캡차를 다시 돌린다
              }
            }}
          />
        )}
        <p className="login-consent">
          시작하면 <Link to="/terms">이용약관</Link>과 <Link to="/privacy">개인정보처리방침</Link>에 동의하는 것으로 봅니다.
          만 14세 이상만 가입할 수 있습니다.
        </p>
        {error && <p className="form-error" role="alert">{error}</p>}
      </div>
    </article>
  );
}

/** [비회원으로 시작하기]를 누르면 그 자리에 열리는 안내 + 봇 확인 + [비회원으로 시작] (Esc·[취소]로 닫힘) */
function GuestStart({ busy, onStart, onCancel }) {
  const needCaptcha = !!captchaSiteKey();
  const [token, setToken] = useState(null);
  const [captchaError, setCaptchaError] = useState(null);
  const captcha = useRef(null);
  const starting = useRef(false); // 한 번 누르면 끝날 때까지 다시 부르지 않음 (state보다 먼저 막힘)

  const go = async () => {
    if (starting.current || busy || (needCaptcha && !token)) return;
    starting.current = true;
    const used = token;
    setToken(null); // 토큰은 한 번만 쓸 수 있다 — 바로 버린다
    try {
      await onStart(used);
    } catch {
      captcha.current?.reset(); // 실패하면 새 토큰을 받게 위젯을 다시 돌린다 (문구는 부모가 보여 줌)
    } finally {
      starting.current = false;
    }
  };

  return (
    <section className="guest-start" aria-label="비회원으로 시작" onKeyDown={(e) => e.key === 'Escape' && !busy && onCancel()}>
      <p className="warn">{guestNotice('web')}</p>
      <p className="hint">비회원은 읽기·탑신병자 커뮤니티 글·문서 댓글·제안을 할 수 있습니다. 탑신병자 커뮤니티 댓글·답글, 문서 댓글의 답글, 추천·비추천·신고는 구글·카카오를 연결한 뒤에 됩니다.</p>
      <Captcha ref={captcha} onToken={setToken} onError={setCaptchaError} />
      {captchaError && <p className="form-error" role="alert">{captchaError}</p>}
      <div className="row-actions">
        <button type="button" className="btn btn-primary" onClick={go} disabled={busy || (needCaptcha && !token)}>
          {busy ? '시작하는 중…' : '비회원으로 시작'}
        </button>
        <button type="button" className="btn" onClick={onCancel} disabled={busy}>취소</button>
      </div>
    </section>
  );
}

/** 카카오 디자인 가이드의 말풍선 심볼 (검정) */
function KakaoSymbol() {
  return (
    <svg className="kakao-symbol" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false">
      <path fill="currentColor" d="M12 3C6.48 3 2 6.54 2 10.9c0 2.82 1.87 5.3 4.69 6.7l-.95 3.5c-.08.3.26.55.52.38l4.13-2.73c.53.06 1.07.1 1.61.1 5.52 0 10-3.54 10-7.95S17.52 3 12 3z" />
    </svg>
  );
}

/** Apple 로그인 버튼의 Apple 로고 (글자색을 따름 — 흰 버튼 위 검정) */
function AppleSymbol() {
  return (
    <svg className="apple-symbol" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false">
      <path fill="currentColor" d="M16.37 12.6c-.02-2.2 1.8-3.26 1.88-3.31-1.03-1.5-2.62-1.7-3.18-1.73-1.35-.14-2.64.8-3.33.8-.69 0-1.74-.78-2.87-.76-1.47.02-2.83.86-3.59 2.18-1.53 2.66-.39 6.6 1.1 8.75.73 1.05 1.6 2.24 2.73 2.2 1.1-.04 1.51-.71 2.84-.71 1.32 0 1.7.71 2.86.69 1.18-.02 1.93-1.07 2.65-2.13.84-1.22 1.18-2.4 1.2-2.46-.03-.01-2.3-.88-2.32-3.5zM14.2 6.13c.6-.73 1.01-1.74.9-2.75-.87.04-1.92.58-2.54 1.3-.56.64-1.05 1.67-.92 2.66.97.08 1.96-.49 2.56-1.21z" />
    </svg>
  );
}

/** 누른 버튼의 "진행 중" 글자 — Apple은 화면을 떠나지 않고 iOS 시트가 뜬다 */
export function busyLabel(provider, name) {
  return provider === 'apple' ? 'Apple 로그인 중…' : `${name}로 이동 중…`;
}

/** 외부 주소로 튕겨 나가지 않게, 우리 사이트 안의 경로만 허용 */
export function safePath(p) {
  return typeof p === 'string' && p.startsWith('/') && !p.startsWith('//') ? p : '/';
}
