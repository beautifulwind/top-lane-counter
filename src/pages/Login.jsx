import { useState } from 'react';
import { Navigate, useLocation } from 'react-router-dom';
import { signInWithGoogle } from '../api/auth';
import { useAuth } from '../lib/auth';
import { Loading } from '../components/Status';

export default function Login() {
  const auth = useAuth();
  const location = useLocation();
  const from = safePath(location.state?.from);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

  if (auth.status === 'loading') return <Loading />;
  // 이미 로그인했으면 원래 페이지로 (닉네임이 없으면 Layout이 /welcome으로 보낸다)
  if (auth.status === 'signedIn') return <Navigate to={from} replace />;

  const google = async () => {
    setBusy(true);
    setError(null);
    try {
      await signInWithGoogle(from); // 성공하면 구글 화면으로 이동한다
    } catch (e) {
      setError(e.message);
      setBusy(false);
    }
  };

  return (
    <article className="login">
      <h1 className="doc-title">로그인</h1>
      <p className="lead">로그인하면 카운터 제안, 문서 수정, 빌드 등록, 투표를 할 수 있어요. 보기는 로그인 없이도 돼요.</p>
      <div className="login-buttons">
        <button type="button" className="btn login-btn google" onClick={google} disabled={busy}>
          {busy ? '구글로 이동 중…' : '구글로 로그인'}
        </button>
        {/* 카카오 로그인은 3단계 후반에 추가 */}
      </div>
      {error && <p className="form-error" role="alert">{error}</p>}
    </article>
  );
}

/** 외부 주소로 튕겨 나가지 않게, 우리 사이트 안의 경로만 허용 */
export function safePath(p) {
  return typeof p === 'string' && p.startsWith('/') && !p.startsWith('//') ? p : '/';
}
