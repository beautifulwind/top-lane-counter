import { useRef, useState } from 'react';
import { Link, Navigate, useLocation, useNavigate } from 'react-router-dom';
import { PROVIDERS, signIn, signInAsGuest } from '../api/auth';
import { isGuest, useAuth } from '../lib/auth';
import { guestNotice } from '../lib/guest';
import { Loading } from '../components/Status';
import Captcha, { captchaSiteKey } from '../components/Captcha';
import GuestLinkDialog from '../components/GuestLinkDialog';

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
      await signIn(provider, from); // 성공하면 구글/카카오 화면으로 이동한다
    } catch (e) {
      setError(e.message);
      setBusy(null);
    }
  };

  return (
    <article className="login">
      <h1 className="doc-title">로그인 · 가입</h1>
      <p className="lead">
        로그인하면 카운터·문서 수정·빌드를 제안하고, 따봉·비추를 누르고, 노가리방과 문서에 글·댓글을 쓸 수 있어요. 보기는 로그인 없이도 돼요.
      </p>
      {guest ? (
        <p className="notice login-join">지금은 비회원이에요. 구글·카카오를 고르면 지금 기록을 이어 갈지 정할 수 있어요.</p>
      ) : (
        <p className="notice login-join">처음이면 자동으로 가입돼요. 따로 회원가입할 필요 없어요.</p>
      )}
      <div className="login-buttons">
        {Object.entries(PROVIDERS).map(([provider, name]) => (
          <button
            key={provider}
            type="button"
            className={`btn login-btn ${provider}`}
            onClick={() => start(provider)}
            disabled={busy !== null}
          >
            {provider === 'kakao' && <KakaoSymbol />}
            {busy === provider ? `${name}로 이동 중…` : `${name}로 시작하기`}
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
            비회원으로 시작하기
          </button>
        )}
      </div>
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
        시작하면 <Link to="/terms">이용약관</Link>과 <Link to="/privacy">개인정보처리방침</Link>에 동의하는 것으로 봐요.
        만 14세 이상만 가입할 수 있어요.
      </p>
      {error && <p className="form-error" role="alert">{error}</p>}
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
      <p className="hint">비회원은 읽기·노가리방 글·댓글·문서 댓글·제안을 할 수 있어요. 따봉·비추·추천·신고는 구글·카카오를 연결한 뒤에 돼요.</p>
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

/** 외부 주소로 튕겨 나가지 않게, 우리 사이트 안의 경로만 허용 */
export function safePath(p) {
  return typeof p === 'string' && p.startsWith('/') && !p.startsWith('//') ? p : '/';
}
