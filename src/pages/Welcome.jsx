import { useEffect, useState } from 'react';
import { Link, Navigate, useLocation, useNavigate } from 'react-router-dom';
import { needsNicknameFor } from '../lib/auth';
import { NICKNAME_MAX, nicknameProblem, saveNickname } from '../api/auth';
import { useAuth } from '../lib/auth';
import { ErrorBox, Loading } from '../components/Status';
import { safePath } from './Login';
import { isGuest } from '../lib/auth';
import { DeleteAccount } from '../components/AccountSettings';

/** 첫 로그인 시 닉네임 설정 */
export default function Welcome() {
  const auth = useAuth();
  const navigate = useNavigate();
  const from = safePath(useLocation().state?.from);
  const [nickname, setNickname] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);
  const { clearCameBack } = auth;
  useEffect(() => { clearCameBack?.(); }, [clearCameBack]); // 한 번 보여 줬으면 다시 끌고 오지 않는다

  if (auth.status === 'loading') return <Loading />;
  if (auth.status === 'signedOut') return <Navigate to="/login" replace />;
  if (auth.profileError) return <ErrorBox error={auth.profileError} />;
  if (auth.profile === undefined) return <Loading />;
  if (auth.profile?.nickname) return <Navigate to={from} replace />;

  const length = [...nickname.trim()].length;
  const submit = async (e) => {
    e.preventDefault();
    const problem = nicknameProblem(nickname);
    if (problem) return setError(problem);
    setBusy(true);
    setError(null);
    try {
      const profile = await saveNickname(auth.user.id, nickname);
      auth.setProfile(profile);
      navigate(from, { replace: true });
    } catch (err) {
      setError(err.message);
      setBusy(false);
    }
  };

  return (
    <article className="welcome">
      <h1 className="doc-title">닉네임 정하기</h1>
      <p className="lead">
        위키에서 다른 사람에게 보일 이름이에요. 다른 사람과 겹칠 수 없어요. 정한 뒤에는 30일에 한 번 [마이페이지]에서 바꿀 수 있어요.
      </p>
      <form onSubmit={submit} className="nick-form">
        <label htmlFor="nickname">닉네임</label>
        <input
          id="nickname"
          value={nickname}
          onChange={(e) => setNickname(e.target.value)}
          autoComplete="off"
          autoFocus
          aria-describedby="nick-help"
        />
        <small id="nick-help" className={length > NICKNAME_MAX ? 'over' : ''}>
          {length}/{NICKNAME_MAX}자
        </small>
        {error && <p className="form-error" role="alert">{error}</p>}
        <button type="submit" className="btn" disabled={busy}>
          {busy ? '저장하는 중…' : '시작하기'}
        </button>
      </form>
      <p className="hint">
        닉네임 없이도 둘러볼 수 있어요.{' '}
        <Link to={needsNicknameFor(from.split(/[?#]/)[0]) ? '/' : from}>나중에 정할게요</Link>
      </p>
      {isGuest(auth) && (
        <>
          <p className="hint">비회원이에요. 다른 사람에게는 닉네임 옆에 &ldquo;비회원&rdquo;이 붙어 보여요.</p>
          {/* 닉네임 없는 비회원은 /me에 못 가므로 여기서 지운다 (로그아웃 대신) */}
          <DeleteAccount auth={auth} />
        </>
      )}
    </article>
  );
}
