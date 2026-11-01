import { useState } from 'react';
import { Link, Navigate, useLocation } from 'react-router-dom';
import { PROVIDERS, getIdentities, linkProvider } from '../api/auth';
import { getChampionMap } from '../api/ddragon';
import { getMyProposals } from '../api/proposals';
import { STATUS_LABEL, TYPE_LABEL, fmtDateTime } from '../lib/format';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import UserName from '../components/UserName';

/**
 * 내 활동 (/me): 내 제안 목록과 상태, 로그인 연결.
 * 레벨·경험치·칭호는 6단계에서 채운다 (SPEC 3장).
 */
export default function Me() {
  const auth = useAuth();
  const sent = useLocation().state?.sent;
  if (auth.status === 'loading') return <Loading />;
  if (auth.status === 'signedOut') return <Navigate to="/login" replace state={{ from: '/me' }} />;
  if (auth.profileError) return <ErrorBox error={auth.profileError} />;
  if (!auth.profile) return <Loading />;

  return (
    <article className="me-page">
      <h1 className="doc-title">
        <UserName profile={auth.profile} />
      </h1>
      {sent && (
        <p className="notice" role="status">
          {sent} 운영자가 승인하면 반영돼요.
        </p>
      )}
      <MyProposals userId={auth.user.id} />
      <LinkedLogins userId={auth.user.id} />
    </article>
  );
}

function MyProposals({ userId }) {
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, proposals] = await Promise.all([getChampionMap(), getMyProposals(userId)]);
    return { champs, proposals };
  }, [userId]);
  const name = (id) => data.champs[id]?.name ?? id;

  return (
    <section className="me-section" aria-labelledby="my-proposals">
      <h2 id="my-proposals">내 제안</h2>
      {loading && <Loading />}
      {error && <ErrorBox error={error} onRetry={retry} />}
      {data && data.proposals.length === 0 && <p className="empty">아직 보낸 제안이 없어요.</p>}
      {data && data.proposals.length > 0 && (
        <ul className="proposal-list">
          {data.proposals.map((p) => {
            const title = `${name(p.counter_champion)}(으)로 ${name(p.target_champion)} 잡는 법`;
            const live = p.status === 'approved' || p.type === 'doc_edit';
            return (
              <li key={p.id} className={`proposal-row ${p.status}`}>
                <div className="proposal-main">
                  <span className="proposal-type">{TYPE_LABEL[p.type]}</span>{' '}
                  {live ? <Link to={`/champion/${p.target_champion}/counter/${p.counter_champion}`}>{title}</Link> : title}
                </div>
                <div className="proposal-meta">
                  <span className={`status-badge ${p.status}`}>{STATUS_LABEL[p.status]}</span>
                  <span>보낸 날 {fmtDateTime(p.created_at)}</span>
                  {p.reviewed_at && <span>처리 {fmtDateTime(p.reviewed_at)}</span>}
                </div>
                {p.status === 'rejected' && <p className="reject-reason">거절 사유: {p.reject_reason}</p>}
              </li>
            );
          })}
        </ul>
      )}
    </section>
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
