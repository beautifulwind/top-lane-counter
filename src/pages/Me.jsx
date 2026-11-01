import { useState } from 'react';
import { Navigate } from 'react-router-dom';
import { PROVIDERS, getIdentities, linkProvider } from '../api/auth';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import UserName from '../components/UserName';

/**
 * 내 활동 (/me). 지금은 로그인 연결만 있다.
 * 레벨·경험치·칭호·내 제안 목록은 4단계 이후에 채운다 (SPEC 3장).
 */
export default function Me() {
  const auth = useAuth();
  if (auth.status === 'loading') return <Loading />;
  if (auth.status === 'signedOut') return <Navigate to="/login" replace state={{ from: '/me' }} />;
  if (auth.profileError) return <ErrorBox error={auth.profileError} />;
  if (!auth.profile) return <Loading />;

  return (
    <article className="me-page">
      <h1 className="doc-title">
        <UserName profile={auth.profile} />
      </h1>
      <LinkedLogins userId={auth.user.id} />
    </article>
  );
}

function LinkedLogins({ userId }) {
  const { data: identities, error, loading, retry } = useAsync(getIdentities, [userId]);
  const [busy, setBusy] = useState(null);
  const [linkError, setLinkError] = useState(null);

  const link = async (provider) => {
    setBusy(provider);
    setLinkError(null);
    try {
      await linkProvider(provider); // 성공하면 구글/카카오 화면으로 이동한다
    } catch (e) {
      setLinkError(e.message);
      setBusy(null);
    }
  };

  return (
    <section className="me-section" aria-labelledby="linked-logins">
      <h2 id="linked-logins">로그인 연결</h2>
      <p className="lead">둘 다 연결하면 구글·카카오 어느 쪽으로 로그인해도 이 계정으로 들어와요.</p>
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {identities && (
        <ul className="identity-list">
          {Object.entries(PROVIDERS).map(([provider, name]) => {
            const linked = identities.find((i) => i.provider === provider);
            return (
              <li key={provider} className="identity-row">
                <span>
                  <span className="identity-name">{name}</span>
                  {linked?.email && <small>{linked.email}</small>}
                </span>
                {linked ? (
                  <span className="identity-linked">✓ 연결됨</span>
                ) : (
                  <button
                    type="button"
                    className={`btn login-btn-sm ${provider}`}
                    onClick={() => link(provider)}
                    disabled={busy !== null}
                  >
                    {busy === provider ? `${name}로 이동 중…` : `${name} 연결하기`}
                  </button>
                )}
              </li>
            );
          })}
        </ul>
      )}
      {linkError && <p className="form-error" role="alert">{linkError}</p>}
    </section>
  );
}
