import { useState } from 'react';
import { Link, Navigate } from 'react-router-dom';
import { PROVIDERS, getIdentities, linkProvider } from '../api/auth';
import { isGuest, useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import SectionHead from '../components/SectionHead';
import AccountSettings from '../components/AccountSettings';
import { CheckCircleIcon, GearIcon, LinkIcon } from '../components/Icons';

/**
 * 계정 설정 (/me/settings): 로그인 연결(회원·운영자) · 닉네임 바꾸기 · 회원 탈퇴(비회원은 "비회원 기록 지우기").
 * 자주 쓰지 않는 계정 일이라 마이페이지에서 빼서 따로 둔다. 들어오는 곳: 마이페이지 프로필 카드의 [계정 설정].
 * 구글·카카오를 연결하고 돌아오면 이 화면으로 온다 (비회원의 구글·카카오 연결은 마이페이지 맨 위 칸 → /me).
 */
export default function MySettings() {
  const auth = useAuth();
  if (auth.status === 'loading') return <Loading />;
  if (auth.status === 'signedOut') return <Navigate to="/login" replace state={{ from: '/me/settings' }} />;
  if (auth.profileError) return <ErrorBox error={auth.profileError} />;
  if (!auth.profile) return <Loading />;

  return (
    <article className="me-page">
      <nav className="crumbs"><Link to="/me">마이페이지</Link> › 계정 설정</nav>
      <h1 className="doc-title page-title"><GearIcon size={26} className="title-icon" /> 계정 설정</h1>
      {!isGuest(auth) && <LinkedLogins userId={auth.user.id} />}
      <AccountSettings auth={auth} />
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
      <SectionHead icon={LinkIcon} id="linked-logins">로그인 연결</SectionHead>
      <p className="lead">둘 다 연결하면 구글·카카오 어느 쪽으로 로그인해도 이 계정으로 들어옵니다.</p>
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
                  <span className="identity-linked"><CheckCircleIcon size={16} /> 연결됨</span>
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
