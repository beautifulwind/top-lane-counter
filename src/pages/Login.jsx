import { useState } from 'react';
import { Link, Navigate, useLocation } from 'react-router-dom';
import { PROVIDERS, signIn } from '../api/auth';
import { useAuth } from '../lib/auth';
import { Loading } from '../components/Status';

export default function Login() {
  const auth = useAuth();
  const location = useLocation();
  const from = safePath(location.state?.from);
  const [busy, setBusy] = useState(null); // 이동 중인 provider ('google' | 'kakao')
  const [error, setError] = useState(null);

  if (auth.status === 'loading') return <Loading />;
  // 이미 로그인했으면 원래 페이지로 (닉네임이 없으면 Layout이 /welcome으로 보낸다)
  if (auth.status === 'signedIn') return <Navigate to={from} replace />;

  const start = async (provider) => {
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
      <h1 className="doc-title">로그인</h1>
      <p className="lead">로그인하면 카운터 제안, 문서 수정, 빌드 등록, 투표를 할 수 있어요. 보기는 로그인 없이도 돼요.</p>
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
            {busy === provider ? `${name}로 이동 중…` : `${name}로 로그인`}
          </button>
        ))}
      </div>
      <p className="login-consent">
        로그인하면 <Link to="/terms">이용약관</Link>과 <Link to="/privacy">개인정보처리방침</Link>에 동의하는 것으로 봐요.
        만 14세 이상만 가입할 수 있어요.
      </p>
      {error && <p className="form-error" role="alert">{error}</p>}
    </article>
  );
}

/** 카카오 디자인 가이드의 말풍선 심볼 (검정) */
function KakaoSymbol() {
  return (
    <svg className="kakao-symbol" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true" focusable="false">
      <path fill="#000" d="M12 3C6.48 3 2 6.54 2 10.9c0 2.82 1.87 5.3 4.69 6.7l-.95 3.5c-.08.3.26.55.52.38l4.13-2.73c.53.06 1.07.1 1.61.1 5.52 0 10-3.54 10-7.95S17.52 3 12 3z" />
    </svg>
  );
}

/** 외부 주소로 튕겨 나가지 않게, 우리 사이트 안의 경로만 허용 */
export function safePath(p) {
  return typeof p === 'string' && p.startsWith('/') && !p.startsWith('//') ? p : '/';
}
