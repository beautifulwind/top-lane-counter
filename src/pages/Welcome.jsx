import { useState } from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router-dom';
import { NICKNAME_MAX, nicknameProblem, saveNickname } from '../api/auth';
import { useAuth } from '../lib/auth';
import { ErrorBox, Loading } from '../components/Status';
import { safePath } from './Login';

/** 첫 로그인 시 닉네임 설정 */
export default function Welcome() {
  const auth = useAuth();
  const navigate = useNavigate();
  const from = safePath(useLocation().state?.from);
  const [nickname, setNickname] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState(null);

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
      <p className="lead">위키에서 다른 사람에게 보일 이름이에요. 다른 사람과 겹칠 수 없어요.</p>
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
          {busy ? '저장 중…' : '시작하기'}
        </button>
      </form>
    </article>
  );
}
