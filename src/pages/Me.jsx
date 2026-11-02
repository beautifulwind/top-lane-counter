import { useEffect, useState } from 'react';
import { Link, Navigate, useLocation } from 'react-router-dom';
import { PROVIDERS, getIdentities, linkProvider } from '../api/auth';
import { getChampionMap, getItems, getLatestVersion, getRunes, getSummonerSpells } from '../api/ddragon';
import { getMyProposals, getMyUnreadNotifications, markNotificationsRead } from '../api/proposals';
import { getMyBuilds } from '../api/builds';
import { BUILD_STATUS_LABEL, STATUS_LABEL, TYPE_LABEL, fmtDateTime } from '../lib/format';
import { useAuth } from '../lib/auth';
import { useAsync } from '../lib/useAsync';
import { ErrorBox, Loading } from '../components/Status';
import UserName from '../components/UserName';
import BuildCard from '../components/BuildCard';

/**
 * 내 활동 (/me): 내 제안·내 빌드 목록과 상태, 로그인 연결.
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
      <MyActivity userId={auth.user.id} />
      <LinkedLogins userId={auth.user.id} />
    </article>
  );
}

function MyActivity({ userId }) {
  const { data, error, loading, retry } = useAsync(async () => {
    const [champs, proposals, builds, unread, items, runes, spells, latest] = await Promise.all([
      getChampionMap(), getMyProposals(userId), getMyBuilds(userId), getMyUnreadNotifications(userId),
      getItems(), getRunes(), getSummonerSpells(), getLatestVersion(),
    ]);
    return { champs, proposals, builds, unread, game: { items, runes, spells, latest } };
  }, [userId]);

  // 화면에 보인 알림 = 확인한 것 → 읽음 처리 (상단 빨간 점이 꺼진다).
  // "새 알림" 표시는 이번에 불러온 화면에서만 보인다. 재검토 요청 내용과 [고쳐서 다시 제출]은 제안 상태라 그대로 남는다.
  const unread = data?.unread;
  useEffect(() => {
    if (unread?.length) markNotificationsRead(unread.map((n) => n.id)).catch(() => {}); // 실패하면 다음에 다시 확인
  }, [unread]);

  if (loading) return <Loading />;
  if (error) return <ErrorBox error={error} onRetry={retry} />;
  return (
    <>
      <MyProposals data={data} />
      <MyBuilds data={data} />
    </>
  );
}

function MyProposals({ data }) {
  const name = (id) => data.champs[id]?.name ?? id;
  const isNew = (p) => data.unread.some((n) => n.proposal_id === p.id);

  return (
    <section className="me-section" aria-labelledby="my-proposals">
      <h2 id="my-proposals">내 제안</h2>
      {data && data.proposals.length === 0 && <p className="empty">아직 보낸 제안이 없어요.</p>}
      {data && data.proposals.length > 0 && (
        <ul className="proposal-list">
          {data.proposals.map((p) => {
            const title = `${name(p.counter_champion)}(으)로 ${name(p.target_champion)} 잡는 법`;
            const live = p.status === 'approved' || (p.type === 'doc_edit' && !['revoked', 'revision_requested'].includes(p.status));
            return (
              <li key={p.id} className={`proposal-row ${p.status}`}>
                <div className="proposal-main">
                  {isNew(p) && <span className="new-badge">새 알림</span>}
                  <span className="proposal-type">{TYPE_LABEL[p.type]}</span>{' '}
                  {live ? <Link to={`/champion/${p.target_champion}/counter/${p.counter_champion}`}>{title}</Link> : title}
                </div>
                <div className="proposal-meta">
                  <span className={`status-badge ${p.status}`}>{STATUS_LABEL[p.status]}</span>
                  <span>보낸 날 {fmtDateTime(p.created_at)}</span>
                  {p.reviewed_at && <span>처리 {fmtDateTime(p.reviewed_at)}</span>}
                </div>
                {p.status === 'approved' && p.approve_note && <p className="approve-note">승인 메모: {p.approve_note}</p>}
                {p.status === 'rejected' && <p className="reject-reason">거절 사유: {p.reject_reason}</p>}
                {p.status === 'revoked' && (
                  <p className="reject-reason">
                    승인 취소 사유: {p.revoke_reason}
                    {p.revoked_at && <> ({fmtDateTime(p.revoked_at)})</>}
                  </p>
                )}
                {p.status === 'revision_requested' && (
                  <div className="revision-note">
                    <p>
                      <strong>재검토 요청</strong>
                      {p.revision_requested_at && <small> ({fmtDateTime(p.revision_requested_at)})</small>}
                    </p>
                    <p>운영자 메모: {p.revision_note}</p>
                    <Link to={`/me/resubmit/${p.id}`} className="btn btn-small">고쳐서 다시 제출</Link>
                  </div>
                )}
                {p.type === 'new_counter' && p.build && (
                  <details className="build-summary">
                    <summary>제안한 빌드 보기</summary>
                    <BuildCard build={{ ...p.build, author: p.proposer }} {...data.game} />
                  </details>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

/** 내 빌드: 상태·메모·따봉 수, [이 빌드로 다시 쓰기] (승인된 빌드는 고치지 않고 새 빌드로 보낸다) */
function MyBuilds({ data }) {
  const name = (id) => data.champs[id]?.name ?? id;
  const isNew = (b) => data.unread.some((n) => n.build_id === b.id);

  return (
    <section className="me-section" aria-labelledby="my-builds">
      <h2 id="my-builds">내 빌드</h2>
      {data.builds.length === 0 && <p className="empty">아직 보낸 빌드가 없어요. 매치업 문서의 [+ 빌드 등록]에서 보낼 수 있어요.</p>}
      {data.builds.length > 0 && (
        <ul className="proposal-list">
          {data.builds.map((b) => {
            const c = b.counter;
            const title = c ? `${name(c.counter_champion)}(으)로 ${name(c.target_champion)} 잡는 법` : '(숨긴 카운터)';
            const path = c && `/champion/${c.target_champion}/counter/${c.counter_champion}`;
            const open = c?.status === 'approved';
            return (
              <li key={b.id} className={`proposal-row ${b.status}`} aria-label={`내 빌드: ${title}`}>
                <div className="proposal-main">
                  {isNew(b) && <span className="new-badge">새 알림</span>}
                  <span className="proposal-type">빌드</span>{' '}
                  {open && b.status === 'approved' ? <Link to={`${path}#builds`}>{title}</Link> : title}
                </div>
                <div className="proposal-meta">
                  <span className={`status-badge ${b.status}`}>{BUILD_STATUS_LABEL[b.status]}</span>
                  <span>보낸 날 {fmtDateTime(b.created_at)}</span>
                  {b.reviewed_at && <span>처리 {fmtDateTime(b.reviewed_at)}</span>}
                  {['approved', 'hidden'].includes(b.status) && <span>👍 {b.up} · 👎 {b.down}</span>}
                </div>
                {b.status === 'approved' && b.approve_note && <p className="approve-note">승인 메모: {b.approve_note}</p>}
                {b.status === 'rejected' && <p className="reject-reason">거절 사유: {b.reject_reason}</p>}
                {b.status === 'hidden' && (
                  <p className="reject-reason">
                    숨긴 사유: {b.hide_reason}
                    {b.hidden_at && <> ({fmtDateTime(b.hidden_at)})</>}
                  </p>
                )}
                <details className="build-summary">
                  <summary>빌드 보기</summary>
                  <BuildCard build={b} {...data.game} />
                </details>
                {open && (
                  <div className="row-actions">
                    <Link to={`${path}/build/new?from=${b.id}`} className="btn btn-small">이 빌드로 다시 쓰기</Link>
                  </div>
                )}
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
